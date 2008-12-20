package NTPPool::Control::Monitor;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);
use Net::IPv6Addr;

sub render {
    my $self = shift;

    $self->r->no_cache(1);

    my $monitor = NP::Model->monitor->fetch(ip => $self->r->connection->remote_ip);
    my $servers;

    if (!$monitor) {
        return 401, "Not a registered monitor";
    }

    if ($self->request->uri =~ m!^/monitor/(v[46])!) {

        my $servers = NP::Model->server->get_servers(
            query => [
                ip_version => $1,
                or         => [
                    deletion_on => undef,                       # not deleted
                    deletion_on => {'gt' => DateTime->today}    # deleted in the future
                ],
            ],
        );

        my $result = "";
        for my $server (@$servers) {
            $result .= $server->ip . "\n";
        }
        return OK, $result, "text/plain";
    }

    return 404;
}

1;
