package NP::Model::Server;
use strict;

sub _resolve_zone {
    my ($zone_name) = @_;
    my $zone = ref $zone_name
                 ? $zone_name
                 : NP::Model->zone->fetch(name => $zone_name);

    unless ($zone) {
        warn "Could not find the zone: $zone_name";
        return;
    }
    $zone
}

sub add_zone {
    my ($self, $zone_name) = @_;
    my $zone = _resolve_zone($zone_name) or return;
    $self->add_zones($zone);
    return;
}

sub leave_zone {
    my ($self, $zone_name) = @_;
    my $zone = _resolve_zone($zone_name) or return;
    # TODO: figure out how to do this on the $self object... :-/
    my $server_zone = NP::Model->server_zone->fetch
      ( zone_id => $zone->id, server_id => $self->id );
    $server_zone && $server_zone->delete;
}

#  local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

sub score {
  my $self = shift;
  sprintf "%0.1f", $self->score_raw;
}

sub admin { shift->user(@_) }


package NP::Model::Server::Manager;
use strict;

sub find_server {
    my ($class, $arg) = @_;
    my $server;
    $server   = $class->fetch(id => $arg) if ($arg =~ m/^\d+$/);
    $server   = $class->fetch(ip => $arg) unless $server; 
    return $server if $server;
    $server = $class->get_servers(query => [ hostname => $arg ]) unless $server;
    $server && @$server ? $server->[0] : ();
}

sub get_check_due {
    my $class = shift;

    $class->get_objects_from_sql
      (
       sql => q[SELECT *
                FROM servers
                WHERE
                  score_ts IS NULL or score_ts < DATE_SUB( NOW(), INTERVAL 24 minute)
                ORDER BY score_ts
               ],
       
              );
}


1;
