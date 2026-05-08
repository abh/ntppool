package NP::NTP;
use strict;
use v5.34.0;
use NP::UA qw($ua);
use OpenTelemetry::Trace;
use OpenTelemetry::Context;
use OpenTelemetry::Constants qw( SPAN_STATUS_ERROR );

sub _record_decode_error {
    my ($source, $ip, $res, $body, $json_error) = @_;
    my $span =
      OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
    return unless $span;

    $span->set_status(SPAN_STATUS_ERROR,
        "Could not decode NTP response: $json_error");
    $span->set_attribute("ntp.check.source",          $source);
    $span->set_attribute("ntp.check.ip",              $ip);
    $span->set_attribute("http.response.status_code", $res->code);
    $span->set_attribute("http.response.body.size",   length($body));
    $span->set_attribute("ntp.response.body_excerpt", substr($body, 0, 500));
    $span->set_attribute("ntp.response.content_type", $res->content_type)
      if $res->content_type;
    my $trace_id = $res->header('TraceID');
    $span->set_attribute("ntp.response.trace_id", $trace_id) if $trace_id;
}

sub info {
    my $ip  = shift;
    my @ntp = info_monitor_api($ip);

    unless (@ntp) {
        warn "didn't get NTP info from monitor-api, trying trace";
        @ntp = info_trace_api($ip);
    }

    return @ntp;
}

sub info_monitor_api {
    my $ip = shift;

    $ua->timeout(10);

    my $res = $ua->post("http://monitor-api/check/ntp/$ip");
    if ($res->code != 200) {
        warn "monitor-api response code for $ip: ", $res->code;
        warn "monitor-api response: ",              $res->decoded_content;
        return ();    # will fallback to the legacy trace check
    }

    my $body = $res->decoded_content;
    warn "JS: ", $body;

    my $json = JSON::XS->new->utf8;
    my @ntp  = eval { @{$json->decode($body)} };
    if ($@) {
        my $err = $@;
        warn "monitor-api json decode error for $ip: $err";
        _record_decode_error('monitor-api', $ip, $res, $body, $err);
        return ({error => "Could not decode NTP response from trace server"});
    }

    warn "NTP response from monitor-api: ", Data::Dumper->Dump([@ntp]);

    @ntp = map {
        $_->{error} = delete $_->{Error} if $_->{Error};
        $_->{error} =~ s/(read udp )\S+:\d+->/$1 /
          if $_->{error};
        $_;
    } @ntp;

    return @ntp;
}

sub info_trace_api {
    my $ip = shift;

    my $res = $ua->get("https://trace2.ntppool.org/ntp/$ip");
    if ($res->code != 200) {
        warn "trace2 response code for $ip: ", $res->code;
        return ({error => "Could not check NTP status"});
    }

    my $body = $res->decoded_content;
    warn "JS: ", $body;

    my $json = JSON::XS->new->utf8;
    my %ntp  = eval { +%{$json->decode($body)} };
    if ($@) {
        my $err = $@;
        warn "trace2 json decode error for $ip: $err";
        _record_decode_error('trace2', $ip, $res, $body, $err);
        return ({error => "Could not decode NTP response from trace server"});
    }

    warn "NTP response: ", Data::Dumper->Dump([\%ntp]);

    return ({Server => 'trace', NTP => \%ntp});
}

1;
