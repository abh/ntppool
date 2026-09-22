package NP::Tracing::LWP;
# ABSTRACT: OpenTelemetry instrumentation for LWP::UserAgent

# Fork of OpenTelemetry::Instrumentation::LWP::UserAgent 0.037 from the
# OpenTelemetry distribution (https://github.com/jjatria/perl-opentelemetry),
# distributed under the same terms as Perl itself. It adds an `is_error`
# option, so an expected non-2xx response (a ConnectRPC not_found) doesn't
# mark the client span as an error. Drop this module and go back to
# `use OpenTelemetry::Instrumentation 'LWP::UserAgent' => {...}` once
# upstream has the option.
#
# Kept in upstream's formatting (not perltidy'd) so it diffs cleanly against
# the original.

our $VERSION = '0.037';

use strict;
use warnings;
use experimental 'signatures';

use Class::Inspector;
use Class::Method::Modifiers 'install_modifier';
use Feature::Compat::Try;
use Syntax::Keyword::Dynamically;
use List::Util 'none';
use OpenTelemetry::Constants qw( SPAN_KIND_CLIENT SPAN_STATUS_ERROR );
use OpenTelemetry::Context;
use OpenTelemetry::Trace;
use OpenTelemetry;

use parent 'OpenTelemetry::Instrumentation';

sub dependencies { 'LWP::UserAgent' }

my sub get_headers ( $have, $want, $prefix ) {
    return unless @$want;

    my %attributes;
    $have->scan( sub ( $key, $value ) {
        $key =~ tr/-/_/;
        return if none { $key =~ $_ } @$want;
        push @{ $attributes{ $prefix . '.' . lc $key } //= [] }, $value;
    });

    %attributes;
}

my ( $original, $loaded );

sub uninstall ( $class ) {
    return unless $loaded;
    no strict 'refs';
    no warnings 'redefine';
    delete $Class::Method::Modifiers::MODIFIER_CACHE{'LWP::UserAgent'}{simple_request};
    *{'LWP::UserAgent::simple_request'} = $original;
    undef $loaded;
    return;
}

sub install ( $class, %config ) {
    return if $loaded;
    return unless Class::Inspector->loaded('LWP::UserAgent');

    my @wanted_request_headers = map qr/^\Q$_\E$/i, map tr/-/_/r,
        @{ delete $config{request_headers}  // [] };

    my @wanted_response_headers = map qr/^\Q$_\E$/i, map tr/-/_/r,
        @{ delete $config{response_headers} // [] };

    my $is_error = delete $config{is_error}
        // sub ( $response ) { !$response->is_success };

    die "is_error must be a code reference\n" unless ref $is_error eq 'CODE';

    $original = \&LWP::UserAgent::simple_request;
    install_modifier 'LWP::UserAgent' => around => simple_request => sub {
        my ( $code, $self, $request, @rest ) = @_;

        my $uri    = $request->uri->clone;
        my $method = $request->method;
        my $length = length $request->content;

        $uri->userinfo('REDACTED:REDACTED') if $uri->userinfo;

        my $agent = $self->agent;

        my $span = OpenTelemetry->tracer_provider->tracer(
            name    => __PACKAGE__,
            version => $VERSION,
        )->create_span(
            name       => $method,
            kind       => SPAN_KIND_CLIENT,
            attributes => {
                # As per https://github.com/open-telemetry/semantic-conventions/blob/main/docs/http/http-spans.md
                'http.request.method'      => $method,
                'network.protocol.name'    => 'http',
                'network.protocol.version' => '1.1',
                'network.transport'        => 'tcp',
                'server.address'           => $uri->host,
                'server.port'              => $uri->port,
                'url.full'                 => "$uri", # redacted

                get_headers(
                    $self->default_headers,
                    \@wanted_request_headers,
                    'http.request.header'
                ),

                get_headers(
                    $request->headers,
                    \@wanted_request_headers,
                    'http.request.header'
                ),

                $agent ? ( 'user_agent.original' => $agent ) : (),
                $length ? ( 'http.request.body.size' => $length ) : (),
            },
        );

        dynamically OpenTelemetry::Context->current
            = OpenTelemetry::Trace->context_with_span($span);

        OpenTelemetry->propagator->inject(
            $request,
            undef,
            sub { shift->header(@_) },
        );

        try {
            my $response = $self->$code( $request, @rest );
            $span->set_attribute( 'http.response.status_code' => $response->code );

            # TODO: this should include retries
            if ( my $count = $response->redirects ) {
                $span->set_attribute( 'http.resend_count' => $count )
            }

            my $length = $response->header('content-length');
            $span->set_attribute( 'http.response.body.size' => $length )
                if defined $length;

            $span->set_status( SPAN_STATUS_ERROR, $response->code )
                if $is_error->($response);

            $span->set_attribute(
                get_headers(
                    $response->headers,
                    \@wanted_response_headers,
                    'http.response.header'
                )
            );

            return $response;
        }
        catch ($error) {
            my ($description) = split /\n/, $error =~ s/^\s+|\s+$//gr, 2;
            $description =~ s/ at \S+ line \d+\.$//a;

            $span->record_exception($error);
            $span->set_status( SPAN_STATUS_ERROR, $description );

            die $error;
        }
        finally {
            $span->end;
        }
    };

    return $loaded = 1;
}

1;
