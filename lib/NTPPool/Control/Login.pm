package NTPPool::Control::Login;
use strict;
use Combust::Constant qw(OK);

sub user_cookie_name {
    return 'npuid';
}

sub login {
    my $self      = shift;
    my $msg       = shift;
    my $login_url = $self->login_url;

    my ($auth0_domain, $auth0_client) = $self->_auth0_config();

    $self->tpl_param('auth0_domain', $auth0_domain);
    $self->tpl_param('auth0_client', $auth0_client);
    $self->tpl_param('login_url',    $login_url);
    $self->tpl_param('callback_url', $self->callback_url);
    $self->tpl_param('message',      $msg);

    return OK, $self->evaluate_template('tpl/login.html');
}

sub bc_user_class { NP::Model->user }

sub user {
    my $self = shift;
    return $self->{_user} if $self->{_user};
    if (@_) { return $self->{_user} = $_[0] }

    my $cookie_name = $self->user_cookie_name;
    my $uid         = $self->cookie($cookie_name) or return;

    my $user;
    if ($self->bc_user_class->can('find')) {

        # DBIx::Class
        $user = $self->bc_user_class->find($uid);
    }
    elsif ($self->bc_user_class->can('fetch')) {

        # RDBO with combust helpers
        $user = $self->bc_user_class->fetch(id => $uid);
    }

    return $self->{_user} = $user if $user;
    $self->cookie($cookie_name, '0');
    return;
}

sub is_logged_in {
    my $self = shift;
    my $user = $self->user;
    return 1 if $user and $user->id;
    return 0;
}

sub logout {
    my $self = shift;
    my $uri  = shift || '/';
    $self->cookie($self->user_cookie_name, 0);
    $self->no_cache(1);
    $self->user(undef);

    $uri = $self->config->base_url($self->site) . $uri
      unless $uri =~ m!^https?://!i;

    return $self->redirect($uri);
}

sub _here_url {
    my $self = shift;
    my $args = $self->request->args || '';
    my $here = URI->new($self->config->base_url($self->site) . $self->request->uri . '?' . $args);
    $here->as_string;
}

1;
