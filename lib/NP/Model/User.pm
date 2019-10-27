package NP::Model::User;
use strict;
use Net::IP ();

sub is_staff {
    my $self       = shift;
    my $privileges = $self->privileges;
    return
         $privileges->see_all_servers
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

sub pending_invites {
    my $user = shift;
    my $invites = NP::Model->account_invite->get_account_invites(
        query => [
            status => {eq => 'pending'},
            or => [
                user_id => $user->id,
                email   => $user->email,
            ],
        ],
        sort_by => 'created_on desc'
    );
    return $invites;
}

package NP::Model::User::Manager;
use strict;

1;
