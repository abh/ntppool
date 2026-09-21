package NTPPool::Control::DNSZone;
use strict;
use parent            qw(NTPPool::Control);
use Combust::Constant qw(OK);
use NP::DNSZone::Root;
use NP::CAPI::Account qw(who_am_i AUTH_TYPE_SERVICE);
use NP::CAPI::Zone    qw(get_dns_zone_data);

sub render {
    my $self = shift;

    $self->cache_control('private, no-cache');

    # Extract bearer token
    my $token = $1
      if ($self->request->header_in("Authorization") || '') =~ /^\s*Bearer\s+(.+)/i;
    return 403 unless $token;

    # Authenticate via API - require service with type=dns
    my $auth_result = who_am_i(auth => $token);
    if ($auth_result->{error}) {
        warn "DNSZone auth error: $auth_result->{error}";
        return 403;
    }

    my $auth_type = $auth_result->{data}{auth_type} || '';
    unless ($auth_type eq AUTH_TYPE_SERVICE) {
        warn "DNSZone: auth_type '$auth_type' is not '" . AUTH_TYPE_SERVICE . "'";
        return 403;
    }

    my $services = $auth_result->{data}{services} || [];
    my $has_dns  = grep { ($_->{type} || '') eq 'dns' } @$services;
    unless ($has_dns) {
        warn "DNSZone: no dns service found in services";
        return 403;
    }

    # Get origin parameter
    my $origin = $self->req_param('origin');
    return 400 unless $origin;

    # Fetch zone data from API
    my $zone_result = get_dns_zone_data(
        auth   => $token,
        origin => $origin,
    );

    if (my $status = $self->capi_error_status($zone_result, $zone_result->{data})) {
        warn "DNSZone API error: $zone_result->{error} [trace: $zone_result->{trace_id}]"
          if $zone_result->{error};
        return $status;
    }

    # Build DNS zone data using API response
    my $root = NP::DNSZone::Root->new_from_api($zone_result->{data}, auth => $token);
    $root->populate;

    my $json = JSON::XS->new->pretty->utf8->convert_blessed;
    my $js   = $json->encode($root);

    return OK, $js;
}

1;
