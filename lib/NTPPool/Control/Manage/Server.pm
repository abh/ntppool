package NTPPool::Control::Manage::Server;
use v5.30;
use strict;
use warnings;
use NTPPool::Control::Manage;
use parent            qw(NTPPool::Control::Manage);
use Combust::Constant qw(OK NOT_FOUND);
use Combust::Config   ();
use Sys::Hostname     qw(hostname);
use Socket            qw(inet_ntoa);
use Socket6;
use JSON::XS qw(encode_json decode_json);
use Net::DNS;
use Math::BaseCalc             qw();
use Math::Random::Secure       qw(irand);
use NP::CAPI::Account          qw(get_related_accounts);
use NP::CAPI::Server           qw(get_account_servers get_server);
use NP::CAPI::ServerManagement qw(
    add_server_precheck
    add_server
    ADD_SERVER_OUTCOME_ADDED
    ADD_SERVER_OUTCOME_NEEDS_ZONE
    ADD_SERVER_OUTCOME_CHECK_EXPIRED
    complete_server_verification
    get_server_verification
    move_server
    update_server
);
use NP::CAPI::Zone   qw(list_zones);
use NP::Data::Server ();
use NP::Util         ();
use OpenTelemetry -all;
use OpenTelemetry::Constants qw( SPAN_KIND_SERVER SPAN_STATUS_ERROR SPAN_STATUS_OK );
use experimental             qw( defer );
use Syntax::Keyword::Dynamically;

my $config     = Combust::Config->new;
my $config_ntp = $config->site->{ntppool};

sub render {
    my $self = shift;
    $self->set_span_name("manage.servers");

    my $span = NP::Tracing->tracer->create_span(
        name => "manage servers",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);

    unless ($self->user) {
        $span->end();
        return $self->login;
    }

    unless ($self->current_account) {
        return $self->redirect("/manage/account");
    }

    my $fn = "";

    for ($self->request->uri) {
        if    (m!^/manage/server/add!)    { $fn = "handle_add" }
        elsif (m!^/manage/server/update!) { $fn = "handle_update" }
        elsif (m!^/manage/server/verify!) { $fn = "handle_verify" }
        elsif (m!^/manage/server/delete!) { $fn = "handle_delete" }
        elsif (m!^/manage/servers/move!)  { $fn = "handle_move" }
        elsif (m!^/manage/servers!)       { $fn = "show_manage" }
    }

    #warn "fn: $fn from ", $self->request->uri;

    if ($fn and $self->can($fn)) {
        my @r = $self->$fn;
        $span->set_name("manage.servers.$fn");
        $span->end();
        return @r;
    }

    $span->end();

    return NOT_FOUND;
}

sub show_manage {
    my $self = shift;
    $self->tpl_params->{page}->{is_servers} = 1;

    my $span = NP::Tracing->tracer->create_span(name => "show_manage",);
    dynamically otel_current_context = otel_context_with_span($span);

    my $account = $self->current_account;
    unless ($account) {
        return OK, $self->evaluate_template('tpl/manage.html');
    }

    # Fetch servers via ConnectRPC API
    my $result = get_account_servers(
        $self->api_auth_params,
        account  => $account->{id_token},
        id_token => $account->{id_token},
    );

    # CAPI layer already logged error, just handle degraded state
    my $servers;
    if ($result->{error}) {
        $self->tpl_param('error', 'Failed to load servers');
        $servers = [];
    }
    else {
        $servers =
          [map { NP::Data::Server->new(%$_) } @{$result->{data}{servers} || []}];
    }
    $self->tpl_param('servers', $servers);

    my @server_ids = map { $_->{id} } @$servers;

    if ($self->user_is_staff) {

        # Use AuditService API (eliminates N+1 query problem: ~150 queries → ~5 queries)
        my $logs = $self->account_logs(
            account => $account,
            limit   => 50,
        );
        $self->tpl_param('logs', $logs);
    }

    return OK, $self->evaluate_template('tpl/manage.html');
}

sub handle_add {
    my $self = shift;

    return 403 unless $self->check_auth_token;

    my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
    $self->set_span_name("manage.servers.add");

    my $account = $self->current_account;

    my $host = $self->req_param('host');
    $host =~ s/^\s+|\s+$//g;

    $self->tpl_param('host', $host);
    $span->set_attribute("param.host", $host);

    unless ($account->{permissions}{can_add_servers}) {
        $span->set_attribute("request.error", "verify_existing");
        $self->tpl_param('error',
            'Please verify your existing servers before adding more.');
        return OK, $self->evaluate_template('tpl/manage/add_form.html');
    }

    return $self->_handle_add_confirm($host) if $self->req_param('yes');

    # Pass raw user input (hostname or IP) directly to API
    # DNS resolution happens in Go API (not Perl)
    my $precheck_result = add_server_precheck(
        $self->api_auth_params,
        account => $account->{id_token},
        inputs  => [$host],                # Go API handles DNS resolution
    );

    # Handle API errors
    if ($precheck_result->{error}) {
        $self->tpl_param('error', $precheck_result->{error});
        return OK, $self->evaluate_template('tpl/manage/add_form.html');
    }

    my $data    = $precheck_result->{data};
    my @servers = _servers_from_precheck($data->{results});

    if (!@servers) {
        return OK, $self->evaluate_template('tpl/manage/add_form.html');
    }

    return $self->_render_add_results($data->{precheck_token},
        \@servers, servers_skipped => $data->{servers_skipped});
}

# Show checked servers for confirmation. The token ties the confirmation
# step to these results.
sub _render_add_results {
    my ($self, $precheck_token, $servers, %extra) = @_;

    $self->tpl_param(precheck_token => $precheck_token);
    $self->tpl_param(servers        => $servers);
    $self->tpl_param(allow_submit   => scalar grep { !$_->{error} } @$servers);
    $self->tpl_param($_, $extra{$_}) for keys %extra;
    $self->_set_all_zones;

    return OK, $self->evaluate_template('tpl/manage/add.html');
}

# The confirmation click: one AddServer call using the precheck token.
sub _handle_add_confirm {
    my ($self, $host) = @_;

    # Each server that passed has an explicit_zone_<ip> field; the first
    # value is the fallback zone (the API ignores it for servers with zones).
    # Keys come in form order, which is the precheck's order.
    my $params = $self->request->req_params;
    my (@servers_to_add, %zone_choice, %seen);
    for my $key ($params->keys) {
        next unless $key =~ m/^explicit_zone_(.+)$/;
        next if $seen{$key}++;
        my $ip = $1;
        my ($zone) = grep { defined and length } $params->get_all($key);

        my %server_to_add = (ip => $ip);
        if (defined $zone) {
            $server_to_add{fallback_zone} = $zone;
            $zone_choice{$ip} = $zone;
        }
        push @servers_to_add, \%server_to_add;
    }

    my $comment = $self->req_param('comment');
    my $result  = add_server(
        $self->api_auth_params,
        account        => $self->current_account->{id_token},
        input          => $host,
        servers        => \@servers_to_add,
        precheck_token => $self->req_param('precheck_token'),
        batch_comment  => $comment,
    );

    if ($result->{error}) {
        warn "Failed to add servers: $result->{error} (trace: $result->{trace_id})";
        $self->tpl_param(error    => $result->{error});
        $self->tpl_param(trace_id => $result->{trace_id});
        return OK, $self->evaluate_template('tpl/manage/add.html');
    }

    my $outcome = $result->{data}{outcome} // '';

    if (   $outcome eq ADD_SERVER_OUTCOME_NEEDS_ZONE
        or $outcome eq ADD_SERVER_OUTCOME_CHECK_EXPIRED)
    {

        # Redraw from the API's results; needs_zone servers show their zone dropdown
        return $self->_render_add_results(
            $result->{data}{precheck_token},
            [_servers_from_precheck($result->{data}{precheck_results})],
            comment       => $comment,
            zone_choice   => \%zone_choice,
            check_expired => $outcome eq ADD_SERVER_OUTCOME_CHECK_EXPIRED,
        );
    }

    if ($outcome ne ADD_SERVER_OUTCOME_ADDED) {
        warn "AddServer returned unexpected outcome '$outcome' (trace: "
          . ($result->{trace_id} // '') . ")";
        $self->tpl_param(error    => "Unexpected response from the API");
        $self->tpl_param(trace_id => $result->{trace_id});
        return OK, $self->evaluate_template('tpl/manage/add.html');
    }

    # Match results to the submitted servers by IP; the API returns one
    # result per requested server.
    my %result_for = map { $_->{ip} => $_ } @{$result->{data}{results} || []};
    my (@servers, @added);

    for my $to_add (@servers_to_add) {
        my %server = (ip => $to_add->{ip});
        push @servers, \%server;

        my $api_result = $result_for{$server{ip}};
        if ($api_result and $api_result->{success}) {
            my $s = NP::Data::Server->new(%{$api_result->{server}});
            $server{id}         = $api_result->{server}{id};
            $server{added}      = 1;
            $server{manage_url} = $self->manage_url($s->manage_url);
            push @added, \%server;
            next;
        }

        my $error = $api_result && $api_result->{error};
        warn "AddServer did not add $server{ip}: "
          . ($error // 'no result')
          . " (trace: "
          . ($result->{trace_id} // '') . ")";
        $server{error} = $error || "The server wasn't added";
    }

    if (@added < @servers_to_add) {
        $self->tpl_param(servers => \@servers);
        return OK, $self->evaluate_template('tpl/manage/add.html');
    }

    return $self->redirect(
        @added ? $added[-1]{manage_url} : $self->manage_url('/manage/servers'));
}

# Transform API precheck results to the template format
sub _servers_from_precheck {
    my ($results) = @_;

    my @servers;
    for my $result (@{$results || []}) {
        my %server = (
            ip         => $result->{ip},
            ip_version => $result->{ip_version},
        );

        # Use hostname from API response (DNS-verified)
        if ($result->{hostname}) {
            $server{hostname} = $result->{hostname};
        }

        $server{not_checked} = 1 if $result->{not_checked};

        if ($result->{needs_zone}) {

            # Still valid; the API wants a zone for it. The error says why.
            $server{needs_zone}       = 1;
            $server{needs_zone_error} = $result->{error};
        }
        elsif ($result->{error}) {

            # Handle errors and already-exists cases
            $server{error} = $result->{error};
            if ($result->{already_exists}) {
                $server{listed} = $result->{already_exists_same_account};
            }
        }

        # API returns zones as hashrefs with name, description, url, dns;
        # the template uses them as-is
        $server{zones} = $result->{zones} if $result->{zones} && @{$result->{zones}};

        push @servers, \%server;
    }

    return @servers;
}

# Country list for the zone dropdowns
sub _set_all_zones {
    my $self = shift;

    my $zones_result = list_zones(
        $self->api_auth_params,
        account   => $self->current_account->{id_token},
        countries => JSON::XS::true,
    );

    my @all_zones;
    if ($zones_result->{error}) {
        warn "Failed to fetch zones via CAPI: " . $zones_result->{error};
        warn "Trace ID: " . $zones_result->{trace_id} if $zones_result->{trace_id};
    }
    else {
        # The API returns DNS-enabled country zones sorted by description
        @all_zones = @{$zones_result->{data}{zones} || []};
    }
    $self->tpl_param(all_zones => \@all_zones);
}

# _get_server_ips removed - DNS resolution now handled by Go API
# See add_server_precheck which accepts hostname/IP inputs
# _add_server removed - now batching all servers in single API call (handle_add)

sub req_server {
    my $self      = shift;
    my $server_id = $self->req_param('server') or return;

    # Call Go API with permission enforcement
    my $result = get_server(
        $self->api_auth_params,
        account => $self->current_account->{id_token},
        ip      => $server_id,                           # Auto-detects IP vs numeric ID
        require_edit_permission => JSON::XS::true,
    );

    # Handle API errors (permission denied or not found)
    if ($result->{error}) {
        warn "Failed to get server: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id};
        return;                                          # Returns undef, same as before
    }

    # Wrap in NP::Data::Server for compatibility with templates
    return NP::Data::Server->new(%{$result->{data}{server}});
}

sub handle_update {
    my $self = shift;

    return $self->handle_update_netspeed
      if $self->request->uri =~ m!^/manage/server/update/netspeed!;

    # deletion and non-js netspeed
    if ($self->request->uri =~ m!^/manage/server/update/server!) {
        return $self->handle_update_netspeed if $self->req_param('Update');
        if ($self->req_param('Delete')) {
            return $self->handle_delete;
        }
    }
    return NOT_FOUND;
}

sub handle_update_netspeed {
    my $self   = shift;
    my $server = $self->req_server or return NOT_FOUND;

    if (defined(my $netspeed = $self->req_param('netspeed'))) {
        return 403 unless $self->check_auth_token;

        return 400 unless $netspeed =~ m/^\d+$/;

        my $api_response = update_server(
            $self->api_auth_params,
            account  => $self->current_account->{id_token},
            ip       => $server->ip,
            netspeed => int($netspeed),
        );

        # For non-HTMX requests, redirect after processing
        unless ($self->is_htmx) {
            return $self->redirect('/manage/servers');
        }

        # Refresh server data for success cases
        if (!$api_response->{error} && $api_response->{data}{server}) {
            $server = NP::Data::Server->new(%{$api_response->{data}{server}});
        }
        $self->tpl_param('server', $server);

        if ($api_response->{error}) {
            my %fallback_message = (
                failed_precondition =>
                  "Please verify your server before increasing the netspeed",
                not_found => "Server not found or access denied",
            );
            $self->tpl_param('error',
                     $api_response->{error}
                  || $fallback_message{$api_response->{connect_code} || ''}
                  || 'Failed to update netspeed');
        }

        return OK, $self->evaluate_template('tpl/manage/server.html');
    }

    # For non-HTMX requests without netspeed parameter, redirect
    return $self->redirect('/manage/servers') unless $self->is_htmx;

    # Default return for HTMX requests without netspeed parameter
    $self->tpl_param('server', $server);
    return OK, $self->evaluate_template('tpl/manage/server.html');
}

sub handle_verify {
    my $self = shift;

    my ($token) = ($self->request->uri =~ m!^/manage/server/verify/(.+)!);
    unless ($token) {
        my $server = $self->req_server or return NOT_FOUND;
        $self->tpl_param(server => $server);
        $self->tpl_param(
            verification_url => $config->site->{ntppool}->{verification_url});

        my $validate_settings = $self->system_setting('validation');
        unless ($validate_settings and %$validate_settings) {
            warn "validate settings not configured in system_settings";
        }

        warn "validation_settings: ", Data::Dump::pp($validate_settings);

        my $validation_server = $validate_settings->{"server_v" . $server->ip_version};
        if (!$validation_server) {
            warn "no validation server for ", $server->ip_version;
        }

        $self->tpl_param('validation_server', $validation_server);

        return OK, $self->evaluate_template('tpl/manage/verify_instructions.html');
    }

    # Single CAPI call to get verification + server data
    my $result = get_server_verification($self->api_auth_params, token => $token,);

    # Handle errors
    if ($result->{error}) {
        if ($result->{connect_code} && $result->{connect_code} eq 'not_found') {
            return NOT_FOUND;
        }
        if ($result->{connect_code} && $result->{connect_code} eq 'unauthenticated') {

            # User not logged in - redirect to login
            return $self->redirect('/manage');
        }
        warn "Server verification lookup failed: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
        return 500;
    }

    my $data   = $result->{data};
    my $server = NP::Data::Server->new(%{$data->{server}});

    # If no account parameter, redirect with server's account to set proper context
    unless ($self->req_param('a')) {
        return $self->redirect(
            $self->manage_url(
                "/manage/server/verify/$token",
                {a => $data->{server}{account}{id_token}}
            )
        );
    }

    # If verified already, redirect to server on manage page
    if ($data->{already_verified}) {
        return $self->redirect($self->manage_url($server->manage_url));
    }

    $self->tpl_param(server => $server);
    $self->tpl_param(token  => $data->{token});

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;

        # Call Go API to complete verification (includes audit logging)
        my $complete_result = complete_server_verification(
            $self->api_auth_params,
            account => $self->current_account->{id_token},
            token   => $data->{token},
        );

        if ($complete_result->{error}) {
            warn "Failed to complete server verification: $complete_result->{error}";
            warn "Trace ID: $complete_result->{trace_id}" if $complete_result->{trace_id};
            $self->tpl_param(error_message => $complete_result->{error});
            return OK, $self->evaluate_template('tpl/manage/verify_confirm.html');
        }

        return $self->redirect($self->manage_url($server->manage_url));
    }

    return OK, $self->evaluate_template('tpl/manage/verify_confirm.html');
}

sub handle_delete {
    my $self   = shift;
    my $server = $self->req_server or return NOT_FOUND;
    $self->tpl_param(server => $server);

    if ($self->request->method eq 'post') {
        if (my $date = $self->req_param('deletion_date')) {
            return 403 unless $self->check_auth_token;

            # Validate date format (YYYY-MM-DD)
            my @date = split /-/, $date;
            if ($date[1]) {
                my $dt = eval {
                    DateTime->new(
                        year      => $date[0],
                        month     => $date[1],
                        day       => $date[2],
                        time_zone => 'UTC'
                    );
                };
                if ($dt && $dt > DateTime->now) {

                    # Call Go API to schedule deletion (includes audit logging)
                    my $result = NP::CAPI::ServerManagement::delete_server(
                        $self->api_auth_params,
                        account       => $self->current_account->{id_token},
                        ip            => $server->ip,
                        deletion_date => $date,
                    );

                    if ($result->{error}) {
                        $self->tpl_param('error',    $result->{error});
                        $self->tpl_param('trace_id', $result->{trace_id});
                    }
                    else {
                        # Redirect so the page re-fetches server state via CAPI
                        return $self->redirect($self->manage_url($server->manage_url));
                    }
                }
            }
        }
        if ($self->req_param('cancel_deletion')) {
            return 403 unless $self->check_auth_token;

            # Permission check is done by the Go API, but we show a better error here
            unless ($self->current_account->{permissions}{can_add_servers}) {
                $self->tpl_param('error',
                    'Please verify active servers in the account first.');
                return OK, $self->evaluate_template('tpl/manage/delete_set.html');
            }

            # Call Go API to cancel deletion (includes audit logging)
            my $result = NP::CAPI::ServerManagement::delete_server(
                $self->api_auth_params,
                account => $self->current_account->{id_token},
                ip      => $server->ip,
                cancel  => JSON::XS::true,
            );

            if ($result->{error}) {
                $self->tpl_param('error',    $result->{error});
                $self->tpl_param('trace_id', $result->{trace_id});
                return OK, $self->evaluate_template('tpl/manage/delete_set.html');
            }

            return $self->redirect($self->manage_url($server->manage_url));
        }
    }

    if ($server->deletion_on) {
        return OK, $self->evaluate_template('tpl/manage/delete_set.html');
    }
    else {
        my @dates;
        my $dt = DateTime->now(time_zone => 'UTC');
        $dt->add(days => 3);
        for (1 .. 10) {
            push @dates, $dt->clone;
            $dt->add(days => ($_ < 5 ? 1 : 3));
        }
        $self->tpl_param('dates' => \@dates);

        return OK, $self->evaluate_template('tpl/manage/delete_instructions.html');
    }
}

sub handle_move {
    my $self = shift;

    # Get servers for current account via CAPI
    my $servers_result = get_account_servers($self->api_auth_params,
        id_token => $self->current_account->{id_token},);
    my $servers = [];
    if (!$servers_result->{error} && $servers_result->{data}{servers}) {
        $servers =
          [map { NP::Data::Server->new(%$_) } @{$servers_result->{data}{servers}}];
    }
    $self->tpl_param('servers', $servers);

    my $errors = {};
    $self->tpl_param('errors', $errors);

    # Get related accounts via CAPI (handles staff/non-staff logic and filtering)
    my $result = NP::CAPI::Account::get_related_accounts(
        auth             => $self->plain_cookie($self->user_cookie_name),
        context          => $self->_get_request_context(),
        account          => $self->current_account->{id_token},
        account_id_token => $self->current_account->{id_token},
    );

    my $http_code = $self->_handle_capi_error($result);
    return $http_code if $http_code != 200;

    my $accounts = $result->{data}{accounts} || [];
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
        my ($new_account) =
          grep { $new_account_code eq $_->{id_token} } @$accounts;
        unless ($new_account) {
            $errors->{new_account} =
              'Please select the account you are transferring the servers to';
            return OK, $self->evaluate_template('tpl/manage/move.html');
        }

        warn "current account: ", $self->current_account->{id_token};
        warn "new     account: ", $new_account->{id_token};

        my @servers_to_move;
        for my $server (@$servers) {
            next unless $selected{$server->id};
            push @servers_to_move, $server->ip;    # Collect IPs not objects
        }

        if ($new_account_code && @servers_to_move) {

            # Move servers via CAPI
            my $result = move_server(
                auth                    => $self->plain_cookie($self->user_cookie_name),
                context                 => $self->_get_request_context(),
                account                 => $self->current_account->{id_token},
                server_ips              => \@servers_to_move,
                target_account_id_token => $new_account_code,
            );

            my $http_code = $self->_handle_capi_error($result);
            return $http_code if $http_code != 200;

            my $data = $result->{data};
            if ($data->{servers_failed_count} > 0) {

                # Some servers failed to move
                $self->tpl_param('partial_failure', 1);
                $self->tpl_param('failed_count',    $data->{servers_failed_count});
                $self->tpl_param('moved_count',     $data->{servers_moved_count});

                # Show which servers failed
                my @failed = grep { !$_->{success} } @{$data->{results}};
                $self->tpl_param('failed_servers', \@failed);
            }

            # Get new account details for success page
            my ($new_account_obj) =
              grep { $new_account_code eq $_->{id_token} } @$accounts;
            $self->tpl_param('old_account',   $self->current_account);
            $self->tpl_param('new_account',   $new_account_obj);
            $self->tpl_param('servers_moved', \@servers_to_move);       # IPs, not objects
            return OK, $self->evaluate_template('tpl/manage/move_done.html');
        }
    }

    return OK, $self->evaluate_template('tpl/manage/move.html');

}

sub netspeed_human {
    my ($self, $netspeed) = @_;
    NP::Util::netspeed_human($netspeed);
}

1;
