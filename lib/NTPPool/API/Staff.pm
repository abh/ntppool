package NTPPool::API::Staff;
use strict;
use base qw(NTPPool::API::Base);
use NP::Model;

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

    local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    warn "getting servers";

    my $servers = NP::Model->server->get_servers
      (
       query => [ or => [ ( $ip ? (ip => $ip->ip) : () ),
                          hostname => { like => $q . '%' },
                        ]
                ],
       require_objects => [ 'user' ]
      );
    if ($servers) {
        warn "got servdrs!", Data::Dump::pp($servers);

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
    warn "USERS: ", join ", ", map { $_->username } @users; 

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

sub server_zones {
    my $self = shift;
    return {};
}

1;
