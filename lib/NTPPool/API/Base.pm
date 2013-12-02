package NTPPool::API::Base;
use strict;
use base qw(Combust::API::Base);

sub api_key {
    my $self = shift;
    my $api_key = $self->_optional_param('api_key') or return;
    my $monitor = NP::Model->monitor->fetch(api_key => $api_key);
    return $monitor;
}

1;
