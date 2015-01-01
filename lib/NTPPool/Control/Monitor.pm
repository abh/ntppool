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

    if ($self->request->path eq '/monitor/map') {
        my $servers = NP::Model->server->get_objects;
        my $now = DateTime->now;
        my $map = {
            map {
                my $deleted = ($_->deletion_on and $_->deletion_on < $now) ? 1 : 0;
                (   $_->ip => {
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

    my $api_key = $self->req_param('api_key')
      or return $self->error('Missing required api_key parameter');

    # local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

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
    my $servers = NP::Model->server->get_check_due($monitor, 50);

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
    #warn "got data: ", pp($data);

    return $self->error('Unknown version') unless $data->{version} and $data->{version} == 1;
    return $self->error('Invalid format') unless ref $data->{servers} eq 'ARRAY';

    my $db = NP::Model->db;

    # local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    my @warnings;

    for my $status ( @{ $data->{servers} } ) {
        my $txn = $db->begin_scoped_work;

        # TODO: Normalize IPv6 IP (or transfer data by ID...)

        my $server_score = NP::Model->server_score->get_server_scores
          (
           query => [
                     'monitor_id' => $monitor->id,
                     'server.ip'  => $status->{server},
                     ],
           require_objects => ['server'],
          );

        $server_score = $server_score && $server_score->[0];
        my $server = $server_score->server;

        unless ($server_score) {
            push @warnings, "No server_score for $status->{server}";
            next;
        }

	my $max_score;
        my $step;
        if (! $status->{stratum} or $status->{no_response}) {
            $step = -5;
        }
        else {
            my $offset_abs = abs($status->{offset});
            if ($offset_abs > 3 or $status->{stratum} >= 8) {
                $step = -4;
		if ($offset_abs > 3) {
		    $max_score = -20;
		}
            }
            elsif ($offset_abs > 0.75) {
                $step = -2;
            }
            elsif ($offset_abs > 0.075) {
                $step = -4 * $offset_abs + 1;
            }
            else {
                $step = 1;
            }
        }
        

        my $ts = DateTime->from_epoch( epoch => $status->{ts} );

        for my $obj ($server_score, $server) {
	    my $new_score = ($obj->score_raw * 0.95) + $step;
	    if (defined $max_score and $new_score > $max_score) {
		$new_score = $max_score;
	    }
            $obj->score_raw($new_score);
            $obj->score_ts($ts);
            $obj->stratum($status->{stratum});
        }

        my %log_score = ( step   => $step,
                          offset => $status->{offset},
                          ts     => int($status->{ts}),
                          attributes => {},
                        );


        $log_score{attributes}->{leap} = $status->{leap}
          if $status->{leap};

        delete $log_score{attributes} unless %{ $log_score{attributes} };

        $server->add_log_scores
          ({   
               %log_score,
               score  => $server->score,
           },
           {   
               %log_score,
               score  => $server_score->score,
               monitor_id => $monitor->id,
           });

        $server_score->save(cascade => 1);

        $db->commit;
    }

    # return how many server results were saved?
    return OK, $json->encode({ ok => 1, warnings => \@warnings });
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
