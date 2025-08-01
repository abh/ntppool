package NP::Model::Server;
use strict;
use Text::CSV_XS;
use File::Path qw(mkpath);
use Carp       qw(croak);
use Net::IP    ();
use Combust::Config;

use experimental qw( defer );
use Syntax::Keyword::Dynamically;
use OpenTelemetry::Constants qw( SPAN_KIND_INTERNAL SPAN_STATUS_ERROR SPAN_STATUS_OK );
use OpenTelemetry -all;

use POSIX qw();
$ENV{TZ} = 'UTC';
POSIX::tzset();

my $config = Combust::Config->new;

sub active_score {
    return 10;
}

sub insert {
    my $self = shift;

    my $ip = Net::IP->new($self->ip);
    $self->ip($ip->short);

    $self->join_zone('.');

    $self->SUPER::insert(@_);

    $self->setup_server;
}

sub setup_server {
    my $self = shift;

    my $start_score = 0;
    my $ls = $self->add_log_scores({step => 1, score => $start_score, offset => 0});
    $self->deletion_on(undef);
    $self->score_raw($start_score);

    my $mr = NP::Model->servers_monitor_review->fetch_or_create(
        server_id => $self->id,
        config    => '{}',
    );
    $mr->next_review(DateTime->now()->add(DateTime::Duration->new(minutes => 2)));
    $mr->save();

    my $monitors =
      NP::Model->monitor->get_objects(query => [ip_version => $self->ip_version]);
    for my $monitor (@$monitors) {
        $self->add_server_scores(
            {   server_id  => $self->id,
                monitor_id => $monitor->id,
                score_raw  => $self->score_raw,
                status     => 'candidate',
            }
        );
    }

    $self->save(cascade => 1);
}

sub _resolve_zone {
    my ($zone_name) = @_;
    my $zone =
      ref $zone_name
      ? $zone_name
      : NP::Model->zone->fetch(name => $zone_name);

    unless ($zone) {
        warn "Could not find the zone: $zone_name";
        return;
    }
    $zone;
}

sub join_zone {
    my ($self, $zone_name) = @_;
    my $zone  = _resolve_zone($zone_name) or return;
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
    $zones = [grep { $zone->id != $_->id } @$zones];
    $self->zones($zones);
}

#  local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

sub zones_display {
    my $self  = shift;
    my $zones = [grep { $_->name ne '.' } sort { $a->name cmp $b->name } @{$self->zones}];
    wantarray ? @$zones : $zones;
}

sub deleted {
    my $self = shift;
    $self->deletion_on and $self->deletion_on <= DateTime->today;
}

sub verified {
    my $self = shift;
    my $v    = $self->server_verification;
    return 1 if $v && $v->verified_on;
    return 0;
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

sub manage_url {
    my $self = shift;
    return '/manage/servers#s-' . $self->ip;
}

sub urls {
    my $urls = shift->server_urls;
    return unless $urls and @$urls;
    [map { $_->url } @$urls];
}

sub alert {
    my $self = shift;
    return NP::Model->server_alert->fetch_or_create(server => $self);
}

sub note {
    my ($self, $name) = @_;
    my $note =
      NP::Model->server_note->fetch_or_create(server => $self->id, name => $name);
    return $note;
}


sub monitors {
    my $self   = shift;
    my $cutoff = shift;

    my $span = NP::Tracing->tracer->create_span(
        name => "server.monitors",
        kind => SPAN_KIND_INTERNAL,
    );
    dynamically otel_current_context = otel_context_with_span($span);
    defer { $span->end(); };

    my $monitors = $self->server_scores;

    $monitors = [
        map {
            my %m = (
                id     => $_->monitor->id + 0,
                score  => $_->score + 0,
                name   => $_->monitor->display_name,
                ts     => $_->score_ts,
                status => $_->status,
                type   => $_->monitor->type,
            );
            \%m;
        } @$monitors
    ];

    if ($cutoff) {
        $monitors = [grep { $_->{ts} && $_->{ts} > $cutoff } @{$monitors}];
    }

    $monitors = [
        map {
            if ($_->{ts}) { $_->{ts} = $_->{ts}->iso8601; }
            $_
        } @{$monitors}
    ];

    return $monitors;
}

sub netspeed_human {
    my $self     = shift;
    my $netspeed = $self->netspeed;
    _netspeed_human($netspeed);
}

sub _netspeed_human {
    my $netspeed = shift;

    return ("disabled, monitoring only") if $netspeed == 0;

    return ($netspeed / 1_000_000) . ' Gbit' if ($netspeed / 1_000_000 >= 1);
    return ($netspeed / 1_000) . ' Mbit'     if ($netspeed / 1_000 >= 1);
    return "$netspeed Kbit";
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
    return $server                      if $server;

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
    $class->get_objects_from_sql(
        sql => q[
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
    my $options = shift || {};

    # these numbers make sense for 2-3 monitors, if there are more they
    # should be adjusted to spread out the checks somewhat evenly in
    # time and between the monitors.
    my $interval     = $options->{interval} || 12;
    my $interval_all = $options->{interval} || 4;

    $class->get_objects_from_sql(
        sql => q[SELECT s.*
         FROM servers s
         LEFT JOIN server_scores ss
         ON (s.id=ss.server_id)
         WHERE
           monitor_id = ?
           AND s.ip_version = ?
           AND (ss.score_ts IS NULL
                 OR (ss.score_raw > -90
                       AND ss.score_ts < DATE_SUB( NOW(), INTERVAL ? minute)
                     OR (ss.score_ts < DATE_SUB( NOW(), INTERVAL 65 minute))
                 )
               )
           AND (s.score_ts IS NULL or s.score_ts < DATE_SUB( NOW(), INTERVAL ? minute) )
           AND (deletion_on IS NULL or deletion_on > NOW())
         ORDER BY score_ts
         LIMIT ?
       ],
        args => [$monitor->id, $monitor->ip_version, $interval, $interval_all, $limit]
    );
}

1;
