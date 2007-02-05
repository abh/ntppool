package NTPPool::Control::UserProfile;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Apache::Constants qw(OK);

sub uri_username {
    my $self = shift;
    my ($username) = ($self->request->uri =~ m!^/user/([^/]+)!);
    $username || '';
}

sub profile_user {
    my $self = shift;
    return $self->{_profile_user} if $self->{_profile_user};
    my $username = $self->uri_username;
    my ($user) = NTPPool::Admin->search(username => $username);
    ($user) = NTPPool::Admin->search(id => $username) unless $user;
    $self->{_profile_user} = $user;
}

sub user_profile_access {
    my $self = shift;
    return $self->{_user_profile_access} if defined $self->{_user_profile_access};

    return $self->{_user_profile_access} = 1
      if $self->profile_user and $self->profile_user->public_profile;

    return $self->{_user_profile_access} = 1
      if $self->user and $self->user->id == $self->profile_user->id;

    return $self->{_user_profile_access} = 1
      if $self->user 
        and $self->user->privileges
        and $self->user->privileges->see_all_user_profiles;

    return $self->{_user_profile_access} = 0;

}

sub render {
    my $self = shift;

    my $user = $self->profile_user or return 404;
    $self->tpl_param('user' => $user);
    
    return OK, $self->evaluate_template('tpl/user/profile_not_public.html')
      unless $self->user_profile_access;
    return OK, $self->evaluate_template('tpl/user/profile_public.html');
}



1;
