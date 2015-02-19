package NTPPool::Control::API;
use strict;
use base qw(Combust::Control::API NTPPool::Control::Manage);
use NTPPool::API;

sub post_process {
    my $self = shift;
    $self->request->header_out('Cache-Control' => 'private');
    return $self->SUPER::post_process(@_);
}


1;
