package NP::Stripe;
use strict;
use NP::Model;
use NP::UA qw($ua);
use JSON::XS;
use List::Util qw(uniq);
use Data::Dump ();
use URI::QueryParam;

my $json = JSON::XS->new->utf8;

sub _gw_api {
    my ($method, $function, $data) = @_;

    my %r;

    my $stripe_gw = $ENV{stripe_gw_service} || 'http://stripe-gw';
    $stripe_gw =~ s{/$}{};

    my $url = "${stripe_gw}/api/v1/$function";

    #warn "calling stripe gw API: $url";

    my $res;

    if ($method eq 'get') {
        if ($data) {
            my $uri = URI->new($url);
            my $o   = $uri->query_form_hash();
            $uri->query_form_hash({%$o, %$data});
            $url = $uri->as_string();
        }
        $res = $ua->$method($url);
    }
    elsif ($method eq 'post') {
        $res = $ua->post($url, $data);
    }
    else {
        warn qq[unknown method "$method" for stripe _gw_api];
    }

    my $request_id = $res->header("X-Request-Id") || "";

    if ($res->code != 200) {
        warn "stripe-gw response code $function call: ", $res->status_line;
        %r = %{$json->decode($res->decoded_content) || {}};
        my $message = $r{message} || "error";
        $r{error} = "Stripe gateway: $message";
        if ($request_id) {
            $r{error} .= " ($request_id)";
        }
        return \%r;
    }

    #warn "JSON: ", $res->decoded_content();

    %r = %{$json->decode($res->decoded_content) || {}};

    #warn "Data: ", Data::Dump::pp(\%r);

    return \%r;
}

sub _gw_get_api {
    _gw_api('get', @_);
}

sub _gw_post_api {
    _gw_api('post', @_);
}

sub create_session {
    my %args = @_;
    my $r    = _gw_post_api('checkout/create_session', \%args);
    return $r;
}

sub get_session {
    my $sid = shift;
    my $r   = _gw_get_api('checkout/session_data', {session_id => $sid});
    return $r;
}

sub create_customer {
    my %args = @_;
    my $r    = _gw_post_api('customer/create', \%args);
    return $r;
}

sub billing_portal_url {
    my $customer_id = shift;
    my $return_url  = shift;

    my $r = _gw_post_api(
        'customer/portal',
        {   customer_id => $customer_id,
            return_url  => $return_url,
        }
    );
    if ($r && $r->{error}) {
        warn "could not get billing portal: ", $r->{error};
    }
    return $r ? $r->{url} : "";
}

sub get_products {
    my $zone_count   = shift || 1;
    my $device_count = shift || 0;
    my $r            = _gw_get_api('products', {quantity => $device_count, zones => $zone_count});
    return $r unless $r and $r->{Products};

    # warn "PRODUCTS: ", Data::Dump::pp($r);

    $r->{Products} = [map { $_->{Name} =~ s/NTP Pool//; $_ } @{$r->{Products}}];
    return $r;
}

sub _plan_process_data {

    # plan or product
    my $p = shift;

    # if we're processing a plan, set single_price / price / tiered
    if ($p->{ID} !~ m/^prod_/) {
        if ($p->{TiersMode} eq "") {
            $p->{single_price} = 1;
            $p->{price}        = $p->{AnnualCostLow};
        }
        else {
            $p->{tiered} = 1;
        }
    }

    # my $tier_mode = $p->{TiersMode};
    # my $price = 0;
    # my $found_price = 0;

    if ($p->{IntervalMonths}) {
        if ($p->{IntervalMonths} == 12) {
            $p->{period_text} = "per year";
        }
        elsif ($p->{IntervalMonths} == 3) {
            $p->{period_text} = "per quarter";
        }
        elsif ($p->{IntervalMonths} == 1) {
            $p->{period_text} = "per month";
        }
        else {
            $p->{period_text} = "per $p->{IntervalMonths} months";
        }
    }

    for my $t (@{$p->{Tiers} || []}) {

        # if ($tier_mode and !$found_price) {
        #     if ($tier_mode eq 'graduated') {
        #         $price +=
        #     }
        # }

        # the next part only for plan or product data, not tiers

    }

}

sub product_groups {
    my $zone_count   = shift || 1;
    my $device_count = shift || 0;
    my $products     = get_products($zone_count, $device_count);

    if ($products->{error}) {
        warn "stripe gw error: ", $products->{error};
        return $products, {}, [];
    }

    #warn "GOT PRODUCTS: ", scalar @{$products->{Products}};

    my %groups = (
        personal   => [],
        business   => [],
        enterprise => [],
        other      => [],
    );

    for my $p (@{$products->{Products}}) {

        # is the product available?
        _plan_process_data($p);

        # warn "product: $p->{Name}";
        # warn "zone: $device_count -- max $p->{MaxClients}; min $p->{MinClients}";

        for my $plan (@{$p->{Plans}}) {
            _plan_process_data($plan);

            # copy "up" some plan data to the product summary
            for my $f (qw(tiered single_price)) {
                $p->{$f} = $plan->{$f} if $plan->{$f};
            }
        }

        my $category = $p->{Metadata} && $p->{Metadata}->{category} || '';
        if (my $g = $groups{$category}) {
            push @{$groups{$category}}, $p;
        }
        else {
            push @{$groups{other}}, $p;
        }
    }

    # just in case the code above changes and something else gets added
    my @group_list =
      grep { $groups{$_} && @{$groups{$_}} > 0 }
      uniq('personal', 'business', 'enterprise', keys %groups);

    return ($products, \%groups, \@group_list);
}

1;
