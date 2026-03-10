package NP::App;
use NP::Tracing;
use Moose;
use Plack::Builder;
extends 'Combust::App';
with 'Combust::App::ApacheRouters';
with 'Combust::Redirect';
use NP::Model;
use OpenTelemetry::Constants qw( SPAN_KIND_SERVER SPAN_STATUS_ERROR SPAN_STATUS_OK );
use OpenTelemetry -all;
use Syntax::Keyword::Dynamically;

require NTPPool::Control;

after 'init' => sub {
    my $self = shift;
};

my $lang_regexp = "(" . join("|", keys %NTPPool::Control::valid_languages) . ")";
$lang_regexp = qr!^/$lang_regexp/!;

$SIG{__WARN__} = sub {
    my $message = shift;
    my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
    if ($span) {
        my $trace_id = $span->context->hex_trace_id;
        my $span_id  = $span->context->hex_span_id;
        warn "trace_id=$trace_id span_id=$span_id $message";
    }
    else {
        warn "$message";
    }
};

augment 'reference' => sub {
    my $self = shift;

    my $tracer = NP::Tracing->tracer;

    enable 'Headers', set => ['Connection' => 'Close'];

    enable sub {
        my $app = shift;
        sub {
            my $env = shift;
            my $uri = $env->{PATH_INFO};

            if ($uri eq "/__health"
                and
                ($env->{REQUEST_METHOD} eq "GET" or $env->{REQUEST_METHOD} eq "HEAD")
              )
            {
                {
                    my $pspan =
                      OpenTelemetry::Trace->span_from_context(
                          OpenTelemetry::Context->current);
                    $pspan->set_name($env->{REQUEST_METHOD} . " __health");
                    my $span = NP::Tracing->tracer->create_span(
                        name => "flush_otel",
                        kind => SPAN_KIND_SERVER,
                    );
                    dynamically otel_current_context = otel_context_with_span($span);

                    NP::Tracing->flush(2);
                    $span->end();
                }
                return [200, ['Content-Type' => 'text/plain'], ["App says ok\n"]];
            }

            if ($uri =~ s!$lang_regexp!/!) {
                my $lang = $1;
                $env->{'combust.notes'}->{lang} = $lang;
                $env->{PATH_INFO} = $uri;
            }
            my $res = $app->($env);

#            NP::Tracing->flush();

            return $res;
        };
    };
};

1;
