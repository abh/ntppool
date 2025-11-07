# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/zone/v1/zone.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Zone;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    list_zones
    get_zone
);

=head1 NAME

NP::CAPI::Zone - ConnectRPC client for ZoneService

=head1 SYNOPSIS

    use NP::CAPI::Zone qw(list_zones get_zone);
    # ListZones returns all zones in the hierarchy for homepage display.
Returns continental/regional zones with current server counts.
No authentication required - all data is public.
    my $result = list_zones(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetZone returns detailed information about a specific zone.
Includes parent/child relationships and historical statistics.
No authentication required - all data is public.
    my $result = get_zone(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.zone.v1.ZoneService.

This module provides Perl wrappers for calling ZoneService RPC methods
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


=head2 list_zones

ListZones returns all zones in the hierarchy for homepage display.
Returns continental/regional zones with current server counts.
No authentication required - all data is public.

B<Arguments:>

    my $result = list_zones(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        parent => $value,       # string - parent is the parent zone name to list children for (e.g., "@" for continents)
 If empty, returns top-level zones (continents + @ + .)
 Special values: "@" for continents, "." is invalid (has no children)
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
                name => ...,  # string - name is the zone identifier (e.g., "na", "eu", "@", ".")
                description => ...,  # string - description is the human-readable zone name (e.g., "North America", "Global")
                url => ...,  # string - url is the relative path to the zone page (e.g., "/zone/na")
                server_count => ...,  # int - server_count is the total number of active servers in this zone
                dns => ...,  # bool - dns indicates whether this zone has a DNS entry
            },
            # ... more items
        ],  # arrayref[hashref (ZoneSummary)] - zones is the list of all zones with current server counts
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<zones> (arrayref[hashref (ZoneSummary)])

zones is the list of all zones with current server counts


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = list_zones(
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

sub list_zones {
    my $validation_error = validate_key_value_args('list_zones', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'parent'} = delete $args{'parent'} if exists $args{'parent'};

    return connect_rpc(
        service     => 'ntppool.zone.v1.ZoneService',
        method      => 'ListZones',
        request     => \%request,
        http_method => 'GET',  # Side-effect free, use GET
        %args  # Pass through auth, account, context
    );
}


=head2 get_zone

GetZone returns detailed information about a specific zone.
Includes parent/child relationships and historical statistics.
No authentication required - all data is public.

B<Arguments:>

    my $result = get_zone(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        name => $value,       # string - name is the zone identifier (e.g., "na", "us", "@", ".")
        basic_only => $value,       # bool - basic_only when true returns only basic zone information (name, description, dns, parents)
 without fetching server counts, children, or historical statistics
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            zone => {
                id => ...,  # int - id is the database ID of the zone
                name => ...,  # string - name is the zone identifier (e.g., "na", "us")
                description => ...,  # string - description is the human-readable zone name (e.g., "North America", "United States")
                url => ...,  # string - url is the relative path to the zone page (e.g., "/zone/na")
                fqdn => ...,  # string - fqdn is the fully qualified domain name (e.g., "na.pool.ntp.org")
                dns => ...,  # bool - dns indicates whether this zone has a DNS entry
                sub_zone_count => ...,  # int - sub_zone_count is always 4 (constant)
                parents => ...,  # arrayref[hashref (ZoneReference)] - parents contains all parent zones ordered from immediate parent to root
 Example: for zone "us.ca", parents would be ["us", "na", "@"]
                children => ...,  # arrayref[hashref (ZoneReference)] - children are the child zones of this zone
                server_counts => ...,  # hashref (ServerCounts) - server_counts contains the current active server counts by IP version
                historical_stats => ...,  # arrayref[hashref (HistoricalStats)] - historical_stats contains historical statistics for both IP versions
            },  # hashref (Zone) - zone contains the complete zone information
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<zone> (hashref (Zone))

zone contains the complete zone information


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_zone(
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

sub get_zone {
    my $validation_error = validate_key_value_args('get_zone', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'name'} = delete $args{'name'} if exists $args{'name'};
    $request{'basic_only'} = delete $args{'basic_only'} if exists $args{'basic_only'};

    return connect_rpc(
        service     => 'ntppool.zone.v1.ZoneService',
        method      => 'GetZone',
        request     => \%request,
        http_method => 'GET',  # Side-effect free, use GET
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/zone/v1/zone.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
