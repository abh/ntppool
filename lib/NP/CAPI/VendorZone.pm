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
    list_vendor_zones_admin
    get_vendor_zone_form_metadata
);

=head1 NAME

NP::CAPI::VendorZone - ConnectRPC client for VendorZoneService

=head1 SYNOPSIS

    use NP::CAPI::VendorZone qw(list_vendor_zones get_vendor_zone request_vendor_zone update_vendor_zone submit_vendor_zone update_vendor_zone_status list_vendor_zones_admin get_vendor_zone_form_metadata);
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

    # ListVendorZonesAdmin lists all vendor zones (admin only).
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User must have vendor_admin privilege.
Returns: All zones across all accounts, with filtering options.
    my $result = list_vendor_zones_admin(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetVendorZoneFormMetadata returns metadata for the vendor zone form.
Authentication: Required via session middleware (sessions.GetUser).
Returns: Available DNS roots and other form options.
    my $result = get_vendor_zone_form_metadata(
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
                vendor_zone_id => ...,  # int - Core identification
 vendor_zone_id is the numeric ID
                id_token => ...,  # string - id_token is the token ID (format: "vz_{token}")
                zone_name => ...,  # string - zone_name is the DNS zone name (e.g., "example")
                status => ...,  # string - status is the zone status (New, Pending, Approved, Rejected)
                created_on => ...,  # string - created_on is when the zone was requested (RFC3339)
                approved_on => ...,  # string - approved_on is when the zone was approved (RFC3339, empty if pending)
                organization_name => ...,  # string - Zone details
 organization_name is the organization name
                request_information => ...,  # string - request_information describes usage
                device_count => ...,  # int - device_count is estimated number of devices
                device_information => ...,  # string - device_information is implementation details (admin-only)
                contact_information => ...,  # string - contact_information is NOC/engineering contacts (admin-only)
                client_type => ...,  # string - client_type is the NTP client type (sntp, ntp, legacy)
                opensource => ...,  # bool - opensource indicates if using opensource exception
                opensource_info => ...,  # string - opensource_info is justification for opensource
                rt_ticket => ...,  # int - rt_ticket is optional admin tracking number
                dns_root_origin => ...,  # string - dns_root_origin is the DNS root domain (e.g., "pool.ntp.org")
                account_token => ...,  # string - account_token identifies the owning account
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
                vendor_zone_id => ...,  # int - Core identification
 vendor_zone_id is the numeric ID
                id_token => ...,  # string - id_token is the token ID (format: "vz_{token}")
                zone_name => ...,  # string - zone_name is the DNS zone name (e.g., "example")
                status => ...,  # string - status is the zone status (New, Pending, Approved, Rejected)
                created_on => ...,  # string - created_on is when the zone was requested (RFC3339)
                approved_on => ...,  # string - approved_on is when the zone was approved (RFC3339, empty if pending)
                organization_name => ...,  # string - Zone details
 organization_name is the organization name
                request_information => ...,  # string - request_information describes usage
                device_count => ...,  # int - device_count is estimated number of devices
                device_information => ...,  # string - device_information is implementation details (admin-only)
                contact_information => ...,  # string - contact_information is NOC/engineering contacts (admin-only)
                client_type => ...,  # string - client_type is the NTP client type (sntp, ntp, legacy)
                opensource => ...,  # bool - opensource indicates if using opensource exception
                opensource_info => ...,  # string - opensource_info is justification for opensource
                rt_ticket => ...,  # int - rt_ticket is optional admin tracking number
                dns_root_origin => ...,  # string - dns_root_origin is the DNS root domain (e.g., "pool.ntp.org")
                account_token => ...,  # string - account_token identifies the owning account
            },  # hashref (VendorZone) - zone contains the complete vendor zone details
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<zone> (hashref (VendorZone))

zone contains the complete vendor zone details


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
            zone => {
                vendor_zone_id => ...,  # int - Core identification
 vendor_zone_id is the numeric ID
                id_token => ...,  # string - id_token is the token ID (format: "vz_{token}")
                zone_name => ...,  # string - zone_name is the DNS zone name (e.g., "example")
                status => ...,  # string - status is the zone status (New, Pending, Approved, Rejected)
                created_on => ...,  # string - created_on is when the zone was requested (RFC3339)
                approved_on => ...,  # string - approved_on is when the zone was approved (RFC3339, empty if pending)
                organization_name => ...,  # string - Zone details
 organization_name is the organization name
                request_information => ...,  # string - request_information describes usage
                device_count => ...,  # int - device_count is estimated number of devices
                device_information => ...,  # string - device_information is implementation details (admin-only)
                contact_information => ...,  # string - contact_information is NOC/engineering contacts (admin-only)
                client_type => ...,  # string - client_type is the NTP client type (sntp, ntp, legacy)
                opensource => ...,  # bool - opensource indicates if using opensource exception
                opensource_info => ...,  # string - opensource_info is justification for opensource
                rt_ticket => ...,  # int - rt_ticket is optional admin tracking number
                dns_root_origin => ...,  # string - dns_root_origin is the DNS root domain (e.g., "pool.ntp.org")
                account_token => ...,  # string - account_token identifies the owning account
            },  # hashref (VendorZone) - zone contains the complete vendor zone details
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<vendor_zone_id> (int)

vendor_zone_id is the ID of the created request


=item * B<id_token> (string)

id_token is the token ID (format: "vz_{token}")


=item * B<status> (string)

status will be "New"


=item * B<zone> (hashref (VendorZone))

zone contains the complete vendor zone details


=back

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
        content => $value,       # hashref (VendorZoneContent) - content holds the fields to update (only provided fields are applied)
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
                vendor_zone_id => ...,  # int - Core identification
 vendor_zone_id is the numeric ID
                id_token => ...,  # string - id_token is the token ID (format: "vz_{token}")
                zone_name => ...,  # string - zone_name is the DNS zone name (e.g., "example")
                status => ...,  # string - status is the zone status (New, Pending, Approved, Rejected)
                created_on => ...,  # string - created_on is when the zone was requested (RFC3339)
                approved_on => ...,  # string - approved_on is when the zone was approved (RFC3339, empty if pending)
                organization_name => ...,  # string - Zone details
 organization_name is the organization name
                request_information => ...,  # string - request_information describes usage
                device_count => ...,  # int - device_count is estimated number of devices
                device_information => ...,  # string - device_information is implementation details (admin-only)
                contact_information => ...,  # string - contact_information is NOC/engineering contacts (admin-only)
                client_type => ...,  # string - client_type is the NTP client type (sntp, ntp, legacy)
                opensource => ...,  # bool - opensource indicates if using opensource exception
                opensource_info => ...,  # string - opensource_info is justification for opensource
                rt_ticket => ...,  # int - rt_ticket is optional admin tracking number
                dns_root_origin => ...,  # string - dns_root_origin is the DNS root domain (e.g., "pool.ntp.org")
                account_token => ...,  # string - account_token identifies the owning account
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
    $request{'content'} = delete $args{'content'} if exists $args{'content'};

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
        content => $value,       # hashref (VendorZoneContent) - content holds any final edits to apply before submission (optional).
 opensource / opensource_info live here.
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
            zone => {
                vendor_zone_id => ...,  # int - Core identification
 vendor_zone_id is the numeric ID
                id_token => ...,  # string - id_token is the token ID (format: "vz_{token}")
                zone_name => ...,  # string - zone_name is the DNS zone name (e.g., "example")
                status => ...,  # string - status is the zone status (New, Pending, Approved, Rejected)
                created_on => ...,  # string - created_on is when the zone was requested (RFC3339)
                approved_on => ...,  # string - approved_on is when the zone was approved (RFC3339, empty if pending)
                organization_name => ...,  # string - Zone details
 organization_name is the organization name
                request_information => ...,  # string - request_information describes usage
                device_count => ...,  # int - device_count is estimated number of devices
                device_information => ...,  # string - device_information is implementation details (admin-only)
                contact_information => ...,  # string - contact_information is NOC/engineering contacts (admin-only)
                client_type => ...,  # string - client_type is the NTP client type (sntp, ntp, legacy)
                opensource => ...,  # bool - opensource indicates if using opensource exception
                opensource_info => ...,  # string - opensource_info is justification for opensource
                rt_ticket => ...,  # int - rt_ticket is optional admin tracking number
                dns_root_origin => ...,  # string - dns_root_origin is the DNS root domain (e.g., "pool.ntp.org")
                account_token => ...,  # string - account_token identifies the owning account
            },  # hashref (VendorZone) - zone contains the complete vendor zone details (for email template)
            email_sent => ...,  # bool - email_sent indicates if the notification email was sent successfully
            user_email => ...,  # string - user_email is the zone owner's email address
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<success> (bool)

success indicates if the submission was successful


=item * B<status> (string)

status will be "Pending"


=item * B<needs_subscription> (bool)

needs_subscription indicates if subscription is required


=item * B<zone> (hashref (VendorZone))

zone contains the complete vendor zone details (for email template)


=item * B<email_sent> (bool)

email_sent indicates if the notification email was sent successfully


=item * B<user_email> (string)

user_email is the zone owner's email address


=back

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
    $request{'content'} = delete $args{'content'} if exists $args{'content'};

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
            zone => {
                vendor_zone_id => ...,  # int - Core identification
 vendor_zone_id is the numeric ID
                id_token => ...,  # string - id_token is the token ID (format: "vz_{token}")
                zone_name => ...,  # string - zone_name is the DNS zone name (e.g., "example")
                status => ...,  # string - status is the zone status (New, Pending, Approved, Rejected)
                created_on => ...,  # string - created_on is when the zone was requested (RFC3339)
                approved_on => ...,  # string - approved_on is when the zone was approved (RFC3339, empty if pending)
                organization_name => ...,  # string - Zone details
 organization_name is the organization name
                request_information => ...,  # string - request_information describes usage
                device_count => ...,  # int - device_count is estimated number of devices
                device_information => ...,  # string - device_information is implementation details (admin-only)
                contact_information => ...,  # string - contact_information is NOC/engineering contacts (admin-only)
                client_type => ...,  # string - client_type is the NTP client type (sntp, ntp, legacy)
                opensource => ...,  # bool - opensource indicates if using opensource exception
                opensource_info => ...,  # string - opensource_info is justification for opensource
                rt_ticket => ...,  # int - rt_ticket is optional admin tracking number
                dns_root_origin => ...,  # string - dns_root_origin is the DNS root domain (e.g., "pool.ntp.org")
                account_token => ...,  # string - account_token identifies the owning account
            },  # hashref (VendorZone) - zone contains the complete vendor zone details (for email template)
            user_email => ...,  # string - user_email is the zone owner's email address (for approval emails)
            email_sent => ...,  # bool - email_sent indicates if the notification email was sent successfully
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<success> (bool)

success indicates if the update was successful


=item * B<status> (string)

status is the new status


=item * B<zone> (hashref (VendorZone))

zone contains the complete vendor zone details (for email template)


=item * B<user_email> (string)

user_email is the zone owner's email address (for approval emails)


=item * B<email_sent> (bool)

email_sent indicates if the notification email was sent successfully


=back

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


=head2 list_vendor_zones_admin

ListVendorZonesAdmin lists all vendor zones (admin only).
Authentication: Required via session middleware (sessions.GetUser).
Authorization: User must have vendor_admin privilege.
Returns: All zones across all accounts, with filtering options.

B<Arguments:>

    my $result = list_vendor_zones_admin(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        status => $value,       # string - status filters by status (optional, e.g., "Pending")
        sort_by => $value,       # string - sort_by specifies sort order (optional, default: created_on desc)
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
                zone => ...,  # hashref (VendorZone) - zone contains the complete vendor zone
                account_name => ...,  # string - account_name is the account name
                user_email => ...,  # string - user_email is the zone owner's email address
                subscription_created_on => ...,  # string - subscription_created_on is when the subscription started (RFC3339, empty if no subscription)
            },
            # ... more items
        ],  # arrayref[hashref (VendorZoneAdmin)] - zones is the list of vendor zones with account details
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<zones> (arrayref[hashref (VendorZoneAdmin)])

zones is the list of vendor zones with account details


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = list_vendor_zones_admin(
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

sub list_vendor_zones_admin {
    my $validation_error = validate_key_value_args('list_vendor_zones_admin', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'status'} = delete $args{'status'} if exists $args{'status'};
    $request{'sort_by'} = delete $args{'sort_by'} if exists $args{'sort_by'};

    return connect_rpc(
        service     => 'ntppool.vendorzone.v1.VendorZoneService',
        method      => 'ListVendorZonesAdmin',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_vendor_zone_form_metadata

GetVendorZoneFormMetadata returns metadata for the vendor zone form.
Authentication: Required via session middleware (sessions.GetUser).
Returns: Available DNS roots and other form options.

B<Arguments:>

    my $result = get_vendor_zone_form_metadata(
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
            dns_roots => [
            {
                dns_root_id => ...,  # int - dns_root_id is the numeric ID
                origin => ...,  # string - origin is the DNS root domain (e.g., "pool.ntp.org")
                vendor_available => ...,  # bool - vendor_available indicates if this root is available for vendor zones
            },
            # ... more items
        ],  # arrayref[hashref (DNSRoot)] - dns_roots is the list of available DNS roots for vendor zones
            default_dns_root_id => ...,  # int - default_dns_root_id is the default DNS root to use
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<dns_roots> (arrayref[hashref (DNSRoot)])

dns_roots is the list of available DNS roots for vendor zones


=item * B<default_dns_root_id> (int)

default_dns_root_id is the default DNS root to use


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_vendor_zone_form_metadata(
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

sub get_vendor_zone_form_metadata {
    my $validation_error = validate_key_value_args('get_vendor_zone_form_metadata', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.vendorzone.v1.VendorZoneService',
        method      => 'GetVendorZoneFormMetadata',
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
