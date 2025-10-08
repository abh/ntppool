# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/account/v1/account.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Account;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use Exporter 'import';

our @EXPORT_OK = qw(
    get_account_status
    process_auth0_login
    validate_session
    delete_session
);

=head1 NAME

NP::CAPI::Account - ConnectRPC client for AccountService

=head1 SYNOPSIS

    use NP::CAPI::Account qw(get_account_status process_auth0_login validate_session delete_session);
    # GetAccountStatus returns the current monitor eligibility and status for an account.
Authentication is handled by middleware - the account is extracted from the session context.
    my $result = get_account_status(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # ProcessAuth0Login handles the Auth0 authorization code callback.
It validates the authorization code with Auth0, creates or updates user and identity records,
creates a session, and returns the session token for cookie storage.
This is an internal-only endpoint called by the Perl frontend after Auth0 redirects.
Authentication: None required (this endpoint creates authentication).
    my $result = process_auth0_login(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # ValidateSession validates a session token and returns user information.
This is called by the Perl frontend on each request to validate the user's session.
Authentication: None required (this endpoint validates the session token itself).
    my $result = validate_session(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # DeleteSession deletes a session by its token.
This is called during logout to invalidate the session.
Authentication: None required (the session token itself authorizes deletion).
    my $result = delete_session(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.account.v1.AccountService.

This module provides Perl wrappers for calling AccountService RPC methods
over HTTP using the ConnectRPC protocol.

=head1 RESPONSE FORMAT

All methods return a hashref with the following structure:

=over 4

=item * B<code> (int)

HTTP status code (e.g., 200 for success, 401 for unauthenticated, 403 for permission denied, 500 for internal errors).

=item * B<status_line> (string)

HTTP status text (e.g., "200 OK", "401 Unauthorized").

=item * B<connect_code> (string or undef)

ConnectRPC error code if the request failed. Possible values include:

    - unauthenticated: No valid authentication provided
    - permission_denied: User lacks required permissions
    - invalid_argument: Request validation failed
    - not_found: Requested resource not found
    - internal: Server-side error occurred
    - unavailable: Service temporarily unavailable

Will be C<undef> for successful requests.

=item * B<data> (hashref or undef)

Response data on success. Contains method-specific fields with the actual response payload.
The structure and available fields vary by method - see each method's documentation below for
the complete list of response fields, their types, and descriptions.

Will be C<undef> if an error occurred.

=item * B<error> (string or undef)

Human-readable error message if the request failed. Will be C<undef> for successful requests.

=item * B<trace_id> (string)

OpenTelemetry trace ID for request tracing and debugging. Include this when reporting issues.

=back

=head2 Error Handling Example

    my $result = some_method(...);

    if ($result->{error}) {
        warn "Request failed: $result->{error}";
        warn "ConnectRPC code: $result->{connect_code}" if $result->{connect_code};
        warn "Trace ID: $result->{trace_id}";
        return;
    }

    # Success - use $result->{data}
    my $data = $result->{data};

=head1 METHODS


=head2 get_account_status

GetAccountStatus returns the current monitor eligibility and status for an account.
Authentication is handled by middleware - the account is extracted from the session context.

B<Arguments:>

    my $result = get_account_status(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            enabled => ...,  # bool - enabled indicates if the account has access to monitor features.
 True if: account has existing monitors, has verified servers for required duration,
 or has the monitor_enabled flag set.
            can_register => ...,  # bool - can_register indicates if the account can register new monitors.
 True if: enabled is true, account hasn't reached monitor limit,
 global limit not reached, and registration not disabled.
            global_limit_reached => ...,  # bool - global_limit_reached indicates if new monitor registration is blocked
 system-wide due to capacity limits. Only present when true.
            server_months => ...,  # int - server_months is the number of months servers must be verified
 before an account becomes eligible for monitors.
            monitor_count => ...,  # int - monitor_count is the current number of active monitors for this account.
            monitor_limit => ...,  # int - monitor_limit is the maximum number of monitors this account can have.
 Default is 3, but can be customized per account.
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account_status(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->id_token,
        context => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_account_status {
    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetAccountStatus',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 process_auth0_login

ProcessAuth0Login handles the Auth0 authorization code callback.
It validates the authorization code with Auth0, creates or updates user and identity records,
creates a session, and returns the session token for cookie storage.
This is an internal-only endpoint called by the Perl frontend after Auth0 redirects.
Authentication: None required (this endpoint creates authentication).

B<Arguments:>

    my $result = process_auth0_login(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        authorization_code => $value,       # string - authorization_code is the code parameter from Auth0's authorization callback.
 Required. This will be exchanged for an access token with Auth0.
        state => $value,       # string - state is the CSRF protection state token from the callback URL.
 Required for logging and validation.
        redirect_uri => $value,       # string - redirect_uri is the callback URL that was used in the original authorization request.
 Must match exactly for Auth0 token exchange. Required.
        client_site => $value,       # string - client_site identifies which site initiated the login (e.g., "manage", "www").
 Used to determine which Auth0 client configuration to use. Required.
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            session_token => ...,  # string - session_token is the session key to set as the npuid cookie.
 Format: "nps_{key}_{checksum}"
            user_id => ...,  # int - user_id is the numeric ID of the authenticated user.
            user_token => ...,  # string - user_token is the user's id_token for identification.
            email => ...,  # string - email is the user's email address from Auth0.
            username => ...,  # string - username is the user's username.
            deletion_cancelled => ...,  # bool - deletion_cancelled indicates if a pending user deletion was cancelled during login.
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = process_auth0_login(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->id_token,
        context => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub process_auth0_login {
    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'authorization_code'} = delete $args{'authorization_code'} if exists $args{'authorization_code'};
    $request{'state'} = delete $args{'state'} if exists $args{'state'};
    $request{'redirect_uri'} = delete $args{'redirect_uri'} if exists $args{'redirect_uri'};
    $request{'client_site'} = delete $args{'client_site'} if exists $args{'client_site'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'ProcessAuth0Login',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 validate_session

ValidateSession validates a session token and returns user information.
This is called by the Perl frontend on each request to validate the user's session.
Authentication: None required (this endpoint validates the session token itself).

B<Arguments:>

    my $result = validate_session(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        session_token => $value,       # string - session_token is the session token from the npuid cookie.
 Format: "nps_{key}_{checksum}" or "nps_{key}_{checksum};{timestamp}"
 Required.
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            valid => ...,  # bool - valid indicates if the session token is valid and active.
            user_id => ...,  # int - user_id is the numeric ID of the authenticated user.
 Only present when valid is true.
            email => ...,  # string - email is the user's email address.
 Only present when valid is true.
            username => ...,  # string - username is the user's username.
 Only present when valid is true.
            user_token => ...,  # string - user_token is the user's id_token for identification.
 Only present when valid is true.
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = validate_session(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->id_token,
        context => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub validate_session {
    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'session_token'} = delete $args{'session_token'} if exists $args{'session_token'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'ValidateSession',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 delete_session

DeleteSession deletes a session by its token.
This is called during logout to invalidate the session.
Authentication: None required (the session token itself authorizes deletion).

B<Arguments:>

    my $result = delete_session(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        session_token => $value,       # string - session_token is the session token to delete.
 Format: "nps_{key}_{checksum}" or "nps_{key}_{checksum};{timestamp}"
 Required.
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            deleted => ...,  # bool - deleted indicates if the session was successfully deleted.
 True if the session existed and was deleted, or if it didn't exist (idempotent).
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = delete_session(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->id_token,
        context => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub delete_session {
    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'session_token'} = delete $args{'session_token'} if exists $args{'session_token'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'DeleteSession',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/account/v1/account.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
