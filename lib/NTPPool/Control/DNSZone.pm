package NTPPool::Control::DNSZone;
use strict;
use parent            qw(NTPPool::Control);
use Combust::Constant qw(OK);
use NP::Model         qw();
use NP::CAPI::Account qw(who_am_i);
use NP::CAPI::Zone    qw(get_dns_zone_data);

sub render {
    my $self = shift;

    #    $self->set_span_name("dnszone");

    $self->cache_control('private, no-cache');

    my $token = $1
      if ($self->request->header_in("Authorization") || '') =~ /^\s*Bearer\s+(.+)/i;
    return 403 unless $token;

    # Authenticate via API and verify dns service access
    my $auth_result = who_am_i(auth => $token);
    if ($auth_result->{error}) {
        warn "DNSZone auth error: $auth_result->{error}";
        return 403;
    }

    # Require service authentication with type=dns
    my $auth_type = $auth_result->{data}{auth_type} || '';
    unless ($auth_type eq 'service') {
        warn "DNSZone: auth_type '$auth_type' is not 'service'";
        return 403;
    }

    my $services = $auth_result->{data}{services} || [];
    my $has_dns = grep { ($_->{type} || '') eq 'dns' } @$services;
    unless ($has_dns) {
        warn "DNSZone: no dns service found in services";
        return 403;
    }

    # if url =~ /index or some such:
    #  my $roots = NP::Model->dns_root->get_objects;
    # print join "\n", map { $_->origin } @$roots;

    my $origin = $self->req_param('origin');

    my $root = NP::Model->dns_root->fetch(origin => $origin);

    return 404 unless $root;

    $root->populate;

    my $json = JSON::XS->new->pretty->utf8->convert_blessed;
    my $js   = $json->encode($root);

    return OK, $js;

}

1;
