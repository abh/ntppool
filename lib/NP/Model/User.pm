package NP::Model::User;
use strict;
use Net::IP ();

sub is_staff {
    my $self       = shift;
    my $privileges = $self->privileges;
    return
         $privileges->see_all_servers
      || $privileges->see_all_user_profiles
      || $privileges->support_staff;
}

sub who {
    my $self = shift;
    $self->username || $self->email;
}

sub privileges {
    my $self = shift;
    $self->user_privilege(@_) || $self->user_privilege({user_id => $self->id})->save;
}


package NP::Model::User::Manager;
use strict;

sub admins_to_notify {
    my $class = shift;
    my $ids   = NP::Model->dbh->selectcol_arrayref(
        qq[SELECT DISTINCT u.id
           FROM
             servers s
             JOIN users u ON(s.user_id=u.id)
             LEFT JOIN server_alerts sa ON(sa.server_id=s.id)
           WHERE
             s.score_raw <= ?
              AND s.in_pool = 1
              AND (s.deletion_on IS NULL 
                   OR s.deletion_on > DATE_ADD(NOW(), INTERVAL ? DAY)
                  )
              AND (sa.last_email_time IS NULL
                   OR (DATE_SUB(NOW(), INTERVAL 14 DAY) > sa.last_email_time
                       AND (sa.last_score+10) >= s.score_raw
                      )
                  )
          ORDER BY u.id
        ],
        undef,
        NP::Model::User->BAD_SERVER_THRESHOLD,
        NP::Model::Zone->deletion_grace_days + 2,
    );
    return unless $ids and @$ids;
    $class->get_users(query => [id => $ids]);
}

1;
