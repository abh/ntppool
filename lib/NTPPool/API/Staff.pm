package NTPPool::API::Staff;
use strict;
use base qw(NTPPool::API::Base);
use NP::Model;
use Net::IP;

sub search {
    my $self = shift;
    return { error => 'No access' } unless $self->user && $self->user->is_staff;
    my $q = $self->_required_param('q');

    my $ip = Net::IP->new($q);

    my $result = {
                  users   => [],
                  servers => [],
                 };

    my @users;

    #local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    my $servers = NP::Model->server->get_servers
      (
       query => [ or => [ ( $ip ? (ip => $ip->ip) : () ),
                          hostname => { like => $q . '%' },
                        ]
                ],
       require_objects => [ 'user' ]
      );
    if ($servers) {
        #warn "got servers!", Data::Dump::pp($servers);
        push @users, $_->user for @$servers;
    }

    warn "getting users";

    my $users = NP::Model->user->get_users
      (
       query => [ or => [ username => { like => $q . '%' },
                          email    => { like => '%' . $q . '%' },
                         ]
                ],
       multi_many_ok => 1,
       with_objects => [ 'servers_all.zones' ]
    );
    push @users, @$users;
    #warn "USERS: ", join ", ", map { $_->username } @users; 

    if (@users) {
        $result->{users} = [];
        for my $user (@users) {
            my $data = $user->get_data_hash;
            push @{$result->{users}}, {
                id       => $data->{id},
                name     => $data->{name},
                username => $data->{username},
                email    => $data->{email},
                servers  => [
                    map {
                        my $s = $_;
                        my $d = $s->get_data_hash;
                        {   id             => $d->{id},
                            ip             => $d->{ip},
                            score          => $s->score,
                            netspeed       => $d->{netspeed},
                            netspeed_human => $s->netspeed_human,
                            created_on     => $d->{created_on},
                            deletion_on    => $d->{deletion_on},  
                            hostname       => $d->{hostname},
                            in_pool        => $d->{in_pool},
                            zones          => [map { $_->name } $s->zones]
                        }
                      } sort {
                          if ($a->deletion_on or $b->deletion_on) {
                              unless ($a->deletion_on and $b->deletion_on) {
                                  return 1 if $a->deletion_on;
                                  return -1;
                              }
                              return $b->deletion_on <=> $a->deletion_on;
                          }
                          return $b->created_on <=> $a->created_on;
                      }
                        $user->servers_all
                ]
            };
        }
        use Data::Dump qw(pp);
        #pp($result);
    }

    # search users by username and email

    return $result;
}

sub edit_server {
    my $self = shift;

    return { error => 'No access' } unless $self->user && $self->user->is_staff;

    # TODO:
    #  check auth_token

    my ($field, $server_ip) = $self->_required_param(qw(id server));
    my $value = $self->_optional_param('value') || '';

    my $server = NP::Model->server->find_server($server_ip)
      or die "Could not find server";

    if ($field eq 'zone_list') {
        my %zones = map { $_->name => $_ } $server->zones_display;
        my %new_zones = map { $_ => 1 } split /[,\s]+/, $value;
        %new_zones = %zones unless %new_zones; # don't allow removing all zones
        for my $zone (keys %new_zones) {
            if ($zones{$zone}) {
                # ok already
                delete $zones{$zone};
                next;
            }
            $server->join_zone($zone);
        }
        for my $zone (keys %zones) {
            next if $zones{$zone}->name eq '.';
            $server->leave_zone($zone);
        }
        $server->save;
        return [ map { $_->name } $server->zones_display ];
    }
    elsif ($field eq 'hostname') {
        my $hostname = $value;
        my $server_ip = Net::IP->new($server->ip);

        my $res = Net::DNS::Resolver->new;
        my $reply = $res->query($hostname, $server->ip_version eq 'v4' ? 'A' : 'AAAA');

        my $error = "";
        my $found = 0;

        if ($reply) {
            for my $rr ($reply->answer) {
                next unless $rr->type eq 'A' or $rr->type eq 'AAAA';
                $found++ if Net::IP->new($rr->address)->short eq $server_ip->short;
            }
        }

        if ($found) {
            $server->hostname( lc $hostname );
            $server->save;
        }
        else {
            $error = "That hostname doesn't resolve to the IP address of the server";
        }

        return {
            hostname => $server->hostname,
            input    => $hostname,
            error    => $error
        };
    }
    else {
        die "Don't know how to edit $field";
    }
}

1;
