package NTPPool::Control::Login;
use strict;
use Combust::Constant qw(OK SERVER_ERROR);
use Crypt::Passphrase;
use Crypt::Passphrase::Bcrypt;
use JSON::XS qw(decode_json);
use OpenTelemetry::Trace;
use OpenTelemetry -all;
use OpenTelemetry::Constants qw( SPAN_KIND_SERVER SPAN_STATUS_ERROR SPAN_STATUS_OK );
use experimental             qw( defer );
use Syntax::Keyword::Dynamically;
use NP::CAPI::Account qw(validate_session delete_session);
use NP::CAPI::User    qw(cancel_user_deletion);

my $api_base = $ENV{'api-internal'} || 'http://api-internal';
$api_base =~ s{/$}{};

sub user_cookie_name {
    return 'npuid';
}

sub _get_request_context {
    my $self            = shift;
    my $x_forwarded_for = $self->request->header_in('X-Forwarded-For');
    return $x_forwarded_for ? {x_forwarded_for => $x_forwarded_for} : undef;
}

sub login {
    my $self      = shift;
    my $msg       = shift;
    my $login_url = $self->login_url;

    $self->tpl_param('login_url',    $login_url);
    $self->tpl_param('callback_url', $self->callback_url);
    $self->tpl_param('message',      $msg);

    # form message has been sent, so don't show the form again
    if (($self->req_param('msg') || '') eq 'thanks') {
        $self->tpl_param('msg_thanks', 1);
    }

    return OK, $self->evaluate_template('tpl/login.html');
}

my $crypt = Crypt::Passphrase->new(
    encoder => {
        module => 'Bcrypt',
        cost   => 4,
        hash   => 'sha256',
    },
    validators => ["Argon2"],
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
    my $user;

    if (my $session_cookie = $self->plain_cookie($self->user_cookie_name)) {

        # Validate session using the Go API instead of database
        my $result = validate_session(
            session_token => $session_cookie,
            context       => $self->_get_request_context(),
        );

        if ($result->{code} == 200 && $result->{data} && $result->{data}->{valid}) {
            my $user_data = $result->{data};
            $uid = $user_data->{user_id};

            # Return user data as hashref directly from API response
            # Eliminates database dependency - matches account pattern
            $user = {
                user_id     => $user_data->{user_id},
                id_token    => $user_data->{id_token},
                email       => $user_data->{email},
                username    => $user_data->{username}    || '',
                deletion_on => $user_data->{deletion_on} || '',
                csrf_token  => $user_data->{csrf_token}  || '',

                # Privileges for authorization checks
                privileges => $user_data->{privileges} || {},
            };
        }
        else {
            my $code = $result->{code} || 0;

            # API unavailable (5xx or network error) - preserve session
            if ($code >= 500 || $code == 0) {
                my $trace = $result->{trace_id} ? " trace_id=$result->{trace_id}" : "";
                warn "Session validation failed (API unavailable): ",
                  ($result->{error} || "code=$code"), $trace;
                $self->{_session_error} = SERVER_ERROR;
                return;    # Return undef but DON'T clear cookies
            }

            # Invalid session (4xx) - clear cookies
            warn "Session validation failed: ", ($result->{error} || 'invalid session');
        }
    }

    # Legacy cookie support removed - all sessions must use validate_session API

    # Only clear cookies if no API error (session_error not set)
    unless ($uid && $user) {
        unless ($self->{_session_error}) {
            $self->cookie($self->user_cookie_name, '0');
            $self->plain_cookie($self->user_cookie_name, '', {expires => -1});
        }
        return;
    }

    return $self->{_user} = $user;
}

sub is_logged_in {
    my $self = shift;
    my $user = $self->user;
    return 1 if $user and $user->{user_id};
    return 0;
}

sub session_error {
    my $self = shift;
    return $self->{_session_error};
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

        # Delete session via ConnectRPC
        my $result = delete_session(
            session_token => $session_token,
            context       => $self->_get_request_context(),
        );

        if ($result->{error}) {
            warn "Failed to delete session: $result->{error}";
        }
        elsif ($result->{data} && $result->{data}->{deleted}) {
            warn "session deleted";
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
    my $here =
      URI->new($self->config->base_url($self->site) . $self->request->uri . '?' . $args);
    $here->as_string;
}

sub setup_session {
    my ($self, $user_id) = @_;
    my $resp = $self->ua->post("$api_base/int/session", {user_id => $user_id});
    if ($resp->is_success) {
        my $data = decode_json($resp->decoded_content());
        unless ($data->{session_token}) {
            warn "could not get session key from response";
            return {success => 0, error => "Invalid session response from API"};
        }
        else {
            $self->_set_session_cookie($data->{session_token});

            # Cancel any scheduled deletion (idempotent - safe even if not scheduled)
            # This is part of the account recovery flow - logging in cancels deletion
            # Note: cancel_user_deletion is idempotent and succeeds even if
            # deletion_on is not set. We call it unconditionally on every
            # login to ensure account recovery flow works correctly.
            my $cancel_result = cancel_user_deletion($self->api_auth_params,);

            if ($cancel_result->{error}) {

                # Log warning but don't fail login
                warn "Failed to cancel user deletion on login: "
                  . $cancel_result->{error};
                warn "Trace ID: " . $cancel_result->{trace_id}
                  if $cancel_result->{trace_id};

                # Continue with login despite cancellation failure
            }

            return {success => 1};
        }
    }
    else {
        warn "could not create sesssion: ", $resp->status_line;
        return {
            success => 0,
            error   => "Could not create session: " . $resp->status_line
        };
    }
}

sub _set_session_cookie {
    my ($self, $session_token) = @_;
    my $cookie_value = $session_token . ";" . time;
    $self->plain_cookie(
        $self->user_cookie_name,
        $cookie_value,    # timestamp to make it unique when set again
        {   expires  => time + (90 * 86400),
            samesite => "Lax",
        }
    );
}
1;
