package NP::Util::DNS;
use strict;
use warnings;
use Net::DNS::Resolver;
use List::Util qw(max first);
use NP::Util qw(uniq);
use DateTime::Duration;
use DateTime::Format::Duration;
use Combust::Config;

sub find_dns_servers {

    my $res = Net::DNS::Resolver->new;

    my %servers;
    
    my $add_servers = sub {
        my $name = shift;
        my @ips = host_to_ips($name);
        for my $ip (@ips) {
            unless ($servers{$ip}) {
                $servers{$ip} = { names => [] };
            }
            push @{ $servers{$ip}->{names} }, $name;
        }
    };

    my $pool_domain = Combust::Config->new->site->{ntppool}->{pool_domain}
      or die "pool_domain configuration not setup";

    my $dns_domains =
      Combust::Config->new->site->{ntppool}->{dns_domains} || $pool_domain;

    my @domains = split /\s+/, $dns_domains;
    for my $domain (@domains) {
        if (my $query = $res->query($domain, "NS")) {
            for my $rr (grep { $_->type eq 'NS' } $query->answer) {
                my $name = $rr->nsdname;
                $add_servers->($name);
            }
        }
    }

    if (my $query = $res->query('all-dns.ntppool.net', "TXT")) {
        for my $rr (grep { $_->type eq 'TXT' } $query->answer) {
            my $names = $rr->txtdata;
            for my $name (split /\s+/, $names) {
                $name =~ m/\./ or $name = "$name.ntppool.net";
                $add_servers->($name);
            }
        }
    }

    #use Data::Dumper qw(Dumper);
    #print Dumper(\%servers);
    #exit;

    return %servers;
}

my $resolver;
sub _res {
    return $resolver = Net::DNS::Resolver->new;
}

sub get_dns_info {

    my $res = _res();

    alarm(10);    # short circuit if we really screwed up

    $res->tcp_timeout(3);
    $res->udp_timeout(3);

    my $pool_domain = Combust::Config->new->site->{ntppool}->{pool_domain}
      or die "pool_domain configuration not setup";

    my %servers = find_dns_servers();

#  { my $name = 'ns1.eu.bitnames.com';
#    $servers{$name} = { name => $name };
#  }

    my %sockets;

    for my $ns (keys %servers) {
        $res->nameserver($ns);
        $sockets{$ns}->{soa_socket}     = $res->bgsend($pool_domain,           'SOA');
        $sockets{$ns}->{status_socket}  = $res->bgsend("status.$pool_domain",  'TXT');
        $sockets{$ns}->{version_socket} = $res->bgsend("version.$pool_domain", 'TXT');
    }

    for my $i (1 .. 5) {

        for my $ns (sort keys %sockets) {
            my $socket = $sockets{$ns}->{soa_socket};
            if ($socket && $res->bgisready($socket)) {
                my $packet = $res->bgread($socket);
                my ($soa) = $packet && grep { $_->type eq 'SOA' } $packet->answer;
                delete $sockets{$ns}->{soa_socket};
                $servers{$ns}->{serial} = $soa && $soa->serial;
            }

            for my $f (qw(version status)) {
                my $socket = $sockets{$ns}->{"${f}_socket"};
                if ($socket && $res->bgisready($socket)) {
                    my $packet = $res->bgread($socket);
                    my ($txt) = $packet && grep { $_->type eq 'TXT' } $packet->answer;
                    delete $sockets{$ns}->{"${f}_socket"};
                    $servers{$ns}->{$f} = $txt && $txt->rdatastr;
                }
            }

            delete $sockets{$ns} unless %{$sockets{$ns}};

        }

        last unless %sockets;

        sleep 1;

    }

    my $max_serial = max map { $servers{$_}->{serial} || 0 } keys %servers;
    my $now = time;

    for my $ns (sort keys %servers) {
        my $d = $servers{$ns};

        #warn Data::Dumper->Dump([\$d], [qw(d)]);
        if ($d->{serial}) {
            $d->{age} = $now - $d->{serial};
            $d->{lag} = $max_serial - $d->{serial};
        }

        for my $type (qw(age lag)) {
            my $s = $d->{$type} || 0;
            $d->{"${type}_text"} = $d->{serial} ? hour_min_sec($s) : 'No response';

            my $alert;
            if ($s < 1200) {
                $alert = '#00FF00';
            }
            elsif ($s < 3600) {
                $alert = 'yellow';
            }
            else {
                $alert = 'red';
            }

            $alert = 'red' unless $d->{serial};

            $d->{"${type}_css_color"} = $alert;
        }
    }

    alarm(0);

    my @servers = sort { $a->{names}->[0] cmp $b->{names}->[0] } values %servers;
    my $master = first { $_->{serial} && $_->{serial} == $max_serial } values %servers;

    return ($master, \@servers);
}

sub host_to_ips {
    my $host = shift;
    my $res = _res();
    my $query = $res->search($host);
  
    my @ips;

    if ($query) {
        for my $rr ($query->answer) {
            next unless $rr->type eq "A";
            push @ips, $rr->address;
        }
    } else {
        warn "query failed: ", $res->errorstring, "\n";
    }
    return @ips;
}

sub hour_min_sec {
    my $sec = shift;

    my $dur = DateTime::Duration->new(seconds => $sec);
    my $durf = DateTime::Format::Duration->new(
        pattern   => '%e days, %k hours, %M minutes',    # , %S seconds',
        normalize => 1,
    );

    my %deltas = $durf->normalise($dur);

    #warn Data::Dumper->Dump([\%deltas], [qw(deltas)]);

    my $s = $durf->format_duration_from_deltas(%deltas);

    $s = join ", ", grep { $_ !~ m/^0\s/ } map { s/^0(\d)/$1/; $_ } split /, /, $s;
    $s eq '0 hours' ? '0 minutes' : $s;

}

1;
