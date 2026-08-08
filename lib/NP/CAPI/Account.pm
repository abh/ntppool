# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/account/v1/account.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Account;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    get_account_status
    validate_session
    delete_session
    create_account
    update_account
    remove_user_from_account
    create_user_task
    list_user_tasks
    get_user_task
    get_account_server_verification_status
    get_accounts_to_notify
    get_account_users
    get_user_accounts
    get_account_invites
    create_account_invite
    accept_account_invite
    resend_account_invite
    get_account
    update_account_monitor_config
    can_delete_account
    schedule_account_deletion
    cancel_account_deletion
    check_user_deletion_eligibility
    get_public_account_by_username
    get_related_accounts
    who_am_i
    BASIC
    WITH_PERMISSIONS
    MANAGEMENT
    TEAM
    DELETION_CHECK
    AUTH_TYPE_UNSPECIFIED
    AUTH_TYPE_SESSION
    AUTH_TYPE_USER_API_KEY
    AUTH_TYPE_ACCOUNT_API_KEY
    AUTH_TYPE_MONITOR_API_KEY
    AUTH_TYPE_SERVICE
);

# Enum constants
use constant {
    BASIC => 'BASIC',
    WITH_PERMISSIONS => 'WITH_PERMISSIONS',
    MANAGEMENT => 'MANAGEMENT',
    TEAM => 'TEAM',
    DELETION_CHECK => 'DELETION_CHECK',
};
use constant {
    AUTH_TYPE_UNSPECIFIED => 'AUTH_TYPE_UNSPECIFIED',
    AUTH_TYPE_SESSION => 'AUTH_TYPE_SESSION',
    AUTH_TYPE_USER_API_KEY => 'AUTH_TYPE_USER_API_KEY',
    AUTH_TYPE_ACCOUNT_API_KEY => 'AUTH_TYPE_ACCOUNT_API_KEY',
    AUTH_TYPE_MONITOR_API_KEY => 'AUTH_TYPE_MONITOR_API_KEY',
    AUTH_TYPE_SERVICE => 'AUTH_TYPE_SERVICE',
};

=head1 NAME

NP::CAPI::Account - ConnectRPC client for AccountService

=head1 SYNOPSIS

    use NP::CAPI::Account qw(get_account_status validate_session delete_session create_account update_account remove_user_from_account create_user_task list_user_tasks get_user_task get_account_server_verification_status get_accounts_to_notify get_account_users get_user_accounts get_account_invites create_account_invite accept_account_invite resend_account_invite get_account update_account_monitor_config can_delete_account schedule_account_deletion cancel_account_deletion check_user_deletion_eligibility get_public_account_by_username get_related_accounts who_am_i);
    # GetAccountStatus returns the current monitor eligibility and status for an account.
Authentication is handled by middleware - the account is extracted from the session context.
    my $result = get_account_status(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # ValidateSession validates a session token and returns user information.
This is called by the Perl frontend on each request to validate the user's session.
Authentication: Required (service key).
    my $result = validate_session(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # DeleteSession deletes a session by its token.
This is called during logout to invalidate the session.
Authentication: Required (service key).
    my $result = delete_session(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # CreateAccount creates a new account for the authenticated user.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: None required for own account creation.
    my $result = create_account(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # UpdateAccount updates account fields.
Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).
Authorization: User must have edit access (see permission model).
    my $result = update_account(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # RemoveUserFromAccount removes a user from an account.
Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).
Authorization: User must have edit access and cannot remove themselves.
    my $result = remove_user_from_account(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # CreateUserTask creates a user task (download, delete, etc.).
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only create tasks for themselves.
    my $result = create_user_task(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # ListUserTasks lists user tasks by type.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only list their own tasks.
    my $result = list_user_tasks(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetUserTask gets a user task by traceid.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only get their own tasks.
    my $result = get_user_task(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetAccountServerVerificationStatus returns server verification counts for an account.
Used to determine if account can add new servers (blocks if 2+ unverified servers).
Authentication: Required via session middleware (sessions.GetAccount).
    my $result = get_account_server_verification_status(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetAccountsToNotify returns account IDs that need server alert notifications.
Finds accounts with servers scoring below threshold that haven't been notified recently.
Authentication: Admin only.
    my $result = get_accounts_to_notify(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetAccountUsers returns the list of users in an account.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have access to the account.
    my $result = get_account_users(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetUserAccounts returns the list of accounts for the authenticated user.
Authentication: Required via session middleware (sessions.GetUser).
    my $result = get_user_accounts(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetAccountInvites returns pending invites for an account or user.
Authentication: Required via session middleware.
Authorization: Can view invites sent to you or for accounts you manage.
    my $result = get_account_invites(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # CreateAccountInvite creates a new account invitation.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have edit access to the account.
    my $result = create_account_invite(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # AcceptAccountInvite accepts a pending invitation.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: Invite must be for authenticated user's email or user_id.
    my $result = accept_account_invite(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # ResendAccountInvite resends the invitation email.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have edit access to the account.
    my $result = resend_account_invite(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetAccount returns full account information.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have access to the account.
    my $result = get_account(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # UpdateAccountMonitorConfig updates the monitor-related account flags.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: monitor_admin privilege required.
Behavior: unset request fields are left unchanged; the update and its
audit log row are written in one transaction.
    my $result = update_account_monitor_config(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # CanDeleteAccount checks if an account can be deleted.
Authentication: Required via session middleware.
Authorization: User must have access to the account being checked.
    my $result = can_delete_account(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # ScheduleAccountDeletion sets accounts.deletion_on so a background task
will permanently remove the account at that time.
Authentication: Required via session middleware.
Authorization: Staff only (support_staff privilege).
Behavior: validates eligibility (no active servers, vendor zones, active
monitors, or members who would be orphaned) and that deletion_on is at
least 7 days in the future. Returns blockers without writing when any
are present. On success writes an audit log row naming the acting staff.
    my $result = schedule_account_deletion(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # CancelAccountDeletion clears accounts.deletion_on.
Authentication: Required via session middleware.
Authorization: Staff only (support_staff privilege).
    my $result = cancel_account_deletion(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # CheckUserDeletionEligibility checks if a user can be deleted.
Validates all accounts owned solely by the user and returns blocker details.
Authentication: Required via session middleware.
Authorization: User must be the target user or staff.
    my $result = check_user_deletion_eligibility(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetPublicAccountByUsername returns public URL for legacy /user/{username} redirects.
Authentication: Required (service key).
    my $result = get_public_account_by_username(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetRelatedAccounts returns accounts related to the source account for server moves.
Returns different results based on caller role:
- Non-staff: accounts where caller is a member
- Staff: accounts sharing users with source account
Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).
    my $result = get_related_accounts(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # WhoAmI returns identity information for the authenticated entity.
Works with all authentication types: session tokens, user API keys,
account API keys, and monitor API keys.
Authentication: Required (any auth type accepted).
    my $result = who_am_i(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_account_status {
    my $validation_error = validate_key_value_args('get_account_status', @_);
    return $validation_error if $validation_error;

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


=head2 validate_session

ValidateSession validates a session token and returns user information.
This is called by the Perl frontend on each request to validate the user's session.
Authentication: Required (service key).

B<Arguments:>

    my $result = validate_session(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        id_token => $value,       # string - id_token optionally specifies which account to use (from ?a= parameter)
 If provided, validates user has access to this account
 If omitted, returns user's default account (first account in user's list)
 Returns error if id_token specified but user lacks access
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
            id_token => ...,  # string - id_token is the user's id_token for identification.
 Only present when valid is true.
            account => {
                account_id => ...,  # int - Core database fields
                id_token => ...,  # string
                name => ...,  # string
                organization_name => ...,  # string
                organization_url => ...,  # string
                url_slug => ...,  # string
                public_profile => ...,  # bool
                flags => ...,  # string
                created_on => ...,  # string
                modified_on => ...,  # string
                url => ...,  # string - Computed fields (always included)
                public_url => ...,  # string
                display_name => ...,  # string
                deletion_on => ...,  # string - deletion_on is the RFC3339 timestamp when the account is scheduled for
 deletion by the accountdelete background task. Unset when no deletion
 is scheduled.
                subscription_summary => ...,  # hashref (SubscriptionSummary) - Subscription summary (computed from account_subscriptions)
            },  # hashref (AccountContext) - account is the current account context (specified or default)
 Omitted if user has no accounts or account is inaccessible
            permissions => {
                can_edit => ...,  # bool - can_edit: User is in account or is staff
                can_view => ...,  # bool - can_view: User is in account, is staff, or is monitor admin
                can_add_servers => ...,  # bool - can_add_servers: Checks server verification status
 - Allow if no servers yet
 - Block if 2+ unverified servers
 - Otherwise allow
            },  # hashref (AccountPermissions) - permissions for the authenticated user on this account
 Only present if account is present
            privileges => {
                support_staff => ...,  # bool - support_staff allows access to admin endpoints like /manage/admin
                monitor_admin => ...,  # bool - monitor_admin allows cross-account monitor access and management
                vendor_admin => ...,  # bool - vendor_admin allows vendor zone management
            },  # hashref (UserPrivileges) - privileges contains the user's global privilege flags
 Only present when valid is true
            deletion_on => ...,  # string - deletion_on is the timestamp when the user is scheduled for deletion.
 RFC3339 format string (e.g., "2025-02-15T10:30:00Z").
 Only present if the user has scheduled deletion.
            csrf_token => ...,  # string - csrf_token is the CSRF protection token for this session.
 Generated on session creation or after 24h idle.
 Only present when valid is true.
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<valid> (bool)

valid indicates if the session token is valid and active.


=item * B<user_id> (int)

user_id is the numeric ID of the authenticated user.
 Only present when valid is true.


=item * B<email> (string)

email is the user's email address.
 Only present when valid is true.


=item * B<username> (string)

username is the user's username.
 Only present when valid is true.


=item * B<id_token> (string)

id_token is the user's id_token for identification.
 Only present when valid is true.


=item * B<account> (hashref (AccountContext))

account is the current account context (specified or default)
 Omitted if user has no accounts or account is inaccessible


=item * B<permissions> (hashref (AccountPermissions))

permissions for the authenticated user on this account
 Only present if account is present


=item * B<privileges> (hashref (UserPrivileges))

privileges contains the user's global privilege flags
 Only present when valid is true


=item * B<deletion_on> (string)

deletion_on is the timestamp when the user is scheduled for deletion.
 RFC3339 format string (e.g., "2025-02-15T10:30:00Z").
 Only present if the user has scheduled deletion.


=item * B<csrf_token> (string)

csrf_token is the CSRF protection token for this session.
 Generated on session creation or after 24h idle.
 Only present when valid is true.


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = validate_session(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub validate_session {
    my $validation_error = validate_key_value_args('validate_session', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'id_token'} = delete $args{'id_token'} if exists $args{'id_token'};

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
Authentication: Required (service key).

B<Arguments:>

    my $result = delete_session(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub delete_session {
    my $validation_error = validate_key_value_args('delete_session', @_);
    return $validation_error if $validation_error;

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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
                id_token => ...,  # string
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub create_account {
    my $validation_error = validate_key_value_args('create_account', @_);
    return $validation_error if $validation_error;

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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
                id_token => ...,  # string
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub update_account {
    my $validation_error = validate_key_value_args('update_account', @_);
    return $validation_error if $validation_error;

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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        id_token => $value,       # string - id_token is the user's id_token (NOT numeric user_id)
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub remove_user_from_account {
    my $validation_error = validate_key_value_args('remove_user_from_account', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'id_token'} = delete $args{'id_token'} if exists $args{'id_token'};

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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub create_user_task {
    my $validation_error = validate_key_value_args('create_user_task', @_);
    return $validation_error if $validation_error;

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


=head2 list_user_tasks

ListUserTasks lists user tasks by type.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only list their own tasks.

B<Arguments:>

    my $result = list_user_tasks(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        task_type => $value,       # string - task_type is the type of tasks to list (e.g., "download", "delete")
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            tasks => [
            {
                id => ...,  # int - id is the task ID
                task => ...,  # string - task is the task type (e.g., "download", "delete")
                status => ...,  # string - status is the JSON status string (empty for pending)
                traceid => ...,  # string - traceid is the trace ID linking to async processing logs
                created_on_unix => ...,  # int - created_on_unix is the creation timestamp in Unix seconds
                download_url => ...,  # string - download_url is the computed download URL (empty if not ready)
 Format: /manage/account/download/data/{traceid}/{filename}
                status_url => ...,  # string - status_url is the URL from the status JSON (for redirect)
                status_error => ...,  # string - status_error is the error from the status JSON (if any)
            },
            # ... more items
        ],  # arrayref[hashref (UserTask)] - tasks is the list of user tasks
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<tasks> (arrayref[hashref (UserTask)])

tasks is the list of user tasks


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = list_user_tasks(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub list_user_tasks {
    my $validation_error = validate_key_value_args('list_user_tasks', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'task_type'} = delete $args{'task_type'} if exists $args{'task_type'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'ListUserTasks',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_user_task

GetUserTask gets a user task by traceid.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only get their own tasks.

B<Arguments:>

    my $result = get_user_task(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        traceid => $value,       # string - traceid is the trace ID of the task
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            task => {
                id => ...,  # int - id is the task ID
                task => ...,  # string - task is the task type (e.g., "download", "delete")
                status => ...,  # string - status is the JSON status string (empty for pending)
                traceid => ...,  # string - traceid is the trace ID linking to async processing logs
                created_on_unix => ...,  # int - created_on_unix is the creation timestamp in Unix seconds
                download_url => ...,  # string - download_url is the computed download URL (empty if not ready)
 Format: /manage/account/download/data/{traceid}/{filename}
                status_url => ...,  # string - status_url is the URL from the status JSON (for redirect)
                status_error => ...,  # string - status_error is the error from the status JSON (if any)
            },  # hashref (UserTask) - task is the user task
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<task> (hashref (UserTask))

task is the user task


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_user_task(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_user_task {
    my $validation_error = validate_key_value_args('get_user_task', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'traceid'} = delete $args{'traceid'} if exists $args{'traceid'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetUserTask',
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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_account_server_verification_status {
    my $validation_error = validate_key_value_args('get_account_server_verification_status', @_);
    return $validation_error if $validation_error;

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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_accounts_to_notify {
    my $validation_error = validate_key_value_args('get_accounts_to_notify', @_);
    return $validation_error if $validation_error;

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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
                id_token => ...,  # string
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_account_users {
    my $validation_error = validate_key_value_args('get_account_users', @_);
    return $validation_error if $validation_error;

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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
                id_token => ...,  # string
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_user_accounts {
    my $validation_error = validate_key_value_args('get_user_accounts', @_);
    return $validation_error if $validation_error;

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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
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
                last_sent_on => ...,  # string - last_sent_on is when the invite email was last sent (ISO 8601)
                sent_count => ...,  # int - sent_count is the number of times the invite email has been sent
                can_resend => ...,  # bool - can_resend is true when the invite may be resent right now
                resend_available_at => ...,  # string - resend_available_at is when resend becomes available (ISO 8601); empty when can_resend is true
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
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_account_invites {
    my $validation_error = validate_key_value_args('get_account_invites', @_);
    return $validation_error if $validation_error;

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


=head2 create_account_invite

CreateAccountInvite creates a new account invitation.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have edit access to the account.

B<Arguments:>

    my $result = create_account_invite(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        email => $value,       # string - email is the email address to invite (required)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            invite_id => ...,  # int - invite_id is the ID of the created invitation
            code => ...,  # string - code is the invitation code
            expires_on => ...,  # string - expires_on is when the invitation expires (ISO 8601)
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = create_account_invite(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub create_account_invite {
    my $validation_error = validate_key_value_args('create_account_invite', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'email'} = delete $args{'email'} if exists $args{'email'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'CreateAccountInvite',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 accept_account_invite

AcceptAccountInvite accepts a pending invitation.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: Invite must be for authenticated user's email or user_id.

B<Arguments:>

    my $result = accept_account_invite(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        code => $value,       # string - code is the invitation code (required)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool - success indicates if the invitation was accepted
            account_id => ...,  # int - account_id is the ID of the account joined
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = accept_account_invite(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub accept_account_invite {
    my $validation_error = validate_key_value_args('accept_account_invite', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'code'} = delete $args{'code'} if exists $args{'code'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'AcceptAccountInvite',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 resend_account_invite

ResendAccountInvite resends the invitation email.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have edit access to the account.

B<Arguments:>

    my $result = resend_account_invite(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        invite_id => $value,       # int - invite_id is the ID of the invitation to resend (required)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool - success indicates if the email was sent
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = resend_account_invite(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub resend_account_invite {
    my $validation_error = validate_key_value_args('resend_account_invite', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'invite_id'} = delete $args{'invite_id'} if exists $args{'invite_id'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'ResendAccountInvite',
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
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        mode => $value,       # string (enum: AccountDataMode) - mode determines what data to include (defaults to BASIC)
        include_permissions => $value,       # bool - Custom flags for fine-grained control (override mode defaults)
        include_users => $value,       # bool
        include_subscriptions => $value,       # bool
        include_monitor_config => $value,       # bool
        include_servers_summary => $value,       # bool
        include_servers => $value,       # bool
        include_vendor_zones => $value,       # bool
        include_monitors => $value,       # bool
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            account => {
                account_id => ...,  # int - Core database fields
                id_token => ...,  # string
                name => ...,  # string
                organization_name => ...,  # string
                organization_url => ...,  # string
                url_slug => ...,  # string
                public_profile => ...,  # bool
                flags => ...,  # string
                created_on => ...,  # string
                modified_on => ...,  # string
                url => ...,  # string - Computed fields (always included)
                public_url => ...,  # string
                display_name => ...,  # string
                deletion_on => ...,  # string - deletion_on is the RFC3339 timestamp when the account is scheduled for
 deletion by the accountdelete background task. Unset when no deletion
 is scheduled.
                subscription_summary => ...,  # hashref (SubscriptionSummary) - Subscription summary (computed from account_subscriptions)
            },  # hashref (AccountContext) - Core account with computed fields (always included)
            permissions => {
                can_edit => ...,  # bool - can_edit: User is in account or is staff
                can_view => ...,  # bool - can_view: User is in account, is staff, or is monitor admin
                can_add_servers => ...,  # bool - can_add_servers: Checks server verification status
 - Allow if no servers yet
 - Block if 2+ unverified servers
 - Otherwise allow
            },  # hashref (AccountPermissions) - Optional fields (based on mode or custom flags)
            users => [
            {
                user_id => ...,  # int - user_id is the numeric ID of the user
                id_token => ...,  # string
                email => ...,  # string - email is the user's email address
                username => ...,  # string - username is the user's username
                public_profile => ...,  # bool - public_profile indicates if the user profile is public
                deletion_on => ...,  # string - deletion_on is when the user is scheduled for deletion (if set)
            },
            # ... more items
        ],  # arrayref[hashref (AccountUser)]
            subscriptions => [
            {
                subscription_id => ...,  # int
                stripe_subscription_id => ...,  # string
                status => ...,  # string
                live_subscription => ...,  # bool
                created_on => ...,  # string
                canceled_at => ...,  # string
            },
            # ... more items
        ],  # arrayref[hashref (AccountSubscription)]
            monitor_config => {
                monitor_enabled => ...,  # bool
                monitor_limit => ...,  # int
                monitors_per_server_limit => ...,  # int
            },  # hashref (MonitorConfig)
            servers_summary => {
                total_servers => ...,  # int
                active_servers => ...,  # int
                deleted_servers => ...,  # int
                bad_servers => ...,  # int
            },  # hashref (ServersSummary)
            servers => [
            {
                id => ...,  # int
                ip => ...,  # string
                hostname => ...,  # string
                ip_version => ...,  # int
                stratum => ...,  # int
                in_pool => ...,  # bool
                netspeed => ...,  # int
                score_raw => ...,  # number
                deletion_on => ...,  # string
                verified => ...,  # bool
                verified_on => ...,  # string
                zones => ...,  # string
                urls => ...,  # string
                created_on => ...,  # string
                modified_on => ...,  # string
            },
            # ... more items
        ],  # arrayref[hashref (ServerDetail)]
            vendor_zones => [
            {
                vendor_zone_id => ...,  # int
                zone_name => ...,  # string
                status => ...,  # string
            },
            # ... more items
        ],  # arrayref[hashref (VendorZone)]
            monitors => [
            {
                monitor_id => ...,  # int
                ip => ...,  # string
                hostname => ...,  # string
                status => ...,  # string
                created_on => ...,  # string
            },
            # ... more items
        ],  # arrayref[hashref (Monitor)]
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<account> (hashref (AccountContext))

Core account with computed fields (always included)


=item * B<permissions> (hashref (AccountPermissions))

Optional fields (based on mode or custom flags)


=item * B<users> (arrayref[hashref (AccountUser)])


=item * B<subscriptions> (arrayref[hashref (AccountSubscription)])


=item * B<monitor_config> (hashref (MonitorConfig))


=item * B<servers_summary> (hashref (ServersSummary))


=item * B<servers> (arrayref[hashref (ServerDetail)])


=item * B<vendor_zones> (arrayref[hashref (VendorZone)])


=item * B<monitors> (arrayref[hashref (Monitor)])


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_account {
    my $validation_error = validate_key_value_args('get_account', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'mode'} = delete $args{'mode'} if exists $args{'mode'};
    $request{'include_permissions'} = delete $args{'include_permissions'} if exists $args{'include_permissions'};
    $request{'include_users'} = delete $args{'include_users'} if exists $args{'include_users'};
    $request{'include_subscriptions'} = delete $args{'include_subscriptions'} if exists $args{'include_subscriptions'};
    $request{'include_monitor_config'} = delete $args{'include_monitor_config'} if exists $args{'include_monitor_config'};
    $request{'include_servers_summary'} = delete $args{'include_servers_summary'} if exists $args{'include_servers_summary'};
    $request{'include_servers'} = delete $args{'include_servers'} if exists $args{'include_servers'};
    $request{'include_vendor_zones'} = delete $args{'include_vendor_zones'} if exists $args{'include_vendor_zones'};
    $request{'include_monitors'} = delete $args{'include_monitors'} if exists $args{'include_monitors'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetAccount',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 update_account_monitor_config

UpdateAccountMonitorConfig updates the monitor-related account flags.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: monitor_admin privilege required.
Behavior: unset request fields are left unchanged; the update and its
audit log row are written in one transaction.

B<Arguments:>

    my $result = update_account_monitor_config(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        monitor_enabled => $value,       # bool
        monitor_limit => $value,       # int
        monitors_per_server_limit => $value,       # int
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            monitor_config => {
                monitor_enabled => ...,  # bool
                monitor_limit => ...,  # int
                monitors_per_server_limit => ...,  # int
            },  # hashref (MonitorConfig)
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<monitor_config> (hashref (MonitorConfig))


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = update_account_monitor_config(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub update_account_monitor_config {
    my $validation_error = validate_key_value_args('update_account_monitor_config', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'monitor_enabled'} = delete $args{'monitor_enabled'} if exists $args{'monitor_enabled'};
    $request{'monitor_limit'} = delete $args{'monitor_limit'} if exists $args{'monitor_limit'};
    $request{'monitors_per_server_limit'} = delete $args{'monitors_per_server_limit'} if exists $args{'monitors_per_server_limit'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'UpdateAccountMonitorConfig',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 can_delete_account

CanDeleteAccount checks if an account can be deleted.
Authentication: Required via session middleware.
Authorization: User must have access to the account being checked.

B<Arguments:>

    my $result = can_delete_account(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        id_token => $value,       # string - id_token optionally specifies which account to check
 If omitted, checks the authenticated user's current account
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            can_delete => ...,  # bool - can_delete indicates if the account can be deleted
            blockers => [...]  # arrayref[string],  # arrayref[string] - blockers lists reasons why deletion is blocked (empty if can_delete is true)
 User-friendly messages suitable for UI display
            details => {
                active_servers_count => ...,  # int - active_servers_count is the number of servers not scheduled for deletion
                vendor_zones_count => ...,  # int - vendor_zones_count is the number of vendor zones (any status)
                active_monitors_count => ...,  # int - active_monitors_count is the number of monitors with status != 'deleted'
                has_other_users => ...,  # bool - has_other_users indicates if account has other non-deleted users
            },  # hashref (DeletionBlockDetails) - details provides structured information about deletion blockers
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<can_delete> (bool)

can_delete indicates if the account can be deleted


=item * B<blockers> (arrayref[string])

blockers lists reasons why deletion is blocked (empty if can_delete is true)
 User-friendly messages suitable for UI display


=item * B<details> (hashref (DeletionBlockDetails))

details provides structured information about deletion blockers


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = can_delete_account(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub can_delete_account {
    my $validation_error = validate_key_value_args('can_delete_account', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'id_token'} = delete $args{'id_token'} if exists $args{'id_token'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'CanDeleteAccount',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 schedule_account_deletion

ScheduleAccountDeletion sets accounts.deletion_on so a background task
will permanently remove the account at that time.
Authentication: Required via session middleware.
Authorization: Staff only (support_staff privilege).
Behavior: validates eligibility (no active servers, vendor zones, active
monitors, or members who would be orphaned) and that deletion_on is at
least 7 days in the future. Returns blockers without writing when any
are present. On success writes an audit log row naming the acting staff.

B<Arguments:>

    my $result = schedule_account_deletion(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        account_id_token => $value,       # string - id_token of the account to schedule for deletion.
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            scheduled => ...,  # bool - True iff deletion was scheduled. False when blockers are present.
            blockers => [...]  # arrayref[string],  # arrayref[string] - Human-readable blockers when scheduled=false.
            details => {
                active_servers_count => ...,  # int - active_servers_count is the number of servers not scheduled for deletion
                vendor_zones_count => ...,  # int - vendor_zones_count is the number of vendor zones (any status)
                active_monitors_count => ...,  # int - active_monitors_count is the number of monitors with status != 'deleted'
                has_other_users => ...,  # bool - has_other_users indicates if account has other non-deleted users
            },  # hashref (DeletionBlockDetails) - Structured details for UI (reuse DeletionBlockDetails).
            orphaned_user_emails => [...]  # arrayref[string],  # arrayref[string] - Emails of members who would be orphaned by deletion.
            deletion_on => ...,  # string - RFC3339 deletion_on timestamp when scheduled=true.
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<scheduled> (bool)

True iff deletion was scheduled. False when blockers are present.


=item * B<blockers> (arrayref[string])

Human-readable blockers when scheduled=false.


=item * B<details> (hashref (DeletionBlockDetails))

Structured details for UI (reuse DeletionBlockDetails).


=item * B<orphaned_user_emails> (arrayref[string])

Emails of members who would be orphaned by deletion.


=item * B<deletion_on> (string)

RFC3339 deletion_on timestamp when scheduled=true.


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = schedule_account_deletion(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub schedule_account_deletion {
    my $validation_error = validate_key_value_args('schedule_account_deletion', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'account_id_token'} = delete $args{'account_id_token'} if exists $args{'account_id_token'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'ScheduleAccountDeletion',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 cancel_account_deletion

CancelAccountDeletion clears accounts.deletion_on.
Authentication: Required via session middleware.
Authorization: Staff only (support_staff privilege).

B<Arguments:>

    my $result = cancel_account_deletion(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        account_id_token => $value,       # string
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = cancel_account_deletion(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub cancel_account_deletion {
    my $validation_error = validate_key_value_args('cancel_account_deletion', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'account_id_token'} = delete $args{'account_id_token'} if exists $args{'account_id_token'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'CancelAccountDeletion',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 check_user_deletion_eligibility

CheckUserDeletionEligibility checks if a user can be deleted.
Validates all accounts owned solely by the user and returns blocker details.
Authentication: Required via session middleware.
Authorization: User must be the target user or staff.

B<Arguments:>

    my $result = check_user_deletion_eligibility(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        id_token => $value,       # string - id_token optionally specifies which user to check
 If omitted, checks the authenticated user
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            can_delete => ...,  # bool - can_delete indicates if the user can be deleted
            blockers => [...]  # arrayref[string],  # arrayref[string] - blockers lists user-friendly messages for UI display
            affected_accounts => [
            {
                account_id => ...,  # int
                id_token => ...,  # string
                account_name => ...,  # string
                user_is_sole_owner => ...,  # bool - True if user is the only non-deleted user on this account
                active_servers_count => ...,  # int - Blocker details (only populated if user_is_sole_owner = true)
                vendor_zones_count => ...,  # int
                active_monitors_count => ...,  # int
            },
            # ... more items
        ],  # arrayref[hashref (AccountDeletionStatus)] - affected_accounts lists all accounts where user is sole owner
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<can_delete> (bool)

can_delete indicates if the user can be deleted


=item * B<blockers> (arrayref[string])

blockers lists user-friendly messages for UI display


=item * B<affected_accounts> (arrayref[hashref (AccountDeletionStatus)])

affected_accounts lists all accounts where user is sole owner


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = check_user_deletion_eligibility(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub check_user_deletion_eligibility {
    my $validation_error = validate_key_value_args('check_user_deletion_eligibility', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'id_token'} = delete $args{'id_token'} if exists $args{'id_token'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'CheckUserDeletionEligibility',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_public_account_by_username

GetPublicAccountByUsername returns public URL for legacy /user/{username} redirects.
Authentication: Required (service key).

B<Arguments:>

    my $result = get_public_account_by_username(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        username => $value,       # string - username is the user's username to look up
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            redirect_url => ...,  # string - redirect_url is the public account URL (e.g., "/a/example-slug")
 Empty string if user/account not public or url_slug not set
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_public_account_by_username(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_public_account_by_username {
    my $validation_error = validate_key_value_args('get_public_account_by_username', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'username'} = delete $args{'username'} if exists $args{'username'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetPublicAccountByUsername',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_related_accounts

GetRelatedAccounts returns accounts related to the source account for server moves.
Returns different results based on caller role:
- Non-staff: accounts where caller is a member
- Staff: accounts sharing users with source account
Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).

B<Arguments:>

    my $result = get_related_accounts(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        account_id_token => $value,       # string - account_id_token is the source account to find related accounts for
 Uses id_token format (e.g., "abc123")
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
                id_token => ...,  # string - id_token is the account ID token for form submission
                name => ...,  # string - name is the account name for display
            },
            # ... more items
        ],  # arrayref[hashref (RelatedAccount)] - accounts is the list of related accounts
 Excludes the source account itself
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<accounts> (arrayref[hashref (RelatedAccount)])

accounts is the list of related accounts
 Excludes the source account itself


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_related_accounts(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_related_accounts {
    my $validation_error = validate_key_value_args('get_related_accounts', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'account_id_token'} = delete $args{'account_id_token'} if exists $args{'account_id_token'};

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'GetRelatedAccounts',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 who_am_i

WhoAmI returns identity information for the authenticated entity.
Works with all authentication types: session tokens, user API keys,
account API keys, and monitor API keys.
Authentication: Required (any auth type accepted).

B<Arguments:>

    my $result = who_am_i(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            auth_type => ...,  # string (enum: AuthenticationType) - auth_type indicates which authentication method was used.
            user => {
                user_id => ...,  # int
                id_token => ...,  # string
                email => ...,  # string
                username => ...,  # string
                privileges => ...,  # hashref (UserPrivileges) - privileges contains global user privilege flags.
                account => ...,  # hashref (WhoAmIAccount) - account is the current account context (if set via X-Account header or session).
 Only present for session tokens when account is selected.
            },  # hashref (WhoAmIUser) - user is populated for session tokens and user API keys.
 Contains user identity and optionally account context.
            account => {
                account_id => ...,  # int
                id_token => ...,  # string
                name => ...,  # string
                organization_name => ...,  # string
            },  # hashref (WhoAmIAccount) - account is populated for account API keys only.
 Account API keys don't have associated user context.
            monitors => [
            {
                monitor_id => ...,  # int
                id_token => ...,  # string
                hostname => ...,  # string
                ip => ...,  # string
                status => ...,  # string
            },
            # ... more items
        ],  # arrayref[hashref (WhoAmIMonitor)] - monitors is populated for monitor API keys only.
 A single monitor API key may authorize multiple monitors.
            services => [
            {
                service_id => ...,  # int
                id_token => ...,  # string
                type => ...,  # string
                name => ...,  # string
                hostname => ...,  # string
                status => ...,  # string
                ips => ...,  # hashref (ServiceIP)
            },
            # ... more items
        ],  # arrayref[hashref (WhoAmIService)] - services is populated for service API keys only.
 A single service API key may authorize multiple services.
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<auth_type> (string (enum: AuthenticationType))

auth_type indicates which authentication method was used.


=item * B<user> (hashref (WhoAmIUser))

user is populated for session tokens and user API keys.
 Contains user identity and optionally account context.


=item * B<account> (hashref (WhoAmIAccount))

account is populated for account API keys only.
 Account API keys don't have associated user context.


=item * B<monitors> (arrayref[hashref (WhoAmIMonitor)])

monitors is populated for monitor API keys only.
 A single monitor API key may authorize multiple monitors.


=item * B<services> (arrayref[hashref (WhoAmIService)])

services is populated for service API keys only.
 A single service API key may authorize multiple services.


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = who_am_i(
        $self->api_auth_params,           # Provides auth and context
        account => $account->{id_token},  # Account from hashref
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub who_am_i {
    my $validation_error = validate_key_value_args('who_am_i', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.account.v1.AccountService',
        method      => 'WhoAmI',
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
