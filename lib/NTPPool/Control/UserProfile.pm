package NTPPool::Control::UserProfile;
use strict;
use parent qw(NTPPool::Control);
use Combust::Constant qw(OK);
use NP::CAPI::Account qw(get_public_account_by_username);
use NP::CAPI::Server qw(get_account_servers);

sub uri_username {
    my $self = shift;
    my ($username) = ($self->request->uri =~ m!^/user/([^/]+)!);
    $username || '';
}

sub get_redirect_url {
    my $self = shift;
    return $self->{_redirect_url} if exists $self->{_redirect_url};

    my $username = $self->uri_username;
    return $self->{_redirect_url} = undef unless $username;

    my $result = get_public_account_by_username(username => $username);

    if ($result->{error}) {
        warn "GetPublicAccountByUsername failed for '$username': $result->{error}";
        return $self->{_redirect_url} = undef;
    }

    $self->{_redirect_url} = $result->{data}{redirect_url};
    return $self->{_redirect_url};
}

sub account_data {
    my $self       = shift;
    my $url_slug   = shift;

    # Cache the account data per request
    my $cache_key = "_account_data_$url_slug";
    return $self->{$cache_key} if exists $self->{$cache_key};

    # Get auth if user is logged in
    my $auth    = $self->user ? $self->plain_cookie($self->user_cookie_name) : undef;
    my $context = $self->_get_request_context();

    my $result = get_account_servers(
        url_slug => $url_slug,
        auth     => $auth,
        context  => $context,
    );

    return $self->{$cache_key} = $result;
}

sub _get_request_context {
    my $self            = shift;
    my $x_forwarded_for = $self->request->header_in('X-Forwarded-For');
    return $x_forwarded_for ? {x_forwarded_for => $x_forwarded_for} : undef;
}

sub render {
    my $self = shift;
    if ($self->request->uri =~ m{^/user/}) {
        return $self->render_user;
    }
    return $self->render_account;
}

# legacy urls, redirecting to new account pages when possible
sub render_user {
    my $self = shift;
    my $redirect_url = $self->get_redirect_url;
    return 404 unless $redirect_url;
    return $self->redirect($redirect_url);
}

# overridden in the manage version
sub profile_visible {
    my $self    = shift;
    my $account = shift;
    return $account->public_profile;
}

sub render_account {
    my $self = shift;

    my ($account_slug, $extra) = ($self->request->uri =~ m!^/a/([^/]+)(?:/([^/]+))?!);

    unless ($account_slug) {
        $self->cache_control('max-age=60');
        return 404;
    }

    # Fetch account data from CAPI
    my $account_result = $self->account_data($account_slug);

    if ($account_result->{error} || !$account_result->{data}) {
        warn "Failed to fetch account data: " . ($account_result->{error} || 'no data');
        $self->cache_control('max-age=60');
        return 404;
    }

    my $account_data = $account_result->{data}{account};
    my $servers = $account_result->{data}{servers} || [];

    my $req_json = ($extra && $extra eq 'json');

    if ($req_json) {
        $self->cache_control('max-age=240');
        my @servers_json = map {
            +{  ip       => $_->{ip},
                hostname => $_->{hostname} || '',
                score    => $_->{score_raw},
                zones    => [map { $_->{name} } @{$_->{zones} || []}],
                history  => "/scores/$_->{ip}/json",
            }
        } @$servers;

        return 200,
          JSON::XS->new->utf8->encode(
              {   account => {
                      url  => $account_data->{public_url},
                      name => $account_data->{display_name},
                  },
                  servers => \@servers_json
              },
          ),
          "application/json; charset=utf-8";
    }

    $self->cache_control('max-age=300');

    $self->tpl_param('account_data', $account_data);
    $self->tpl_param('servers',      $servers);
    return OK, $self->evaluate_template('tpl/user/profile_public.html');
}

1;
