package NTPPool::Control::Manage::Server;
use strict;
use NTPPool::Control::Manage;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);
use Combust::Config ();
use NP::Email       ();
use Email::Stuffer  ();
use Sys::Hostname qw(hostname);
use Socket qw(inet_ntoa);
use Socket6;
use JSON::XS qw(encode_json decode_json);
use Net::DNS;
use Math::BaseCalc qw();
use Math::Random::Secure qw(irand);
use NP::NTP;

my $config     = Combust::Config->new;
my $config_ntp = $config->site->{ntppool};

sub render {
    my $self = shift;

    return $self->login unless $self->user;

    unless ($self->current_account) {
        return $self->redirect("/manage/account");
    }

    return $self->handle_add if $self->request->uri =~ m!^/manage/server/add!;
    return $self->handle_update
      if $self->request->uri =~ m!^/manage/server/update!;
    return $self->handle_delete
      if $self->request->uri =~ m!^/manage/server/delete!;
    return $self->handle_move
      if $self->request->uri =~ m!^/manage/servers/move!;

    return $self->show_manage if $self->request->uri =~ m!^/manage/servers!;

    return NOT_FOUND;
}

sub show_manage {
    my $self = shift;
    $self->tpl_params->{page}->{is_servers} = 1;

    my $servers = $self->current_account->servers;
    $self->tpl_param('servers', $servers);

    my @server_ids = map { $_->id } @$servers;

    if ($self->user->is_staff) {
        my $logs = NP::Model->log->get_objects(
            query => [
                or => [
                    account_id => [$self->current_account->id],
                    (@server_ids ? (server_id => \@server_ids) : ()),
                ],
            ],
            sort_by => "created_on desc",
        );
        $self->tpl_param('logs', $logs);
    }

    return OK, $self->evaluate_template('tpl/manage.html');
}

sub handle_add {
    my $self = shift;

    return 403 unless $self->check_auth_token;

    my $account = $self->current_account;
    my $host    = $self->req_param('host');
    $host =~ s/^\s+|\s+$//g;

    $self->tpl_param('host', $host);

    my @servers;

    my @ips = $self->_get_server_ips($host);

    for my $ip (@ips) {
        my $server = $self->get_server_info($ip);
        next unless $server;
        unless (Net::IP->new($host)) {
            $server->{hostname} = $host;
            $server->{account}  = $account;
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
                $server->{id} = $s->id;
                push @added, $server;
            }
        }
        $self->tpl_param(servers => \@added);
        my $msg = $self->evaluate_template('tpl/manage/add_email.txt');
        my $email =
          Email::Stuffer->from(NP::Email::address("sender"))
          ->to(NP::Email::address("notifications"))->reply_to($self->user->email)->text_body($msg);

        my $subject =
          "New addition to the NTP Pool: " . join(", ", map { $_->{ip} } @added);
        if (grep { $_->{hostname} } @added) {
            $subject .= " (" . join(", ", map { $_->{hostname} } @added) . ")";
        }
        $email->subject($subject);

        my $return = NP::Email::sendmail($email->email);
        warn Data::Dumper->Dump([\$msg, \$email, \$return], [qw(msg email return)]);

        return $self->redirect($self->manage_url('/manage/servers') . '#s-' . ($s && $s->ip));
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

    my $res = Net::DNS::Resolver->new(domain => "", defnames => 0);
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

    my $db  = NP::Model->db;
    my $txn = $db->begin_scoped_work;

    if ($s = NP::Model->server->fetch(ip => $server->{ip})) {
        $s->setup_server;
    }
    else {
        # the model calls setup_server
        $s = NP::Model->server->create(ip => $server->{ip});
    }

    $s->hostname($server->{hostname} || '');
    $s->ip_version($server->{ip_version});
    $s->admin($self->user);
    $s->account($server->{account});
    $s->account($self->current_account);
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

    NP::Model::Log->log_changes($self->user, "server-create",
        "Server added." . ($comment =~ m/\S/ ? "\n\n$comment" : ""), $s,);

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
          $s->account_id eq $self->current_account->id
          ? ""
          : "Please email us for help.";
        unless ($s->deleted or $s->deletion_on) {
            $server{listed} = 1 unless $other;
            $server{error}  = "$server{ip} is already registered in the pool. $other\n";
            return \%server;
        }
    }

    my @ntp = NP::NTP::info( $ip->short );

    my $ntp_ok = 0;

    for my $check (@ntp) {
        next if $check->{error};

        my $ntp = $check->{NTP} or next;

        unless (defined $ntp->{Stratum}) {
            $ntp->{error} = "Didn't get an NTP response from $server{ip}\n";
        }

        unless ($ntp->{Stratum} > 0 and $ntp->{Stratum} < 6) {
            $ntp->{error} =
              "Invalid stratum response from ${ip} (Your server is in stratum $ntp->{Stratum}).  Is your server configured properly? Is public access allowed?  If you just restarted your ntpd, then it might still be stabilizing the timesources - try again in 10-20 minutes.\n";
        }

        unless ($ntp->{error}) {
            $ntp_ok = 1;
            $server{ntp} = $ntp;
        }
    }

    unless ($ntp_ok) {
        ($server{error}) = map { $_->{error} } grep { $_->{error} } @ntp;
    }


    if ($server{error}) {
        warn "Error: $server{error}";
        return \%server;
    }

    my $geoip = $ENV{geoip_service} || 'geoip';
    my $res   = $self->ua->get("http://${geoip}/api/country?ip=$server{ip}");
    $server{geoip_country} = $res->decoded_content if $res->is_success;

    my $country =
      $self->req_param('explicit_zone_' . $server{ip}) || $server{geoip_country};

    $country = 'UK' if $country eq 'GB';
    warn "Country: $country\n";
    $server{country_zone} = $country && NP::Model->zone->fetch(name => $country);

    return \%server;
}

sub req_server {
    my $self      = shift;
    my $server_id = $self->req_param('server') or return;
    my $server    = NP::Model->server->fetch(($server_id =~ m/[.:]/ ? 'ip' : 'id') => $server_id);
    return unless $server and $server->account->can_edit($self->user);
    return $server;
}

sub handle_update {
    my $self = shift;

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
    my $url      = URI->new("$ntpcheck");
    $url->path("/check/" . $server->ip);
    $url->query("queue=1");
    warn "URL: $url";
    $self->ua->post($url);
    return $self->redirect('/manage/servers') if $self->req_param('noscript');

    my $return = {queued => 1,};

    return OK, encode_json($return);

}

sub handle_update_netspeed {
    my $self   = shift;
    my $server = $self->req_server or return NOT_FOUND;
    if (defined(my $netspeed = $self->req_param('netspeed'))) {
        return 403 unless $self->check_auth_token;

        my $db  = NP::Model->db;
        my $txn = $db->begin_scoped_work;

        return unless $netspeed =~ m/^\d+$/;
        $netspeed = 10000 if $netspeed > 1000000;
        $netspeed = 1000  if $netspeed < 0;

        my $old = $server->get_data_hash;
        $server->netspeed($netspeed);
        if ($server->netspeed < 768) {
            $server->leave_zone('@');
        }
        else {
            $server->join_zone('@');
        }

        NP::Model::Log->log_changes($self->user, "server-netspeed",
            "set netspeed to " . $server->netspeed,
            $server, $old);

        $server->save;

        $db->commit;
    }

    return $self->redirect('/manage/servers') if $self->req_param('noscript');

    my $return = {
        netspeed => $self->netspeed_human($server->netspeed),
        zones    => $self->evaluate_template(
            'tpl/manage/server_zones.html',
            {page_style => "bare.html", server => $server}
        )
    };

    #warn Data::Dumper->Dump([\$return],[qw(return)]);

    return OK, encode_json($return);

}

sub handle_delete {
    my $self   = shift;
    my $server = $self->req_server or return NOT_FOUND;
    $self->tpl_param(server => $server);

    my $db  = NP::Model->db;
    my $txn = $db->begin_scoped_work;

    if ($self->request->method eq 'post') {
        if (my $date = $self->req_param('deletion_date')) {
            return 403 unless $self->check_auth_token;

            my $old = $server->get_data_hash();

            my @date = split /-/, $date;
            $date = $date[1] && DateTime->new(
                year      => $date[0],
                month     => $date[1],
                day       => $date[2],
                time_zone => 'UTC'
            );
            if ($date and $date > DateTime->now) {
                $server->deletion_on($date);
                NP::Model::Log->log_changes($self->user, "server-delete",
                    "Deletion scheduled for " . $date->ymd,
                    $server, $old);
                $server->save;
            }
        }
        if ($self->req_param('cancel_deletion')) {
            return 403 unless $self->check_auth_token;

            my $old = $server->get_data_hash;

            $server->deletion_on(undef);
            NP::Model::Log->log_changes($self->user, "server-delete",
                "Deletion cancelled by " . $self->user->who,
                $server, $old);
            $server->save;
        }
    }

    $db->commit;

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

sub handle_move {
    my $self = shift;

    my $servers = $self->current_account->servers;
    $self->tpl_param('servers', $servers);

    my $errors = {};
    $self->tpl_param('errors', $errors);

    my $accounts;
    if ($self->user->is_staff) {

        # get all accounts available to any user in this account
        my ($account_users) = NP::Model->user->get_users(
            require_objects => ['accounts'],
            query           => ['accounts.id' => $self->current_account->id]
        );
        ($accounts) = NP::Model->account->get_accounts(
            require_objects => ['users'],
            query           => ['users.id' => [map { $_->id } @$account_users]],
        );
    }
    else {
        ($accounts) = NP::Model->account->get_accounts(
            require_objects => ['users'],
            query           => ['users.id' => $self->user->id]
        );
    }
    $accounts = [grep { $_->id != $self->current_account->id } @$accounts];
    $self->tpl_param('move_accounts', $accounts);

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;

        my %selected = ();
        for my $select ($self->request->req_params->get_all('selected_servers')) {
            warn "selected: $select";
            $selected{$select} = 1;
        }
        $self->tpl_param('selected', \%selected);

        my $new_account_code = $self->req_param('new_account');
        my ($new_account) = grep { $new_account_code eq $_->id_token } @$accounts;
        unless ($new_account) {
            $errors->{new_account} =
              'Please select the account you are transferring the servers to';
            return OK, $self->evaluate_template('tpl/manage/move.html');
        }

        warn "current account: ", $self->current_account->id_token;
        warn "new     account: ", $new_account->id_token;

        my $db  = NP::Model->db;
        my $txn = $db->begin_scoped_work;

        my @servers_to_move;
        for my $server (@$servers) {
            warn "was server selected? ", $server->id;
            next unless $selected{$server->id};
            warn "moving ", $server->id;
            push @servers_to_move, $server;
        }

        if ($new_account_code && @servers_to_move) {

            warn "really moving ...";

            for my $server (@servers_to_move) {
                my $old = $server->get_data_hash();

                warn "changing account to token / id ", $new_account->token_id, $new_account->id;
                $server->account_id($new_account->id);

                NP::Model::Log->log_changes($self->user, "server-move", "Server account change",
                    $server, $old);
                $server->save;
            }
            $db->commit;
            $self->tpl_param('old_account',   $self->current_account);
            $self->tpl_param('new_account',   $new_account);
            $self->tpl_param('servers_moved', \@servers_to_move);
            return OK, $self->evaluate_template('tpl/manage/move_done.html');
        }
    }

    return OK, $self->evaluate_template('tpl/manage/move.html');

}

sub netspeed_human {
    my ($self, $netspeed) = @_;
    NP::Model::Server::_netspeed_human($netspeed);
}

1;
