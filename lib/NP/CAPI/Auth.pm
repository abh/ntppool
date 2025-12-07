# GENERATED CODE - DO NOT EDIT
# Generated from: ntppool/auth/v1/auth.proto
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Auth;
use strict;
use warnings;
use NP::CAPI qw(connect_rpc);
use NP::CAPI::Util qw(validate_key_value_args);
use Exporter 'import';

our @EXPORT_OK = qw(
    process_auth0_login
    get_oauth_login_url
);

=head1 NAME

NP::CAPI::Auth - ConnectRPC client for AuthService

=head1 SYNOPSIS

    use NP::CAPI::Auth qw(process_auth0_login get_oauth_login_url);
    # ProcessAuth0Login handles the Auth0 authorization code callback.
It validates the authorization code with Auth0, creates or updates user and identity records,
creates a session, and returns the session token for cookie storage.
This is an internal-only endpoint called by the Perl frontend after Auth0 redirects.
Authentication: None required (this endpoint creates authentication).
    my $result = process_auth0_login(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );

    # GetOAuthLoginURL generates an OAuth authorization URL for the authentication flow.
This removes OAuth provider configuration from Perl, centralizing it in the Go API.
The URL includes the environment-specific audience parameter and CSRF state token.
Authentication: None required (this starts the authentication flow).
    my $result = get_oauth_login_url(
        $self->api_auth_params,      # Provides auth and context
        account => $account->{id_token},
    );


=head1 DESCRIPTION

Auto-generated ConnectRPC client for ntppool.auth.v1.AuthService.

This module provides Perl wrappers for calling AuthService RPC methods
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


=head2 process_auth0_login

ProcessAuth0Login handles the Auth0 authorization code callback.
It validates the authorization code with Auth0, creates or updates user and identity records,
creates a session, and returns the session token for cookie storage.
This is an internal-only endpoint called by the Perl frontend after Auth0 redirects.
Authentication: None required (this endpoint creates authentication).

B<Arguments:>

    my $result = process_auth0_login(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        authorization_code => $value,       # string - authorization_code is the code parameter from Auth0's authorization callback.
 Required. This will be exchanged for an access token with Auth0.
        state => $value,       # string - state is the CSRF protection state token from the callback URL.
 Required for logging and validation.
        redirect_uri => $value,       # string - redirect_uri is the callback URL that was used in the original authorization request.
 Must match exactly for Auth0 token exchange. Required.
        client_site => $value,       # string - client_site identifies which site initiated the login (e.g., "manage", "www").
 Used to determine which Auth0 client configuration to use. Required.
        audience => $value,       # string - audience is the Auth0 API audience identifier for token exchange.
 Should be environment-specific: "api-dev", "api-test", or "api-prod".
 Optional - if not provided, token exchange will work without audience.
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            session_token => ...,  # string - session_token is the session key to set as the npuid cookie.
 Format: "nps_{key}_{checksum}"
            user_id => ...,  # int - user_id is the numeric ID of the authenticated user.
            id_token => ...,  # string - id_token is the user's id_token for identification.
            email => ...,  # string - email is the user's email address from Auth0.
            username => ...,  # string - username is the user's username.
            deletion_cancelled => ...,  # bool - deletion_cancelled indicates if a pending user deletion was cancelled during login.
            account => {
                account_id => ...,  # int - Core database fields
                id_token => ...,  # string
                name => ...,  # string
                organization_name => ...,  # string
                organization_url => ...,  # string
                url_slug => ...,  # string
                public_profile => ...,  # bool
                flags => ...,  # string
                created_on => ...,  # string
                modified_on => ...,  # string
                url => ...,  # string - Computed fields (always included)
                public_url => ...,  # string
                display_name => ...,  # string
            },  # hashref (AccountContext) - account is the user's default account (or auto-created account).
 Omitted if user has no accounts (meaning they have pending invitations).
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<Response Data Structure:>

The C<data> field contains:

=over 4

=item * B<session_token> (string)

session_token is the session key to set as the npuid cookie.
 Format: "nps_{key}_{checksum}"


=item * B<user_id> (int)

user_id is the numeric ID of the authenticated user.


=item * B<id_token> (string)

id_token is the user's id_token for identification.


=item * B<email> (string)

email is the user's email address from Auth0.


=item * B<username> (string)

username is the user's username.


=item * B<deletion_cancelled> (bool)

deletion_cancelled indicates if a pending user deletion was cancelled during login.


=item * B<account> (hashref (AccountContext))

account is the user's default account (or auto-created account).
 Omitted if user has no accounts (meaning they have pending invitations).


=back

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = process_auth0_login(
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

sub process_auth0_login {
    my $validation_error = validate_key_value_args('process_auth0_login', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'authorization_code'} = delete $args{'authorization_code'} if exists $args{'authorization_code'};
    $request{'state'} = delete $args{'state'} if exists $args{'state'};
    $request{'redirect_uri'} = delete $args{'redirect_uri'} if exists $args{'redirect_uri'};
    $request{'client_site'} = delete $args{'client_site'} if exists $args{'client_site'};
    $request{'audience'} = delete $args{'audience'} if exists $args{'audience'};

    return connect_rpc(
        service     => 'ntppool.auth.v1.AuthService',
        method      => 'ProcessAuth0Login',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}


=head2 get_oauth_login_url

GetOAuthLoginURL generates an OAuth authorization URL for the authentication flow.
This removes OAuth provider configuration from Perl, centralizing it in the Go API.
The URL includes the environment-specific audience parameter and CSRF state token.
Authentication: None required (this starts the authentication flow).

B<Arguments:>

    my $result = get_oauth_login_url(
        $self->api_auth_params,      # Provides auth (user/session token) and context (X-Forwarded-For)
        account => $account->{id_token},  # Optional: Account selection token
        redirect_uri => $value,       # string - redirect_uri is the callback URL where the OAuth provider will redirect after authentication.
 Must be registered in the OAuth provider's dashboard. Required.
        state => $value,       # string - state is the CSRF protection token that will be validated in the callback.
 Should be a cryptographically random value stored in a secure cookie. Required.
        client_site => $value,       # string - client_site identifies which site is initiating the login (e.g., "manage", "www").
 Used for logging and potential site-specific configuration. Required.
    );

B<Returns:>

Hashref with structure:

    {
        code         => 200,         # HTTP status code
        status_line  => "200 OK",    # HTTP status text
        connect_code => undef,       # ConnectRPC error code (or undef)
        data         => {            # Response data
            login_url => ...,  # string - login_url is the complete OAuth authorization URL to redirect the user to.
 Includes all necessary parameters: client_id, redirect_uri, response_type, audience, scope, state.
        },
        error        => undef,       # Error message (if any)
        trace_id     => "...",       # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

    unauthenticated, permission_denied, internal, invalid_argument, etc.

B<Example:>

    my $result = get_oauth_login_url(
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

sub get_oauth_login_url {
    my $validation_error = validate_key_value_args('get_oauth_login_url', @_);
    return $validation_error if $validation_error;

    my %args = @_;

    # Extract request fields from args
    my %request = ();
    $request{'redirect_uri'} = delete $args{'redirect_uri'} if exists $args{'redirect_uri'};
    $request{'state'} = delete $args{'state'} if exists $args{'state'};
    $request{'client_site'} = delete $args{'client_site'} if exists $args{'client_site'};

    return connect_rpc(
        service     => 'ntppool.auth.v1.AuthService',
        method      => 'GetOAuthLoginURL',
        request     => \%request,
        %args  # Pass through auth, account, context
    );
}



1;

__END__

=head1 GENERATED

This module was auto-generated by protoc-gen-perl-capi from ntppool/auth/v1/auth.proto.

DO NOT EDIT THIS FILE MANUALLY.

=head1 SEE ALSO

L<NP::CAPI>

=cut
