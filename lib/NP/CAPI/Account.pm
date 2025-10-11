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
    create_account
    update_account
    remove_user_from_account
    create_user_task
    get_account_server_verification_status
    get_accounts_to_notify
    get_account_users
    get_user_accounts
    get_account_invites
    get_account
);

=head1 NAME

NP::CAPI::Account - ConnectRPC client for AccountService

=head1 SYNOPSIS

    use NP::CAPI::Account qw(get_account_status process_auth0_login validate_session delete_session create_account update_account remove_user_from_account create_user_task get_account_server_verification_status get_accounts_to_notify get_account_users get_user_accounts get_account_invites get_account);
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

    # CreateAccount creates a new account for the authenticated user.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: None required for own account creation.
    my $result = create_account(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # UpdateAccount updates account fields.
Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).
Authorization: User must have edit access (see permission model).
    my $result = update_account(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # RemoveUserFromAccount removes a user from an account.
Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).
Authorization: User must have edit access and cannot remove themselves.
    my $result = remove_user_from_account(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # CreateUserTask creates a user task (download, delete, etc.).
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only create tasks for themselves.
    my $result = create_user_task(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # GetAccountServerVerificationStatus returns server verification counts for an account.
Used to determine if account can add new servers (blocks if 2+ unverified servers).
Authentication: Required via session middleware (sessions.GetAccount).
    my $result = get_account_server_verification_status(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # GetAccountsToNotify returns account IDs that need server alert notifications.
Finds accounts with servers scoring below threshold that haven't been notified recently.
Authentication: Admin only.
    my $result = get_accounts_to_notify(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # GetAccountUsers returns the list of users in an account.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have access to the account.
    my $result = get_account_users(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # GetUserAccounts returns the list of accounts for the authenticated user.
Authentication: Required via session middleware (sessions.GetUser).
    my $result = get_user_accounts(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # GetAccountInvites returns pending invites for an account or user.
Authentication: Required via session middleware.
Authorization: Can view invites sent to you or for accounts you manage.
    my $result = get_account_invites(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # GetAccount returns full account information.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have access to the account.
    my $result = get_account(
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


=head2 create_account

CreateAccount creates a new account for the authenticated user.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: None required for own account creation.

B<Arguments:>

    my $result = create_account(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        name => $value,       # string - name is the account name (required, 1-255 chars, trimmed)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            account => {
                account_id => ...,  # int - account_id is the numeric ID of the account
                account_token => ...,  # string - account_token is the id_token for the account
                name => ...,  # string - name is the account name
                organization_name => ...,  # string - organization_name is the organization name (if set)
                organization_url => ...,  # string - organization_url is the organization URL (if set)
                public_profile => ...,  # bool - public_profile indicates if the account profile is public
                url_slug => ...,  # string - url_slug is the URL slug for the account (if set)
                flags => ...,  # string - flags is the JSON flags configuration for the account
                created_on => ...,  # string - created_on is when the account was created (RFC3339 format)
                modified_on => ...,  # string - modified_on is when the account was last modified (RFC3339 format)
            },  # hashref (Account) - account is the complete account object
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<account> (hashref (Account))

account is the complete account object


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = create_account(
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

sub create_account {
    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'name'} = delete $args{'name'} if exists $args{'name'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'CreateAccount',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 update_account

UpdateAccount updates account fields.
Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).
Authorization: User must have edit access (see permission model).

B<Arguments:>

    my $result = update_account(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        name => $value,       # string - Fields to update (only provided fields are updated)
 If a field is not set in the request, it remains unchanged
        organization_name => $value,       # string
        organization_url => $value,       # string
        url_slug => $value,       # string
        public_profile => $value,       # bool
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool - success indicates if the update was successful
            account => {
                account_id => ...,  # int - account_id is the numeric ID of the account
                account_token => ...,  # string - account_token is the id_token for the account
                name => ...,  # string - name is the account name
                organization_name => ...,  # string - organization_name is the organization name (if set)
                organization_url => ...,  # string - organization_url is the organization URL (if set)
                public_profile => ...,  # bool - public_profile indicates if the account profile is public
                url_slug => ...,  # string - url_slug is the URL slug for the account (if set)
                flags => ...,  # string - flags is the JSON flags configuration for the account
                created_on => ...,  # string - created_on is when the account was created (RFC3339 format)
                modified_on => ...,  # string - modified_on is when the account was last modified (RFC3339 format)
            },  # hashref (Account) - account is the updated account object
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<success> (bool)

success indicates if the update was successful


=item * B<account> (hashref (Account))

account is the updated account object


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = update_account(
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

sub update_account {
    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'name'} = delete $args{'name'} if exists $args{'name'};
    $request{'organization_name'} = delete $args{'organization_name'} if exists $args{'organization_name'};
    $request{'organization_url'} = delete $args{'organization_url'} if exists $args{'organization_url'};
    $request{'url_slug'} = delete $args{'url_slug'} if exists $args{'url_slug'};
    $request{'public_profile'} = delete $args{'public_profile'} if exists $args{'public_profile'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'UpdateAccount',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 remove_user_from_account

RemoveUserFromAccount removes a user from an account.
Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).
Authorization: User must have edit access and cannot remove themselves.

B<Arguments:>

    my $result = remove_user_from_account(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        user_token => $value,       # string - user_token is the id_token of the user to remove (NOT numeric user_id)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool - success indicates if the removal was successful
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = remove_user_from_account(
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

sub remove_user_from_account {
    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'user_token'} = delete $args{'user_token'} if exists $args{'user_token'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'RemoveUserFromAccount',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 create_user_task

CreateUserTask creates a user task (download, delete, etc.).
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only create tasks for themselves.

B<Arguments:>

    my $result = create_user_task(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        task_type => $value,       # string - task_type is the type of task (e.g., "download", "delete")
        status => $value,       # string - status is the initial status (usually empty string for pending)
        execute_on_unix => $value,       # int - execute_on_unix is when the task should be executed (optional, Unix timestamp)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            task_id => ...,  # int - task_id is the ID of the created task
            traceid => ...,  # string - traceid links this task to trace logs for async processing
 Used by background workers to correlate task execution with original request
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = create_user_task(
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

sub create_user_task {
    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'task_type'} = delete $args{'task_type'} if exists $args{'task_type'};
    $request{'status'} = delete $args{'status'} if exists $args{'status'};
    $request{'execute_on_unix'} = delete $args{'execute_on_unix'} if exists $args{'execute_on_unix'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'CreateUserTask',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_account_server_verification_status

GetAccountServerVerificationStatus returns server verification counts for an account.
Used to determine if account can add new servers (blocks if 2+ unverified servers).
Authentication: Required via session middleware (sessions.GetAccount).

B<Arguments:>

    my $result = get_account_server_verification_status(
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
            verified_count => ...,  # int - verified_count is the number of servers with verified_on set
            unverified_count => ...,  # int - unverified_count is the number of servers without verified_on
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account_server_verification_status(
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

sub get_account_server_verification_status {
    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetAccountServerVerificationStatus',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_accounts_to_notify

GetAccountsToNotify returns account IDs that need server alert notifications.
Finds accounts with servers scoring below threshold that haven't been notified recently.
Authentication: Admin only.

B<Arguments:>

    my $result = get_accounts_to_notify(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        score_threshold => $value,       # int - score_threshold is the score below which servers trigger notifications (default: -10)
        grace_period_days => $value,       # int - grace_period_days is how many days after deletion_on to still notify (default: 14)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            account_ids => [...]  # arrayref[int],  # arrayref[int] - account_ids is the list of account IDs with servers needing alerts
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<account_ids> (arrayref[int])

account_ids is the list of account IDs with servers needing alerts


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_accounts_to_notify(
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

sub get_accounts_to_notify {
    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'score_threshold'} = delete $args{'score_threshold'} if exists $args{'score_threshold'};
    $request{'grace_period_days'} = delete $args{'grace_period_days'} if exists $args{'grace_period_days'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetAccountsToNotify',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_account_users

GetAccountUsers returns the list of users in an account.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have access to the account.

B<Arguments:>

    my $result = get_account_users(
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
            users => [
            {
                user_id => ...,  # int - user_id is the numeric ID of the user
                user_token => ...,  # string - user_token is the id_token for the user
                email => ...,  # string - email is the user's email address
                username => ...,  # string - username is the user's username
                public_profile => ...,  # bool - public_profile indicates if the user profile is public
                deletion_on => ...,  # string - deletion_on is when the user is scheduled for deletion (if set)
            },
            # ... more items
        ],  # arrayref[hashref (AccountUser)] - users is the list of users in the account
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<users> (arrayref[hashref (AccountUser)])

users is the list of users in the account


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account_users(
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

sub get_account_users {
    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetAccountUsers',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_user_accounts

GetUserAccounts returns the list of accounts for the authenticated user.
Authentication: Required via session middleware (sessions.GetUser).

B<Arguments:>

    my $result = get_user_accounts(
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
            accounts => [
            {
                account_id => ...,  # int - account_id is the numeric ID of the account
                account_token => ...,  # string - account_token is the id_token for the account
                name => ...,  # string - name is the account name
                organization_name => ...,  # string - organization_name is the organization name (if set)
                organization_url => ...,  # string - organization_url is the organization URL (if set)
                public_profile => ...,  # bool - public_profile indicates if the account profile is public
                url_slug => ...,  # string - url_slug is the URL slug for the account (if set)
            },
            # ... more items
        ],  # arrayref[hashref (UserAccount)] - accounts is the list of accounts the user belongs to
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<accounts> (arrayref[hashref (UserAccount)])

accounts is the list of accounts the user belongs to


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_user_accounts(
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

sub get_user_accounts {
    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetUserAccounts',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_account_invites

GetAccountInvites returns pending invites for an account or user.
Authentication: Required via session middleware.
Authorization: Can view invites sent to you or for accounts you manage.

B<Arguments:>

    my $result = get_account_invites(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        for_user => $value,       # bool - for_user when true, returns invites sent to the authenticated user
 When false (default), returns invites for the authenticated account
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            invites => [
            {
                invite_id => ...,  # int - invite_id is the numeric ID of the invite
                account_id => ...,  # int - account_id is the ID of the account being invited to
                email => ...,  # string - email is the email address invited
                status => ...,  # string - status is the invite status (pending, accepted, expired)
                code => ...,  # string - code is the invitation code (only for pending invites)
                expires_on => ...,  # string - expires_on is when the invite expires
                created_on => ...,  # string - created_on is when the invite was created
            },
            # ... more items
        ],  # arrayref[hashref (AccountInvite)] - invites is the list of account invitations
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<invites> (arrayref[hashref (AccountInvite)])

invites is the list of account invitations


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account_invites(
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

sub get_account_invites {
    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'for_user'} = delete $args{'for_user'} if exists $args{'for_user'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetAccountInvites',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_account

GetAccount returns full account information.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have access to the account.

B<Arguments:>

    my $result = get_account(
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
            account => {
                account_id => ...,  # int - account_id is the numeric ID of the account
                account_token => ...,  # string - account_token is the id_token for the account
                name => ...,  # string - name is the account name
                organization_name => ...,  # string - organization_name is the organization name (if set)
                organization_url => ...,  # string - organization_url is the organization URL (if set)
                public_profile => ...,  # bool - public_profile indicates if the account profile is public
                url_slug => ...,  # string - url_slug is the URL slug for the account (if set)
                flags => ...,  # string - flags is the JSON flags configuration for the account
                created_on => ...,  # string - created_on is when the account was created (RFC3339 format)
                modified_on => ...,  # string - modified_on is when the account was last modified (RFC3339 format)
            },  # hashref (Account) - account is the complete account object
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<account> (hashref (Account))

account is the complete account object


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account(
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

sub get_account {
    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetAccount',
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
