# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/monitor/v1/monitor.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Monitor;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    get_monitor
    list_monitors
    update_monitor_status
);

=head1 NAME

NP::CAPI::Monitor - ConnectRPC client for MonitorService

=head1 SYNOPSIS

    use NP::CAPI::Monitor qw(get_monitor list_monitors update_monitor_status);
    # GetMonitor returns a single monitor by TLS name.
Authentication: Required via session middleware (sessions.RequireUser).
Authorization: monitor_admin OR the monitor's account member (enforced in SQL).
    my $result = get_monitor(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # ListMonitors lists monitors for the authenticated account, or all
accounts when all_accounts is set (monitor_admin only).
Authentication: Required via session middleware (sessions.RequireUser / RequireAccount).
    my $result = list_monitors(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # UpdateMonitorStatus sets the status of one or more monitors (identified by
id_token, all sharing the given TLS name). Delete is status="deleted".
Authentication: Required via session middleware (sessions.RequireUser).
Authorization: monitor_admin may set any status; account members may only
set "deleted" on monitors they own (enforced in q.UpdateMonitorStatus).
    my $result = update_monitor_status(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.monitor.v1.MonitorService.

This module provides Perl wrappers for calling MonitorService RPC methods
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


=head2 get_monitor

GetMonitor returns a single monitor by TLS name.
Authentication: Required via session middleware (sessions.RequireUser).
Authorization: monitor_admin OR the monitor's account member (enforced in SQL).

B<Arguments:>

    my $result = get_monitor(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        name => $value,       # string
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            monitor => {
                id => ...,  # int
                id_token => ...,  # string
                name => ...,  # string
                tls_name => ...,  # string
                display_name => ...,  # string
                hostname => ...,  # string
                location => ...,  # string
                status => ...,  # string
                status_color => ...,  # string
                client_version => ...,  # string
                ipv4 => ...,  # hashref (MonitorAddr)
                ipv6 => ...,  # hashref (MonitorAddr)
                is_dualstack => ...,  # bool
                combined_status => ...,  # bool
                combined_last_seen => ...,  # bool
                last_seen_status => ...,  # hashref (LastSeenStatus)
                account => ...,  # hashref (MonitorAccount)
                can_edit => ...,  # bool - server-computed permissions
                can_delete => ...,  # bool
                can_set_status => ...,  # bool
            },  # hashref (Monitor)
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<monitor> (hashref (Monitor))


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_monitor(
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

sub get_monitor {
    my $validation_error = validate_key_value_args('get_monitor', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'name'} = delete $args{'name'} if exists $args{'name'};

    return connect_rpc(
        service     => 'ntppool.monitor.v1.MonitorService',
        method      => 'GetMonitor',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 list_monitors

ListMonitors lists monitors for the authenticated account, or all
accounts when all_accounts is set (monitor_admin only).
Authentication: Required via session middleware (sessions.RequireUser / RequireAccount).

B<Arguments:>

    my $result = list_monitors(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        all_accounts => $value,       # bool
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            monitors => [
            {
                id => ...,  # int
                id_token => ...,  # string
                name => ...,  # string
                tls_name => ...,  # string
                display_name => ...,  # string
                hostname => ...,  # string
                location => ...,  # string
                status => ...,  # string
                status_color => ...,  # string
                client_version => ...,  # string
                ipv4 => ...,  # hashref (MonitorAddr)
                ipv6 => ...,  # hashref (MonitorAddr)
                is_dualstack => ...,  # bool
                combined_status => ...,  # bool
                combined_last_seen => ...,  # bool
                last_seen_status => ...,  # hashref (LastSeenStatus)
                account => ...,  # hashref (MonitorAccount)
                can_edit => ...,  # bool - server-computed permissions
                can_delete => ...,  # bool
                can_set_status => ...,  # bool
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

=item * B<monitors> (arrayref[hashref (Monitor)])


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = list_monitors(
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

sub list_monitors {
    my $validation_error = validate_key_value_args('list_monitors', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'all_accounts'} = delete $args{'all_accounts'} if exists $args{'all_accounts'};

    return connect_rpc(
        service     => 'ntppool.monitor.v1.MonitorService',
        method      => 'ListMonitors',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 update_monitor_status

UpdateMonitorStatus sets the status of one or more monitors (identified by
id_token, all sharing the given TLS name). Delete is status="deleted".
Authentication: Required via session middleware (sessions.RequireUser).
Authorization: monitor_admin may set any status; account members may only
set "deleted" on monitors they own (enforced in q.UpdateMonitorStatus).

B<Arguments:>

    my $result = update_monitor_status(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        name => $value,       # string
        ids => $value,       # arrayref[string]
        status => $value,       # string
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            deleted => ...,  # bool
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = update_monitor_status(
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

sub update_monitor_status {
    my $validation_error = validate_key_value_args('update_monitor_status', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'name'} = delete $args{'name'} if exists $args{'name'};
    $request{'ids'} = delete $args{'ids'} if exists $args{'ids'};
    $request{'status'} = delete $args{'status'} if exists $args{'status'};

    return connect_rpc(
        service     => 'ntppool.monitor.v1.MonitorService',
        method      => 'UpdateMonitorStatus',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/monitor/v1/monitor.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
