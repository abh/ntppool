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

sub who {
    my $self = shift;
    $self->username || $self->email;
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
