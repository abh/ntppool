package NP::NTP;
use strict;
use v5.34.0;
use NP::UA qw($ua);

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

    warn "JS: ", $res->decoded_content();

    my $json = JSON::XS->new->utf8;
    my @ntp  = eval { @{$json->decode($res->decoded_content)} };
    if ($@) {
        warn "json error: $@";
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

    warn "JS: ", $res->decoded_content();

    my $json = JSON::XS->new->utf8;
    my %ntp  = eval { +%{$json->decode($res->decoded_content)} };
    if ($@) {
        return ({error => "Could not decode NTP response from trace server"});
    }

    warn "NTP response: ", Data::Dumper->Dump([\%ntp]);

    return ({Server => 'trace', NTP => \%ntp});
}

1;
