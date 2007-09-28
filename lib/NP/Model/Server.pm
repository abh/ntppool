package NP::Model::Server;
use strict;
use Text::CSV_XS;
use File::Path qw(mkpath);
use Carp qw(croak);
 
sub insert {
    my $self = shift;

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

  my $history = NP::Model->log_score->get_log_scores
      (query   => [ server_id => $self->id ],
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
    "$rrd_path/" . $self->id . ".rrd";
}

sub graph_filename {
    my ($self, $name) = @_;
    $self->id . ($name ? "-$name" : "") . ".png";
}

sub graph_path {
    my $self = shift;
   "$rrd_path/graph/" . $self->graph_filename(@_);
}

sub graph_uri {
    my $self = shift;
    "/scores/graph/" . $self->graph_filename(@_);
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

sub score_graph {
    my ($server, $defaults) = @_;

    my $path = $server->graph_path('score');
    my $rrd  = $server->rrd_path;

    my $title = "Score history for " . $server->ip;

    my @options = (@$defaults,
                   '--height' => 160,
                   '--title'  => $title,
                   '--lower-limit' => -10,
                   '--upper-limit' => 20,
#                   '--alt-autoscale-max',
                   '--slope-mode',
                   qq[DEF:score=$rrd:score:AVERAGE],
                   qq[DEF:step=$rrd:step:AVERAGE],
                   q[CDEF:step_blue=step,1,LT,INF,0,IF],
                   q[CDEF:step_yellow=step,0.6,LT,INF,0,IF],
                   q[CDEF:step_orange=step,-0.9,LT,INF,0,IF],
                   q[CDEF:step_red=step,-3.9,LT,INF,0,IF],
                   q[CDEF:step_white=step,0,EQ,INF,0,IF],

                   qq[AREA:step_blue#9999FF:],
                   qq[AREA:step_yellow#EEEE33:],
                   qq[AREA:step_orange#FFAA22:],
                   qq[AREA:step_red#FF6666:],
                   qq[AREA:step_white#FFFFFF],
                   q[LINE2:5#660000:Bad server cutoff],
                   q[LINE1:20#000000:],
                   qq[LINE2:score#00BB00:Score],
#                   qq[LINE1:step#001100:Step],
                  );

    RRDs::graph($path, @options);
    my $ERROR = RRDs::error();
    if ($ERROR) {
        warn "$0: unable to create '$path': $ERROR\n";
    }
}


sub offset_graph {
    my ($server, $defaults) = @_;

    my $path = $server->graph_path('offset');
    my $rrd  = $server->rrd_path;

    my $title = "Offset history for " . $server->ip;

    my @options = (@$defaults,
                   '--width'  => 420,
                   '--height' => 130,
                   '--title'  => $title,
                   '--alt-autoscale-max',
                    '--slope-mode',
                   #'--logarithmic', # get empty graphs with this enabled
                   #'--no-gridfit',
                   #qq[DEF:score=$rrd:score:AVERAGE],
                   qq[DEF:offset_avg=$rrd:offset:AVERAGE],
                   qq[DEF:offset_top=$rrd:offset:MAX],
                   qq[DEF:offset_bot=$rrd:offset:MIN],
                   
                   q[CDEF:offset_area=offset_top,offset_bot,-],

                   q[LINE1:offset_bot#00FF00:Minimum offset],
                   q[AREA:offset_area#FFBFBF::STACK],  
                   q[LINE1:offset_top#FF0000:Maximum offset],
                   q[LINE1:offset_avg#000000:Offset],
                  );

    RRDs::graph($path, @options);
    my $ERROR = RRDs::error();
    if ($ERROR) {
        warn "$0: unable to create '$path': $ERROR\n";
    }
}





package NP::Model::Server::Manager;
use strict;

sub find_server {
    my ($class, $arg) = @_;
    my $server;
    $server   = $class->fetch(id => $arg) if ($arg =~ m/^\d+$/);
    # TODO: normalize IP properly with Net::IP
    $server   = $class->fetch(ip => $arg) if (!$server and $arg =~ /^[\d.]+$/); 
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
                       AND (sa.first_email_time < DATE_SUB(NOW(), INTERVAL 62 DAY))
                       AND (sa.last_email_time  < DATE_SUB(NOW(), INTERVAL 5 DAY))
                       AND (sa.last_score+10) >= s.score_raw
                  ]
         );
}

sub get_check_due {
    my $class = shift;

    #my ($now, $now24) = NP::Model->dbh->selectrow_array(q[select now(), DATE_SUB( NOW(), INTERVAL 24 minute)]);
    #warn "NOW: $now - NOW24: $now24";

    $class->get_objects_from_sql
      (
       sql => q[SELECT *
                FROM servers
                WHERE
                  score_ts IS NULL or score_ts < DATE_SUB( NOW(), INTERVAL 24 minute)
                  AND (deletion_on IS NULL or deletion_on > NOW())
                ORDER BY score_ts
               ],
       
              );
}


1;
