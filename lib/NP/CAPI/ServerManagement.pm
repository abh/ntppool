# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/server/v1/management.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::ServerManagement;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    add_server_precheck
    add_server
    update_server
    delete_server
    start_server_verification
);

=head1 NAME

NP::CAPI::ServerManagement - ConnectRPC client for ServerManagementService

=head1 SYNOPSIS

    use NP::CAPI::ServerManagement qw(add_server_precheck add_server update_server delete_server start_server_verification);
    # AddServerPrecheck validates multiple server IPs and returns results for each
Accepts unlimited IPs; processes first 6 NEW servers only
Authentication: Required via session middleware
Authorization: User must have access to account
    my $result = add_server_precheck(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # AddServer adds multiple servers to an account (all-or-nothing transaction)
Accepts unlimited servers; processes first 6 NEW servers only
Authentication: Required via session middleware
Authorization: User must have access to account
    my $result = add_server(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # UpdateServer updates server configuration
Authentication: Required via session middleware
Authorization: User must own server (by account) or be staff
    my $result = update_server(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # DeleteServer schedules a server for deletion
Authentication: Required via session middleware
Authorization: User must own server (by account) or be staff
    my $result = delete_server(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # StartServerVerification initiates the verification process
Authentication: Required via session middleware
Authorization: User must own server (by account) or be staff
    my $result = start_server_verification(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.server.v1.ServerManagementService.

This module provides Perl wrappers for calling ServerManagementService RPC methods
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


=head2 add_server_precheck

AddServerPrecheck validates multiple server IPs and returns results for each
Accepts unlimited IPs; processes first 6 NEW servers only
Authentication: Required via session middleware
Authorization: User must have access to account

B<Arguments:>

    my $result = add_server_precheck(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        inputs => $value,       # arrayref[string] - inputs can be hostnames OR IP addresses (unlimited input)
 Go API will detect type and perform DNS lookup for hostnames
 Multiple IPs may result from a single hostname input

 DNS SECURITY (DNS rebinding protection):
 - All DNS resolution occurs in Go API (client cannot control DNS responses)
 - Hostname-to-IP mapping is captured and stored in precheck token
 - AddServer validates IP matches the hostname from precheck token
 - 5-minute token expiry limits window for DNS changes between precheck and add
 - Internal domains (.local, .cluster) are blocked to prevent information leakage
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            results => [
            {
                ip => ...,  # string - ip is the IP address that was validated
                valid => ...,  # bool - valid indicates if this IP passed validation
                error => ...,  # string - Error information (only if invalid)
                already_exists => ...,  # bool - Already-exists flags
                already_exists_same_account => ...,  # bool
                already_exists_other_account => ...,  # bool
                ip_version => ...,  # string - Server information (only if valid and not exists)
                stratum => ...,  # int - NTP check results
                ntp_error => ...,  # string
                zones => ...,  # hashref (ZoneReference) - Zone assignment (using existing ZoneReference type)
                detected_country => ...,  # string - detected_country from GeoIP (empty if GeoIP failed)
                hostname => ...,  # string - hostname if input was a hostname (empty if direct IP input)
 Multiple IPs may share the same hostname if DNS returned multiple addresses
                original_input => ...,  # string - original_input is what the user originally entered (for grouping results in UI)
 This allows grouping results by the input that generated them
            },
            # ... more items
        ],  # arrayref[hashref (ServerPrecheckResult)] - results contains validation results for each IP
            precheck_token => ...,  # string - precheck_token is valid for 5 minutes and covers all IPs in this validation
 Can be used in AddServer to skip re-validation (if token not expired)
            servers_skipped => ...,  # int - servers_skipped is count of servers not processed due to 6-server limit
            already_exists_count => ...,  # int - already_exists_count is count of servers already in system (not processed)
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<results> (arrayref[hashref (ServerPrecheckResult)])

results contains validation results for each IP


=item * B<precheck_token> (string)

precheck_token is valid for 5 minutes and covers all IPs in this validation
 Can be used in AddServer to skip re-validation (if token not expired)


=item * B<servers_skipped> (int)

servers_skipped is count of servers not processed due to 6-server limit


=item * B<already_exists_count> (int)

already_exists_count is count of servers already in system (not processed)


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = add_server_precheck(
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

sub add_server_precheck {
    my $validation_error = validate_key_value_args('add_server_precheck', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'inputs'} = delete $args{'inputs'} if exists $args{'inputs'};

    return connect_rpc(
        service     => 'ntppool.server.v1.ServerManagementService',
        method      => 'AddServerPrecheck',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 add_server

AddServer adds multiple servers to an account (all-or-nothing transaction)
Accepts unlimited servers; processes first 6 NEW servers only
Authentication: Required via session middleware
Authorization: User must have access to account

B<Arguments:>

    my $result = add_server(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        servers => $value,       # arrayref[hashref (ServerToAdd)] - servers is the list of servers to add (unlimited input, max 6 processed)
        precheck_token => $value,       # string - precheck_token skips validation if provided and valid (expires after 5 minutes)
 If expired, re-validation occurs before adding
        batch_comment => $value,       # string - batch_comment applies to all servers (sent to notifications)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            results => [
            {
                ip => ...,  # string
                success => ...,  # bool
                error => ...,  # string
                server => ...,  # hashref (Server)
            },
            # ... more items
        ],  # arrayref[hashref (ServerAddResult)] - results contains add result for each requested server (only first 6 new servers processed)
            servers_skipped => ...,  # int - servers_skipped is count of servers not processed due to 6-server limit
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<results> (arrayref[hashref (ServerAddResult)])

results contains add result for each requested server (only first 6 new servers processed)


=item * B<servers_skipped> (int)

servers_skipped is count of servers not processed due to 6-server limit


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = add_server(
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

sub add_server {
    my $validation_error = validate_key_value_args('add_server', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'servers'} = delete $args{'servers'} if exists $args{'servers'};
    $request{'precheck_token'} = delete $args{'precheck_token'} if exists $args{'precheck_token'};
    $request{'batch_comment'} = delete $args{'batch_comment'} if exists $args{'batch_comment'};

    return connect_rpc(
        service     => 'ntppool.server.v1.ServerManagementService',
        method      => 'AddServer',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 update_server

UpdateServer updates server configuration
Authentication: Required via session middleware
Authorization: User must own server (by account) or be staff

B<Arguments:>

    my $result = update_server(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        ip => $value,       # string
        hostname => $value,       # string - Fields to update (only provided fields are updated)
        netspeed => $value,       # int
        in_pool => $value,       # bool
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool
            server => {
                id => ...,  # int - id is the database ID of the server
                ip => ...,  # string - ip is the IP address (IPv4 or IPv6)
                hostname => ...,  # string - hostname is the DNS hostname (may be empty)
                ip_version => ...,  # int - ip_version is 4 or 6
                stratum => ...,  # int - stratum is the NTP stratum level
                in_pool => ...,  # bool - in_pool indicates if the server is active in the pool
                netspeed => ...,  # int - netspeed is the configured network speed weight
                score_raw => ...,  # number - score_raw is the current raw score
                deletion_on => ...,  # string - deletion_on is when the server is/was scheduled for deletion (ISO 8601)
 Empty if not scheduled for deletion
                account => ...,  # hashref (AccountInfo) - account contains account information (conditionally included)
 Included if: account.public_profile=true OR authenticated user owns server OR user is staff
                zones => ...,  # arrayref[hashref (ZoneReference)] - zones this server is assigned to (excludes root '.' zone)
                verification => ...,  # hashref (ServerVerification) - verification contains verification status
                urls => ...,  # arrayref[string] - urls are server-provided traffic/stats URLs
            },  # hashref (Server)
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<success> (bool)


=item * B<server> (hashref (Server))


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = update_server(
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

sub update_server {
    my $validation_error = validate_key_value_args('update_server', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'ip'} = delete $args{'ip'} if exists $args{'ip'};
    $request{'hostname'} = delete $args{'hostname'} if exists $args{'hostname'};
    $request{'netspeed'} = delete $args{'netspeed'} if exists $args{'netspeed'};
    $request{'in_pool'} = delete $args{'in_pool'} if exists $args{'in_pool'};

    return connect_rpc(
        service     => 'ntppool.server.v1.ServerManagementService',
        method      => 'UpdateServer',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 delete_server

DeleteServer schedules a server for deletion
Authentication: Required via session middleware
Authorization: User must own server (by account) or be staff

B<Arguments:>

    my $result = delete_server(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        ip => $value,       # string
        immediate => $value,       # bool - immediate schedules deletion immediately instead of grace period
 Default is false (14-day grace period)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool
            deletion_on => ...,  # string
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = delete_server(
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

sub delete_server {
    my $validation_error = validate_key_value_args('delete_server', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'ip'} = delete $args{'ip'} if exists $args{'ip'};
    $request{'immediate'} = delete $args{'immediate'} if exists $args{'immediate'};

    return connect_rpc(
        service     => 'ntppool.server.v1.ServerManagementService',
        method      => 'DeleteServer',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 start_server_verification

StartServerVerification initiates the verification process
Authentication: Required via session middleware
Authorization: User must own server (by account) or be staff

B<Arguments:>

    my $result = start_server_verification(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        ip => $value,       # string
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            token => ...,  # string
            instructions => ...,  # string
            expires_on => ...,  # string
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = start_server_verification(
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

sub start_server_verification {
    my $validation_error = validate_key_value_args('start_server_verification', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'ip'} = delete $args{'ip'} if exists $args{'ip'};

    return connect_rpc(
        service     => 'ntppool.server.v1.ServerManagementService',
        method      => 'StartServerVerification',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/server/v1/management.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
