package NTPPool::Control::Manage;
use strict;
use base qw(NTPPool::Control);
use NTPPool::Server;
use Apache::Constants qw(OK);
use Socket qw(inet_ntoa);
use Net::NTP;
use Geo::IP;
use Email::Send 'SMTP';
use Sys::Hostname qw(hostname);
use Email::Date qw();

sub render {
    my $self = shift;
    
    if ($self->request->uri =~ m!^/manage/logout!) {
        $self->cookie($NTPPool::Control::cookie_name, 0);
        $self->redirect( $self->bitcard->logout_url( r => $self->config->base_url('ntppool') ));
    }
    
    return $self->login unless $self->user;
    
    return $self->handle_add if $self->request->uri =~ m!^/manage/add!;
    return $self->show_manage;
}

sub show_manage {
    my $self = shift;
    return OK, $self->evaluate_template('tpl/manage.html');
}

sub handle_add {
    my $self = shift;

    $self->tpl_param('host', $self->req_param('host'));

    my $server = eval { $self->get_server_info };
    if (!$server or $@) {
        $self->tpl_param('host_error', $@ || 'Error checking your server');
        return OK, $self->evaluate_template('tpl/manage/add_form.html');
    }

    $self->tpl_param(server => $server);

    if ($self->req_param('yes')) {

        $self->tpl_param('comment', $self->req_param('comment'));

        my $msg = $self->evaluate_template('tpl/manage/add_email.txt');
        my $email = Email::Simple->new($$msg);
        $email->header_set('Message-ID' => join("-", int(rand(1000)), $$, time) . '@' . hostname);
        $email->header_set('Date'       => Email::Date::format_date);
        my $return = send SMTP => $email, 'localhost';
        warn Data::Dumper->Dump([\$msg, \$email, \$return], [qw(msg amil return)]);

        my $s = NTPPool::Server->create
          ({ ip       => $server->{ip}, 
             hostname => $server->{hostname} || '',
             admin    => $self->user,
           });
        $s->add_to_locations({ zone => $_ }) for @{$server->{zones}};
        return $self->show_manage;
    }

    return OK, $self->evaluate_template('tpl/manage/add.html');
}

my $geo_ip = Geo::IP->new(GEOIP_STANDARD);
sub get_server_info {
    my $self = shift;
    my $host = $self->req_param('host');
    die "No hostname or IP\n" unless $host;

    my $iaddr = gethostbyname $host;
    die "Could not find the IP for $host\n" unless $iaddr;

    my %server;
    $server{ip} = inet_ntoa($iaddr);
    $server{hostname} = $host if $host ne $server{ip};

    if (my ($s) = NTPPool::Server->search(ip => $server{ip})) {
        my $other = $s->admin eq $self->user ? "" : "Email us your username to have it moved to this account";
        die "$server{ip} is already listed in the pool. $other\n";
    }
    
    local $Net::NTP::TIMEOUT = 2;
    my %ntp = eval { get_ntp_response($server{ip}); };
    warn "checking $host / $server{ip}";
    warn Data::Dumper->Dump([\%ntp]);

    die "Didn't get an NTP response from $host\n" unless defined $ntp{Stratum};
    die "Invalid stratum response from $host. Is your server configured properly? Is public access allowed?\n"
      unless $ntp{Stratum} > 0 and $ntp{Stratum} < 6;

    $server{ntp} = \%ntp;

    my $country = $geo_ip->country_code_by_addr($server{ip});
    my @zones = NTPPool::Zone->search(name => $country);
    @zones = NTPPool::Zone->search(name => '@') unless @zones;
    unshift @zones, $zones->[0]->parent while ($zones[0]->parent);

    $server{zones} = \@zones;

    return \%server;
}

1;
