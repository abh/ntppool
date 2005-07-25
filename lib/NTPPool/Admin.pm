package NTPPool::Admin;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('users');
__PACKAGE__->has_many('servers' => 'NTPPool::Server');


1;
