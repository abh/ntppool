package NTPPool::Control::DNSStatus;
use strict;
use base qw(NTPPool::Control);
use Net::DNS::Resolver;
use Apache::Constants qw(OK);
use DateTime::Duration;
use DateTime::Format::Duration;

sub render {
  my $self = shift;

  my $res   = Net::DNS::Resolver->new;

  alarm(10);

  $res->tcp_timeout(3);
  $res->udp_timeout(3);

  $res->nameserver('ns1.us.bitnames.com', 'ns2.us.bitnames.com');

  my $pool_domain = $config->site->{ntppool}->{pool_domain} or die "pool_domain configuration not setup";

  my $query = $res->query($pool_domain, "NS");

  my %servers;
  if ($query) {
    for my $rr (grep { $_->type eq 'NS' } $query->answer) {
      my $name = $rr->nsdname;
      $servers{$name} = { name => $name };
    }
  }

  { my $name = 'ns1.eu.bitnames.com';
    $servers{$name} = { name => $name };
  }
            
  my $prim = 'ns3.rbl.bitnames.com';

  $servers{$prim} = { name => $prim };

  for my $ns (keys %servers) {
    $res->nameserver($ns);
    $servers{$ns}->{socket} = $res->bgsend($pool_domain, 'SOA');
  }

  for my $ns (sort keys %servers) {
    my $socket = $servers{$ns}->{socket} or next;
    my $packet = $res->bgread($socket);
    my ($soa) = grep { $_->type eq 'SOA' } $packet->answer;
    delete $servers{$ns}->{socket};
    $servers{$ns}->{serial} = $soa && $soa->serial;
  }

  my $max_serial = $servers{$prim}->{serial};
  my $now = time;

  for my $ns (sort keys %servers) {
    my $d = $servers{$ns};
    #warn Data::Dumper->Dump([\$d], [qw(d)]);
    $d->{age} = $now - $d->{serial};
    $d->{lag} = $max_serial - $d->{serial};
    for my $type (qw(age lag)) {
      my $s = $d->{$type};
      $d->{"${type}_text"} = hour_min_sec($s);

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
      $d->{"${type}_css_color"} = $alert;
    }
  }

  $self->tpl_param('master' => delete $servers{$prim});

  my @servers = sort { $a->{name} cmp $b->{name} } values %servers;
  $self->tpl_param('servers' => \@servers);

  alarm(0);

  return OK, $self->evaluate_template('tpl/dns.html');

}

sub hour_min_sec {
  my $sec = shift;

  my $dur = DateTime::Duration->new(seconds => $sec);
  my $durf = DateTime::Format::Duration->new
      (pattern => '%e days, %k hours, %M minutes', # , %S seconds',
       normalize => 1,
       );

  my %deltas = $durf->normalise($dur);
  #warn Data::Dumper->Dump([\%deltas], [qw(deltas)]);

  my $s = $durf->format_duration_from_deltas(%deltas);

  $s = join ", ", grep { $_ !~ m/^0\s/ } map { s/^0(\d)/$1/; $_ } split /, /, $s;
  $s eq '0 hours' ? '0 minutes' : $s;
 
}

1;
