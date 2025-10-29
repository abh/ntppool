# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/audit/v1/audit.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Audit;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    get_account_audit_logs
);

=head1 NAME

NP::CAPI::Audit - ConnectRPC client for AuditService

=head1 SYNOPSIS

    use NP::CAPI::Audit qw(get_account_audit_logs);
    # GetAccountAuditLogs returns audit log entries for an account.
Includes related entity information (account, user, server) via JOINs.
Authentication: Required (sessions.GetUser and sessions.GetAccount from context)
Authorization: Staff only (support_staff privilege required)
    my $result = get_account_audit_logs(
        auth    => $user_token,
        account => $account_token,
        context => $request_context,
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.audit.v1.AuditService.

This module provides Perl wrappers for calling AuditService RPC methods
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


=head2 get_account_audit_logs

GetAccountAuditLogs returns audit log entries for an account.
Includes related entity information (account, user, server) via JOINs.
Authentication: Required (sessions.GetUser and sessions.GetAccount from context)
Authorization: Staff only (support_staff privilege required)

B<Arguments:>

    my $result = get_account_audit_logs(
        auth    => $user_token,      # Optional: User/session authentication token
        account => $account_token,   # Optional: Account selection token
        context => $request_context, # Optional: Request context for X-Forwarded-For
        types => $value,       # arrayref[string] - types optionally filters logs to specific types (e.g., ["invitation", "server-delete"])
 Empty array or omitted means no filtering by type.
        limit => $value,       # int - limit is the maximum number of logs to return (default: 50, max: 200)
        offset => $value,       # int - offset is the number of logs to skip for pagination (default: 0)
        sort_by => $value,       # string - sort_by determines the sort field (default: "created_on")
 Supported values: "created_on", "type"
        sort_order => $value,       # string - sort_order determines the sort direction (default: "desc")
 Supported values: "asc", "desc"
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            logs => [
            {
                id => ...,  # int - id is the database ID of the log entry
                type => ...,  # string - type is the log type (e.g., "invitation", "server-delete")
                message => ...,  # string - message is the human-readable log message
                created_on => ...,  # string - created_on is when the log entry was created (RFC3339 format)
                account => ...,  # hashref (RelatedAccount) - account is the related account information (if account_id is set)
                user => ...,  # hashref (RelatedUser) - user is the related user information (if user_id is set)
                server => ...,  # hashref (RelatedServer) - server is the related server information (if server_id is set)
                changes => ...,  # hashref (FieldChange) - changes is the list of field changes (parsed from JSON)
            },
            # ... more items
        ],  # arrayref[hashref (AuditLogEntry)] - logs is the list of audit log entries
            pagination => {
                total_count => ...,  # int - total_count is the total number of logs matching the query
                limit => ...,  # int - limit is the maximum number of logs returned
                offset => ...,  # int - offset is the starting position in the result set
                has_more => ...,  # bool - has_more indicates if there are more results beyond this page
            },  # hashref (PaginationInfo) - pagination contains information about the result set
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<logs> (arrayref[hashref (AuditLogEntry)])

logs is the list of audit log entries


=item * B<pagination> (hashref (PaginationInfo))

pagination contains information about the result set


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account_audit_logs(
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

sub get_account_audit_logs {
    my $validation_error = validate_key_value_args('get_account_audit_logs', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'types'} = delete $args{'types'} if exists $args{'types'};
    $request{'limit'} = delete $args{'limit'} if exists $args{'limit'};
    $request{'offset'} = delete $args{'offset'} if exists $args{'offset'};
    $request{'sort_by'} = delete $args{'sort_by'} if exists $args{'sort_by'};
    $request{'sort_order'} = delete $args{'sort_order'} if exists $args{'sort_order'};

    return connect_rpc(
        service     => 'ntppool.audit.v1.AuditService',
        method      => 'GetAccountAuditLogs',
        request     => \%request,
        http_method => 'GET',  # Side-effect free, use GET
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/audit/v1/audit.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
