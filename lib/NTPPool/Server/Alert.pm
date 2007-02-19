package NTPPool::Server::Alert;
use strict;
use base qw(NTPPool::DBI);
use HTTP::Date qw(time2iso);

__PACKAGE__->set_up_table('server_alerts');
__PACKAGE__->add_trigger(before_create => sub{ $_[0]->set(first_email_time => time2iso) } );




1;
