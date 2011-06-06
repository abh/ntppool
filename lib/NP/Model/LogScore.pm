package NP::Model::LogScore;
use strict;
use RRDs;
use File::Path qw(mkpath);
use File::Basename qw(dirname);

sub save {
    my $self = shift;
    my $rv = $self->SUPER::save(@_);
    $self->update_rrd;
    $rv;
}

sub history_symbol {
  my $self = shift;
  _symbol($self->step);
}

sub history_css_class {
  my $self = shift;
  _css_class($self->step);
}

sub _css_class {
  my $step = shift;
  if    ($step >= 0)  { return 's_his s_his_ok'; }
  elsif ($step >= -1) { return 's_his s_his_tol'; }
  elsif ($step >= -4) { return 's_his s_his_big'; }
  else { return 's_his s_his_down'; }
}

sub _symbol {
  my $step = shift;
  if    ($step >= 0)  { return '#'; }
  elsif ($step >= -1) { return 'x'; }
  elsif ($step >= -4) { return 'o'; }
  else { return '_'; }
}

sub update_rrd {
    my $self = shift;
    my $server = $self->server->id;

    $self->create_rrd;

    #warn join " / ", $self->id, $self->ts; #, $self->ts->epoch;

    RRDs::update $self->rrd_path,
        (
         '--template' => 'score:step:offset',
         join(":", $self->ts->epoch, 
              $self->score,
              $self->step, 
              (defined $self->offset ? $self->offset : 'U') 
             )
        );

    if (my $ERROR = RRDs::error()) {
        warn "$0: unable to update ",$self->rrd_path,": $ERROR\n";
    }
}

sub rrd_path {
    my $self = shift;
    return $self->server->rrd_path( $self->monitor_id );
}

sub create_rrd {
    my $self = shift;

    my $path = $self->rrd_path;
    return if -e $path;

    my $dir = dirname($path);
    mkpath $dir, unless -d $dir;

    my $step = $self->monitor_id ? "20m" : "5m";

    my @ds = (
                 "--start", "now-180d",
                 "--step", $step,
                 "DS:score:GAUGE:3600:-100:20",   # heartbeat of ~2 hours, min value = -100, max = 20
                 "DS:offset:GAUGE:3600:-86400:86400",
                 "DS:step:GAUGE:3600:-10:5",
                 "RRA:AVERAGE:0.3:1:4320",   # 5/20 minutes, 15/60 days
                 "RRA:AVERAGE:0.3:3:3456",   # 15/60 minutes, 36/144 days
                 "RRA:AVERAGE:0.3:12:2304",  # 1/4 hours, 96/384 days
                 "RRA:AVERAGE:0.3:72:2048",  # 1 day, ~5 years
                 "RRA:MIN:0.3:3:3456",
                 "RRA:MIN:0.3:72:2048",
                 "RRA:MAX:0.3:3:3456",,
                 "RRA:MAX:0.3:72:2048",
                 "RRA:LAST:0.3:3:3456",,
                 "RRA:LAST:0.3:72:2048",
                );

    RRDs::create("$path", @ds);
    my $ERROR = RRDs::error();
    if ($ERROR) {
        die "$0: unable to create '$path': $ERROR\n";
    }

}

1;
