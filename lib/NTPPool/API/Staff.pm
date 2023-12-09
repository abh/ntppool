package NTPPool::API::Staff;
use strict;
use base qw(NTPPool::API::Base);
use NP::Model;
use Net::IP;

sub search {
    my $self = shift;
    $self->set_span_name("api.search");

    return {error => 'No access'} unless $self->user && $self->user->is_staff;
    my $q = $self->_required_param('q');

    my $ip = Net::IP->new($q);

    my $result = {
        users   => [],
        servers => [],
    };

    my @accounts;

    #local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    my $servers = NP::Model->server->get_servers(
        query => [or => [($ip ? (ip => $ip->short) : ()), hostname => {like => $q . '%'},]],
        require_objects => ['account']
    );
    if ($servers) {

        #warn "got servers!", Data::Dump::pp($servers);
        push @accounts, $_->account for @$servers;
    }

    my $user_query = [
        or => [
            'users.username' => {like => $q . '%'},
            'users.email'    => {like => '%' . $q . '%'},
            'users.name'     => {like => '%' . $q . '%'},
            'name'           => {like => '%' . $q . '%'},
        ]
    ];

    my $include_identities = 0;

    if ($q =~ m/^id:(\d+)/i) {
        $user_query         = [id => $1];
        $include_identities = 1;
    }

    my $accounts = NP::Model->account->get_accounts(
        query         => $user_query,
        multi_many_ok => 1,
        with_objects  => ['servers_all.zones', 'users']
    );
    push @accounts, @$accounts;

    #warn "USERS: ", join ", ", map { $_->username } @users;

    if (@accounts) {
        $result->{accounts} = [];
        for my $account (@accounts) {
            my $account_token = $account->id_token;
            my $data          = $account->get_data_hash;
            push @{$result->{accounts}}, {
                account_token => $account_token,

                # id       => 0 + $data->{id},
                name  => $data->{name},
                users => [
                    map {
                        my $u = $_;
                        my $d = $u->get_data_hash;
                        {   name     => $d->{name},
                            username => $d->{username},
                            email    => $d->{email},
                            id       => $d->{id} + 0,
                        }
                    } $account->users
                ],
                servers => [
                    map {
                        my $s = $_;
                        my $d = $s->get_data_hash;
                        {   id             => $d->{id} + 0,
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
                    } $account->servers_all
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

    return {error => 'No access'} unless $self->user && $self->user->is_staff;

    my ($field, $server_ip) = $self->_required_param(qw(id server));
    my $value = $self->_optional_param('value') || '';

    my $server = NP::Model->server->find_server($server_ip)
      or die "Could not find server";

    if ($field eq 'zone_list') {
        my %zones     = map { $_->name => $_ } $server->zones_display;
        my %new_zones = map { $_ => 1 } split /[,\s]+/, $value;
        %new_zones = %zones unless %new_zones;    # don't allow removing all zones
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
        return [map { $_->name } $server->zones_display];
    }
    elsif ($field eq 'hostname') {
        my $hostname  = $value;
        my $server_ip = Net::IP->new($server->ip);

        my $res   = Net::DNS::Resolver->new(defnames => 0);
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
            $server->hostname(lc $hostname);
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
