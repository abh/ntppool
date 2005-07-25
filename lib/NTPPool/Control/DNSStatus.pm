package NTPPool::Control::DNSStatus;
use strict;
use base qw(NTPPool::Control);
use Net::DNS::Resolver;
use Apache::Constants qw(OK);

sub render {
  my $self = shift;

  my $res   = Net::DNS::Resolver->new;

  $res->nameserver('ns1.us.bitnames.com', 'ns2.us.bitnames.com');
  my $query = $res->query("pool.ntp.org", "NS");

  my %servers;
  if ($query) {
    for my $rr (grep { $_->type eq 'NS' } $query->answer) {
      my $name = $rr->nsdname;
      $servers{$name} = { name => $name };
    }
  }

  $res->tcp_timeout(3);
  $res->udp_timeout(3);

  my $prim = 'ns3.rbl.bitnames.com';

  $servers{$prim} = { name => $prim };

  for my $ns (keys %servers) {
    $res->nameserver($ns);
    $servers{$ns}->{socket} = $res->bgsend('pool.ntp.org', 'SOA');
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

  return OK, $self->evaluate_template('tpl/dns.html');

}

sub hour_min_sec {
  my $d = shift;
  my $min = $d ? int($d / 60) : 0;
  $d -= $min * 60;
  "$min " . ($min == 1 ? 'minute ' : 'minutes ');
}

1;
