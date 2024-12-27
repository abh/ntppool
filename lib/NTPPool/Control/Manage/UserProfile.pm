package NTPPool::Control::Manage::UserProfile;
use strict;
use NTPPool::Control::Manage;
use NTPPool::Control::UserProfile;
use parent            qw(NTPPool::Control::UserProfile NTPPool::Control::Manage);
use Combust::Constant qw(OK);

sub profile_visible {
    my $self    = shift;
    my $account = shift;
    return $account->public_profile || $self->user->is_staff;
}

1;
