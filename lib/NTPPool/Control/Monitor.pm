package NTPPool::Control::Monitor;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);
use Net::IPv6Addr;

sub render {
    my $self = shift;

    $self->no_cache(1);

    # check api_key, too.

    my $monitor = NP::Model->monitor->fetch(ip => $self->request->remote_ip);
    my $servers;

    if (!$monitor) {
        return 401, "Not a registered monitor";
    }

    if ($self->request->method eq 'POST') {
        return $self->upload($monitor, $1);
    }

    # go through server array and fetch offset for all servers
    my $servers = NP::Model->server->get_check_due($monitor, 10);

    my $json = JSON::XS->new->pretty;

    return OK, $json->encode({ servers => [ map { $_->ip } @$servers ]  }), "text/plain";
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

    my $dbh = NP::Model->dbh;

    # Delete old records from this monitor for the same protocol
    $dbh->do(q[delete m.* from monitor_report m, servers s 
               where m.monitor_id=? and s.id=m.server_id and s.ip_version=?],
	     undef,
	     $monitor->id, $proto);

    warn $stats;
    my @stats = split(/\n/, $stats);
    my $sth = $dbh->prepare(q[INSERT INTO monitor_report(monitor_id, server_id, ts, offset, stratum)
                              SELECT ?, s.id, now(), ?, ? FROM servers s WHERE s.ip=?]);
    for my $line (@stats) {
	my @line = split(/ +/,$line);
	my $res;
	my ($ip, $offset, $stratum);
	if (@line == 3) {
	    ($ip, $offset, $stratum) = @line;
	    $res = $sth->execute($monitor->id, $offset, $stratum, $ip);
	} else {
	    ($ip, $offset) = @line;
	    if ($offset ne "unreachable") {
		return 400, "Invalid line:" . $line;
	    }
	    $res = $sth->execute($monitor->id, undef, undef, $ip);
	}
	if ($res != 1) {
	    return 400, "Failed to update " . $ip;
	}
    }
    $monitor->last_seen(time);
    $monitor->save;
    return OK, "Saved " . ($#stats+1) . " records", "text/plain";
}

1;
