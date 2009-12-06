package NP::Model::LogScore;
use strict;
use RRDs;

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

    RRDs::update $self->server->rrd_path,
        (
         '--template' => 'score:step:offset',
         join(":", $self->ts->epoch, 
              $self->score,
              $self->step, 
              (defined $self->offset ? $self->offset : 'U') 
             )
        );

    if (my $ERROR = RRDs::error()) {
        warn "$0: unable to update ",$self->server->rrd_path,": $ERROR\n";
    }
}


sub create_rrd {
    my $self = shift;

    my $path = $self->server->rrd_path;
    return if -e $path;

    my @graph = (
                 "--start", "now-180d", "--step", "15m", # 15 minutes interval
                 "DS:score:GAUGE:7500:-100:20",   # heartbeat of ~2 hours, min value = -100, max = 20
                 "DS:offset:GAUGE:7500:-86400:86400",
                 "DS:step:GAUGE:7500:-10:5",
                 "RRA:AVERAGE:0.5:1:2048",   # 15 minutes, ~20 days
                 "RRA:AVERAGE:0.5:4:1536",   # 1 hour, ~60 days
                 "RRA:AVERAGE:0.5:12:1536",  # 3 hours, ~180 days
                 "RRA:AVERAGE:0.5:96:2048",  # 1 day, ~5 years
                 "RRA:MIN:0.5:4:1536",       
                 "RRA:MAX:0.5:4:1536",       
                 "RRA:MIN:0.5:96:2048",      
                 "RRA:MAX:0.5:96:2048",      
                );
                 

    RRDs::create("$path", @graph);
    my $ERROR = RRDs::error();
    if ($ERROR) {
        die "$0: unable to create '$path': $ERROR\n";
    }
}

1;
