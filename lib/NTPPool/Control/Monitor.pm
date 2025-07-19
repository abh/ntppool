package NTPPool::Control::Monitor;
use strict;
use parent qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);
use Data::Dump        qw(pp);

my $json = JSON::XS->new->pretty;

sub error {
    my ($self, $error) = @_;
    return OK, $json->encode({error => $error});
}

sub render {
    my $self = shift;
    if ($self->request->path eq '/monitor/map') {

        # todo: move to api service with api token auth
        return $self->render_server_map;
    }

    return NOT_FOUND;
}

sub render_server_map {
    my $self    = shift;
    my $servers = NP::Model->server->get_objects;
    my $now     = DateTime->now;
    my $map     = {
        map {
            my $deleted = ($_->deletion_on and $_->deletion_on < $now) ? 1 : 0;
            (   $_->ip => {
                    ip      => $_->ip,
                    id      => $_->id + 0,
                    deleted => ($deleted ? $JSON::true : $JSON::false),
                    c       => $_->created_on->epoch,
                    ($deleted ? (d => $_->deletion_on->epoch) : ()),
                }
            )
        } @$servers
    };
    $self->cache_control('max-age=900');
    return OK, $json->encode($map);
}

1;
