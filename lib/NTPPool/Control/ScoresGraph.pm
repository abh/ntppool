package NTPPool::Control::ScoresGraph;
use strict;
use base qw(NTPPool::Control);
#use GD::Graph::lines;
use NTPPool::Server;

sub render {
  my $self = shift;
  my $ip = $self->req_param('ip') or return 404;
  my ($server) = NTPPool::Server->search(ip => $ip) or return 404;
  
  return 404;
}


1;
