# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/search/v1/search.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Search;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    search
);

=head1 NAME

NP::CAPI::Search - ConnectRPC client for SearchService

=head1 SYNOPSIS

    use NP::CAPI::Search qw(search);
    # Search dispatches a query across accounts, users, servers, and monitors.
The query is interpreted by prefix/shape: an IP address searches
servers/monitors by IP; "id:N" looks up an account by numeric ID;
"monitors:" lists accounts that have monitors; "zone:NAME" lists
accounts with servers in that zone; anything else is a pattern search
across account/user/server/monitor fields.
Authentication: Required via session middleware.
Authorization: Staff only (support_staff privilege required).
    my $result = search(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.search.v1.SearchService.

This module provides Perl wrappers for calling SearchService RPC methods
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


=head2 search

Search dispatches a query across accounts, users, servers, and monitors.
The query is interpreted by prefix/shape: an IP address searches
servers/monitors by IP; "id:N" looks up an account by numeric ID;
"monitors:" lists accounts that have monitors; "zone:NAME" lists
accounts with servers in that zone; anything else is a pattern search
across account/user/server/monitor fields.
Authentication: Required via session middleware.
Authorization: Staff only (support_staff privilege required).

B<Arguments:>

    my $result = search(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        query => $value,       # string - query is the raw search string (IP, "id:N", "monitors:", "zone:NAME",
 or a free-text pattern). Required, must be non-empty after trimming.
        include_deleted => $value,       # bool - include_deleted includes servers/monitors that have a deletion_on set.
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
                id_token => ...,  # string - id_token is the account's public identifier token.
                name => ...,  # string
                users => ...,  # hashref (User)
                servers => ...,  # hashref (Server)
                monitors => ...,  # hashref (Monitor)
            },
            # ... more items
        ],  # arrayref[hashref (Account)] - accounts is the list of matched accounts with their nested users,
 servers, and monitors. Empty (not an error) when nothing matches.
            filter_context => {
                search_type => ...,  # string - search_type is one of "monitors", "zone", "pattern", "ip", "id".
                zone_name => ...,  # string - zone_name is the zone searched, set only when search_type is "zone".
                show_monitors_only => ...,  # bool - show_monitors_only hints the UI to highlight the monitors section.
                show_zone_servers_only => ...,  # bool - show_zone_servers_only hints the UI to highlight servers in zone_name.
            },  # hashref (FilterContext) - filter_context provides UI hints for "monitors:"/"zone:" searches
 (e.g. which section to highlight). Absent for other query types.
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<accounts> (arrayref[hashref (Account)])

accounts is the list of matched accounts with their nested users,
 servers, and monitors. Empty (not an error) when nothing matches.


=item * B<filter_context> (hashref (FilterContext))

filter_context provides UI hints for "monitors:"/"zone:" searches
 (e.g. which section to highlight). Absent for other query types.


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = search(
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

sub search {
    my $validation_error = validate_key_value_args('search', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'query'} = delete $args{'query'} if exists $args{'query'};
    $request{'include_deleted'} = delete $args{'include_deleted'} if exists $args{'include_deleted'};

    return connect_rpc(
        service     => 'ntppool.search.v1.SearchService',
        method      => 'Search',
        request     => \%request,
        http_method => 'GET',  # Side-effect free, use GET
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/search/v1/search.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
