package NP::Stripe;
use strict;
use NP::Model;
use NP::LWP;
use JSON::XS;

my $json = JSON::XS->new->utf8;

sub _gw_api {
    my ($method, $function, $data) = @_;

    my %r;

    my $stripe_gw = $ENV{stripe_gw_service} || 'http://stripe-gw';
    $stripe_gw =~ s{/$}{};

    my $url = "${stripe_gw}/api/v1/$function";

    warn "calling stripe gw API: $url";

    my $res;

    if ($method eq 'get') {
        $res = NP::LWP->ua->$method($url);
    }
    elsif ($method eq 'post') {
        $res = NP::LWP->ua->post($url, $data);
    }
    else {
        warn qq[unknown method "$method" for stripe _gw_api];
    }

    if ($res->code != 200) {
        warn "stripe-gw response code $function call: ", $res->status_line;
        $r{error} = "Stripe GW error";
        return \%r;
    }

    warn "JS: ", $res->decoded_content();

    %r = %{ $json->decode($res->decoded_content) || {} };
    warn "STRIPE R: ", Data::Dump::pp(\%r);
    if ($@) {
        warn "stripe gw json error: $@";
        $r{error} = "Could not decode NTP response from trace server";
        return \%r;
    }
    
    return \%r;
}

sub _gw_get_api {
    _gw_api('get', @_);
}

sub _gw_post_api {
    _gw_api('post', @_);
}

sub get_products {
    my $r = _gw_get_api('products');
    return $r unless $r and $r->{Products};
    $r->{Products} = [map { $_->{Name} =~ s/NTP Pool//; $_ } @{$r->{Products}}];
    return $r;
}

sub create_session {
    my %args = @_;

    my $r = _gw_post_api('checkout/session', \%args);
    return $r;

#  -d success_url="https://example.com/success?session_id={CHECKOUT_SESSION_ID}" \
#  -d cancel_url="https://example.com/cancel"
    
}

1;
