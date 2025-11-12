# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/vendorzone/v1/vendor.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::VendorZone;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    list_vendor_zones
    get_vendor_zone
    request_vendor_zone
    update_vendor_zone
    submit_vendor_zone
    update_vendor_zone_status
);

=head1 NAME

NP::CAPI::VendorZone - ConnectRPC client for VendorZoneService

=head1 SYNOPSIS

    use NP::CAPI::VendorZone qw(list_vendor_zones get_vendor_zone request_vendor_zone update_vendor_zone submit_vendor_zone update_vendor_zone_status);
    # ListVendorZones lists vendor zones for an account.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have access to the account.
    my $result = list_vendor_zones(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetVendorZone gets details for a specific vendor zone.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: vendor_admin privilege OR user in zone's account.
    my $result = get_vendor_zone(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # RequestVendorZone creates a new vendor zone request (status=New).
The request must be submitted and approved before becoming active.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have edit access to the account.
    my $result = request_vendor_zone(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # UpdateVendorZone updates vendor zone fields (only when status=New).
Authentication: Required via session middleware (sessions.GetUser).
Authorization: vendor_admin privilege OR (status=New AND user in account).
    my $result = update_vendor_zone(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # SubmitVendorZone submits zone for approval (New -> Pending).
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have edit access to the account.
Validates: subscription limits or opensource request.
    my $result = submit_vendor_zone(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # UpdateVendorZoneStatus updates vendor zone status (admin only).
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User must have vendor_admin privilege.
Transitions: Pending->Approved, Pending->Rejected, Rejected->Approved.
    my $result = update_vendor_zone_status(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.vendorzone.v1.VendorZoneService.

This module provides Perl wrappers for calling VendorZoneService RPC methods
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


=head2 list_vendor_zones

ListVendorZones lists vendor zones for an account.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have access to the account.

B<Arguments:>

    my $result = list_vendor_zones(
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
            zones => [
            {
                vendor_zone_id => ...,  # int - vendor_zone_id is the numeric ID
                zone_name => ...,  # string - zone_name is the DNS zone name (e.g., "example")
                status => ...,  # string - status is the zone status (New, Pending, Approved, Rejected)
                created_on => ...,  # string - created_on is when the zone was requested (RFC3339)
                approved_on => ...,  # string - approved_on is when the zone was approved (RFC3339, empty if pending)
            },
            # ... more items
        ],  # arrayref[hashref (VendorZone)] - zones is the list of vendor zones
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<zones> (arrayref[hashref (VendorZone)])

zones is the list of vendor zones


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = list_vendor_zones(
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

sub list_vendor_zones {
    my $validation_error = validate_key_value_args('list_vendor_zones', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.vendorzone.v1.VendorZoneService',
        method      => 'ListVendorZones',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_vendor_zone

GetVendorZone gets details for a specific vendor zone.
Authentication: Required via session middleware (sessions.GetUser).
Authorization: vendor_admin privilege OR user in zone's account.

B<Arguments:>

    my $result = get_vendor_zone(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        id_token => $value,       # string - id_token identifies the zone (required, format: "vz_{token}")
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            zone => {
                vendor_zone_id => ...,  # int - vendor_zone_id is the numeric ID
                zone_name => ...,  # string - zone_name is the DNS zone name (e.g., "example")
                status => ...,  # string - status is the zone status (New, Pending, Approved, Rejected)
                created_on => ...,  # string - created_on is when the zone was requested (RFC3339)
                approved_on => ...,  # string - approved_on is when the zone was approved (RFC3339, empty if pending)
            },  # hashref (VendorZone) - zone contains the vendor zone details
            organization_name => ...,  # string - Additional fields for full details
            request_information => ...,  # string
            device_count => ...,  # int
            device_information => ...,  # string
            contact_information => ...,  # string
            client_type => ...,  # string
            opensource => ...,  # bool
            opensource_info => ...,  # string
            rt_ticket => ...,  # int
            dns_root_origin => ...,  # string
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<zone> (hashref (VendorZone))

zone contains the vendor zone details


=item * B<organization_name> (string)

Additional fields for full details


=item * B<request_information> (string)


=item * B<device_count> (int)


=item * B<device_information> (string)


=item * B<contact_information> (string)


=item * B<client_type> (string)


=item * B<opensource> (bool)


=item * B<opensource_info> (string)


=item * B<rt_ticket> (int)


=item * B<dns_root_origin> (string)


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_vendor_zone(
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

sub get_vendor_zone {
    my $validation_error = validate_key_value_args('get_vendor_zone', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'id_token'} = delete $args{'id_token'} if exists $args{'id_token'};

    return connect_rpc(
        service     => 'ntppool.vendorzone.v1.VendorZoneService',
        method      => 'GetVendorZone',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 request_vendor_zone

RequestVendorZone creates a new vendor zone request (status=New).
The request must be submitted and approved before becoming active.
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have edit access to the account.

B<Arguments:>

    my $result = request_vendor_zone(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        zone_name => $value,       # string - zone_name is the requested zone name (required, e.g., "example")
        organization_name => $value,       # string - organization_name is the organization name (required)
        request_information => $value,       # string - request_information describes usage (required)
        device_count => $value,       # int - device_count is estimated number of devices (required)
        device_information => $value,       # string - device_information is implementation details (optional, admin-only)
        contact_information => $value,       # string - contact_information is NOC/engineering contacts (optional, admin-only)
        client_type => $value,       # string - client_type is the NTP client type (default: sntp)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            vendor_zone_id => ...,  # int - vendor_zone_id is the ID of the created request
            id_token => ...,  # string - id_token is the token ID (format: "vz_{token}")
            status => ...,  # string - status will be "New"
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = request_vendor_zone(
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

sub request_vendor_zone {
    my $validation_error = validate_key_value_args('request_vendor_zone', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'zone_name'} = delete $args{'zone_name'} if exists $args{'zone_name'};
    $request{'organization_name'} = delete $args{'organization_name'} if exists $args{'organization_name'};
    $request{'request_information'} = delete $args{'request_information'} if exists $args{'request_information'};
    $request{'device_count'} = delete $args{'device_count'} if exists $args{'device_count'};
    $request{'device_information'} = delete $args{'device_information'} if exists $args{'device_information'};
    $request{'contact_information'} = delete $args{'contact_information'} if exists $args{'contact_information'};
    $request{'client_type'} = delete $args{'client_type'} if exists $args{'client_type'};

    return connect_rpc(
        service     => 'ntppool.vendorzone.v1.VendorZoneService',
        method      => 'RequestVendorZone',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 update_vendor_zone

UpdateVendorZone updates vendor zone fields (only when status=New).
Authentication: Required via session middleware (sessions.GetUser).
Authorization: vendor_admin privilege OR (status=New AND user in account).

B<Arguments:>

    my $result = update_vendor_zone(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        id_token => $value,       # string - id_token identifies the zone (required, format: "vz_{token}")
        zone_name => $value,       # string - Fields to update (only provided fields are updated)
        organization_name => $value,       # string
        request_information => $value,       # string
        device_count => $value,       # int
        device_information => $value,       # string
        contact_information => $value,       # string
        client_type => $value,       # string
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool - success indicates if the update was successful
            zone => {
                vendor_zone_id => ...,  # int - vendor_zone_id is the numeric ID
                zone_name => ...,  # string - zone_name is the DNS zone name (e.g., "example")
                status => ...,  # string - status is the zone status (New, Pending, Approved, Rejected)
                created_on => ...,  # string - created_on is when the zone was requested (RFC3339)
                approved_on => ...,  # string - approved_on is when the zone was approved (RFC3339, empty if pending)
            },  # hashref (VendorZone) - zone contains the updated vendor zone
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<success> (bool)

success indicates if the update was successful


=item * B<zone> (hashref (VendorZone))

zone contains the updated vendor zone


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = update_vendor_zone(
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

sub update_vendor_zone {
    my $validation_error = validate_key_value_args('update_vendor_zone', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'id_token'} = delete $args{'id_token'} if exists $args{'id_token'};
    $request{'zone_name'} = delete $args{'zone_name'} if exists $args{'zone_name'};
    $request{'organization_name'} = delete $args{'organization_name'} if exists $args{'organization_name'};
    $request{'request_information'} = delete $args{'request_information'} if exists $args{'request_information'};
    $request{'device_count'} = delete $args{'device_count'} if exists $args{'device_count'};
    $request{'device_information'} = delete $args{'device_information'} if exists $args{'device_information'};
    $request{'contact_information'} = delete $args{'contact_information'} if exists $args{'contact_information'};
    $request{'client_type'} = delete $args{'client_type'} if exists $args{'client_type'};

    return connect_rpc(
        service     => 'ntppool.vendorzone.v1.VendorZoneService',
        method      => 'UpdateVendorZone',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 submit_vendor_zone

SubmitVendorZone submits zone for approval (New -> Pending).
Authentication: Required via session middleware (sessions.GetAccount).
Authorization: User must have edit access to the account.
Validates: subscription limits or opensource request.

B<Arguments:>

    my $result = submit_vendor_zone(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        id_token => $value,       # string - id_token identifies the zone (required, format: "vz_{token}")
        opensource => $value,       # bool - opensource indicates if requesting opensource exception
        opensource_info => $value,       # string - opensource_info is justification for opensource (required if opensource=true)
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool - success indicates if the submission was successful
            status => ...,  # string - status will be "Pending"
            needs_subscription => ...,  # bool - needs_subscription indicates if subscription is required
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = submit_vendor_zone(
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

sub submit_vendor_zone {
    my $validation_error = validate_key_value_args('submit_vendor_zone', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'id_token'} = delete $args{'id_token'} if exists $args{'id_token'};
    $request{'opensource'} = delete $args{'opensource'} if exists $args{'opensource'};
    $request{'opensource_info'} = delete $args{'opensource_info'} if exists $args{'opensource_info'};

    return connect_rpc(
        service     => 'ntppool.vendorzone.v1.VendorZoneService',
        method      => 'SubmitVendorZone',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 update_vendor_zone_status

UpdateVendorZoneStatus updates vendor zone status (admin only).
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User must have vendor_admin privilege.
Transitions: Pending->Approved, Pending->Rejected, Rejected->Approved.

B<Arguments:>

    my $result = update_vendor_zone_status(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        id_token => $value,       # string - id_token identifies the zone (required, format: "vz_{token}")
        status => $value,       # string - status is the new status (Approved, Rejected) (required)
        rt_ticket => $value,       # int - rt_ticket is optional admin tracking number
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool - success indicates if the update was successful
            status => ...,  # string - status is the new status
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = update_vendor_zone_status(
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

sub update_vendor_zone_status {
    my $validation_error = validate_key_value_args('update_vendor_zone_status', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'id_token'} = delete $args{'id_token'} if exists $args{'id_token'};
    $request{'status'} = delete $args{'status'} if exists $args{'status'};
    $request{'rt_ticket'} = delete $args{'rt_ticket'} if exists $args{'rt_ticket'};

    return connect_rpc(
        service     => 'ntppool.vendorzone.v1.VendorZoneService',
        method      => 'UpdateVendorZoneStatus',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/vendorzone/v1/vendor.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
