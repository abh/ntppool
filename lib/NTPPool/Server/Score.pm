package NTPPool::Server::Score;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('scores');
__PACKAGE__->has_a('server' => 'NTPPool::Server');


1;


