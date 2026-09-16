# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/subscription/v1/subscription.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Subscription;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    process_stripe_webhook
    update_account_stripe_customer
    get_account_subscription_status
    get_account_subscriptions
    SUBMIT_STATE_UNSPECIFIED
    SUBMIT_STATE_COVERED
    SUBMIT_STATE_NEEDS_SUBSCRIPTION
    SUBMIT_STATE_OVER_LIMIT
);

# Enum constants
use constant {
    SUBMIT_STATE_UNSPECIFIED => 'SUBMIT_STATE_UNSPECIFIED',
    SUBMIT_STATE_COVERED => 'SUBMIT_STATE_COVERED',
    SUBMIT_STATE_NEEDS_SUBSCRIPTION => 'SUBMIT_STATE_NEEDS_SUBSCRIPTION',
    SUBMIT_STATE_OVER_LIMIT => 'SUBMIT_STATE_OVER_LIMIT',
};

=head1 NAME

NP::CAPI::Subscription - ConnectRPC client for SubscriptionService

=head1 SYNOPSIS

    use NP::CAPI::Subscription qw(process_stripe_webhook update_account_stripe_customer get_account_subscription_status get_account_subscriptions);
    # Call ProcessStripeWebhook RPC method
    my $result = process_stripe_webhook(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # Call UpdateAccountStripeCustomer RPC method
    my $result = update_account_stripe_customer(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # Call GetAccountSubscriptionStatus RPC method
    my $result = get_account_subscription_status(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # Call GetAccountSubscriptions RPC method
    my $result = get_account_subscriptions(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.subscription.v1.SubscriptionService.

This module provides Perl wrappers for calling SubscriptionService RPC methods
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


=head2 process_stripe_webhook

Call ProcessStripeWebhook RPC method

B<Arguments:>

    my $result = process_stripe_webhook(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        stripe_subscription_id => $value,       # string
        stripe_customer_id => $value,       # string
        status => $value,       # string
        created_on_unix => $value,       # int
        ended_on_unix => $value,       # int
        name => $value,       # string
        max_zones => $value,       # int
        max_devices => $value,       # int
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool
            error => ...,  # string
            account_token => ...,  # string
            subscription => {
                subscription_id => ...,  # int
                stripe_subscription_id => ...,  # string
                status => ...,  # string
                name => ...,  # string
                max_zones => ...,  # int
                max_devices => ...,  # int
                live_subscription => ...,  # bool
                created_on => ...,  # string
                ended_on => ...,  # string
                stripe_dashboard_link => ...,  # string
            },  # hashref (AccountSubscription) - subscription is the row as saved, including live_subscription. Unset when
 success is false.
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<success> (bool)


=item * B<error> (string)


=item * B<account_token> (string)


=item * B<subscription> (hashref (AccountSubscription))

subscription is the row as saved, including live_subscription. Unset when
 success is false.


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = process_stripe_webhook(
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

sub process_stripe_webhook {
    my $validation_error = validate_key_value_args('process_stripe_webhook', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'stripe_subscription_id'} = delete $args{'stripe_subscription_id'} if exists $args{'stripe_subscription_id'};
    $request{'stripe_customer_id'} = delete $args{'stripe_customer_id'} if exists $args{'stripe_customer_id'};
    $request{'status'} = delete $args{'status'} if exists $args{'status'};
    $request{'created_on_unix'} = delete $args{'created_on_unix'} if exists $args{'created_on_unix'};
    $request{'ended_on_unix'} = delete $args{'ended_on_unix'} if exists $args{'ended_on_unix'};
    $request{'name'} = delete $args{'name'} if exists $args{'name'};
    $request{'max_zones'} = delete $args{'max_zones'} if exists $args{'max_zones'};
    $request{'max_devices'} = delete $args{'max_devices'} if exists $args{'max_devices'};

    return connect_rpc(
        service     => 'ntppool.subscription.v1.SubscriptionService',
        method      => 'ProcessStripeWebhook',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 update_account_stripe_customer

Call UpdateAccountStripeCustomer RPC method

B<Arguments:>

    my $result = update_account_stripe_customer(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        stripe_customer_id => $value,       # string
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            success => ...,  # bool
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = update_account_stripe_customer(
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

sub update_account_stripe_customer {
    my $validation_error = validate_key_value_args('update_account_stripe_customer', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'stripe_customer_id'} = delete $args{'stripe_customer_id'} if exists $args{'stripe_customer_id'};

    return connect_rpc(
        service     => 'ntppool.subscription.v1.SubscriptionService',
        method      => 'UpdateAccountStripeCustomer',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_account_subscription_status

Call GetAccountSubscriptionStatus RPC method

B<Arguments:>

    my $result = get_account_subscription_status(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        account_token => $value,       # string
        device_count => $value,       # int
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            has_live_subscription => ...,  # bool
            limits_exceeded => ...,  # bool
            limits_error => ...,  # string
            existing_devices => ...,  # int
            existing_zones => ...,  # int
            max_devices => ...,  # int
            max_zones => ...,  # int
            submit_state => ...,  # string (enum: SubmitState)
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account_subscription_status(
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

sub get_account_subscription_status {
    my $validation_error = validate_key_value_args('get_account_subscription_status', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'account_token'} = delete $args{'account_token'} if exists $args{'account_token'};
    $request{'device_count'} = delete $args{'device_count'} if exists $args{'device_count'};

    return connect_rpc(
        service     => 'ntppool.subscription.v1.SubscriptionService',
        method      => 'GetAccountSubscriptionStatus',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_account_subscriptions

Call GetAccountSubscriptions RPC method

B<Arguments:>

    my $result = get_account_subscriptions(
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
            subscriptions => [
            {
                subscription_id => ...,  # int
                stripe_subscription_id => ...,  # string
                status => ...,  # string
                name => ...,  # string
                max_zones => ...,  # int
                max_devices => ...,  # int
                live_subscription => ...,  # bool
                created_on => ...,  # string
                ended_on => ...,  # string
                stripe_dashboard_link => ...,  # string
            },
            # ... more items
        ],  # arrayref[hashref (AccountSubscription)]
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<subscriptions> (arrayref[hashref (AccountSubscription)])


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_account_subscriptions(
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

sub get_account_subscriptions {
    my $validation_error = validate_key_value_args('get_account_subscriptions', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();

    return connect_rpc(
        service     => 'ntppool.subscription.v1.SubscriptionService',
        method      => 'GetAccountSubscriptions',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/subscription/v1/subscription.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
