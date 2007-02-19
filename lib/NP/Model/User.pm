package NP::Model::User;
use strict;

sub who {
    my $self = shift;
    $self->username || $self->email;
}

sub privileges {
    shift->user_privilege(@_);
}

package NP::Model::User::Manager;
use strict;

my $BAD_THRESHOLD = -20;

sub admins_to_notify {
    my $class = shift;
    my $ids = NP::Model->dbh->selectcol_arrayref
      (qq[SELECT DISTINCT u.id
           FROM
             servers s
             JOIN users u ON(s.user_id=u.id)
             LEFT JOIN server_alerts sa ON(sa.server_id=s.id)
           WHERE
             s.score_raw <= $BAD_THRESHOLD
              AND s.in_pool = 1
              AND (sa.last_email_time IS NULL
                   OR (DATE_SUB(NOW(), INTERVAL 14 DAY) > sa.last_email_time
                       AND (sa.last_score+10) >= s.score_raw
                     ) 
                  )
          ORDER BY s.user_id
        ]
        );
    return unless $ids and @$ids;
    $class->get_users
      (query => [ id => $ids ]);
}

1;
