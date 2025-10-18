package NTPPool::API::Staff;
use strict;
use base qw(NTPPool::API::Base);
use NP::Model;
use Net::IP;

sub edit_server {
    my $self = shift;

    # Access control is handled by the calling controller
    # (staff_zone_edit and staff_hostname_edit check user_is_staff before calling)
    return {error => 'No access'} unless $self->user;

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
        my $hostname = $value;
        my $error    = "";

        # Allow clearing the hostname (setting to empty string)
        if (!$hostname || $hostname eq '') {
            warn "Clearing hostname for server ID: " . $server->id;
            $server->hostname('');
            $server->save;
            warn "After save, server hostname is: " . ($server->hostname || 'undef');
        }
        else {
            # Validate that hostname resolves to server IP
            my $server_ip = Net::IP->new($server->ip);
            my $res       = Net::DNS::Resolver->new(defnames => 0);
            my $reply =
              $res->query($hostname, $server->ip_version eq 'v4' ? 'A' : 'AAAA');

            my $found = 0;

            if ($reply) {
                for my $rr ($reply->answer) {
                    next unless $rr->type eq 'A' or $rr->type eq 'AAAA';
                    $found++ if Net::IP->new($rr->address)->short eq $server_ip->short;
                }
            }

            if ($found) {
                warn "Setting hostname to: "
                  . lc($hostname)
                  . " for server ID: "
                  . $server->id;
                $server->hostname(lc $hostname);
                $server->save;
                warn "After save, server hostname is: " . ($server->hostname || 'undef');
            }
            else {
                $error = "That hostname doesn't resolve to the IP address of the server";
            }
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
