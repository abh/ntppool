# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/server/v1/server.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Server;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    get_server
    get_account_servers
);

=head1 NAME

NP::CAPI::Server - ConnectRPC client for ServerService

=head1 SYNOPSIS

    use NP::CAPI::Server qw(get_server get_account_servers);
    # GetServer returns detailed information about a specific server.
Authentication is handled by middleware - if authenticated, additional
data may be returned based on ownership and account settings.
    my $result = get_server(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );

    # GetAccountServers returns all servers for an account by url_slug.
Access control: public_profile=true OR authenticated user owns account OR user is staff.
Returns 404 if account not found or not visible.
    my $result = get_account_servers(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.server.v1.ServerService.

This module provides Perl wrappers for calling ServerService RPC methods
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


=head2 get_server

GetServer returns detailed information about a specific server.
Authentication is handled by middleware - if authenticated, additional
data may be returned based on ownership and account settings.

B<Arguments:>

    my $result = get_server(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        ip => $value,       # string - ip is the server IP address (IPv4 or IPv6)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
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
            },  # hashref (Server) - server contains the complete server information
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<server> (hashref (Server))

server contains the complete server information


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_server(
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

sub get_server {
    my $validation_error = validate_key_value_args('get_server', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'ip'} = delete $args{'ip'} if exists $args{'ip'};

    return connect_rpc(
        service     => 'ntppool.server.v1.ServerService',
        method      => 'GetServer',
        request     => \%request,
        http_method => 'GET',  # Side-effect free, use GET
        %args  # Pass through auth, account, context
    );
}


=head2 get_account_servers

GetAccountServers returns all servers for an account by url_slug.
Access control: public_profile=true OR authenticated user owns account OR user is staff.
Returns 404 if account not found or not visible.

B<Arguments:>

    my $result = get_account_servers(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        url_slug => $value,       # string - url_slug is the account's URL-friendly identifier (e.g., "fancytime")
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            account => {
                id_token => ...,  # string - id_token is the public account identifier
                display_name => ...,  # string - display_name is the account's display name
                public_url => ...,  # string - public_url is the URL to the account's public profile page
                public_profile => ...,  # bool - public_profile indicates if the account profile is publicly visible
            },  # hashref (AccountInfo) - account contains the account information
            servers => [
            {
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
                zones => ...,  # hashref (ZoneReference) - zones this server is assigned to (excludes root '.' zone)
                verification => ...,  # hashref (ServerVerification) - verification contains verification status
                urls => ...,  # string - urls are server-provided traffic/stats URLs
            },
            # ... more items
        ],  # arrayref[hashref (Server)] - servers contains all active servers for this account
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<account> (hashref (AccountInfo))

account contains the account information


=item * B<servers> (arrayref[hashref (Server)])

servers contains all active servers for this account


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account_servers(
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

sub get_account_servers {
    my $validation_error = validate_key_value_args('get_account_servers', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'url_slug'} = delete $args{'url_slug'} if exists $args{'url_slug'};

    return connect_rpc(
        service     => 'ntppool.server.v1.ServerService',
        method      => 'GetAccountServers',
        request     => \%request,
        http_method => 'GET',  # Side-effect free, use GET
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/server/v1/server.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
