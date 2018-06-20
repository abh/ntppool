package NTPPool::Control::DNSZone;
use strict;
use base qw(NTPPool::Control);
use Combust::Constant qw(OK);
use NP::Util::DNS;

sub render {
    my $self = shift;

    $self->cache_control('private, no-cache');

    my $token = $1 if ($self->request->header_in("Authorization") || '') =~ /^\s*Bearer\s+(.+)/i;
    return 403 unless $token; 

    my $api_key = NP::Model->api_key->fetch("api_key" => $token);
    return 403 unless $api_key;

    # return 403 unless $api_key->grants->zonefiles 

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
