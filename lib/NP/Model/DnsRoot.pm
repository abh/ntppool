package NP::Model::DnsRoot;
use Combust::Config;
use List::Util qw(shuffle);
use NP::Model;

my $config     = Combust::Config->new;
my $config_ntp = $config->site->{ntppool};

sub ttl {
    return 150;
}

sub serial {
    return $self->{_dns_serial} ||= time;
}

sub data {
    my $self = shift;
    return $self->{_dns_data} ||= do {

        my $www_record = {
            cname => $config_ntp->{www_cname} || 'www-lb.ntppool.org.',
            ttl => 7200,
        };

        my $data = {};
        $data->{www} = $www_record;
        $data->{web} = $www_record;
        $data->{gb}  = {alias => 'uk'};

        $data->{""}->{ns} = {map { $_ => undef } split /[\s+,]/, $self->ns_list};
        $data;
    };
}

sub TO_JSON {
    my $self = shift;
    return {
        serial => $self->serial,
        ttl    => $self->ttl,
        data   => $self->data
    };
}

sub populate {
    my $self = shift;

    my $zones = NP::Model->zone->get_zones_iterator(query => [dns => 1]);
    my $data = $self->data;

    while (my $zone = $zones->next) {
        my $name = $zone->name;
        $name = ''       if $name eq '@';
        $name = "$name." if $name;

        if (my $entries = $zone->active_servers('v4')) {

            my $min_non_duplicate_size = 2;
            my $response_records       = 3;
            my @zones                  = ("", "0.", "1.", "2.", "3.");
            my $zone_count             = scalar @zones;

            $min_non_duplicate_size = int(@$entries / $zone_count)
              if (@$entries / $zone_count > $min_non_duplicate_size);

            # print $fh "# " . scalar @$entries . " active servers in ", $zone->name, "\n";

            if ($#$entries < ($min_non_duplicate_size * $zone_count - 1)) {

                # possible duplicates, not enough servers
                foreach my $z (@zones) {
                    (my $pgeodns_group = "$z${name}") =~ s/\.$//;
                    $data->{$pgeodns_group}->{a} = [];
                    @$entries = shuffle(@$entries);
                    foreach my $e (@$entries) {
                        push @{$data->{$pgeodns_group}->{a}}, $e;
                    }
                }
            }
            else {

                # 'big' zone without duplicates
                @$entries = shuffle(@$entries);
                foreach my $z (@zones) {
                    (my $pgeodns_group = "$z${name}") =~ s/\.$//;
                    $data->{$pgeodns_group}->{a} = [];
                    for (my $i = 0; $i < $min_non_duplicate_size; $i++) {
                        my $e = shift @$entries;
                        push @{$data->{$pgeodns_group}->{a}}, $e;
                    }
                }
            }
        }

        if (my $entries = $zone->active_servers('v6')) {
            @$entries = shuffle(@$entries);

            # for now just put all IPv6 servers in the '2' zone
            (my $pgeodns_group = "2.${name}") =~ s/\.$//;
            push @{$data->{$pgeodns_group}->{aaaa}}, $_ for @$entries;
        }

    }
}

1;
