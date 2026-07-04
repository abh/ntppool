# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/monitorreg/v1/registration.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::MonitorRegistration;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    get_registration_data
    accept_registration
    PENDING
    COMPLETED
    ACCEPTED
    CONFLICT
    GONE
);

# Enum constants
use constant {
    PENDING => 'PENDING',
    COMPLETED => 'COMPLETED',
    ACCEPTED => 'ACCEPTED',
    CONFLICT => 'CONFLICT',
    GONE => 'GONE',
};

=head1 NAME

NP::CAPI::MonitorRegistration - ConnectRPC client for MonitorRegistrationService

=head1 SYNOPSIS

    use NP::CAPI::MonitorRegistration qw(get_registration_data accept_registration);
    # Call GetRegistrationData RPC method
    my $result = get_registration_data(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # Call AcceptRegistration RPC method
    my $result = accept_registration(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.monitorreg.v1.MonitorRegistrationService.

This module provides Perl wrappers for calling MonitorRegistrationService RPC methods
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


=head2 get_registration_data

Call GetRegistrationData RPC method

B<Arguments:>

    my $result = get_registration_data(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        token => $value,       # string
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            registration_state => ...,  # string (enum: RegistrationState)
            code => ...,  # int
            status => ...,  # string
            client => ...,  # string
            hostname => ...,  # string
            tls_name => ...,  # string
            ip4 => ...,  # string
            ip6 => ...,  # string
            precheck => {
                code => ...,  # string
                message => ...,  # string
                monitors => ...,  # arrayref[hashref (RegistrationMonitor)]
                delete_monitors => ...,  # arrayref[hashref (RegistrationMonitor)]
                new_ips => ...,  # arrayref[string]
            },  # hashref (RegistrationPrecheck)
            locations => [
            {
                code => ...,  # string
                name => ...,  # string
            },
            # ... more items
        ],  # arrayref[hashref (Location)]
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<registration_state> (string (enum: RegistrationState))


=item * B<code> (int)


=item * B<status> (string)


=item * B<client> (string)


=item * B<hostname> (string)


=item * B<tls_name> (string)


=item * B<ip4> (string)


=item * B<ip6> (string)


=item * B<precheck> (hashref (RegistrationPrecheck))


=item * B<locations> (arrayref[hashref (Location)])


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_registration_data(
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

sub get_registration_data {
    my $validation_error = validate_key_value_args('get_registration_data', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'token'} = delete $args{'token'} if exists $args{'token'};

    return connect_rpc(
        service     => 'ntppool.monitorreg.v1.MonitorRegistrationService',
        method      => 'GetRegistrationData',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 accept_registration

Call AcceptRegistration RPC method

B<Arguments:>

    my $result = accept_registration(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        token => $value,       # string
        location_code => $value,       # string
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            registration_state => ...,  # string (enum: RegistrationState)
            code => ...,  # int
            status => ...,  # string
            tls_name => ...,  # string
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = accept_registration(
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

sub accept_registration {
    my $validation_error = validate_key_value_args('accept_registration', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'token'} = delete $args{'token'} if exists $args{'token'};
    $request{'location_code'} = delete $args{'location_code'} if exists $args{'location_code'};

    return connect_rpc(
        service     => 'ntppool.monitorreg.v1.MonitorRegistrationService',
        method      => 'AcceptRegistration',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/monitorreg/v1/registration.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
