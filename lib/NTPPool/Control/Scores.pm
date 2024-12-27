package NTPPool::Control::Scores;
use strict;
use parent            qw(NTPPool::Control);
use Combust::Constant qw(OK DECLINED);
use NP::Model;
use List::Util   qw(min);
use JSON         ();
use experimental qw( defer );
use Syntax::Keyword::Dynamically;
use OpenTelemetry::Constants qw( SPAN_KIND_INTERNAL SPAN_STATUS_ERROR SPAN_STATUS_OK );
use OpenTelemetry -all;

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
    $self->cache_control('s-maxage=600,max-age=300') if $public;

    unless ($public or $self->user) {
        return $self->redirect(
            $self->www_url($self->request->uri, $self->request->query_parameters));
    }

    if (!$public) {
        $self->tpl_param('manage_site', 1);
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
        if ($server->deletion_on && $server->deletion_on < DateTime->now->subtract(years => 3)) {
            return 404;
        }
        return $self->redirect('/scores/' . $server->ip, 301);
    }

    if (my ($id, $mode) = ($self->request->uri =~ m!^/scores/graph/(\d+)-(score|offset).png!)) {
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

        my ($server) = NP::Model->server->find_server($p);
        return 404 unless $server;

        return 404
          if ($public and $server->deletion_on < DateTime->now->subtract(years => 3));

        return $self->redirect('/scores/' . $server->ip, 301) unless $p eq $server->ip;

        if ($mode eq '') {
            $self->tpl_param('graph_explanation' => 1)
              if $self->req_param('graph_explanation');
            $self->tpl_param('server' => $server);

            if ($self->req_param('graph_only')) {
                return OK, $self->evaluate_template('tpl/server_static_graph.html');
            }

            return OK, $self->evaluate_template('tpl/server.html');
        }

        $self->request->header_out('Vary', undef);

        if ($mode eq 'monitors') {
            $self->cache_control('s-maxage=480,max-age=240') if $public;
            my $cutoff   = DateTime->now->subtract(days => 120);
            my $monitors = $server->monitors($cutoff);
            return OK, $json->convert_blessed->encode({monitors => $monitors}), 'application/json';
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

1;
