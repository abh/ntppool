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

1;
