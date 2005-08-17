package NTPPool::Zone::Stats;
use strict;
use base qw(NTPPool::DBI);
use Time::Duration qw();
use Time::Piece;
use Time::Piece::MySQL;

__PACKAGE__->set_up_table('zone_server_counts');
__PACKAGE__->columns(Essential => __PACKAGE__->columns);
__PACKAGE__->columns(TEMP => qw/today then/);

__PACKAGE__->has_a('zone' => 'NTPPool::Zone');
__PACKAGE__->autoinflate(dates => 'Time::Piece');

__PACKAGE__->set_sql(days_ago => qq{
                                    SELECT __ESSENTIAL__, 
                                    unix_timestamp(date) as `then`,
                                    unix_timestamp(CURDATE()) as today
                                    FROM __TABLE__
                                    WHERE 
                                      zone = ?
                                    AND
                                      date = DATE_SUB(CURDATE(), INTERVAL ? DAY)
                 });


sub ago {
    my $self = shift;
    warn "THEN: ", $self->then;
    warn "NOW : ", $self->today;
    Time::Duration::ago($self->today - $self->then, 2);
}


1;
