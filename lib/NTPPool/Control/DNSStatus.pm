package NTPPool::Control::DNSStatus;
use strict;
use base qw(NTPPool::Control);
use Net::DNS::Resolver;
use List::Util qw(max first);
use Combust::Constant qw(OK);
use DateTime::Duration;
use DateTime::Format::Duration;
use Combust::Config;

sub render {
  my $self = shift;

  my $res   = Net::DNS::Resolver->new;

  alarm(10);

  $res->tcp_timeout(2);
  $res->udp_timeout(2);

  my $pool_domain = Combust::Config->new->site->{ntppool}->{pool_domain}
    or die "pool_domain configuration not setup";

  # $pool_domain = 'pool.ntp.org';

  $self->cache_control('s-maxage=45');

  my $query = $res->query($pool_domain, "NS");

  my %servers;
  if ($query) {
    for my $rr (grep { $_->type eq 'NS' } $query->answer) {
      my $name = $rr->nsdname;
      $servers{$name} = { name => $name };
    }
  }

#  { my $name = 'ns1.eu.bitnames.com';
#    $servers{$name} = { name => $name };
#  }
            
  for my $ns (keys %servers) {
    $res->nameserver($ns);
    $servers{$ns}->{soa_socket}     = $res->bgsend($pool_domain, 'SOA');
    $servers{$ns}->{status_socket}  = $res->bgsend("status.$pool_domain", 'TXT');
    $servers{$ns}->{version_socket} = $res->bgsend("version.$pool_domain", 'TXT');
  }

  for my $ns (sort keys %servers) {
    if (my $socket = $servers{$ns}->{soa_socket}) {
      my $packet = $res->bgread($socket);
      my ($soa) = $packet && grep { $_->type eq 'SOA' } $packet->answer;
      delete $servers{$ns}->{soa_socket};
      $servers{$ns}->{serial} = $soa && $soa->serial;
    }

    for my $f (qw(version status)) {
      if (my $socket = $servers{$ns}->{"${f}_socket"}) {
        my $packet = $res->bgread($socket);
        my ($txt) = $packet && grep { $_->type eq 'TXT' } $packet->answer;
        delete $servers{$ns}->{"${f}_socket"};
        $servers{$ns}->{$f} = $txt && $txt->rdatastr;
       }
    }

  }

  my $max_serial = max map { $servers{$_}->{serial} } keys %servers;
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

  alarm(0);

  my @servers = sort { $a->{name} cmp $b->{name} } values %servers;
  $self->tpl_param('servers' => \@servers);
  my $master = first { $_->{serial} && $_->{serial} == $max_serial } values %servers;
  $self->tpl_param('master'  => $master);

  $self->tpl_param('now' => DateTime->now);

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
