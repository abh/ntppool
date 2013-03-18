package NTPPool::Control::Graph;
use strict;
use base qw(NTPPool::Control);
use Combust::Constant qw(OK DECLINED);
use Combust::Gearman::Client ();
use NP::Model;

my $gearman = Combust::Gearman::Client->new;

sub render {
    my $self = shift;

    $self->cache_control('s-maxage=1800');

    my ($p, $type) = ($self->request->uri =~ m!^/graph/([^/]+)/(\w+).png!);

    # people breaking the varnish cache by adding query parameters
    if (keys %{$self->request->query_parameters}) {
        return $self->redirect($self->request->uri, 301);
    }

    my ($server) = $p && NP::Model->server->find_server($p);
    return 404 unless $server;
    return 404 unless $type and $type =~ m!^(offset|score)$!;

    # we only have one graph type now
    $type = 'offset';

    return $self->redirect('/graph/' . $server->ip . "/$type" , 301) unless $p eq $server->ip;

    my $graph = eval { $gearman->do_task('update_graphs', $server->id, {uniq => 'graphs-' . $server->id}); };

    my $err = $@ || !$graph;
    warn "update_graphs error: $err" if $err;
    my $ttl = $err ? 10 : 7200;

    my $mtime = time;
    $self->request->update_mtime($mtime);

    $self->cache_control(sprintf('max-age=%i, s-maxage=%i', $ttl, $ttl * 0.75));
    return OK, $graph, 'image/png';
}

1;
