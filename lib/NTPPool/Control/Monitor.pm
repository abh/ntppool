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

	if ($self->r->method eq 'POST') {
	    return $self->upload($monitor, $1);
	}

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

sub upload {
    my $self = shift;
    my $monitor = shift;
    my $proto = shift;
    my $stats = $self->req_param('stats');
    if (!defined($stats)) {
	warn "No stats parameter";
	return 400;
    }
    warn $stats;
    my @stats = split(/\n/, $stats);
    for my $line (@stats) {
	my ($ip, $offset) = split(/ +/,$line);
	my $server = NP::Model->server->fetch(ip => $ip);
	if (!defined($server)) {
	    warn "Bad IP" . $ip;
	    return 400;
	}
	if ($offset eq "unreachable") {
	    undef($offset);
	}
	$server = NP::Model->monitor_report->create(
	    monitor_id => $monitor->id,
	    server_id => $server->id,
	    offset => $offset);
	$server->save;
    }
    return OK, "Saved " . ($#stats+1) . " records", "text/plain";
}

1;
