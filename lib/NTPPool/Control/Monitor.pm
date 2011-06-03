package NTPPool::Control::Monitor;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);
use Data::Dump qw(pp);

my $json = JSON::XS->new->pretty;

sub error {
    my ($self, $error) = @_;
    return OK, $json->encode({ error => $error });
}

sub render {
    my $self = shift;

    $self->no_cache(1);

    my $api_key = $self->req_param('api_key')
      or return $self->error('Missing required api_key parameter');

    local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    my $monitor = NP::Model->monitor->fetch(api_key => $api_key);

    if (!$monitor) {
        return $self->error('Not a registered monitor');
    }

    my $ip = $self->request->remote_ip;
    # TODO: check that the current IP is allowed for this monitor

    if ($self->request->method eq 'post') {
        return $self->upload($monitor);
    }

    # go through server array and fetch offset for all servers
    my $servers = NP::Model->server->get_check_due($monitor, 10);

    return OK, $json->encode({ servers => [ map { $_->ip } @$servers ]  }), "application/json";
}

sub post_data {
    my $self    = shift;
    my $request = $self->request;
    return unless $request->method eq 'post';
    my $ct = $request->header_in("Content-Type") or return;
    return unless $ct =~ m!^application/json!;
    my $content = $request->content;
    return $json->decode($content);
}

sub upload {
    my $self = shift;
    my $monitor = shift;

    my $data = $self->post_data;
    warn "got data: ", pp($data);

    #  for each server
    #     calculate score 'step'
    #     begin
    #     - add data to server_scores
    #     - add data to log_scores
    #     - update servers.score_ts, servers.score_raw, servers.stratum, too.
    #     commit
    #

    # return how many server results were saved?
    return OK, $json->encode({ ok => 1 });
}

1;

__END__

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
