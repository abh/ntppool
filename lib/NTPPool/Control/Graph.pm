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
    my ($server) = $p && NP::Model->server->find_server($p);
    return 404 unless $server;
    return 404 unless $type and $type =~ m!^(offset|score)$!;

    return $self->redirect('/graph/' . $server->ip . "/$type" , 301) unless $p eq $server->ip;

    eval { $gearman->do_task('update_graphs', $server->id, {uniq => 'graphs-' . $server->id}); };

    my $err = $@;
    warn "update_graphs error: $err" if $err;
    my $ttl = $err ? 10 : 1800;
    my $path = $server->graph_path($type);
    open my $fh, $path
      or warn "Could not open $path: $!" and return 403;

    my $mtime = (stat($fh))[9];
    $self->request->update_mtime($mtime);

    $self->cache_control('max-age=1800, s-maxage=900');
    return OK, $fh, 'image/png';

}

1;
