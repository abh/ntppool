package NTPPool::Server::LogScore;
use strict;
use base qw(NTPPool::DBI);
use RRDs;
use Class::DBI::AbstractSearch;
use Time::Piece ();
use Time::Piece::MySQL ();

__PACKAGE__->set_up_table('log_scores');
__PACKAGE__->columns(Essential => __PACKAGE__->columns);

__PACKAGE__->has_a('server' => 'NTPPool::Server');

# Class::DBI::mysql uses 'timestamp' in Time::Piece::MySQL which isn't
# working with newer MySQL's (as of version 0.5)
# __PACKAGE__->autoinflate('dates' => 'Time::Piece');
__PACKAGE__->has_a('ts' => 'Time::Piece', 
                     inflate => 'from_mysql_datetime',
                     deflate => 'mysql_datetime',
                  );

#__PACKAGE__->set_sql( last_ok_score => qq {
#    SELECT * from log_scores where score >= 5 and server = ?
#    ORDER BY ts DESC LIMIT 1 
#}); 

__PACKAGE__->add_trigger( after_create => \&update_rrd );

sub delete_server {
    my ($class, $server) = @_;
    #use Data::Dumper::Simple;
    #warn Dumper(\$server);
    my $dbh = $class->dbh;
    $dbh->do(q[delete from log_scores where server=?], {}, $server->id);
}

sub update_rrd {
    my $self = shift;
    my $server = $self->server->id;

    $self->create_rrd;

    # warn join " / ", $self->id, $self->ts; #, $self->ts->epoch;

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
                 "DS:offset:GAUGE:7500:0:86400",
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
