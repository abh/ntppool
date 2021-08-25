package NTPPool::Control::Scores;
use strict;
use base qw(NTPPool::Control);
use Combust::Constant qw(OK DECLINED);
use NP::Model;
use List::Util qw(min);
use JSON qw(encode_json);

sub render {
    my $self = shift;

    my $public = $self->site->name eq 'ntppool' ? 1 : 0;
    $self->cache_control('s-maxage=1200,max-age=600') if $public;

    unless ($public or $self->user) {
        $self->redirect($self->www_url($self->request->uri, $self->request->query_parameters));
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

        my ($server) = NP::Model->server->find_server($p);
        return 404 unless $server;

        return 404 if ($public and $server->deletion_on < DateTime->now->subtract(years => 3));

        return $self->redirect('/scores/' . $server->ip, 301) unless $p eq $server->ip;

        if ($mode eq '') {
            $self->tpl_param('graph_explanation' => 1) if $self->req_param('graph_explanation');
            $self->tpl_param('server' => $server);

            if ($self->req_param('graph_only')) {
                return OK, $self->evaluate_template('tpl/server_static_graph.html');
            }

            return OK, $self->evaluate_template('tpl/server.html');
        }

        $self->request->header_out('Vary', undef);

        if ($mode eq 'monitors') {
            $self->cache_control('s-maxage=480,max-age=240') if $public;
            return OK, encode_json({monitors => $self->_monitors($server)}), 'application/json';
        }
        elsif ($mode eq 'log' or $self->req_param('log') or $mode eq 'json') {
            $mode = $mode eq 'json' ? $mode : 'log';
            my $limit = $self->req_param('limit') || 0;
            $limit = 50 unless $limit and $limit !~ m/\D/;
            $limit = 4000 if $limit > 4000;

            my $since = $self->req_param('since');
            $since = 0 if defined $since and $since =~ m/\D/;

            my $options = {
                count      => $limit,
                since      => $since,
                monitor_id => $self->req_param('monitor'),
            };

            if ($since) {
                $self->cache_control('s-maxage=300');
            }

            if ($mode eq 'log') {
                return OK, $server->log_scores_csv($options), 'text/plain';
            }

            #local ($Rose::DB::Object::Debug, $Rose::DB::Object::Manager::Debug) = (1, 1);
            # This logic should probably just be in the server
            # model, similar to log_scores_csv.

            $self->request->header_out('Access-Control-Allow-Origin' => '*');

            my %relevant_monitors;

            my $history = $server->history($options);
            $history = [
                map {
                    my $h      = $_;
                    my %h      = ();
                    my @fields = qw(offset step score monitor_id);
                    @h{@fields} = map { my $v = $h->$_; defined $v ? $v + 0 : $v } @fields;
                    $h{ts} = $h->ts->epoch;
                    $relevant_monitors{$h{monitor_id}} = 1;
                    \%h;
                } @$history
            ];

            unless (defined $options->{since}) {
                $history = [reverse @$history];
            }

            # if it hasn't changed for a while, cache it for longer
            if (@$history && $history->[-1]->{ts} < time - 86400) {
                $self->cache_control('maxage=28800');
            }

            my $monitors = [grep { $relevant_monitors{$_->{id}} } @{$self->_monitors($server)}];

            return OK,
              encode_json(
                {   history  => $history,
                    monitors => $monitors,
                    server   => {ip => $server->ip}
                }
              ),
              'application/json';
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

sub _monitors {
    my ($self, $server) = @_;
    my $monitors = $server->server_scores;
    $monitors = [
        map {
            my %m = (
                id    => $_->monitor->id + 0,
                score => $_->score + 0,
                name  => $_->monitor->name,
            );
            \%m;
        } @$monitors
    ];
    return $monitors;
}

sub bc_user_class    { NP::Model->user }
sub bc_info_required {'username,email'}


1;
