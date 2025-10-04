package NP::CAPI;
use strict;
use warnings;
use NP::UA qw();
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
our @EXPORT_OK = qw(connect_rpc);

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
    my ($request_context) = @_;
    my $ua = $NP::UA::ua;

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

    my %result;

    # Construct ConnectRPC URL: /service.name/MethodName
    my $url = "${api_base}/${service}/${method}";

    # Debug logging (controlled by environment variable)
    if ($ENV{CAPI_DEBUG}) {
        warn "CAPI: calling connect rpc: $url\n";
        warn "CAPI: auth = " . ($auth // 'UNDEF') . "\n";
        warn "CAPI: account = " . ($account // 'UNDEF') . "\n";
    }

    # Build HTTP request
    my $req = HTTP::Request->new('POST', $url);

    # Set headers
    $req->header('Content-Type' => 'application/json');

    # Authentication header
    if ($auth) {
        $req->header('Authorization' => "Bearer $auth");
    }

    # Account selection header
    if ($account) {
        $req->header('X-Account' => $account);
    }

    # Encode request as JSON
    my $json_body = $json->encode($request);
    $req->content($json_body);

    # Debug: Log outgoing headers
    if ($ENV{CAPI_DEBUG}) {
        warn "CAPI: Request headers:\n";
        for my $h ($req->headers->header_field_names) {
            warn "  $h: " . $req->header($h) . "\n";
        }
    }

    # Make request with error handling
    my $ua = ua($context);
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

    if ($ENV{CAPI_DEBUG}) {
        warn $res->status_line, "\n";
        warn $res->decoded_content, "\n";
    }

    # Parse response
    %result = _parse_connect_response($res, $service, $method);

    # Add metadata
    $result{code}        ||= $res->code;
    $result{status_line} ||= $res->status_line;
    $result{trace_id}    ||= $res->header('TraceID');

    # Mark OpenTelemetry span as error for ConnectRPC errors
    if ($result{error} && $NP::CAPI::OTEL_AVAILABLE) {
        eval {
            my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
            if ($span) {
                $span->set_status(SPAN_STATUS_ERROR, "ConnectRPC error: " . $result{error});
                $span->set_attribute("rpc.system", "connect");
                $span->set_attribute("rpc.service", $service);
                $span->set_attribute("rpc.method", $method);
                $span->set_attribute("rpc.grpc.status_code", $result{connect_code} || "unknown");
                $span->set_attribute("http.status_code", $result{code});
                $span->set_attribute("api.trace_id", $result{trace_id}) if $result{trace_id};
            }
        };
    }

    if ($ENV{CAPI_DEBUG}) {
        warn "Data: ", Data::Dump::pp(\%result), "\n";
    }

    return \%result;
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

    # ConnectRPC always returns JSON
    if ($res->content_type !~ m{^application/json}) {
        $result{error} = "Invalid response content-type: " . ($res->content_type || 'none');
        $result{connect_code} = "internal";
        return %result;
    }

    my $content = $res->decoded_content;
    my $data = eval { $json->decode($content) };

    if ($@) {
        $result{error} = "Failed to decode JSON response: $@";
        $result{connect_code} = "internal";
        return %result;
    }

    # ConnectRPC uses HTTP status codes to indicate success vs error
    # Success: HTTP 2xx with response message as body (no "code" field)
    # Error: HTTP 4xx/5xx with {"code": "error_code", "message": "..."}

    if ($res->is_success) {
        # HTTP 2xx - success, entire body is the response message
        $result{connect_code} = undef;
        $result{error} = undef;
        $result{data} = $data;
    } else {
        # HTTP 4xx/5xx - error, body contains error object
        $result{connect_code} = $data->{code} || "unknown";
        $result{error} = $data->{message} || "HTTP error: " . $res->status_line;
        $result{data} = undef;
    }

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
