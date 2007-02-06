package NTPPool::Zone::Stats;
use strict;
use base qw(NTPPool::DBI);
use Time::Duration qw();
use Time::Piece ();
use Time::Piece::MySQL ();

__PACKAGE__->set_up_table('zone_server_counts');
__PACKAGE__->columns(Essential => __PACKAGE__->columns);
__PACKAGE__->columns(TEMP => qw/today then/);

__PACKAGE__->has_a('zone' => 'NTPPool::Zone');
__PACKAGE__->autoinflate(dates => 'Time::Piece');






1;
