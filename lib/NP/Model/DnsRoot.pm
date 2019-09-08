package NP::Model::DnsRoot;
use strict;
use warnings;
use Combust::Config;
use List::Util qw(shuffle);
use NP::Model;

my $config     = Combust::Config->new;
my $config_ntp = $config->site->{ntppool};

sub ttl {
    return 150;
}

sub serial {
    return shift->{_dns_serial} ||= time;
}

sub stathat_api {
    return $config_ntp->{stathat_api} || '';
}

sub data {
    my $self = shift;

    # return a singleton for the root so other methods can add to the data
    return $self->{_dns_data} ||= do {

        my $www_record = {
            cname => $config_ntp->{www_cname} || 'www-lb.ntppool.org.',
            ttl => 7200,
        };

        my $data = {};
        $data->{www} = $www_record;
        $data->{web} = $www_record;
        $data->{gb}  = {alias => 'uk'};
        for my $i (0 .. 3) {
            $data->{"$i.gb"} = {alias => "$i.uk"};
        }

        $data->{""}->{ns} = {map { $_ => undef } split /[\s+,]/, $self->ns_list};
        $data->{"_dmarc"}->{txt} =
          "v=DMARC1; p=reject; pct=100; rua=mailto:re+h6dgrfy2ghh\@dmarc.postmarkapp.com; sp=reject; aspf=r;";

        $data->{""}->{txt} = [
            # Fastly TLS verification
            {txt => "_globalsign-domain-verification=mVYWxIl-2ab_B1yPPFxEmDCLrBcl6ucouXJOU_P0_C"},
        ];

        if ($self->origin eq "pool.ntp.org") {
            # google domain verification
            $data->{"v4zgfk4oagsu"}->{cname} = "gv-35off4weczdcxg.dv.googlehosted.com.";
            push @{$data->{""}->{txt}}, {txt => "facebook-domain-verification=sfjgxys7hmryn50lszk658gi7amidt"};
        }
        elsif ($self->origin eq "beta.grundclock.com") {
            $data->{"fchof3xzaiyl"}->{cname} = "gv-fveibxaoathoje.dv.googlehosted.com.";
            push @{$data->{""}->{txt}}, {txt => "facebook-domain-verification=9gahpfmem9gwjmxypka1o3v3fgnb4k"};
        }

        $data;
    };
}

sub TO_JSON {
    my $self = shift;
    return {
        serial    => $self->serial,
        ttl       => $self->ttl,
        data      => $self->data,
        max_hosts => 4,
        logging => {stathat_api => $self->stathat_api},
    };
}

sub populate {
    my $self = shift;
    $self->populate_vendor_zones;
    $self->populate_country_zones;
}

sub populate_country_zones {
    my $self = shift;

    my $zones = NP::Model->zone->get_zones_iterator(query => [dns => 1]);
    my $data = $self->data;

    while (my $zone = $zones->next) {
        my $name = $zone->name;

        my $ttl;

        #if ($name eq 'br' or $name eq 'au') {
        #    $ttl = 55;
        #}

        $name = ''       if $name eq '@';
        $name = "$name." if $name;

        if (my $entries = $zone->active_servers('v4')) {

            my $min_non_duplicate_size = 2;
            my $response_records       = 3;
            my @zones                  = ("0.", "1.", "2.", "3.");
            my $zone_count             = scalar @zones;

            # add all servers to the non-numbered "NTP" zone
            (my $pgeodns_group = "${name}") =~ s/\.$//;
            push @{$data->{$pgeodns_group}->{a}}, $_ for @$entries;
            if ($ttl) {
                $data->{$pgeodns_group}->{ttl} = $ttl;
            }

            $min_non_duplicate_size = int(@$entries / $zone_count)
              if (@$entries / $zone_count > $min_non_duplicate_size);

            # print $fh "# " . scalar @$entries . " active servers in ", $zone->name, "\n";

            if ($#$entries < ($min_non_duplicate_size * $zone_count - 1)) {

                # possible duplicates, not enough servers
                foreach my $z (@zones) {
                    (my $pgeodns_group = "$z${name}") =~ s/\.$//;

                    # already has an alias, so don't add more data
                    if ($data->{$pgeodns_group}->{alias}) {
                        next;
                    }

                    $data->{$pgeodns_group}->{a} = [];
                    if ($ttl) {
                        $data->{$pgeodns_group}->{ttl} = $ttl;
                    }
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
                    if ($ttl) {
                        $data->{$pgeodns_group}->{ttl} = $ttl;
                    }
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

            # add all servers to the non-numbered "NTP" zone
            (my $pgeodns_group = "${name}") =~ s/\.$//;
            push @{$data->{$name}->{aaaa}}, $_ for @$entries;

            # Historically, only '2' has had ipv6 records, so we ALSO put all
            # of the records there, for anyone who is relying on 2 having a
            # large number of entries (Who would do such a crazy thing?)
            (my $pgeodns_group = "2.${name}") =~ s/\.$//;
            push @{$data->{$pgeodns_group}->{aaaa}}, $_ for @$entries;

            # Smear the rest of the IPv6 records over the remaining zones,
            # up to 4 records per zone.
            my $maxrecords  = 4;
            my $recordcount = 0;
            my $currentzone = 0;
            my @zones       = ("0.", "1.", "3.");
            while ($recordcount < $maxrecords) {
                (my $pgeodns_group = @zones[$currentzone++].$name) =~ s/\.$//;
                # If we've run out of zones, reset back to zero, and increase
                # the count of records in the zone.
                if (!@zones[$currentzone]) {
                    $currentzone = 0;
                    $recordcount++;
                }
                # Add the next entry to this zone.
                my $e = shift @$entries;
                push @{$data->{$pgeodns_group}->{aaaa}}, $e;
            }
        }
    }
}

sub populate_vendor_zones {
    my $root = shift;

    my $vendor_zones = NP::Model->vendor_zone->get_vendor_zones(
        query => [
            status      => 'Approved',
            dns_root_id => $root->id
        ],
        sort_by => 'approved_on',
    );

    my %vendors;

    for my $vendor (@$vendor_zones) {
        my $name = $vendor->zone_name;
        $vendors{$name} = {
            type   => $vendor->client_type,
            vendor => $vendor
        };
    }

    if ($root->origin eq 'pool.ntp.org') {
        my $vendordir = "vendordns";
        opendir my $dir, $vendordir or die "could not open '$vendordir' dir: $!";
        my @vendor_files =
          grep { $_ !~ /\~$/ and -f $_ } map {"$vendordir/$_"} readdir($dir);
        closedir $dir;
        for my $vendor (@vendor_files) {
            $vendor =~ s!.*/!!;
            $vendors{$vendor} = {type => 'ntp'};
        }
    }

    for my $name (sort keys %vendors) {
        next unless $name;    # vendor_name="" on separate dns root
        my $client_type = $vendors{$name}->{type};
        my $sntp        = ($client_type eq 'sntp' or $client_type eq 'all');
        my $ntp         = ($client_type eq 'ntp'  or $client_type eq 'all');
        unless ($sntp or $ntp) {
            $sntp = 1;
            $ntp  = 1;
        }
        if ($sntp) {
            $root->data->{"$name"}->{alias} = "";
        }
        if ($ntp) {
            for my $i (0 .. 3) {
                $root->data->{"$i.$name"}->{alias} = $i;
            }
        }
    }
}

1;
