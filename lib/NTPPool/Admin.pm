package NTPPool::Admin;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('users');
__PACKAGE__->has_many('servers'  => 'NTPPool::Server');
__PACKAGE__->might_have('privileges' => 'NTPPool::User::Privileges');

my $BAD_THRESHOLD = -20;

sub bad_servers {
    my $self = shift;
    grep { $_->score <= $BAD_THRESHOLD } $self->servers
}


1;
