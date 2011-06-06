package NP::Model::Server;
use strict;
use Text::CSV_XS;
use File::Path qw(mkpath);
use Carp qw(croak);
use NP::RRD qw(score_graph offset_graph);
use Net::IP ();

use POSIX qw();
$ENV{TZ} = 'UTC';   
POSIX::tzset();

sub active_score {
    return 10
};
 
sub insert {
    my $self = shift;

    my $ip = Net::IP->new( $self->ip );
    $self->ip($ip->short);

    $self->join_zone('.');

    $self->SUPER::insert(@_);

    $self->setup_server;
}

sub setup_server {
    my $self = shift;

    my $start_score = -5;
    my $ls = $self->add_log_scores({ step => 1, score => $start_score, offset => 0 });
    $self->deletion_on(undef);
    $self->score_raw($start_score);
    $self->save(cascade => 1);
    $self->update_graphs;
}

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

sub zones_display {
    my $self = shift;
    my $zones = [ grep { $_->name ne '.' } sort { $a->name cmp $b->name } @{ $self->zones } ];
    wantarray ? @$zones : $zones;
}

sub deleted {
    my $self = shift;
    $self->deletion_on and $self->deletion_on <= DateTime->today;
}

sub score {
  my $self = shift;
  croak "Can't set 'score' - use 'score_raw'" if @_;
  sprintf "%0.1f", $self->score_raw;
}

sub admin { shift->user(@_) }

sub url {
    my $self = shift;
    return '/scores/' . $self->ip;
}

sub urls {
    my $urls = shift->server_urls;
    return unless $urls and @$urls;
    [ map { $_->url } @$urls ]
}

sub history {
    my ($self, $count) = @_;

    $count ||= 50;

    my $history = NP::Model->log_score->get_log_scores(
        query   => [server_id => $self->id, monitor_id => undef],
        sort_by => 'ts desc',
        limit   => $count,
    );
}

sub score_sparkline_url {
    my $self = shift;
    my $min = 0;
    my $history = $self->history;
    my @d;
    for my $h (@$history) {
        push @d, int($h->score);
        $min = int($h->score) if $h->score < $min;
    }

    my $url = URI->new("http://bitworking.org/projects/sparklines/spark.cgi");
    $url->query_param("limits" => "$min,20");
    $url->query_param("d" => join ",", @d);
    $url->query_param("type" => "smooth");
    $url->query_param("last-m" => 'true');
    $url->as_string;
}

sub alert {
    my $self  = shift;
    return NP::Model->server_alert->fetch_or_create(server => $self);
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


my $rrd_path = "$ENV{CBROOTLOCAL}/rrd/server";
mkpath "$rrd_path/graph/" unless -e "$rrd_path/graph";

sub rrd_path {
    my $self = shift;
    my $monitor_id = shift;
    my $dir  = int( $self->id / 100 ) * 100;
    "$rrd_path/$dir/" . $self->id . ($monitor_id ? "-$monitor_id" : "") . ".rrd";
}

sub graph_path {
    my ($self, $name) = @_;
    my $dir  = int( $self->id / 500 ) * 500;
    my $file = $dir . '/' . $self->id . ($name ? "-$name" : "") . ".png";
    return "$rrd_path/graph/" . $file;
}

sub graph_uri {
    my ($self, $name) = @_;
    return "/scores/graph/" . $self->id . ($name ? "-$name" : "") . ".png";
} 

sub update_graphs {
    my $server = shift;

    # should never happen as we create the rrd when the server object is created
    # return unless -e $server->rrd_path;

    my @defaults = (
                    '--lazy',
                    '--end'    => 'now',
                    '--start'  => 'end-3d',
                    '--width'  => 420,
                    '--height' => 130,
                   );

    offset_graph($server, \@defaults);
    score_graph($server, \@defaults);
}




package NP::Model::Server::Manager;
use strict;

sub find_server {
    my ($class, $arg) = @_;
    my $server;
    $server   = $class->fetch(id => $arg) if ($arg =~ m/^\d+$/);
    # TODO: normalize IP properly with Net::IP
    $server   = $class->fetch(ip => $arg) if (!$server and $arg =~ /^[[:xdigit:].:]+$/);
    return $server if $server;
    $server = $class->get_servers(query => [ hostname => $arg ]) unless $server;
    $server && @$server ? $server->[0] : ();
}

sub get_bad_servers_to_remove {
    my $class = shift;
    $class->get_objects_from_sql
        (sql => q[
                  SELECT s.*
                    FROM
                      servers s
                      LEFT JOIN server_alerts sa ON(sa.server_id=s.id)
                    WHERE
                      s.score_raw < 0
                       AND s.in_pool = 1
                       AND s.deletion_on IS NULL
                       AND (sa.first_email_time < DATE_SUB(NOW(), INTERVAL 45 DAY))
                       AND (sa.last_email_time  < DATE_SUB(NOW(), INTERVAL 5 DAY))
                       AND (sa.last_score+10) >= s.score_raw
                  ]
         );
}

sub get_check_due {
    my $class   = shift;
    my $monitor = shift or return;
    my $limit   = shift || 200;

    # local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    $class->get_objects_from_sql
      (
       sql => q[SELECT s.*
         FROM servers s
         LEFT JOIN server_scores ss
         ON (s.id=ss.server_id)
         WHERE
           monitor_id = ?
           AND (ss.score_ts IS NULL or ss.score_ts < DATE_SUB( NOW(), INTERVAL 24 minute))
           AND s.ip_version = ?
           AND (deletion_on IS NULL or deletion_on > NOW())
         ORDER BY score_ts
         LIMIT ?
       ],
       args => [ $monitor->id, $monitor->ip_version, $limit ]
      );
}

1;
