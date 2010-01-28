package NTPPool::Control::DNSStatus;
use strict;
use base qw(NTPPool::Control);
use Combust::Constant qw(OK);
use NP::Util::DNS;

sub render {
    my $self = shift;

    $self->cache_control('s-maxage=45');

    my ($master, $servers) = NP::Util::DNS::get_dns_info();

    $self->tpl_param('servers' => $servers);
    $self->tpl_param('master'  => $master);

    $self->tpl_param('now' => DateTime->now);

    return OK, $self->evaluate_template('tpl/dns.html');

}


1;
