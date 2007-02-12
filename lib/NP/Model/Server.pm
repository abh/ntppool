package NP::Model::Server;
use strict;
use Text::CSV_XS;

sub _resolve_zone {
    my ($zone_name) = @_;
    my $zone = ref $zone_name
                 ? $zone_name
                 : NP::Model->zone->fetch(name => $zone_name);

    unless ($zone) {
        warn "Could not find the zone: $zone_name";
        return;
    }
    $zone
}

sub join_zone {
    my ($self, $zone_name) = @_;
    my $zone = _resolve_zone($zone_name) or return;
    my $zones = $self->zones;
    return if grep { $zone->id == $_->id } @$zones;
    push @$zones, $zone;
    $self->zones($zones);
}

sub leave_zone {
    my ($self, $zone_name) = @_;
    my $zone = _resolve_zone($zone_name) or return;
    # TODO: figure out how to do this on the $self object... :-/
    my $zones = $self->zones;
    $zones = [ grep { $zone->id != $_->id } @$zones ];
    $self->zones($zones);
}

#  local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

sub score {
  my $self = shift;
  sprintf "%0.1f", $self->score_raw;
}

sub admin { shift->user(@_) }

sub urls {
    my $urls = shift->server_urls;
    return unless $urls and @$urls;
    [ map { $_->url } @$urls ]
}

sub history {
  my ($self, $count) = @_;

  $count ||= 50;

  my $history = NP::Model->log_score->get_log_scores
      (query   => [ server_id => $self->id ],
       sort_by => 'ts desc',
       limit   => $count,
       );
}

sub log_scores_csv {
    my ($self, $count) = @_;
    my $history = $self->history($count);
    my $csv = Text::CSV_XS->new();
    $csv->combine(qw(ts_epoch ts offset step score));
    my $out = $csv->string . "\n";
    for my $l (@$history) {
        $csv->combine($l->ts->epoch, $l->ts->strftime("%F %T"), map { $l->$_ } qw(offset step score));
        $out .= $csv->string . "\n";
    }
    $out;
}


sub netspeed_human {
  my $self = shift;
  my $netspeed = $self->netspeed;
  _netspeed_human($netspeed);
}

sub _netspeed_human {
  my $netspeed = shift;

  return ($netspeed/1_000_000) . ' Gbit' if ($netspeed / 1_000_000 > 1);
  return ($netspeed/1_000) . ' Mbit' if ($netspeed / 1_000 >= 1);
  return "$netspeed Kbit";
}



package NP::Model::Server::Manager;
use strict;

sub find_server {
    my ($class, $arg) = @_;
    my $server;
    $server   = $class->fetch(id => $arg) if ($arg =~ m/^\d+$/);
    $server   = $class->fetch(ip => $arg) unless $server; 
    return $server if $server;
    $server = $class->get_servers(query => [ hostname => $arg ]) unless $server;
    $server && @$server ? $server->[0] : ();
}

sub get_check_due {
    my $class = shift;

    $class->get_objects_from_sql
      (
       sql => q[SELECT *
                FROM servers
                WHERE
                  score_ts IS NULL or score_ts < DATE_SUB( NOW(), INTERVAL 24 minute)
                ORDER BY score_ts
               ],
       
              );
}


1;
