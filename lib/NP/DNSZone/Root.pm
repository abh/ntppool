package NP::DNSZone::Root;
use strict;
use warnings;
use Combust::Config;
use List::Util     qw(shuffle);
use NP::CAPI::Zone qw(get_zone_active_servers);
use Carp           qw(croak);

my $config     = Combust::Config->new;
my $config_ntp = $config->site->{ntppool};

use constant default_ttl => 150;

sub new_from_api {
    my ($class, $api_data, %opts) = @_;

    my $dns_root = $api_data->{dns_root} || {};

    my $self = bless {
        id                => $dns_root->{id},
        origin            => $dns_root->{origin},
        ns_list           => $dns_root->{ns_list},
        _api_zones        => $api_data->{zones}        || [],
        _api_vendor_zones => $api_data->{vendor_zones} || [],
        ttl               => ($api_data->{settings} || {})->{ttl},
        _auth             => $opts{auth},
    }, $class;

    # Sanity check required fields from API
    croak "Missing origin from API response"  unless defined $self->{origin};
    croak "Missing ns_list from API response" unless defined $self->{ns_list};
    croak "Missing TTL from API response" unless defined $self->{ttl} && $self->{ttl} > 0;

    return $self;
}

sub serial {
    return shift->{_dns_serial} ||= time;
}

sub data {
    my $self = shift;

    # return a singleton for the root so other methods can add to the data
    return $self->{_dns_data} ||= do {

        my $www_record = {
            cname => $config_ntp->{www_cname} || 'www-lb.ntppool.org.',
            ttl   => 7200,
        };

        my $data = {};
        $data->{www} = $www_record;
        $data->{web} = $www_record;
        $data->{gb}  = {alias => 'uk'};
        for my $i (0 .. 3) {
            $data->{"$i.gb"} = {alias => "$i.uk"};
        }

        $data->{""}->{ns} = {map { $_ => undef } split /[\s+,]/, $self->{ns_list}};

        $data->{""}->{txt} = [

            # Fastly TLS verification
            {   txt =>
                  "_globalsign-domain-verification=mVYWxIl-2ab_B1yPPFxEmDCLrBcl6ucouXJOU_P0_C"
            },
        ];

        # null MX records by default, rfc7505
        $data->{""}->{mx} = [{mx => ".", preference => 0},];

        if ($self->{origin} eq "pool.ntp.org") {

            # google domain verification
            $data->{"v4zgfk4oagsu"}->{cname} = "gv-35off4weczdcxg.dv.googlehosted.com.";
            push @{$data->{""}->{txt}},
              {txt => "v=spf1 -all"},
              {txt => "facebook-domain-verification=sfjgxys7hmryn50lszk658gi7amidt"},
              {txt =>
                  "google-site-verification=PRDJb3cjUxA4K-Abx2wItCnGwTkkNTRqJVjCkmAk54Q"};

            $data->{"_dmarc"}->{txt} =
              'v=DMARC1; p=reject; pct=100; rua=mailto:4649a710@in.mailhardener.com; sp=reject; adkim=s; aspf=r; ruf=mailto:4649a710@in.mailhardener.com';

        }
        elsif ($self->{origin} eq "beta.grundclock.com") {
            $data->{"fchof3xzaiyl"}->{cname} = "gv-fveibxaoathoje.dv.googlehosted.com.";
            push @{$data->{""}->{txt}},
              {txt => "facebook-domain-verification=9gahpfmem9gwjmxypka1o3v3fgnb4k"};
        }

        $data;
    };
}

sub TO_JSON {
    my $self = shift;
    return {
        serial    => $self->serial,
        ttl       => $self->{ttl},
        data      => $self->data,
        max_hosts => 4,
        logging   => {},
    };
}

sub populate {
    my $self = shift;
    $self->populate_vendor_zones;
    $self->populate_country_zones;
}

sub _get_zone_servers {
    my ($self, $zone_name, $ip_version) = @_;

    my $result = get_zone_active_servers(
        zone_name  => $zone_name,
        ip_version => $ip_version,
        ($self->{_auth} ? (auth => $self->{_auth}) : ()),
    );

    # Fail hard on API errors
    if ($result->{error}) {
        my $msg = "Failed to get active servers for zone $zone_name ($ip_version): ";
        $msg .= $result->{error} // 'unknown error';
        $msg .= " [code: " . $result->{connect_code} . "]" if $result->{connect_code};
        $msg .= " [trace: " . $result->{trace_id} . "]"    if $result->{trace_id};
        croak $msg;
    }

    unless (defined $result->{data}) {
        croak "No data returned for zone $zone_name ($ip_version)";
    }

    my $servers = $result->{data}{servers};
    unless (defined $servers && ref($servers) eq 'ARRAY') {
        croak "Invalid servers response for zone $zone_name ($ip_version)";
    }

    # Convert from CAPI format [{ip => ..., netspeed => ...}, ...]
    # to legacy format [[ip, netspeed], ...]
    my @entries;
    for my $srv (@$servers) {
        unless (ref($srv) eq 'HASH') {
            croak "Invalid server entry (not a hash) for zone $zone_name";
        }

        my $ip = $srv->{ip};
        unless (defined $ip && length($ip) > 0) {
            croak "Missing or empty IP in server entry for zone $zone_name";
        }

        my $netspeed = $srv->{netspeed};
        unless (defined $netspeed && $netspeed =~ /^\d+$/ && $netspeed > 0) {
            croak "Invalid netspeed '$netspeed' for server $ip in zone $zone_name";
        }

        push @entries, [$ip, $netspeed];
    }

    return \@entries;
}

sub populate_country_zones {
    my $self = shift;

    my $zones = $self->{_api_zones} || [];
    my $data  = $self->data;

    for my $zone (@$zones) {
        my $name = $zone->{name};

        my $ttl;

        #if ($name eq 'br' or $name eq 'au') {
        #    $ttl = 55;
        #}

        $name = ''       if $name eq '@';
        $name = "$name." if $name;

        if (my $entries = $self->_get_zone_servers($zone->{name}, 'v4')) {

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
            $data->{$pgeodns_group}->{mx} = [{mx => ".", preference => 0}];

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

                    $data->{$pgeodns_group}->{mx} = [{mx => ".", preference => 0}];

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

                    $data->{$pgeodns_group}->{mx} = [{mx => ".", preference => 0}];
                }
            }
        }

        if (my $entries = $self->_get_zone_servers($zone->{name}, 'v6')) {
            @$entries = shuffle(@$entries);

            # for now just put all IPv6 servers in the '2' zone
            (my $pgeodns_group = "2.${name}") =~ s/\.$//;
            push @{$data->{$pgeodns_group}->{aaaa}}, $_ for @$entries;
        }

    }
}

sub populate_vendor_zones {
    my $root = shift;

    my %vendors;

    for my $vz (@{$root->{_api_vendor_zones} || []}) {
        my $name = $vz->{zone_name};
        $vendors{$name} = {type => $vz->{client_type},};
    }

    if ($root->{origin} eq 'pool.ntp.org') {
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
        my $sntp        = ($client_type eq 'sntp' or $client_type eq 'legacy');
        my $ntp         = ($client_type eq 'ntp'  or $client_type eq 'legacy');
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
