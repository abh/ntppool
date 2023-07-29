package NTPPool::Control::UserProfile;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK);

sub uri_username {
    my $self = shift;
    my ($username) = ($self->request->uri =~ m!^/user/([^/]+)!);
    $username || '';
}

sub profile_user {
    my $self = shift;
    return $self->{_profile_user} if $self->{_profile_user};
    my $username = $self->uri_username;
    my $user     = NP::Model->user->get_users(query => [username => $username]);
    $user                  = $user && $user->[0];
    $user                  = NP::Model->user->fetch(id => $username) unless $user;
    $self->{_profile_user} = $user;
}

sub profile_account {
    my $self = shift;
    return $self->{_profile_account} if $self->{_profile_account};
    my ($account_name, $extra) = ($self->request->uri =~ m!^/a/([^/]+)(?:/([^/]+))?!);
    return unless $account_name;
    my $account = NP::Model->account->fetch(url_slug => $account_name);
    $self->{_profile_account} = $account;
    return ($account, $extra);
}

sub render {
    my $self = shift;
    if ($self->request->uri =~ m{^/user/}) {
        return $self->render_user;
    }
    return $self->render_account;
}

sub render_user {
    my $self = shift;

    my $user = $self->profile_user;
    return 404 unless $user and $user->public_profile;

    my $accounts = $user->accounts;
    my ($account) = sort { $a->id <=> $b->id } grep { $_->public_profile } @$accounts;

    return 404 unless $account;
    return $self->redirect($account->public_url);
}

sub render_account {
    my $self = shift;

    my ($account, $extra) = $self->profile_account;

    unless ($account && $account->public_profile) {
        $self->cache_control('max-age=30');
        return 404;
    }

    my $req_json = ($extra && $extra eq 'json');

    if ($req_json) {
        $self->cache_control('max-age=240');
        my @servers = map {
            +{  ip       => $_->ip,
                hostname => $_->hostname,
                score    => $_->score_raw,
                zones    => [map { $_->name } $_->zones_display],
                history  => $_->url + "/json",
            }
        } $account->servers;

        return 200,
          JSON::XS->new->utf8->encode(
              {   account => {
                      url  => $account->public_url,
                      name => ($account->organization_name || $account->name || $account->id_token),
                  },
                  servers => \@servers
              },
          ),
          "application/json; charset=utf-8";
    }

    $self->cache_control('max-age=300');

    $self->tpl_param('account', $account);
    return OK, $self->evaluate_template('tpl/user/profile_public.html');
}

1;
