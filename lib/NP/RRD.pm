package NP::RRD;
use strict;
use warnings;
use RRDs;
use File::Basename qw(dirname);
use base 'Exporter';
our @EXPORT_OK = qw(score_graph offset_graph);

use namespace::clean;

sub score_graph {
    my ($server, $defaults) = @_;

    my $path = $server->graph_path('score');
    my $rrd  = $server->rrd_path;

    _ensure_dir($path);

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
                   q[LINE2:10#660000:Bad server cutoff],
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

    _ensure_dir($path);

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

sub _ensure_dir {
    my $path = shift;
    my $dir = dirname($path);
    unless (-e $dir) {
        mkdir $dir;
    }
}

1;
