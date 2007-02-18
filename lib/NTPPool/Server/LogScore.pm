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



1;
