package NTPPool::Control::Manage;
use strict;
use base qw(NTPPool::Control);
use NTPPool::Server;
use Apache::Constants qw(OK NOT_FOUND);
use Socket qw(inet_ntoa);
use Net::NTP;
use Geo::IP;
use Email::Send 'SMTP';
use Sys::Hostname qw(hostname);
use Email::Date qw();
use JSON qw();

my $json = JSON->new();

sub render {
    my $self = shift;

    $self->r->no_cache(1);
    
    if ($self->request->uri =~ m!^/manage/logout!) {
        $self->cookie($Combust::Control::Bitcard::cookie_name, 0);
        $self->redirect( $self->bitcard->logout_url( r => $self->config->base_url('ntppool') ));
    }
    
    return $self->login unless $self->user;
    
    return $self->handle_add if $self->request->uri =~ m!^/manage/add!;
    return $self->handle_update if $self->request->uri =~ m!^/manage/update!;
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
        warn $self->tpl_param('host_error');
        return OK, $self->evaluate_template('tpl/manage/add_form.html');
    }

    $self->tpl_param(server => $server);

    if ($self->req_param('yes')) {

        $self->tpl_param('comment', $self->req_param('comment'));
        $self->tpl_param('scores_url', $self->config->base_url('ntppool') . '/scores/' . $server->{ip});

        my $msg = $self->evaluate_template('tpl/manage/add_email.txt');
        my $email = Email::Simple->new(ref $msg ? $$msg : $msg); # until we decide what eval_tpl should return :)
        $email->header_set('Message-ID' => join("-", int(rand(1000)), $$, time) . '@' . hostname);
        $email->header_set('Date'       => Email::Date::format_date);
        my $return = send SMTP => $email, 'localhost';
        warn Data::Dumper->Dump([\$msg, \$email, \$return], [qw(msg amil return)]);

        my $s = NTPPool::Server->create
          ({ ip       => $server->{ip}, 
             hostname => $server->{hostname} || '',
             admin    => $self->user,
             in_pool  => 1,
           });
        $s->add_to_locations({ zone => $_ }) for @{$server->{zones}};
        return $self->show_manage;
    }

    return OK, $self->evaluate_template('tpl/manage/add.html');
}

sub get_server_info {
    my $self = shift;
    my $host = $self->req_param('host');
    die "No hostname or IP\n" unless $host;

    my $iaddr = gethostbyname $host;
    die "Could not find the IP for $host\n" unless $iaddr;

    my %server;
    $server{ip} = inet_ntoa($iaddr);
    $server{hostname} = $host if $host ne $server{ip};

    die "Bad IP address\n" if $server{ip} =~ m/^(127|10|192.168)\./;

    if (my ($s) = NTPPool::Server->search(ip => $server{ip})) {
        my $other = $s->admin eq $self->user ? "" : "Email us your username to have it moved to this account";
        die "$server{ip} is already listed in the pool. $other\n";
    }
    
    local $Net::NTP::TIMEOUT = 2;
    my %ntp = eval { get_ntp_response($server{ip}); };
    warn "checking $host / $server{ip}";
    warn Data::Dumper->Dump([\%ntp]);

    die "Didn't get an NTP response from $host\n" unless defined $ntp{Stratum};
    die "Invalid stratum response from $host (Your server is in stratum $ntp{Stratum}).  Is your server configured properly? Is public access allowed?  If you just restarted your ntpd, then it might still be stabalizing the timesources - try again in 10-20 minutes.\n"
      unless $ntp{Stratum} > 0 and $ntp{Stratum} < 6;

    $server{ntp} = \%ntp;

    my $geo_ip = Geo::IP->new(GEOIP_STANDARD);
    my $country = $geo_ip->country_code_by_addr($server{ip});
    $country = 'UK' if $country eq 'GB';
    warn "Country: $country\n";
    my $country_zone = NTPPool::Zone->retrieve_by_name($country);
    my @zones;
    push @zones, $country_zone if $country_zone;
    @zones = NTPPool::Zone->search(name => '@') unless @zones;
    unshift @zones, $zones[0]->parent while ($zones[0]->parent and $zones[0]->parent->dns);
    $server{zones} = \@zones;

    return \%server;
}

sub handle_update {
    my $self = shift;

    return $self->handle_update_profile  if $self->request->uri =~ m!^/manage/update/profile!;
    return $self->handle_update_netspeed if $self->request->uri =~ m!^/manage/update/netspeed!;

    return NOT_FOUND;
}

sub handle_update_netspeed {
    my $self = shift;
    my $server_id = $self->req_param('server');
    my $server = NTPPool::Server->retrieve($server_id);
    return NOT_FOUND unless $server and $server->admin == $self->user;
    if (my $netspeed = $self->req_param('netspeed')) {
        $server->netspeed($netspeed) if $netspeed =~ m/^\d+$/;
        if ($server->netspeed < 768) {
            $server->leave_zone('@');
        }
        else {
            $server->join_zone('@');
        }
        $server->update;
    }

    return $self->show_manage if $self->req_param('noscript');

    my $return = { 
        netspeed => $self->netspeed_human($server->netspeed),
        zones    => join " ", map { join "",
                                     '<a href="/zone/',
                                     $_->name, '">',
                                     $_->name,
                                     '</a>' } $server->zones,
    };

    return OK, $json->objToJson($return);

}

sub handle_update_profile {
    my $self = shift;

    my $public = ($self->request->uri =~ m/public/) ? 1 : 0;
    $self->user->public_profile($public);
    $self->user->update;

    $self->tpl_param('user' => $self->user );

    return $self->show_manage if $self->r->method eq 'GET';
    return OK, $self->evaluate_template('tpl/manage/profile_link.html', { style => 'bare.html' });
}

sub netspeed_human {
    my ($self, $netspeed) = @_;
    NTPPool::Server::_netspeed_human($netspeed);
}

1;
