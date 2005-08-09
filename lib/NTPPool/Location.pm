package NTPPool::Location;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('locations');
__PACKAGE__->has_a('server' => 'NTPPool::Server');
__PACKAGE__->has_a('zone'   => 'NTPPool::Zone');


1;

