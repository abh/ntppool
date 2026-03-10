package NP::Model::User;
use strict;
use Net::IP ();
use base    qw(NP::Model::TokenID);

sub token_key_config {
    return 'user_id_key';
}

sub insert {
    my $self = shift;
    $self->SUPER::insert(@_);
    $self->insert_token_id();
}

sub is_staff {
    my $self       = shift;
    my $privileges = $self->privileges;
    return $privileges->support_staff;
}

sub is_monitor_admin {
    my $self       = shift;
    my $privileges = $self->privileges;
    return $privileges->monitor_admin;
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
    my $user    = shift;
    my $invites = NP::Model->account_invite->get_account_invites(
        query => [
            status => {eq => 'pending'},
            or     => [
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
