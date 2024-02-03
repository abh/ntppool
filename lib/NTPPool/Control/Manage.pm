package NTPPool::Control::Manage;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);
use Socket qw(inet_ntoa);
use Socket6;
use JSON::XS qw(encode_json decode_json);
use Net::DNS;
use Crypt::JWT qw(decode_jwt);
use LWP::UserAgent qw();
use Mozilla::CA qw();
use Math::BaseCalc qw();
use Math::Random::Secure qw(irand);
use URI::URL ();
use NP::UA;
use OpenTelemetry::Trace;
use OpenTelemetry -all;
use OpenTelemetry::Constants qw( SPAN_KIND_SERVER SPAN_STATUS_ERROR SPAN_STATUS_OK );
use experimental qw( defer );
use Syntax::Keyword::Dynamically;

sub ua { return $NP::UA::ua }

my $base36 = Math::BaseCalc->new(digits => ['a' .. 'k', 'm' .. 'z', 2 .. 9]);

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    $self->cache_control('private');

    $self->tpl_params->{page} ||= {};

    if ($self->is_logged_in) {
        $self->request->env->{REMOTE_USER} = $self->user->username . '|' . $self->user->id_token;

        my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);

        if (my $account = $self->current_account) {
            $self->tpl_param('account' => $account);
            $span->set_attribute("account.id",       $account->id);
            $span->set_attribute("account.id_token", $account->id_token);

            $self->request->env->{REMOTE_USER} .= '|' . $account->id_token;
        }

        if (my $user = $self->user) {
            $span->set_attribute("user.is_staff", $user->is_staff);
            $span->set_attribute("user.email",    $user->email);
            $span->set_attribute("user.username", $user->username);
            $span->set_attribute("user.id",       $user->id);
            $span->set_attribute("user.id_token", $user->id_token);
        }

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
        my $account    = $account_id ? NP::Model->account->fetch(id => $account_id) : undef;
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
        return $self->{_current_account} = $accounts->[0];
    }

    warn "did not find an account for the user?!! -- user id ", $self->user->id;

    return $self->{_current_account} = undef;
}

sub current_url {
    my $self = shift;
    my $args = shift;

    $args = {$self->request->args, $args ? %$args : {}};

    my $here = URI->new($self->config->base_url($self->site) . $self->request->uri);
    $here->query_form($args);

    $here->as_string;
}

sub render {
    my $self = shift;

    unless ($self->request->uri =~ m{^/(manage(/.*)?)?$}) {
        return NOT_FOUND;
    }

    my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);

    # $span->set_name("request manage");
    $span->set_attribute("manage_class", ref $self);

    # this method is shared between the Manage related controllers

    $self->cache_control('private');

    if ($self->request->uri =~ m!^/manage/logout!) {
        $self->set_span_name("manage.logout");
        $self->cookie($self->user_cookie_name, 0);
        $self->cookie("xs",                    0);
        $self->cookie("login_state",           0);
        $self->redirect('/manage');
    }

    $self->tpl_param('xs', $self->cookie('xs'));

    if ($self->request->uri =~ m!^/manage/login!) {
        $self->set_span_name("manage.login");
        if ($self->req_param('code')) {
            $self->handle_login();
        }
        if ($self->user) {
            my $r = $self->req_param('r') || '/manage';
            return $self->redirect($r);
        }

        # if something goes terribly wrong this would just pointlessly
        # and frustratingly loop. It's added so the Auth0 config can have
        # a "default login url" that redirects to the login server /authorize
        # url and we can only have so many .../login urls, right?
        return $self->redirect($self->login_url);
    }

    return $self->login unless ($self->user);

    if ($self->request->method eq 'get') {
        my $account       = $self->current_account;
        my $account_param = $self->req_param('a');
        if (    $account_param
            and $account
            and $account_param ne $account->id_token)
        {
            return $self->redirect($self->current_url({a => $account->id_token}));
        }
    }

    return $self->manage_dispatch;
}

sub handle_login {
    my $self = shift;

    my $span = NP::Tracing->tracer->create_span(
        name => "handle_login",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);

    my $code = $self->req_param('code');
    unless ($code) {
        $span->set_status(SPAN_STATUS_ERROR, "missing code parameter");
        $span->end;
        return;
    }

    my $state = $self->req_param('state');
    unless ($state && $state eq $self->cookie('login_state')) {
        $span->set_status(SPAN_STATUS_ERROR, "invalid state parameter");
        $span->end;
        return;
    }

    # todo: check state variable

    my ($userdata, $error) = $self->_get_auth0_user($code);
    if ($error) {
        warn "Auth0 error: ", Data::Dump::pp(\$error) if $error;
        $span->set_status(SPAN_STATUS_ERROR, "auth0 user error: $error");
        $span->end();
    }

    my ($identity, $user);

    #$userdata = {
    #   map { ($userdata->{$_} ? ($_ => $userdata->{$_}) : () }
    #   qw( sub iat sid iss exp aud user_id identities
    #       email emails email_verified name app_metadata picture
    #       created_at updated_at)
    #};

    # check if profile exists for any of the identities
    my $identity_id = $userdata->{sub};
    my $identity    = NP::Model->user_identity->fetch(profile_id => $identity_id);

    my $email = $userdata->{email_verified} && $userdata->{email};

    my ($provider) = ($identity_id =~ m/^(.*)\|/);

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
            profile_id => $identity_id,
            email      => $email,
            data       => encode_json($userdata),
            provider   => $provider,
            created_on => 'now',
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

    $span->end();

    $self->user($user);
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

    # https://auth0.com/docs/secure/tokens/access-tokens/get-access-tokens
    my %form = (
        'code'          => $self->req_param('code'),
        'client_id'     => $auth0_client,
        'redirect_uri'  => $self->callback_url,
        'client_secret' => $auth0_secret,

        'grant_type' => 'authorization_code',
        'scope'      => 'openid profile name email preferred_username',

        # 'grant_type' => 'client_credentials',
        'audience' => 'api-dev',
    );
    my $resp = $self->ua->post($url, \%form);

    # warn "token request: ", pp(\%form);
    use Data::Dump qw(pp);

    $resp->is_success or return undef, "Could not fetch oauth token";

    my $data = decode_json($resp->decoded_content())
      or return undef, "Could not decode token data";

    warn "token data: ", pp($data);

    #$resp =
    #  $self->ua->get("https://${auth0_domain}/userinfo/?access_token=" . $data->{access_token});
    #$resp->is_success or return undef, "Could not fetch user data";

    my $cache = Combust::Cache->new();

    my $jwt_keys = $cache->fetch(id => "auth0_jwks");
    if ($jwt_keys) {
        $jwt_keys = $jwt_keys->{data};
    }
    else {
        my $resp = ua()->get("https://${auth0_domain}/.well-known/jwks.json");
        unless ($resp->is_success) {
            return undef, "could not fetch jwks";
        }
        $jwt_keys = $resp->decoded_content;
        $cache->store(data => $jwt_keys, expires => 60 * 60 * 4);
    }

    my $jwt_data = decode_jwt(token => $data->{id_token}, kid_keys => $jwt_keys);
    warn "jwt: ", pp($jwt_data);

    $jwt_data or return undef, "Could not decode user data";

    my $user = $jwt_data;

    warn "user data: ", pp($user);

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

    my $state = $self->cookie('login_state');
    unless ($state) {
        $state = (join "", map { $base36->to_base(irand) } (undef) x 6);
        $self->cookie('login_state', $state);
    }

    my ($auth0_domain, $auth0_client, $auth0_secret) = $self->_auth0_config();

 # https://auth0.com/docs/get-started/authentication-and-authorization-flow/add-login-auth-code-flow
 # https://community.auth0.com/t/invalid-access-token-payload-jwt-encrypted-with-a256gcm/77893

    my $login_url = URI->new('https://' . $auth0_domain . "/authorize");
    $login_url->query_form(
        client_id     => $auth0_client,
        redirect_uri  => $self->callback_url,
        response_type => 'code',
        audience      => 'api-dev',
        scope         => 'openid name email profile preferred_username',
        state         => $state,
    );

    use Data::Dump qw(pp);
    warn "login_url: ", $login_url->as_string, pp($login_url);

    return $login_url->as_string;
}

sub manage_dispatch {
    my $self = shift;

    # .../servers and .../account have their own handlers

    if ($self->user->is_staff and $self->request->uri =~ m{/manage/admin/?$}) {
        return $self->show_staff;
    }

    if ($self->request->uri eq "/" or $self->request->uri =~ m{^/manage/?$}) {
        my $account  = $self->current_account;
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

sub account_monitor_count {
    my $self = shift;
    return $self->{_account_monitor_count}
      if defined $self->{_account_monitor_count};

    return $self->{_account_monitor_count} = 0
      unless $self->current_account;    # if we are being invited to a new account

    my $monitor_count =
      NP::Model->monitor->get_objects_count(query => [account_id => $self->current_account->id]);

    return $self->{_account_monitor_count} = $monitor_count;
}

1;
