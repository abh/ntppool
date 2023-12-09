package NP::Tracing;
use strict;
use warnings;

# Get logs from the OpenTelemetry code
use Log::Any::Adapter 'Stderr';

# use Metrics::Any::Adapter 'Stderr';

BEGIN {
    #$ENV{OTEL_EXPORTER_OTLP_ENDPOINT} = 'http://otelcol-ntp.ntppipeline.svc:4318';
    #$ENV{OTEL_EXPORTER_OTLP_ENDPOINT} = 'http://100.90.46.106:4318';
    $ENV{OTEL_SERVICE_NAME} = "ntppool";

    # console just to give a little more output
    #$ENV{OTEL_TRACES_EXPORTER}           = 'otlp,console';
    #$ENV{OTEL_BSP_MAX_EXPORT_BATCH_SIZE} = 8;

    # $ENV{OTEL_TRACES_EXPORTER} = 'console';
}

use OpenTelemetry;
use OpenTelemetry::SDK;
use OpenTelemetry::Context;
use OpenTelemetry::Trace;
use Syntax::Keyword::Dynamically;

use OpenTelemetry::Integration 'DBI';
use OpenTelemetry::Integration 'LWP::UserAgent';

my $tracer = OpenTelemetry->tracer_provider->tracer(name => 'perl', version => '1.0');

sub tracer {
    return $tracer;
}

my $i = 0;

sub flush {
    return unless $i++ > 10;
    OpenTelemetry->tracer_provider->force_flush(5);    # ->get;
    $i = 0;
}

1;
