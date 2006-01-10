package NTPPool::Admin;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('users');
__PACKAGE__->has_many('servers'  => 'NTPPool::Server');
__PACKAGE__->might_have('privileges' => 'NTPPool::User::Privileges');

my $BAD_THRESHOLD = -20;

__PACKAGE__->set_sql(admins_to_notify => qq{
                     SELECT DISTINCT u.id
                         FROM
                           servers s
                           JOIN users u ON(s.admin=u.id)
                           JOIN scores sc ON(sc.server=s.id)
                           LEFT JOIN server_alerts sa ON(sa.server=s.id)
                         WHERE
                           sc.score <= $BAD_THRESHOLD
                            AND (sa.last_email_time IS NULL
                                 OR (DATE_SUB(NOW(), INTERVAL 14 DAY) > sa.last_email_time
                                     AND (sa.last_score+10) >= sc.score
                                   ) 
                                )
                         ORDER BY s.admin
               });

sub bad_servers {
    my $self = shift;
    grep { $_->score <= $BAD_THRESHOLD } $self->servers
}


1;
