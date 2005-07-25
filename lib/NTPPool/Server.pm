package NTPPool::Server;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('servers');
__PACKAGE__->has_a('admin' => 'NTPPool::Admin');

# map through the mapping table?
# __PACKAGE__->has_many(zones => 'NTPPool::(Zones|Locations)');


1;
