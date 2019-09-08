package NTPPool::Control::Manage;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);
use Socket qw(inet_ntoa);
use Socket6;
use JSON::XS qw(encode_json decode_json);
use Net::DNS;
use Net::OAuth2::Profile::WebServer;
use LWP::UserAgent qw();
use Mozilla::CA qw();
use Math::BaseCalc qw();
use Math::Random::Secure qw(irand);
use URI::URL ();
use URI::QueryParam;


my $ua = LWP::UserAgent->new(
    timeout  => 2,
    ssl_opts => {
        SSL_verify_mode => 0x02,
        SSL_ca_file     => Mozilla::CA::SSL_ca_file()
    }
);
sub ua { return $ua }

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    $self->tpl_params->{page} ||= {};

    if ($self->is_logged_in) {
        $self->request->env->{REMOTE_USER} = $self->user->username;
        $self->tpl_param('account' => $self->current_account);
    }

    return OK;
}

sub current_account {
    my $self = shift;

    if (exists $self->{_current_account}) {
        return $self->{_current_account};
    }

    if (my $account_token = $self->req_param('a')) {
        my $account_id = NP::Model::Account->token_id($account_token);
        my $account = $account_id ? NP::Model->account->fetch(id => $account_id) : undef;
        if ($account) {
            return $self->{_current_account} = $account
                if $account->can_edit($self->user);
        }
    }

    my ($accounts) = NP::Model->account->get_accounts(
        require_objects => ['users'],
        query           => ['users.id' => $self->user->id]
    );

    if ($accounts && @$accounts) {
        warn "got fallback account id ", $accounts->[0]->id;
        return $self->{_current_account} = $accounts->[0];
    }
    return $self->{_current_account} = undef;
}

sub current_url {
    my $self = shift;
    my $args = shift;

    $args = { $self->request->args, $args ? %$args : {} };

    my $here = URI->new($self->config->base_url($self->site)
                      . $self->request->uri
                      );
    $here->query_form($args);

    $here->as_string;
}


sub render {
    my $self = shift;

    # this method is shared between the Manage related controllers

    $self->cache_control('private');

    if ($self->request->uri =~ m!^/manage/logout!) {
        $self->cookie($self->user_cookie_name, 0);
        $self->cookie("xs",                    0);
        $self->redirect('/manage');
    }

    $self->tpl_param('xs', $self->cookie('xs'));

    if ($self->request->uri =~ m!^/manage/login!) {

        if (my $code = $self->req_param('code')) {
            my ($userdata, $error) = $self->_get_auth0_user($code);
            if ($error) {
                warn "auth0 user error: $error";
                return $self->login($error);
            }
            warn "Error: ", Data::Dump::pp(\$error);

            my ($identity, $user);

            # check if profile exists for any of the identities
            for my $identity_id ($userdata->{user_id},
                map { join "|", $_->{provider}, $_->{user_id} } @{$userdata->{identities}})
            {
                warn "Identity id: '$identity_id'";
                $identity = NP::Model->user_identity->fetch(profile_id => $identity_id);
                last if $identity;
            }

            my $email = $userdata->{email_verified} && $userdata->{email};
            my $provider =
                 $userdata->{identities}
              && $userdata->{identities}->[0]
              && $userdata->{identities}->[0]->{provider};

            if ($identity) {
                $identity->provider($provider) if $provider;
                $identity->data(encode_json($userdata));
            }
            else {
                warn "Didn't find identity in the database";

                if (!$email) {
                    return $self->login("Email not verified");
                }

                $identity = NP::Model->user_identity->create(
                    profile_id => $userdata->{user_id},
                    email      => $email,
                    data       => encode_json($userdata),
                    provider   => $provider,
                );

                # look for an account with a verified email address we
                # can recognize.
                my %uniq;
                my @emails =
                  map { $_->{profileData}->{email} }
                  grep {
                    my $p = $_->{profileData};
                    my $ok =
                         $p
                      && $p->{email}
                      && $p->{email_verified}
                      && !$uniq{$p->{email}}++;
                    $ok;
                  } ({profileData => $userdata}, @{$userdata->{identities}});

                for my $email (@emails) {
                    warn "Testing email: $email";
                    my ($email_user) = NP::Model->user->fetch(email => $email);
                    if ($email_user) {
                        warn "Found email user in the database";
                        $user = $email_user;
                        last;
                    }
                }
            }

            # we do this outside the identity check just in case for
            # some reason we have an identity without a user
            # associated.

            $user = $user || $identity->user;

            my $base36 = Math::BaseCalc->new(digits => ['a' .. 'k', 'm' .. 'z', 2 .. 9]);
            if (!$user) {
                my $username = join "", map { $base36->to_base(irand) } (undef) x 3;
                $user = NP::Model->user->create(
                    email    => $identity->email,
                    name     => $userdata->{name},
                    username => $username,
                );
                $user->save;
            }

            if ($identity->user_id != $user->id) {
                $identity->user_id($user->id);
            }

            $identity->save;

            $self->cookie("xs", join "", map { $base36->to_base(irand) } (undef) x 6);
            $self->cookie($self->user_cookie_name, $user->id);
            $self->user($user);

            my $r = $self->req_param('r') || '/manage';
            return $self->redirect($r);
        }

    }

    return $self->login unless $self->user;

    if ($self->request->method eq 'get') {
        my $account = $self->current_account;
        my $account_param = $self->req_param('a');
        if ($account_param and $account_param ne $account->id_token) {
            return $self->redirect($self->current_url({a => $account->id_token}));
        }
    }

    return $self->manage_dispatch;
}

sub _auth0_config {
    my $self = shift;

    return @{$self->{_auth0_config}} if $self->{_auth0_config};

    my $site = $self->site;

    my $auth0_domain = $self->config->site->{$site}->{auth0_domain}
      or die "auth0_domain not configured for site $site";

    my $auth0_client = $self->config->site->{$site}->{auth0_client}
      or die "auth0_client not configured for site $site";

    my $auth0_secret = $self->config->site->{$site}->{auth0_secret}
      or die "auth0_secret not configured for site $site";

    $self->{_auth0_config} = [$auth0_domain, $auth0_client, $auth0_secret];

    return @{$self->{_auth0_config}};
}

sub _get_auth0_user {
    my ($self, $code) = @_;

    # https://auth0.com/docs/protocols#3-getting-the-access-token

    my ($auth0_domain, $auth0_client, $auth0_secret) = $self->_auth0_config();

    my $url = URI->new("https://${auth0_domain}/oauth/token");

    my %form = (
        'code'          => $self->req_param('code'),
        'client_id'     => $auth0_client,
        'redirect_uri'  => $self->callback_url,
        'client_secret' => $auth0_secret,
        'grant_type'    => 'authorization_code',
    );
    my $resp = $self->ua->post($url, \%form);
    use Data::Dump qw(pp);
    pp($resp);

    $resp->is_success or return undef, "Could not fetch oauth token";

    my $data = decode_json($resp->decoded_content())
      or return undef, "Could not decode token data";

    $resp = $self->ua->get("https://${auth0_domain}/userinfo/?access_token=" . $data->{access_token});
    $resp->is_success or return undef, "Could not fetch user data";

    my $user = decode_json($resp->decoded_content())
      or return undef, "Could not decode user data";

    return $user, undef;

}

sub callback_url {
    my $self = shift;

    my $uri = URI->new($self->config->base_url($self->site));
    $uri->path('/manage/login');

    my $here = $self->_here_url;
    if ($here =~ m{manage/login}) {
        $here = "/manage";
    }

    $uri->query_form(r => $here);
    $uri->as_string();
}

sub login_url {
    my $self = shift;

    my ($auth0_domain, $auth0_client, $auth0_secret) = $self->_auth0_config();

    my $auth = Net::OAuth2::Profile::WebServer->new(
        name              => 'NTP Pool Login',
        client_id         => $auth0_client,
        client_secret     => $auth0_secret,
        site              => 'https://' + $auth0_domain,
        authorize_path    => '/authorize',
        access_token_path => '/token',
        scope             => 'openid email',
        redirect_uri      => $self->callback_url,
    );

    warn "AUTH RESP TEST: ", $auth->authorize_response->as_string();

    return "https://" . $auth0_domain . $auth->authorize;
}

sub manage_dispatch {
    my $self = shift;

    # .../servers and .../account have their own handlers

    if ($self->user->is_staff and $self->request->uri =~ m{/manage/admin/?$}) {
        return $self->show_staff;
    }

    if ($self->request->uri =~ m{^/manage/?$}) {
        my $account = $self->current_account;
        my $redirect = URI->new('/manage/servers');
        $redirect->query_param(a => $account->id_token) if $account;
        return $self->redirect($redirect);
    }

    return 404;
}

sub show_staff {
    my $self = shift;
    $self->tpl_params->{page}->{is_admin} = 1;
    return OK, $self->evaluate_template('tpl/staff.html');
}


1;
