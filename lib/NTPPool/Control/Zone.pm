package NTPPool::Control::Zone;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK);

sub cache_info {
  my $self = shift;

  return {} if $self->deployment_mode eq 'devel';

  return +{ expires => 3600,
            id => join(";",
                       "zonepage",
                       $self->zone_name,
                       $self->sort_order,
                       $self->show_servers,
                       ($self->show_servers_access ? 1 : 0)
                      ),
          }
}

sub zone_name {
  my $self = shift;
  my ($zone_name) = ($self->request->uri =~ m!^/zone/([^/]+)!);
  $zone_name ||= '.';
  $zone_name;
}

# TODO: make the web interface actually do this
sub sort_order {
    my $self = shift;
    my $sort = $self->req_param('sort') || ''; 
    $sort = 'description' unless $sort eq 'server_count';
}

sub show_servers_access {
    my $self = shift;
    return $self->{_show_servers_access} if defined $self->{_show_servers_access};
    return $self->{_show_servers_access} = 1
      if $self->user 
        and $self->user->privileges
        and $self->user->privileges->see_all_servers;

    return $self->{_show_servers_access} = 0;
}

sub show_servers {
    my $self = shift;
    return 1 if $self->req_param('show_servers') and $self->show_servers_access;
    return 0;
} 

sub render {
  my $self = shift;
  my $zone_name = $self->zone_name;
  my $zone = NP::Model->zone->fetch(name => $zone_name);
  return 404 unless $zone;
  $self->tpl_param('zone' => $zone);

  $self->tpl_param('is_logged_in' => $self->show_servers_access );
  $self->tpl_param('show_servers' => $self->show_servers);
  if ($self->show_servers) {
      my @servers = sort { $a->ip cmp $b->ip } $zone->servers;
      $self->tpl_param('servers', \@servers);
  }

  return OK, $self->evaluate_template('tpl/zone.html');
}

1;
