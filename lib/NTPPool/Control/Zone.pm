package NTPPool::Control::Zone;
use strict;
use base qw(NTPPool::Control);
use NTPPool::Server;
use Apache::Constants qw(OK);

sub cache_info {
  my $self = shift;
  return +{ id => "zonepage;" . $self->zone_name }
}

sub zone_name {
  my $self = shift;
  my ($zone_name) = ($self->request->uri =~ m!^/zone/([^/]+)!);
  $zone_name ||= '@';
  $zone_name;
}

sub render {
  my $self = shift;
  my $zone_name = $self->zone_name;
  my ($zone) = NTPPool::Zone->search(name => $zone_name) or return 404;
  $self->tpl_param('zone' => $zone);

  return OK, $self->evaluate_template('tpl/zone.html');
}

1;
