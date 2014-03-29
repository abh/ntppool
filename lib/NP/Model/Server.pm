package NP::Model::Server;
use strict;
use Text::CSV_XS;
use File::Path qw(mkpath);
use Carp qw(croak);
use Net::IP ();
use Combust::Config;

use POSIX qw();
$ENV{TZ} = 'UTC';
POSIX::tzset();

my $config = Combust::Config->new;

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
    my $ls          = $self->add_log_scores({step => 1, score => $start_score, offset => 0});
    my $log_status  = $self->log_status({last_check => 'now', ts_archived => 'now'});
    $self->deletion_on(undef);
    $self->score_raw($start_score);

    my $monitors = NP::Model->monitor->get_objects
      ( query => [ ip_version => $self->ip_version ]
      );

    for my $monitor (@$monitors) {
        $self->add_server_scores(
            {   server_id  => $self->id,
                monitor_id => $monitor->id,
                score_raw  => $self->score_raw,
            }
        );
    }

    $self->save(cascade => 1);
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
    my ($self, $options) = @_;
    ref $options or $options = { count => $options };

    my $count = $options->{count};
    my $since = $options->{since};
    my $monitor_id = $options->{monitor_id};

    $count ||= 50;

    if ($since) {
        $since = DateTime->from_epoch( epoch => $since );
    }

    my $history = NP::Model->log_score->get_log_scores(
        query => [
            server_id => $self->id,
            ($monitor_id && $monitor_id eq '*' ? () : (monitor_id => $monitor_id)),
            ($since ? (ts => {'>' => $since}) : ())
        ],
        sort_by => 'ts ' . ( defined $since ? "" : "desc"),
        limit   => $count,
    );
}

sub alert {
    my $self  = shift;
    return NP::Model->server_alert->fetch_or_create(server => $self);
}

sub note {
    my ($self, $name) = @_;
    my $note = NP::Model->server_note->fetch_or_create(server => $self->id, name => $name);
    return $note;
}

sub mode7check {
    my $self = shift;
    my $mode7 = $self->note('mode7check');
    return unless $mode7->id;
    return $mode7;
}

sub log_scores_csv {
    my ($self, $options) = @_;
    my $history = $self->history($options);
    my $csv = Text::CSV_XS->new();
    $csv->combine(qw(ts_epoch ts offset step score),
                  defined $options->{monitor_id} ? qw(monitor_id monitor_name) : ());
    my $out = $csv->string . "\n";

    my %monitors;

    for my $l (@$history) {

        my $monitor_id;
        my $monitor_name;

        if ($options->{monitor_id}) {
            $monitor_id = $l->monitor_id;
            if ($monitor_id) {
                $monitor_name = defined $monitors{ $monitor_id }
                     ? $monitors{ $monitor_id }
                     : ($monitors{ $monitor_id } = $l->monitor->name || "");
            }
        }

        $csv->combine(
                      $l->ts->epoch, $l->ts->strftime("%F %T"), map ({ $l->$_ } qw(offset step score)),
                      ($options->{monitor_id} ? ($monitor_id, $monitor_name) : ())
                     );
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

sub graph_path {
    my ($self, $name) = @_;
    my $dir  = int( $self->id / 500 ) * 500;
    my $file = $dir . '/' . $self->id . ($name ? "-$name" : "") . ".png";
    return "$rrd_path/graph/" . $file;
}

sub graph_uri {
    my ($self, $name) = @_;
    return unless $name;
    my $path = join "/", "", "graph", $self->ip, "${name}.png";
    if (my $base = $config->site->{ntpgraphs} && $config->base_url('ntpgraphs')) {
        my $uri = URI->new($base);
        $uri->path($path);
        return $uri->as_string;
    }
    else {
        return $path;
    }
}


package NP::Model::Server::Manager;
use strict;

sub find_server {
    my ($class, $arg) = @_;
    my $server;
    $server = $class->fetch(id => $arg) if ($arg =~ m/^\d+$/);
    return $server if $server;

    my $ip = Net::IP->new($arg);
    if ($ip) {
        $server = $class->fetch(ip => $ip->short);
        return $server if $server;
    }

    $server = $class->get_servers(query => [hostname => $arg], sort_by => 'deletion_on')
      unless $server;
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

    my $interval = $monitor->ip_version eq 'v6' ? 10 : 12;

    $class->get_objects_from_sql
      (
       sql => q[SELECT s.*
         FROM servers s
         LEFT JOIN server_scores ss
         ON (s.id=ss.server_id)
         WHERE
           monitor_id = ?
           AND (ss.score_ts IS NULL or ss.score_ts < DATE_SUB( NOW(), INTERVAL ? minute))
           AND s.ip_version = ?
           AND (deletion_on IS NULL or deletion_on > NOW())
         ORDER BY score_ts
         LIMIT ?
       ],
       args => [ $monitor->id, $interval, $monitor->ip_version, $limit ]
      );
}

1;
