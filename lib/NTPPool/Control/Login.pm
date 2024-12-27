package NTPPool::Control::Login;
use strict;
use Combust::Constant qw(OK);
use Crypt::Passphrase;
use Crypt::Passphrase::Bcrypt;
use JSON::XS qw(decode_json);
use OpenTelemetry::Trace;
use OpenTelemetry -all;
use OpenTelemetry::Constants qw( SPAN_KIND_SERVER SPAN_STATUS_ERROR SPAN_STATUS_OK );
use experimental             qw( defer );
use Syntax::Keyword::Dynamically;

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

    # form message has been sent, so don't show the form again
    if (($self->req_param('msg') || '') eq 'thanks') {
        $self->tpl_param('msg_thanks', 1);
    }

    return OK, $self->evaluate_template('tpl/login.html');
}

sub bc_user_class { NP::Model->user }

my $crypt = Crypt::Passphrase->new(
    encoder => {
        module => 'Bcrypt',
        cost   => 4,
        hash   => 'sha256',
    }
);

sub user {
    my $self = shift;

    return $self->{_user} if $self->{_user};
    if (@_) { return $self->{_user} = $_[0] }

    # if there's no user cookie, we can't be logged in
    return
      unless $self->plain_cookie($self->user_cookie_name)
      or $self->cookie($self->user_cookie_name);

    my $uid;

    if (my $session_cookie = $self->plain_cookie($self->user_cookie_name)) {
        if (my ($session_key, $checksum) = ($session_cookie =~ m!^nps_([^_]+)_(\d+)(?:;\d+)?$!)) {
            my $sessions = NP::Model->user_session->get_objects(
                query   => [token_lookup => $checksum],
                sort_by => 'last_seen desc',
            );
            for my $session (@$sessions) {
                my $ok = $crypt->verify_password($session_key, $session->token_hashed);
                if ($ok) {
                    $uid = $session->user_id;
                    if (  !$session->last_seen
                        or $session->last_seen < DateTime->now->subtract(hours => 4))
                    {
                        # set the cookie again to update the expires time
                        $session_cookie =~ s/;.*//;    # remove timestamp
                        $self->_set_session_cookie($session_cookie);
                        $session->last_seen(DateTime->now);
                        $session->update;
                    }
                    last;
                }
            }
        }
    }
    else {

        # legacy cookie session support; delete some months after release
        $uid = $self->cookie($self->user_cookie_name);
        warn "legacy session cookie" if $uid;
    }

    unless ($uid) {
        $self->cookie($self->user_cookie_name, '0');
        $self->plain_cookie($self->user_cookie_name, '', {expires => -1});
        return;
    }

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

    $self->cookie($self->user_cookie_name, '0');
    $self->plain_cookie($self->user_cookie_name, '', {expires => -1});
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

    my $span = NP::Tracing->tracer->create_span(
        name => "logout",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);
    defer { $span->end(); };

    $self->cookie($self->user_cookie_name, 0);
    $self->cookie("login_state",           0);
    $self->cookie("xs",                    '');

    my $session_token = $self->plain_cookie($self->user_cookie_name);
    if ($session_token) {
        $self->plain_cookie($self->user_cookie_name, '', {expires => -1});

        # todo: check if there's a current user first to validate
        # the token before deleting it?

        my ($lookup) = ($session_token =~ m/_(\d+)$/);

        if ($lookup) {
            my $resp = $self->ua->delete("http://api-internal/int/session/" . $lookup);
            if ($resp->is_success) {
                warn "session deleted";
            }
        }
    }

    $self->redirect('/manage');

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

sub setup_session {
    my ($self, $user_id) = @_;
    warn "setup_session for $user_id";
    my $resp = $self->ua->post("http://api-internal/int/session", {user_id => $user_id});
    if ($resp->is_success) {
        my $data = decode_json($resp->decoded_content());
        unless ($data->{session_token}) {
            warn "could not get session key from response";
        }
        else {
            $self->_set_session_cookie($data->{session_token});
        }
    }
    else {
        warn "could not create sesssion: ", $resp->status_line;
    }
}

sub _set_session_cookie {
    my ($self, $session_token) = @_;
    $self->plain_cookie(
        $self->user_cookie_name,
        $session_token . ";" . time,    # timestamp to make it unique when set again
        {   expires  => time + (90 * 86400),
            samesite => "Lax",
        }
    );
}
1;
