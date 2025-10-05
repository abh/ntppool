package NTPPool::Control::Scores;
use strict;

# include ::Login since the manage site use this controller, too
use parent            qw(NTPPool::Control::Login NTPPool::Control);
use Combust::Constant qw(OK DECLINED);
use NP::Model;
use List::Util   qw(min);
use JSON         ();
use experimental qw( defer );
use Syntax::Keyword::Dynamically;
use OpenTelemetry::Constants qw( SPAN_KIND_INTERNAL SPAN_STATUS_ERROR SPAN_STATUS_OK );
use OpenTelemetry -all;
use NP::CAPI::Server qw(get_server);
use DateTime::Format::ISO8601;

my $json = JSON::XS->new->utf8;

sub render {
    my $self = shift;

    my $span = NP::Tracing->tracer->create_span(
        name => "scores.render",
        kind => SPAN_KIND_INTERNAL,
    );
    dynamically otel_current_context = otel_context_with_span($span);
    defer { $span->end(); };

    my $public = $self->site->name eq 'ntppool' ? 1 : 0;

    if ($public && $self->deployment_mode ne "devel") {
        $self->cache_control('s-maxage=600,max-age=300');
    }

    unless ($public or $self->user) {

        # for manage site, redirect to the public site
        # unless the user is logged in
        return $self->redirect(
            $self->www_url($self->request->uri, $self->request->query_parameters));
    }

    if (!$public) {
        $self->tpl_param('manage_site', 1);
        $self->cache_control('s-maxage=0,max-age=0');
    }

    if (my $ip = ($self->req_param('ip') || $self->req_param('server_ip'))) {
        my $server = NP::Model->server->find_server($ip) or return 404;
        return $self->redirect('/scores/' . $server->ip) if $server;
    }

    # "tell me your IP" form
    if ($self->request->uri eq '/scores/') {
        return OK, $self->evaluate_template('tpl/server.html');
    }

    return $self->redirect('/scores/') if ($self->request->uri =~ m!^/s(cores)?/?$!);

    if ($self->request->uri =~ m!^/s/([^/]+)!) {
        my $server = NP::Model->server->find_server($1) or return 404;
        $self->cache_control('max-age=14400, s-maxage=7200');
        if (   $server->deletion_on
            && $server->deletion_on < DateTime->now->subtract(years => 3))
        {
            return 404;
        }
        return $self->redirect('/scores/' . $server->ip, 301);
    }

    if (my ($id, $mode) =
        ($self->request->uri =~ m!^/scores/graph/(\d+)-(score|offset).png!))
    {
        my $server = NP::Model->server->find_server($id) or return 404;
        $self->cache_control('max-age=14400, s-maxage=7200');
        return $self->redirect($server->graph_uri($mode), 301);
    }

    if (my ($p, $mode) = $self->request->uri =~ m!^/scores/([^/]+)(?:/(\w+))?!) {
        return 404 unless $p;
        $mode ||= '';

        if ($mode) {
            $span->set_attribute("scores.mode", $mode);
        }

        # For main page display, use CAPI
        if ($mode eq '' || $mode eq 'graph') {

            # Fetch server data from CAPI
            my $server_result = $self->server_data($p);

            if ($server_result->{error} || !$server_result->{data}{server}) {
                warn "Failed to fetch server data: "
                  . ($server_result->{error} || 'no server data');
                return 404;
            }

            my $server_data = $server_result->{data}{server};

            # Redirect if requested IP doesn't match canonical IP
            return $self->redirect('/scores/' . $server_data->{ip}, 301)
              unless $p eq $server_data->{ip};

            # regular html page

            $self->tpl_param('graph_explanation' => 1)
              if $self->req_param('graph_explanation');
            $self->tpl_param('server_data' => $server_data);

            # Hide history sections if server was deleted more than 6 months ago
            my $show_history = 1;
            if ($server_data->{deletionOn}) {
                $self->tpl_param('now' => DateTime->now());
                my $deletion_date =
                  DateTime::Format::ISO8601->parse_datetime($server_data->{deletionOn});
                my $six_months_ago = DateTime->now->subtract(months => 6);
                $show_history = 0 if $deletion_date < $six_months_ago;
            }
            $self->tpl_param('show_history' => $show_history);

            if ($self->req_param('graph_only')) {
                return OK, $self->evaluate_template('tpl/server_static_graph.html');
            }

            return OK, $self->evaluate_template('tpl/server.html');
        }

        # For other modes, still use the old DB model
        my ($server) = NP::Model->server->find_server($p);
        return 404 unless $server;

        return 404
          if ($public and $server->deletion_on < DateTime->now->subtract(years => 3));

        return $self->redirect('/scores/' . $server->ip, 301) unless $p eq $server->ip;

        $self->request->header_out('Vary', undef);

        if ($mode eq 'monitors') {
            $self->cache_control('s-maxage=480,max-age=240') if $public;
            my $cutoff   = DateTime->now->subtract(days => 120);
            my $monitors = $server->monitors($cutoff);
            return OK, $json->convert_blessed->encode({monitors => $monitors}),
              'application/json';
        }
        elsif ($mode eq 'log' or $self->req_param('log') or $mode eq 'json') {
            $mode = $mode eq 'json' ? $mode : 'log';

   # $self->request->header_out('Cache-Control' => 'public,max-age=86400,s-maxage=86400');
            $self->request->header_out('Fastly-Follow' => '1');
            return $self->redirect(
                $self->www_url(
                    "/api/data/server/scores/" . $server->ip . "/$mode",
                    $self->request->query_parameters
                ),
                301
            );
        }
        elsif ($mode eq 'rrd') {
            return 404;
        }
        elsif ($mode eq 'graph') {
            my ($type) = ($self->request->uri =~ m{/(offset|score)\.png$});
            return $self->redirect($server->graph_uri($type), 301);
        }
        else {
            return $self->redirect('/scores/' . $server->ip);
        }
    }

    # if we didn't match on any URL, return 404
    return 404;
}

sub bc_user_class    { NP::Model->user }
sub bc_info_required {'username,email'}

sub server_data {
    my ($self, $ip) = @_;

    # Cache the server data per request
    my $cache_key = "_server_data_$ip";
    return $self->{$cache_key} if exists $self->{$cache_key};

    my $result = get_server(
        ip      => $ip,
        context => $self->_get_request_context(),
    );

    return $self->{$cache_key} = $result;
}

sub _get_request_context {
    my $self            = shift;
    my $x_forwarded_for = $self->request->header_in('X-Forwarded-For');
    return $x_forwarded_for ? {x_forwarded_for => $x_forwarded_for} : undef;
}

1;
