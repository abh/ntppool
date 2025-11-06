# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/user/v1/user.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::User;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    get_user
    update_user
    cancel_user_deletion
    schedule_user_deletion
);

=head1 NAME

NP::CAPI::User - ConnectRPC client for UserService

=head1 SYNOPSIS

    use NP::CAPI::User qw(get_user update_user cancel_user_deletion schedule_user_deletion);
    # GetUser returns complete user information including accounts and invites.

Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can view own profile; staff can view any user via id_token parameter.

Replaces Perl: $user->accounts, $user->pending_invites
    my $result = get_user(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # UpdateUser updates user profile fields (name, username).

Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only update own profile (no staff override).

Validation:
- Username uniqueness enforced (returns error if username already exists)
- Name cannot be empty string
- Username cannot be empty string

Replaces Perl: $user->name($new_name); $user->username($new_username); $user->save()
    my $result = update_user(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # CancelUserDeletion cancels a scheduled user deletion.

Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only cancel own deletion.

Side Effects:
- Clears deletion_on timestamp
- Deletes any pending deletion tasks (via DeleteUserDeletionTasks)

Replaces Perl: $user->deletion_on(undef); $user->save()
Used in Auth0 login flow (auto-cancel deletion on login)
    my $result = cancel_user_deletion(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # ScheduleUserDeletion schedules a user for deletion at a future date.

Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only schedule own deletion.

Validation:
- deletion_on_unix must be at least 7 days in the future

Replaces Perl: $user->deletion_on($date); $user->save()
    my $result = schedule_user_deletion(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.user.v1.UserService.

This module provides Perl wrappers for calling UserService RPC methods
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


=head2 get_user

GetUser returns complete user information including accounts and invites.

Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can view own profile; staff can view any user via id_token parameter.

Replaces Perl: $user->accounts, $user->pending_invites

B<Arguments:>

    my $result = get_user(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        id_token => $value,       # string - id_token optionally specifies which user to retrieve.
 If omitted, returns authenticated user's profile.
 If provided, requires staff privileges to access other users.
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            user => {
                user_id => ...,  # int - user_id is the numeric ID of the user
                id_token => ...,  # string
                email => ...,  # string - email is the user's email address
                username => ...,  # string - username is the user's username
                name => ...,  # string - name is the user's display name
                public_profile => ...,  # bool - public_profile indicates if the user profile is public (LEGACY - see issue #18)
                deletion_on => ...,  # string - deletion_on is when the user is scheduled for deletion (RFC3339 format)
 Empty string means not scheduled for deletion
                created_on => ...,  # string - created_on is when the user was created (RFC3339 format)
                modified_on => ...,  # string - modified_on is when the user was last modified (RFC3339 format)
            },  # hashref (User) - user contains the complete user profile
            accounts => [
            {
                account_id => ...,  # int - account_id is the numeric ID of the account
                id_token => ...,  # string
                name => ...,  # string - name is the account name
                organization_name => ...,  # string - organization_name is the organization name (if set)
                url_slug => ...,  # string - url_slug is the URL slug for the account (if set)
                created_on => ...,  # string - created_on is when the account was created (RFC3339 format)
            },
            # ... more items
        ],  # arrayref[hashref (UserAccountSummary)] - accounts contains all accounts the user belongs to
 Uses UserAccountSummary to avoid circular dependency on AccountService
            invites => [
            {
                invite_id => ...,  # int - invite_id is the numeric ID of the invite
                account_id => ...,  # int - account_id is the ID of the account being invited to
                account_name => ...,  # string - account_name is the name of the account (for display)
                email => ...,  # string - email is the email address invited
                status => ...,  # string - status is the invite status (pending, accepted, expired)
                code => ...,  # string - code is the invitation code (only for pending invites)
                expires_on => ...,  # string - expires_on is when the invite expires (RFC3339 format)
                created_on => ...,  # string - created_on is when the invite was created (RFC3339 format)
            },
            # ... more items
        ],  # arrayref[hashref (AccountInviteSummary)] - invites contains pending account invitations for this user
 Uses AccountInviteSummary to avoid circular dependency on AccountService
            privileges => {
                support_staff => ...,  # bool - support_staff allows access to admin endpoints like /manage/admin
                monitor_admin => ...,  # bool - monitor_admin allows cross-account monitor access and management
                vendor_admin => ...,  # bool - vendor_admin allows vendor zone management
            },  # hashref (UserPrivileges) - privileges contains the user's global privilege flags (if any)
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<user> (hashref (User))

user contains the complete user profile


=item * B<accounts> (arrayref[hashref (UserAccountSummary)])

accounts contains all accounts the user belongs to
 Uses UserAccountSummary to avoid circular dependency on AccountService


=item * B<invites> (arrayref[hashref (AccountInviteSummary)])

invites contains pending account invitations for this user
 Uses AccountInviteSummary to avoid circular dependency on AccountService


=item * B<privileges> (hashref (UserPrivileges))

privileges contains the user's global privilege flags (if any)


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_user(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->{id_token},
        context => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub get_user {
    my $validation_error = validate_key_value_args('get_user', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'id_token'} = delete $args{'id_token'} if exists $args{'id_token'};

    return connect_rpc(
        service     => 'ntppool.user.v1.UserService',
        method      => 'GetUser',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 update_user

UpdateUser updates user profile fields (name, username).

Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only update own profile (no staff override).

Validation:
- Username uniqueness enforced (returns error if username already exists)
- Name cannot be empty string
- Username cannot be empty string

Replaces Perl: $user->name($new_name); $user->username($new_username); $user->save()

B<Arguments:>

    my $result = update_user(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        name => $value,       # string - name is the user's display name (optional)
 If provided, cannot be empty string
        username => $value,       # string - username is the user's username (optional)
 If provided:
 - Cannot be empty string
 - Must be unique across all users (validated)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool - success indicates if the update was successful
            user => {
                user_id => ...,  # int - user_id is the numeric ID of the user
                id_token => ...,  # string
                email => ...,  # string - email is the user's email address
                username => ...,  # string - username is the user's username
                name => ...,  # string - name is the user's display name
                public_profile => ...,  # bool - public_profile indicates if the user profile is public (LEGACY - see issue #18)
                deletion_on => ...,  # string - deletion_on is when the user is scheduled for deletion (RFC3339 format)
 Empty string means not scheduled for deletion
                created_on => ...,  # string - created_on is when the user was created (RFC3339 format)
                modified_on => ...,  # string - modified_on is when the user was last modified (RFC3339 format)
            },  # hashref (User) - user is the complete updated user object
 Perl MUST use this data, NOT reload from database
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<success> (bool)

success indicates if the update was successful


=item * B<user> (hashref (User))

user is the complete updated user object
 Perl MUST use this data, NOT reload from database


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = update_user(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->{id_token},
        context => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub update_user {
    my $validation_error = validate_key_value_args('update_user', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'name'} = delete $args{'name'} if exists $args{'name'};
    $request{'username'} = delete $args{'username'} if exists $args{'username'};

    return connect_rpc(
        service     => 'ntppool.user.v1.UserService',
        method      => 'UpdateUser',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 cancel_user_deletion

CancelUserDeletion cancels a scheduled user deletion.

Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only cancel own deletion.

Side Effects:
- Clears deletion_on timestamp
- Deletes any pending deletion tasks (via DeleteUserDeletionTasks)

Replaces Perl: $user->deletion_on(undef); $user->save()
Used in Auth0 login flow (auto-cancel deletion on login)

B<Arguments:>

    my $result = cancel_user_deletion(
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
            success => ...,  # bool - success indicates if the cancellation was successful
            user => {
                user_id => ...,  # int - user_id is the numeric ID of the user
                id_token => ...,  # string
                email => ...,  # string - email is the user's email address
                username => ...,  # string - username is the user's username
                name => ...,  # string - name is the user's display name
                public_profile => ...,  # bool - public_profile indicates if the user profile is public (LEGACY - see issue #18)
                deletion_on => ...,  # string - deletion_on is when the user is scheduled for deletion (RFC3339 format)
 Empty string means not scheduled for deletion
                created_on => ...,  # string - created_on is when the user was created (RFC3339 format)
                modified_on => ...,  # string - modified_on is when the user was last modified (RFC3339 format)
            },  # hashref (User) - user is the complete updated user object (deletion_on cleared)
 Perl MUST use this data, NOT reload from database
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<success> (bool)

success indicates if the cancellation was successful


=item * B<user> (hashref (User))

user is the complete updated user object (deletion_on cleared)
 Perl MUST use this data, NOT reload from database


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = cancel_user_deletion(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->{id_token},
        context => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub cancel_user_deletion {
    my $validation_error = validate_key_value_args('cancel_user_deletion', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.user.v1.UserService',
        method      => 'CancelUserDeletion',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 schedule_user_deletion

ScheduleUserDeletion schedules a user for deletion at a future date.

Authentication: Required via session middleware (sessions.GetUser).
Authorization: User can only schedule own deletion.

Validation:
- deletion_on_unix must be at least 7 days in the future

Replaces Perl: $user->deletion_on($date); $user->save()

B<Arguments:>

    my $result = schedule_user_deletion(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        deletion_on_unix => $value,       # int - deletion_on_unix is the Unix timestamp when user should be deleted
 Must be at least 7 days (604800 seconds) in the future
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool - success indicates if the scheduling was successful
            user => {
                user_id => ...,  # int - user_id is the numeric ID of the user
                id_token => ...,  # string
                email => ...,  # string - email is the user's email address
                username => ...,  # string - username is the user's username
                name => ...,  # string - name is the user's display name
                public_profile => ...,  # bool - public_profile indicates if the user profile is public (LEGACY - see issue #18)
                deletion_on => ...,  # string - deletion_on is when the user is scheduled for deletion (RFC3339 format)
 Empty string means not scheduled for deletion
                created_on => ...,  # string - created_on is when the user was created (RFC3339 format)
                modified_on => ...,  # string - modified_on is when the user was last modified (RFC3339 format)
            },  # hashref (User) - user is the complete updated user object (with deletion_on set)
 Perl MUST use this data, NOT reload from database
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<success> (bool)

success indicates if the scheduling was successful


=item * B<user> (hashref (User))

user is the complete updated user object (with deletion_on set)
 Perl MUST use this data, NOT reload from database


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = schedule_user_deletion(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->{id_token},
        context => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "Error: $result->{error}";
    } else {
        my $data = $result->{data};
        # Use response fields...
    }

=cut

sub schedule_user_deletion {
    my $validation_error = validate_key_value_args('schedule_user_deletion', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'deletion_on_unix'} = delete $args{'deletion_on_unix'} if exists $args{'deletion_on_unix'};

    return connect_rpc(
        service     => 'ntppool.user.v1.UserService',
        method      => 'ScheduleUserDeletion',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/user/v1/user.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
