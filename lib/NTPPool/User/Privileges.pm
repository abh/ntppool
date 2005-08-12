package NTPPool::User::Privileges;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('user_privileges');
__PACKAGE__->has_a('user' => 'NTPPool::Admin');

1;
