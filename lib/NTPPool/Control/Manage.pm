package NTPPool::Control::Manage;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);
use Socket qw(inet_ntoa);
use Socket6;
use Net::NTP;
use Geo::IP;
use Email::Send 'SMTP';
use Sys::Hostname qw(hostname);
use Email::Date qw();
use JSON::XS qw(encode_json decode_json);
use Net::DNS;
use LWP::UserAgent qw();
use Mozilla::CA qw();
use Math::BaseCalc qw();
use Math::Random::Secure qw(irand);

my $config     = Combust::Config->new;
my $config_ntp = $config->site->{ntppool};

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    if (0 and $self->req_param('sig') or $self->req_param('bc_id')) {
        my $bc = $self->bitcard;
        my $bc_user = eval { $bc->verify($self->request) };
        warn $@ if $@;
        unless ($bc_user) {
            warn $bc->errstr;
        }
        if ($bc_user and $bc_user->{id} and $bc_user->{username}) {
            use Data::Dump qw(pp);
            warn "Logging in user: ", pp($bc_user);
            my ($email_user) = NP::Model->user->fetch(email      => $bc_user->{email});
            my ($user)       = NP::Model->user->fetch(bitcard_id => $bc_user->{id});
            $user = $email_user if ($email_user and !$user);
            if ($user and $email_user and $user->id != $email_user->id) {
                my @servers = NP::Model->server->get_servers(query => [user_id => $email_user->id]);
                if (@servers && $servers[0]) {
                    for my $server (@servers) {
                        $server->user_id($user);
                        $server->save;
                    }
                }
                $email_user->delete;
            }
            unless ($user) {
                ($user) = NP::Model->user->create(bitcard_id => $bc_user->{id});
            }
            my $uid = $user->id;
            $user->username($bc_user->{username});
            $user->email($bc_user->{email});
            $user->name($bc_user->{name});
            $user->bitcard_id($bc_user->{id});
            $user->save;
            $self->cookie($self->user_cookie_name, $uid);
            $self->user($user);
        }
    }

    if ($self->is_logged_in) {
        $self->request->env->{REMOTE_USER} = $self->user->username;
    }

    return OK;
}

sub render {
    my $self = shift;

    $self->cache_control('private');

    if ($self->request->uri =~ m!^/manage/logout!) {
        $self->cookie($self->user_cookie_name, 0);
        $self->cookie("xs", 0);
        $self->redirect('/manage');
    }

    if ($self->request->uri =~ m!^/manage/login!) {

        if (my $code = $self->req_param('code')) {
            my ($userdata, $error) = $self->_get_auth0_user($code);
            if ($error) {
                return $self->login($error);
            }
            warn "Error: ", Data::Dump::pp(\$error);

            my ($identity, $user);

            # check if profile exists for any of the identities
            for my $identity_id ($userdata->{user_id},
                map { join "|", $_->{provider}, $_->{user_id} } @{$userdata->{identities}})
            {
                warn "Identity id: '$identity_id'";
                $identity = NP::Model->user_identity->fetch(profile_id => $identity_id);
                last if $identity;
            }

            my $email = $userdata->{email_verified} && $userdata->{email};
            my $provider = $userdata->{identities} && $userdata->{identities}->[0] && $userdata->{identities}->[0]->{provider};

            if ($identity) {
                $identity->provider($provider) if $provider;
                $identity->data(encode_json($userdata));
            }
            else {
                warn "Didn't find identity in the database";

                if (!$email) {
                    return $self->login("Email not verified");
                }

                $identity = NP::Model->user_identity->create(
                    profile_id => $userdata->{user_id},
                    email      => $email,
                    data       => encode_json($userdata),
                    provider   => $provider,
                );

                # look for an account with a verified email address we
                # can recognize.
                my %uniq;
                my @emails =
                  map { $_->{profileData}->{email} }
                  grep {
                    my $p = $_->{profileData};
                    my $ok =
                         $p
                      && $p->{email}
                      && $p->{email_verified}
                      && !$uniq{$p->{email}}++;
                    $ok;
                  } ({ profileData => $userdata }, @{$userdata->{identities}});

                for my $email (@emails) {
                    warn "Testing email: $email";
                    my ($email_user) = NP::Model->user->fetch(email => $email);
                    if ($email_user) {
                        warn "Found email user in the database";
                        $user = $email_user;
                        last;
                    }
                }
            }

            # we do this outside the identity check just in case for
            # some reason we have an identity without a user
            # associated.

            $user = $user || $identity->user;

            my $base36 = Math::BaseCalc->new(digits => ['a' .. 'k', 'm' .. 'z', 2 .. 9]);
            if (!$user) {
                my $username = join "", map { $base36->to_base(irand) } (undef) x 3;
                $user = NP::Model->user->create(
                    email    => $identity->email,
                    name     => $userdata->{name},
                    username => $username,
                );
                $user->save;
            }

            if ($identity->user_id != $user->id) {
                $identity->user_id($user->id);
            }

            $identity->save;

            $self->cookie("xs", join "", map { $base36->to_base(irand) } (undef) x 6);
            $self->cookie($self->user_cookie_name, $user->id);
            $self->user($user);

            my $r = $self->req_param('r') || '/manage';
            return $self->redirect( $r );
        }

    }

    return $self->login unless $self->user;

    return $self->manage_dispatch;
}

sub _auth0_config {
    my $self = shift;

    return @{$self->{_auth0_config}} if $self->{_auth0_config};

    my $site = $self->site;

    my $auth0_domain = $self->config->site->{$site}->{auth0_domain}
      or die "auth0_domain not configured for site $site";

    my $auth0_client = $self->config->site->{$site}->{auth0_client}
      or die "auth0_client not configured for site $site";

    my $auth0_secret = $self->config->site->{$site}->{auth0_secret}
      or die "auth0_secret not configured for site $site";

    $self->{_auth0_config} = [$auth0_domain, $auth0_client, $auth0_secret];

    return @{$self->{_auth0_config}};
}

sub _get_auth0_user {
    my ($self, $code) = @_;

    # https://auth0.com/docs/protocols#3-getting-the-access-token

    my ($auth0_domain, $auth0_client, $auth0_secret) = $self->_auth0_config();

    my $ua = LWP::UserAgent->new(
        ssl_opts => {
            SSL_verify_mode => 0x02,
            SSL_ca_file     => Mozilla::CA::SSL_ca_file()
        }
    );

    my $url = URI->new("https://${auth0_domain}/oauth/token");

    my %form = (
        'code'          => $self->req_param('code'),
        'client_id'     => $auth0_client,
        'redirect_uri'  => $self->callback_url,
        'client_secret' => $auth0_secret,
        'grant_type'    => 'authorization_code',
    );
    my $resp = $ua->post($url, \%form);
    use Data::Dump qw(pp);
    pp($resp);

    $resp->is_success or return undef, "Could not fetch oauth token";

    my $data = decode_json($resp->decoded_content())
      or return undef, "Could not decode token data";

    $resp = $ua->get("https://${auth0_domain}/userinfo/?access_token=" . $data->{access_token});
    $resp->is_success or return undef, "Could not fetch user data";

    my $user = decode_json($resp->decoded_content())
      or return undef, "Could not decode user data";

    return $user, undef;

}

sub callback_url {
    my $self = shift;

    my $uri  = URI->new($self->config->base_url($self->site));
    $uri->path('/manage/login');

    my $here = $self->_here_url;
    if ($here =~ m{manage/login}) {
        $here = "/manage";
    }

    $uri->query_form(r => $here);
    $uri->as_string();
}

sub login_url {
    my $self = shift;

#    return 'https://ntp.auth0.com/authorize?response_type=code'
#    . '&client_id=kDlOYWYyIQlLMjgyzrKJhQmARaM8rOaM&connection=github'
#    . '&state=&redirect_uri=' . $self->_here_url;

    my ($auth0_domain, $auth0_client) = $self->_auth0_config();

    return
        "https://${auth0_domain}/authorize?response_type=code"
      . "&client_id=${auth0_client}"
      . '&redirect_uri=' . $self->callback_url;
}

sub manage_dispatch {
    my $self = shift;

    $self->tpl_param('xs', $self->cookie('xs'));

    return $self->handle_add if $self->request->uri =~ m!^/manage/server/add!;
    return $self->handle_update
      if $self->request->uri =~ m!^/manage/(server|profile)/update!;
    return $self->handle_delete
      if $self->request->uri =~ m!^/manage/server/delete!;
    return $self->show_manage if $self->request->uri =~ m!^/manage/servers!;

    return $self->redirect('/manage/servers')
      unless $self->user->is_staff;

    return $self->show_staff;
}

sub show_staff {
    my $self = shift;
    return OK, $self->evaluate_template('tpl/staff.html');
}

sub show_manage {
    my $self = shift;
    return OK, $self->evaluate_template('tpl/manage.html');
}

sub handle_add {
    my $self = shift;

    my $host = $self->req_param('host');
    $self->tpl_param('host', $host);

    my @servers;

    my @ips = $self->_get_server_ips($host);

    for my $ip (@ips) {
        my $server = $self->get_server_info($ip);
        unless (Net::IP->new($host)) {
            $server->{hostname} = $host if $server;
        }
        push @servers, $server;
    }

    if (!@servers) {
        return OK, $self->evaluate_template('tpl/manage/add_form.html');
    }

    for my $server (@servers) {
        my @zones;
        if (!$server->{country_zone}) {
            $server->{data_missing} ||= 'Country not specified'
              if !$server->{error} and $self->req_param('yes');
            next;
        }
        my @zones;
        push @zones, $server->{country_zone};
        unshift @zones, $zones[0]->parent while ($zones[0]->parent);
        $server->{zones} = \@zones;
    }

    my $allow_submit = grep { !$_->{error} } @servers;
    my $data_missing = grep { $_->{data_missing} } @servers;

    $self->tpl_param(servers => \@servers);

    $self->tpl_param('allow_submit' => $allow_submit);

    if ($self->req_param('yes') and $allow_submit and !$data_missing) {
        my $s;
        my @added;
        for my $server (@servers) {
            unless ($server->{error} or $server->{listed}) {
                $s = $self->_add_server($server);
                push @added, $server;
            }
        }
        $self->tpl_param(servers => \@added);
        my $msg = $self->evaluate_template('tpl/manage/add_email.txt');
        my $email =
          Email::Simple->new(ref $msg ? $$msg : $msg)
          ;    # until we decide what eval_tpl should return :)
        $email->header_set('Message-ID' => join("-", int(rand(1000)), $$, time) . '@' . hostname);
        $email->header_set('Date' => Email::Date::format_date);
        my $return = send SMTP => $email, 'localhost';
        warn Data::Dumper->Dump([\$msg, \$email, \$return], [qw(msg email return)]);

        return $self->redirect('/manage/servers#s-' . ($s && $s->ip));
    }

    my @all_zones = NP::Model->zone->get_zones(
        query => [
            name => {like => '__'},
            dns  => 1,
        ],
        sort_by => 'description',
    );
    $self->tpl_param(all_zones => @all_zones);

    #use Data::Dump qw(pp);
    #warn "SERVERS: ", pp(\@servers);

    return OK, $self->evaluate_template('tpl/manage/add.html');
}

sub _get_server_ips {
    my ($self, $host) = @_;

    if (my $ip = Net::IP->new($host)) {
        return ($ip->short);
    }

    my $res = Net::DNS::Resolver->new;
    my @ips;
    for my $type (qw(A AAAA)) {
        my $query = $res->query($host, $type);
        if ($query) {
            for my $rr ($query->answer) {
                next unless $rr->type eq "A" or $rr->type eq "AAAA";
                push @ips, $rr->address;
            }
        }
        else {
            warn "query failed: ", join(" ", $host, $type, $res->errorstring), "\n";
        }
    }
    warn "GOT IPS: ", join ", ", @ips;
    return @ips;
}

sub _add_server {
    my ($self, $server) = @_;

    my $comment = $self->req_param('comment');
    $self->tpl_param('comment',    $comment);
    $self->tpl_param('scores_url', $self->config->base_url('ntppool') . '/scores/' . $server->{ip});

    my $s;

    my $db = NP::Model->db;

    my $txn = $db->begin_scoped_work;

    if ($s = NP::Model->server->fetch(ip => $server->{ip})) {
        $s->setup_server;
    }
    else {
        $s = NP::Model->server->create(ip => $server->{ip});
    }

    $s->hostname($server->{hostname} || '');
    $s->ip_version($server->{ip_version});
    $s->admin($self->user);
    $s->in_pool(1);
    $s->deleted(0);
    $s->deletion_on(undef);
    $s->zones([]);

    $s->join_zone($_) for @{$server->{zones}};
    if (my $zone_name = $self->req_param('explicit_zone_' . $s->ip)) {
        warn "user picked [$zone_name]";
        my $explicit_zone = NP::Model->zone->get_zones(query => [name => $zone_name]);
        $explicit_zone = $explicit_zone->[0];
        while ($explicit_zone) {
            $s->join_zone($explicit_zone);
            $explicit_zone = $explicit_zone && $explicit_zone->parent;
        }
    }
    $s->add_logs(
        {   user_id => $self->user->id,
            type    => 'create',
            message => "Server added." . ($comment =~ m/\S/ ? "\n\n$comment" : ""),
        }
    );

    #local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;
    $s->save(cascade => 1);

    $db->commit;

    return $s;
}

sub get_server_info {
    my ($self, $ip) = @_;

    warn "getting server info for $ip";

    $ip = Net::IP->new($ip);

    my %server;

    $server{ip}         = $ip->short;
    $server{ip_version} = 'v' . $ip->version;

    {
        my $type = $ip->iptype;
        if ($type and $type !~ m/^(PUBLIC|GLOBAL-UNICAST)/) {
            $server{error} = "Bad IP address: $type";
            return \%server;
        }
    }

    if (my $s = NP::Model->server->fetch(ip => $server{ip})) {
        my $other =
          $s->admin->id eq $self->user->id
          ? ""
          : "Email us your username to have it moved to this account";
        unless ($s->deleted or $s->deletion_on) {
            $server{listed} = 1 unless $other;
            $server{error} = "$server{ip} is already listed in the pool. $other\n";
            return \%server;
        }
    }

    local $Net::NTP::TIMEOUT = 3;
    my %ntp = eval { get_ntp_response($server{ip}); };
    warn "checking $ip / $server{ip}";
    warn Data::Dumper->Dump([\%ntp]);

    unless (defined $ntp{Stratum}) {
        $server{error} = "Didn't get an NTP response from $server{ip}\n";
    }

    unless ($ntp{Stratum} > 0 and $ntp{Stratum} < 6) {
        $server{error} =
          "Invalid stratum response from $server{ip} (Your server is in stratum $ntp{Stratum}).  Is your server configured properly? Is public access allowed?  If you just restarted your ntpd, then it might still be stabilizing the timesources - try again in 10-20 minutes.\n";
    }

    $server{ntp} = \%ntp;

    if ($server{error}) {
        warn "Error: $server{error}";
        return \%server;
    }

    my $geo_ip = eval "Geo::IP->new(GEOIP_STANDARD)";
    $server{geoip_country} = $geo_ip && $geo_ip->country_code_by_addr($server{ip}) || '';

    my $country = $self->req_param('explicit_zone_' . $server{ip}) || $server{geoip_country};

    $country = 'UK' if $country eq 'GB';
    warn "Country: $country\n";
    $server{country_zone} = $country && NP::Model->zone->fetch(name => $country);

    return \%server;
}

sub req_server {
    my $self      = shift;
    my $server_id = $self->req_param('server') or return;
    my $server    = NP::Model->server->fetch(($server_id =~ m/[.:]/ ? 'ip' : 'id') => $server_id);
    return unless $server and $server->admin->id == $self->user->id;
    $server;
}

sub handle_update {
    my $self = shift;

    return $self->handle_update_profile
      if $self->request->uri =~ m!^/manage/profile/update!;
    return $self->handle_update_netspeed
      if $self->request->uri =~ m!^/manage/server/update/netspeed!;
    return $self->handle_mode7_check
      if $self->request->uri =~ m!^/manage/server/update/mode7check!;

    # deletion and non-js netspeed
    if ($self->request->uri =~ m!^/manage/server/update/server!) {
        return $self->handle_mode7_check     if $self->req_param('mode7check');
        return $self->handle_update_netspeed if $self->req_param('Update');
        if ($self->req_param('Delete')) {
            return $self->handle_delete;
        }
    }
    return NOT_FOUND;
}

sub handle_mode7_check {
    my $self     = shift;
    my $server   = $self->req_server or return NOT_FOUND;
    my $ntpcheck = $config_ntp->{ntpcheck};
    my $ua       = LWP::UserAgent->new;
    my $url      = URI->new("$ntpcheck");
    $url->path("/check/" . $server->ip);
    $url->query("queue=1");
    warn "URL: $url";
    $ua->post($url);
    return $self->redirect('/manage/servers') if $self->req_param('noscript');

    my $return = {queued => 1,};

    return OK, encode_json($return);

}

sub handle_update_netspeed {
    my $self = shift;
    my $server = $self->req_server or return NOT_FOUND;
    if (my $netspeed = $self->req_param('netspeed')) {
        $server->netspeed($netspeed) if $netspeed =~ m/^\d+$/;
        if ($server->netspeed < 768) {
            $server->leave_zone('@');
        }
        else {
            $server->join_zone('@');
        }
        $server->save;
    }

    return $self->redirect('/manage/servers') if $self->req_param('noscript');

    my $return = {
        netspeed => $self->netspeed_human($server->netspeed),
        zones    => join " ",
        map { join "", '<a href="/zone/', $_->name, '">', $_->name, '</a>' } $server->zones_display,
    };

    #warn Data::Dumper->Dump([\$return],[qw(return)]);

    return OK, encode_json($return);

}

sub handle_update_profile {
    my $self = shift;

    my $public = ($self->request->uri =~ m/public/) ? 1 : 0;
    $self->user->public_profile($public);
    $self->user->update;

    $self->tpl_param('user' => $self->user);

    return $self->redirect('/manage') if $self->request->method eq 'GET';
    return OK, $self->evaluate_template('tpl/manage/profile_link.html', {style => 'bare.html'});
}

sub handle_delete {
    my $self = shift;
    my $server = $self->req_server or return NOT_FOUND;
    $self->tpl_param(server => $server);

    if ($self->request->method eq 'post') {
        if (my $date = $self->req_param('deletion_date')) {
            my @date = split /-/, $date;
            $date = $date[1] && DateTime->new(
                year      => $date[0],
                month     => $date[1],
                day       => $date[2],
                time_zone => 'UTC'
            );
            if ($date and $date > DateTime->now) {
                $server->deletion_on($date);
                $server->add_logs(
                    {   user_id => $self->user->id,
                        type    => 'delete',
                        message => "Deletion scheduled for "
                          . $date->ymd . " by "
                          . $self->user->who,
                    }
                );
                $server->save;
            }
        }
        if ($self->req_param('cancel_deletion')) {
            $server->deletion_on(undef);
            $server->add_logs(
                {   user_id => $self->user->id,
                    type    => 'delete',
                    message => "Deletion cancelled by " . $self->user->who,
                }
            );
            $server->save;
        }
    }

    if ($server->deletion_on) {
        return OK, $self->evaluate_template('tpl/manage/delete_set.html');
    }
    else {
        my @dates;
        my $dt = DateTime->now(time_zone => 'UTC');
        $dt->add(days => 4);
        for (1 .. 90) {
            push @dates, $dt->clone;
            $dt->add(days => 1);
        }
        $self->tpl_param('dates' => \@dates);

        return OK, $self->evaluate_template('tpl/manage/delete_instructions.html');
    }
}

sub netspeed_human {
    my ($self, $netspeed) = @_;
    NP::Model::Server::_netspeed_human($netspeed);
}

1;
