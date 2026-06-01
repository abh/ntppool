package NP::CAPI;
use strict;
use warnings;
use NP::UA qw($ua_long);
use JSON::XS ();
use Data::Dump ();
use HTTP::Request;
BEGIN {
    eval {
        require OpenTelemetry::Trace;
        require OpenTelemetry::Context;
        require OpenTelemetry::Constants;
        OpenTelemetry::Constants->import('SPAN_STATUS_ERROR');
    };
    our $OTEL_AVAILABLE = !$@;
}

use Exporter 'import';
our @EXPORT_OK = qw(connect_rpc result_http_status);

our $VERSION = '0.1.0';

my $json = JSON::XS->new->utf8;

my $api_base = $ENV{'api-internal'} || 'http://api-internal/';
$api_base =~ s{/$}{};

=head1 NAME

NP::CAPI - ConnectRPC client for NTP Pool internal APIs

=head1 SYNOPSIS

    use NP::CAPI qw(connect_rpc);

    my $result = connect_rpc(
        service => 'ntppool.account.v1.AccountService',
        method  => 'GetAccountStatus',
        request => {},
        auth    => $user_token,
        account => $account_token,  # Optional
        context => $request_context,
    );

    if ($result->{error}) {
        warn "Error: $result->{error} (code: $result->{connect_code})";
    } else {
        my $data = $result->{data};
        print "Can register: $data->{can_register}\n";
    }

=head1 DESCRIPTION

ConnectRPC client library for calling internal gRPC/ConnectRPC services.
Provides a Perl interface to Protocol Buffer-defined RPC services.

This module follows similar patterns to L<NP::IntAPI> but is specifically
designed for ConnectRPC protocol.

=head1 FUNCTIONS

=cut

# ua returns a user agent object with the correct headers
sub ua {
    my ($request_context, $service, $method) = @_;

    # Use long-timeout UA for server management operations (precheck, add)
    my $ua = ($service && $service =~ /ServerManagementService/ && $method =~ /^(AddServerPrecheck|AddServer)$/)
        ? $NP::UA::ua_long
        : $NP::UA::ua;

    # Add X-Forwarded-For header if request context is provided
    if ($request_context && $request_context->{x_forwarded_for}) {
        $ua->default_header('X-Forwarded-For' => $request_context->{x_forwarded_for});
    }

    return $ua;
}

=head2 connect_rpc

Generic ConnectRPC caller. Calls any RPC method on any service.

    my $result = connect_rpc(
        service => 'ntppool.account.v1.AccountService',  # Full service name
        method  => 'GetAccountStatus',                   # RPC method name
        request => { ... },                              # Request message as hashref
        auth    => $user_token,                          # Optional: User/session token
        account => $account_token,                       # Optional: Account selection
        context => $request_context,                     # Optional: Request context
    );

B<Arguments:>

=over 4

=item service (required)

Full service name from proto package (e.g., 'ntppool.account.v1.AccountService')

=item method (required)

RPC method name (e.g., 'GetAccountStatus')

=item request (optional)

Hashref containing request message fields. Defaults to empty hashref {}.

=item auth (optional)

Authentication token (user or session). Sent as C<Authorization: Bearer> header.

=item account (optional)

Account selection token. Sent as C<X-Account> header.

=item context (optional)

Request context hashref with C<x_forwarded_for> field for client IP tracking.

=item prefix (optional)

URL prefix for the API endpoint. Defaults to C</int/rpc> for internal ConnectRPC API.
Use empty string C<''> for no prefix, or provide a custom prefix like C</api>.

=back

B<Returns:>

Hashref with structure:

    {
        code         => 200,           # HTTP status code
        status_line  => "200 OK",      # HTTP status text
        connect_code => undef,         # ConnectRPC error code (or undef if success)
        data         => { ... },       # Response message as hashref
        error        => undef,         # Error message (if any)
        trace_id     => "...",         # OpenTelemetry trace ID
    }

B<ConnectRPC Error Codes:>

Common error codes returned in C<connect_code> field:

=over 4

=item unauthenticated

Missing or invalid authentication

=item permission_denied

Authenticated but not authorized for this operation

=item invalid_argument

Request validation failed

=item not_found

Requested resource doesn't exist

=item internal

Server-side error

=item unavailable

Service temporarily unavailable

=back

B<Error Handling:>

    if ($result->{error}) {
        # RPC error or network failure
        warn "Error: $result->{error}";

        if ($result->{connect_code}) {
            # Specific ConnectRPC error
            if ($result->{connect_code} eq 'unauthenticated') {
                # Redirect to login
            }
        }
    }

=cut

sub connect_rpc {
    my %args = @_;

    my $service = delete $args{service} or die "service parameter required";
    my $method  = delete $args{method}  or die "method parameter required";
    my $request = delete $args{request} // {};
    my $auth    = delete $args{auth};
    my $account = delete $args{account};
    my $context = delete $args{context};
    my $http_method = delete $args{http_method} // 'POST';  # Allow GET for side-effect free RPCs
    my $prefix = delete $args{prefix} // '/int/rpc';  # Default to internal RPC API prefix

    my %result;

    # Construct ConnectRPC URL: /int/rpc/service.name/MethodName (or custom prefix)
    my $url = "${api_base}${prefix}/${service}/${method}";

    # For GET requests, encode the request message in query parameters
    if ($http_method eq 'GET') {
        my $message_json = $json->encode($request);
        require URI::Escape;
        my $encoded_message = URI::Escape::uri_escape($message_json);
        # Connect protocol requires connect=v1 for GET requests
        $url .= "?connect=v1&encoding=json&message=${encoded_message}";
    }

    # Debug logging (controlled by environment variable)
    if ($ENV{CAPI_DEBUG}) {
        warn "CAPI: calling connect rpc: $url\n";
        warn "CAPI: http_method = $http_method\n";
        warn "CAPI: auth = " . ($auth // 'UNDEF') . "\n";
        warn "CAPI: account = " . (defined $account ? "'$account'" : 'UNDEF') . "\n";
        warn "CAPI: account is " . ($account ? "TRUTHY" : "FALSY") . " in boolean context\n";
    }

    # Build HTTP request
    my $req = HTTP::Request->new($http_method, $url);

    # Set headers based on HTTP method
    if ($http_method eq 'GET') {
        # For GET requests, set Accept header for ConnectRPC
        # Note: curl uses Accept: */* and it works, but application/json is more specific
        $req->header('Accept' => '*/*');
    } else {
        # For POST requests, set Content-Type
        $req->header('Content-Type' => 'application/json');
    }

    # Note: Accept-Encoding is set globally in NP::UA
    # We don't need to set it per-request

    # Authentication header
    if ($auth) {
        $req->header('Authorization' => "Bearer $auth");
        warn "CAPI: Set Authorization header\n" if $ENV{CAPI_DEBUG};
    }

    # Account selection header
    if ($account) {
        $req->header('X-Account' => $account);
        warn "CAPI: Set X-Account header to: $account\n" if $ENV{CAPI_DEBUG};
    } else {
        warn "CAPI: NOT setting X-Account header (account param is " . (defined $account ? "defined but falsy: '$account'" : "undefined") . ")\n" if $ENV{CAPI_DEBUG};
    }

    # Encode request as JSON and set body (only for POST requests)
    if ($http_method ne 'GET') {
        my $json_body = $json->encode($request);
        $req->content($json_body);
    }

    # Debug: Log outgoing headers (always log for troubleshooting)
    if ($ENV{CAPI_DEBUG}) {
        warn "CAPI: Request headers:\n";
        for my $h ($req->headers->header_field_names) {
            warn "  $h: " . $req->header($h) . "\n";
        }
        warn "CAPI: Full URL: $url\n";
    }

    # Make request with error handling
    my $ua = ua($context, $service, $method);
    my $res = eval { $ua->request($req) };
    if ($@ || !$res) {
        return {
            code => 0,
            status_line => "Network error",
            connect_code => "unavailable",
            error => "Failed to connect to API: " . ($@ || "no response"),
            data => undef,
        };
    }

    # Decode compressed response (gzip, deflate, etc.)
    # This decompresses the content and removes Content-Encoding header
    $res->decode();

    if ($ENV{CAPI_DEBUG}) {
        warn $res->status_line, "\n";
        warn "Response headers (after decode):\n";
        warn "  Content-Type: ", $res->header('Content-Type') || 'none', "\n";
        warn "  Content-Encoding: ", $res->header('Content-Encoding') || 'none', "\n";
        warn "  Content-Length: ", $res->header('Content-Length') || 'none', "\n";
        warn substr($res->content, 0, 200), "...\n";
    }

    # Parse response
    %result = _parse_connect_response($res, $service, $method);

    # Add metadata
    $result{code}        ||= $res->code;
    $result{status_line} ||= $res->status_line;
    $result{trace_id}    ||= $res->header('TraceID');
    $result{service}     = $service;
    $result{method}      = $method;

    # Mark OpenTelemetry span as error for ConnectRPC errors
    if ($result{error} && $NP::CAPI::OTEL_AVAILABLE) {
        eval {
            my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
            if ($span) {
                $span->set_status(SPAN_STATUS_ERROR, $result{error});
                # NOTE: record_exception creates attributes that may exceed limits
                # We skip it here since set_status already records the error
                # $span->record_exception($result{error});
                $span->set_attribute("rpc.system", "connect");
                $span->set_attribute("rpc.service", $service);
                $span->set_attribute("rpc.method", $method);
                $span->set_attribute("rpc.grpc.status_code", $result{connect_code} || "unknown");
                $span->set_attribute("http.status_code", $result{code});
                $span->set_attribute("api.trace_id", $result{trace_id}) if $result{trace_id};
            }
        };
        if ($@) {
            warn "OpenTelemetry error: $@";
        }
        # Log the error with trace ID
        warn "ConnectRPC error: " . $result{error};
        warn "Trace ID: " . ($result{trace_id} || 'none');
    }

    if ($ENV{CAPI_DEBUG}) {
        warn "Data: ", Data::Dump::pp(\%result), "\n";
    }

    return \%result;
}

=head2 result_http_status($result)

Map a result hashref (from L</connect_rpc>, or the compatible structure
returned by L<NP::IntAPI>) to the HTTP status a web controller should return
when the record it wanted is absent.

Distinguishes a deterministic client outcome from an unreachable or failing
backend, so a transient outage isn't reported to clients (or cached) as a 404:

=over 4

=item * C<connect_code> 'not_found', or a clean response with no error => B<404>

=item * an explicit HTTP 4xx from the API => B<that 4xx> (e.g. permission_denied)

=item * API unreachable (C<code> 0 / 'unavailable'), a 5xx, or any other RPC
error => B<503>

=back

B<Returns:> C<($status, $transient)>, where C<$transient> is true for the 503
case so the caller can disable caching of the failure.

=cut

sub result_http_status {
    my ($result) = @_;

    my $connect_code = $result->{connect_code} || '';
    my $code         = $result->{code}         || 0;

    return (404, 0) if $connect_code eq 'not_found';    # genuine "not found"
    return (404, 0) if !$result->{error};               # clean response, no record

    # A deterministic client error (4xx) is the API's real answer, not a
    # transient failure.
    return ($code, 0) if $code >= 400 && $code < 500;

    # API unreachable, a 5xx, or any other RPC error: a transient failure.
    return (503, 1);
}

=head2 _parse_connect_response (internal)

Parse ConnectRPC HTTP response into standard result structure.

ConnectRPC uses HTTP status codes AND response body error format:
- HTTP 200 with error body: RPC-level error
- HTTP 4xx/5xx: Transport/server error

=cut

sub _parse_connect_response {
    my ($res, $service, $method) = @_;

    my %result;

    # DEBUG: Log response status and content-type for troubleshooting
    if ($ENV{CAPI_DEBUG}) {
        warn "HTTP Status: " . $res->code . " " . $res->status_line;
        warn "Content-Type: " . ($res->content_type || 'none');
        warn "Body length: " . length($res->content || '');
    }

    # Check HTTP status FIRST - infrastructure errors (502, 503, 504) won't have JSON
    if (!$res->is_success) {
        # Log rate limit headers for 429 responses
        if ($res->code == 429) {
            my $limit = $res->header('X-RateLimit-Limit') || 'unknown';
            my $remaining = $res->header('X-RateLimit-Remaining') || 'unknown';
            my $reset = $res->header('X-RateLimit-Reset') || 'unknown';
            warn "Rate limit exceeded - Limit: $limit/s, Remaining: $remaining, Reset: $reset";
        }

        # HTTP 4xx/5xx error
        # Try to parse as ConnectRPC JSON error if content-type suggests it
        if ($res->content_type =~ m{^application/json}) {
            my $content = $res->content;
            my $data = eval { $json->decode($content) };

            if ($data && ref($data) eq 'HASH') {
                # Successfully parsed JSON error response from API
                $result{connect_code} = $data->{code} || "unknown";

                # Ensure error message is always a string, not a hashref/arrayref
                # Defense-in-depth: don't trust API to return correct types
                my $message = $data->{message};
                if (ref($message)) {
                    # API returned structured data instead of string - serialize it
                    $message = "API error (invalid message type): " . Data::Dump::pp($message);
                }
                $result{error} = $message || "HTTP error: " . $res->status_line;
                $result{data} = undef;
                return %result;
            }
        }

        # Fall back to HTTP status line (502, 503, 504, or malformed JSON)
        $result{connect_code} = "unavailable";
        $result{error} = "HTTP error: " . $res->status_line;
        $result{data} = undef;
        return %result;
    }

    # HTTP 2xx - success, ConnectRPC always returns JSON for successful responses
    if ($res->content_type !~ m{^application/json}) {
        $result{error} = "Invalid response content-type for successful response: " . ($res->content_type || 'none');
        $result{connect_code} = "internal";
        warn "Content-type check failed for 2xx response: regex did not match";
        return %result;
    }

    # Parse successful JSON response
    my $content = $res->content;
    my $data = eval { $json->decode($content) };

    if ($@) {
        $result{error} = "Failed to decode JSON response: $@";
        $result{connect_code} = "internal";
        return %result;
    }

    # HTTP 2xx with valid JSON - success
    $result{connect_code} = undef;
    $result{error} = undef;
    $result{data} = $data;

    return %result;
}

1;

__END__

=head1 ENVIRONMENT

=over 4

=item api-internal

Base URL for internal API server. Defaults to C<http://api-internal/>.

Example: C<http://localhost:4211/>

=back

=head1 SEE ALSO

L<NP::IntAPI>, L<NP::CAPI::Account>

=head1 AUTHOR

NTP Pool Project

=cut
