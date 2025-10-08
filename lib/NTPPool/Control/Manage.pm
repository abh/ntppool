package NTPPool::Control::Manage;
use strict;
use parent qw(NTPPool::Control::Login NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND SERVER_ERROR);
use Socket            qw(inet_ntoa);
use Socket6;
use JSON::XS   qw(encode_json decode_json);
use Data::Dump qw(pp);
use Net::DNS;
use Math::BaseCalc       qw();
use Math::Random::Secure qw(irand);
use URI::URL             ();
use NP::UA;
use NP::IntAPI        qw(int_api);
use NP::CAPI::Account qw(get_account_status process_auth0_login);
use OpenTelemetry::Trace;
use OpenTelemetry -all;
use OpenTelemetry::Constants qw( SPAN_KIND_SERVER SPAN_STATUS_ERROR SPAN_STATUS_OK );
use experimental             qw( defer );
use Syntax::Keyword::Dynamically;
use Combust::Util ();

sub ua { return $NP::UA::ua }

sub _get_request_context {
    my $self            = shift;
    my $x_forwarded_for = $self->request->header_in('X-Forwarded-For');
    return $x_forwarded_for ? {x_forwarded_for => $x_forwarded_for} : undef;
}

my $base36 = Math::BaseCalc->new(digits => ['a' .. 'k', 'm' .. 'z', 2 .. 9]);

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    $self->cache_control('private, no-cache');

    $self->tpl_params->{page} ||= {};

    # For HTMX requests, return just fragments
    if ($self->is_htmx) {
        $self->tpl_param('page_style' => "none");
        $self->tpl_param('bare'       => 1);
    }

    if ($self->is_logged_in) {
        $self->request->env->{REMOTE_USER} =
          $self->user->username . '|' . $self->user->id_token;

        my $span =
          OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);

        if (my $account = $self->current_account) {
            $self->tpl_param('account' => $account);
            $span->set_attribute("account.id",       $account->id);
            $span->set_attribute("account.id_token", $account->id_token);

            $self->request->env->{REMOTE_USER} .= '|' . $account->id_token;
        }

        if (my $user = $self->user) {
            $span->set_attribute("user.is_staff", $user->is_staff);
            $span->set_attribute("user.email",    $user->email);
            $span->set_attribute("user.username", $user->username);
            $span->set_attribute("user.id",       $user->id);
            $span->set_attribute("user.id_token", $user->id_token);

            $self->plausible_props("user" => $user->id_token);
            if (my $a = $self->current_account) {
                $self->plausible_props("account" => $a->id_token);
            }
        }

        if ($self->user->deletion_on and $self->request->uri ne "/manage/logout") {
            return $self->redirect($self->manage_url('/manage/logout'));
        }

    }

    return OK;
}

sub current_account {
    my $self = shift;

    if (exists $self->{_current_account}) {
        return $self->{_current_account};
    }

    if (my $account_token = $self->req_param('a')) {
        my $account_id = NP::Model::Account->token_id($account_token);
        my $account = $account_id ? NP::Model->account->fetch(id => $account_id) : undef;
        if ($account) {
            return $self->{_current_account} = $account
              if $account->can_view($self->user);
        }
    }

    my ($accounts) = NP::Model->account->get_accounts(
        require_objects => ['users'],
        query           => ['users.id' => $self->user->id]
    );

    if ($accounts && @$accounts) {
        return $self->{_current_account} = $accounts->[0];
    }

    return $self->{_current_account} = undef;
}

sub current_url {
    my $self = shift;
    my $args = shift;

    $args = {$self->request->args, $args ? %$args : {}};

    my $here = URI->new($self->config->base_url($self->site) . $self->request->uri);
    $here->query_form($args);

    $here->as_string;
}

sub render {
    my $self = shift;

    unless ($self->request->uri =~ m{^/(manage(/.*)?)?$}) {
        return NOT_FOUND;
    }

    my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);

    # $span->set_name("request manage");
    $span->set_attribute("manage_class", ref $self);

    # this method is shared between the Manage related controllers

    if ($self->request->uri =~ m!^/manage/logout!) {
        return $self->logout;
    }

    $self->tpl_param("xs", $self->cookie("xs"));

    if ($self->request->uri =~ m!^/manage/login!) {
        $self->set_span_name("manage.login");
        if ($self->req_param('code')) {
            $self->handle_login();
        }
        if ($self->user) {
            my $r = $self->req_param('r') || '/manage';
            return $self->redirect($r);
        }

        # if something goes terribly wrong this would just pointlessly
        # and frustratingly loop. It's added so the Auth0 config can have
        # a "default login url" that redirects to the login server /authorize
        # url and we can only have so many .../login urls, right?
        return $self->redirect($self->login_url);
    }

    return $self->login unless ($self->user);

    if ($self->request->method eq 'get') {
        my $account       = $self->current_account;
        my $account_param = $self->req_param('a');
        if (    $account_param
            and $account
            and $account_param ne $account->id_token)
        {
            return $self->redirect($self->current_url({a => $account->id_token}));
        }
    }

    return $self->manage_dispatch;
}

sub handle_login {
    my $self = shift;

    my $span = NP::Tracing->tracer->create_span(
        name => "handle_login",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);
    defer { $span->end(); };

    my $code = $self->req_param('code');
    unless ($code) {
        $span->set_status(SPAN_STATUS_ERROR, "missing code parameter");
        return;
    }

    my $state = $self->req_param('state');
    unless ($state && $state eq $self->cookie('login_state')) {
        $span->set_status(SPAN_STATUS_ERROR, "invalid state parameter");
        return;
    }

    # Call ConnectRPC API to process Auth0 login
    my $result = NP::CAPI::Account::process_auth0_login(
        authorization_code => $code,
        state              => $state,
        redirect_uri       => $self->callback_url,
        client_site        => "" . $self->site,   # Force to string: 'manage', 'www', etc.
        context            => $self->_get_request_context(),
    );

    if ($result->{error}) {
        $span->set_status(SPAN_STATUS_ERROR, "auth0 login failed: " . $result->{error});

        # ConnectRPC errors are automatically structured by CAPI layer:
        # $result->{error} - error message (user-friendly)
        # $result->{code}  - ConnectRPC error code (e.g., 'unauthenticated', 'internal')

        # Set error details for user display
        $self->cache_control('private, max-age=0, no-cache');
        $self->tpl_param('error',    $result->{error});
        $self->tpl_param('trace_id', $result->{trace_id} || $span->context->hex_trace_id);

        return SERVER_ERROR;
    }

    my $data = $result->{data};

    # Set session cookie
    $self->_set_session_cookie($data->{session_token});

    # Clear legacy cookie information
    $self->cookie($self->user_cookie_name, '');

    # XSS token for manage page
    $self->cookie("xs", join("", map { $base36->to_base(irand) } (undef) x 6));

    # Clear login state
    $self->cookie('login_state', '');

    # Load user object for request
    # Since we now have a session cookie, the user() method will work
    my $user = NP::Model->user->fetch(id => $data->{user_id});
    $self->user($user);

    # Show message if deletion was cancelled
    if ($data->{deletion_cancelled}) {
        return $self->login("Your account deletion has been cancelled.");
    }

    return;    # Will redirect via parent handler
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

sub callback_url {
    my $self = shift;

    my $uri = URI->new($self->config->base_url($self->site));
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

    my $state = $self->cookie('login_state');
    unless ($state) {
        $state = (join "", map { $base36->to_base(irand) } (undef) x 6);
        $self->cookie('login_state', $state);
    }

    my ($auth0_domain, $auth0_client, $auth0_secret) = $self->_auth0_config();

# https://auth0.com/docs/get-started/authentication-and-authorization-flow/add-login-auth-code-flow
# https://community.auth0.com/t/invalid-access-token-payload-jwt-encrypted-with-a256gcm/77893

    my $login_url = URI->new('https://' . $auth0_domain . "/authorize");
    $login_url->query_form(
        client_id     => $auth0_client,
        redirect_uri  => $self->callback_url,
        response_type => 'code',
        audience      => 'api-dev',
        scope         => 'openid name email profile preferred_username',
        state         => $state,
    );

    use Data::Dump qw(pp);

    # warn "login_url: ", $login_url->as_string, pp($login_url);

    return $login_url->as_string;
}

sub manage_dispatch {
    my $self = shift;

    # .../servers and .../account have their own handlers

    if ($self->user->is_staff) {
        if ($self->request->uri =~ m{/manage/admin/?$}) {
            return $self->show_staff;
        }
        elsif ($self->request->uri =~ m{/manage/admin/search/?$}) {
            return $self->staff_search;
        }
        elsif ($self->request->uri =~ m{/manage/admin/zones/(edit|save)/?$}) {
            return $self->staff_zone_edit;
        }
        elsif ($self->request->uri =~ m{/manage/admin/hostname/(edit|save)/?$}) {
            return $self->staff_hostname_edit;
        }
    }

    if ($self->request->uri eq "/" or $self->request->uri =~ m{^/manage/?$}) {
        my $account  = $self->current_account;
        my $redirect = URI->new('/manage/servers');
        $redirect->query_param(a => $account->id_token) if $account;
        return $self->redirect($redirect);
    }

    return 404;
}

sub show_staff {
    my $self = shift;
    $self->set_span_name("manage.admin");
    $self->tpl_params->{page}->{is_admin} = 1;
    return OK, $self->evaluate_template('tpl/staff.html');
}

sub staff_search {
    my $self = shift;
    $self->set_span_name("manage.admin.search");

    # Check staff access
    unless ($self->user && $self->user->is_staff) {
        return 403, "Access denied";
    }

    my $q               = $self->req_param('q')               || '';
    my $include_deleted = $self->req_param('include_deleted') || '';

    # Add telemetry attributes for search parameters
    my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
    $span->set_attribute("search.query",           $q);
    $span->set_attribute("search.include_deleted", $include_deleted ? 1 : 0);
    $span->set_attribute("search.query_empty",     $q               ? 0 : 1);

    # If no query, return empty result
    unless ($q) {
        $self->tpl_param('results' => {});
        return OK, $self->evaluate_template('tpl/admin/search_results.html');
    }

    # Call the new internal API search endpoint
    my $data = int_api(
        'get', 'search',
        {   q               => $q,
            user            => $self->plain_cookie($self->user_cookie_name),
            include_deleted => $include_deleted ? 'true' : 'false',
        },
        $self->_get_request_context()
    );

    my $results = {};
    if ($data->{code} == 200) {
        $results = $data->{data} || {};
    }
    elsif ($data->{code} == 404) {

        # No results found - return empty results
        $results = {accounts => []};
    }
    else {
        # API error - log and return empty results for degraded experience
        $results = {
            accounts => [],
            error    => 'Search temporarily unavailable',
            trace_id => $data->{trace_id}
        };
    }

    # Add highlighting to IP addresses and hostnames (similar to old jQuery code)
    if ($results && $results->{accounts} && $q) {
        for my $account (@{$results->{accounts}}) {

            # Highlight server IPs and hostnames
            for my $server (@{$account->{servers} || []}) {
                for my $field (qw(ip hostname)) {
                    if ($server->{$field} && $server->{$field} =~ /\Q$q\E/i) {
                        my $escaped = Combust::Util::escape_html($server->{$field});
                        $server->{"${field}_highlighted"} = "<b>$escaped</b>";
                    }
                }
            }

            # Highlight monitor IPs and hostnames
            for my $monitor (@{$account->{monitors} || []}) {
                for my $field (qw(ip hostname)) {
                    if ($monitor->{$field} && $monitor->{$field} =~ /\Q$q\E/i) {
                        my $escaped = Combust::Util::escape_html($monitor->{$field});
                        $monitor->{"${field}_highlighted"} = "<b>$escaped</b>";
                    }
                }
            }
        }
    }

    # Add CSS classes for relevance filtering
    if ($results && $results->{accounts} && $results->{filter_context}) {
        my $filter_context = $results->{filter_context};

        for my $account (@{$results->{accounts}}) {

            # Compute CSS classes for servers
            for my $server (@{$account->{servers} || []}) {
                my @css_classes = ();

                # Add deletion styling
                push @css_classes, 'text-muted' if $server->{deletion_on};

                # Add relevance filtering for zone searches
                if ($filter_context->{show_zone_servers_only}) {
                    my $zone_name  = $filter_context->{zone_name};
                    my $is_in_zone = grep { $_ eq $zone_name } @{$server->{zones} || []};
                    push @css_classes, 'search-result-secondary' unless $is_in_zone;
                }

                # Set computed CSS classes
                $server->{css_classes} = join(' ', @css_classes) if @css_classes;
            }
        }
    }

    # Add telemetry attributes for search results
    if ($results && $results->{accounts}) {
        my $account_count = scalar @{$results->{accounts}};
        my $server_count  = 0;
        my $monitor_count = 0;

        for my $account (@{$results->{accounts}}) {
            $server_count  += scalar @{$account->{servers}  || []};
            $monitor_count += scalar @{$account->{monitors} || []};
        }

        $span->set_attribute("search.results.accounts",    $account_count);
        $span->set_attribute("search.results.servers",     $server_count);
        $span->set_attribute("search.results.monitors",    $monitor_count);
        $span->set_attribute("search.results.has_results", $account_count > 0 ? 1 : 0);
    }
    else {
        $span->set_attribute("search.results.accounts",    0);
        $span->set_attribute("search.results.servers",     0);
        $span->set_attribute("search.results.monitors",    0);
        $span->set_attribute("search.results.has_results", 0);
    }
    $span->set_attribute("search.api_code", $data->{code} || 0);

    # Pass results to template
    $self->tpl_param('results' => $results);
    $self->tpl_param('query'   => $q);

    # Return HTML fragment for HTMX
    if ($self->is_htmx) {
        return OK, $self->evaluate_template('tpl/admin/search_results.html');
    }

    # For non-HTMX requests, return the full page
    return OK, $self->evaluate_template('tpl/staff.html');
}

sub staff_zone_edit {
    my $self = shift;
    $self->set_span_name("manage.admin.zone_edit");

    # Disable caching for admin endpoints
    $self->cache_control('private, no-cache');

    # Check staff access
    unless ($self->user && $self->user->is_staff) {
        return 403, "Access denied";
    }

    my $server_ip = $self->req_param('server') || '';
    return 400, "Server IP required" unless $server_ip;

    my $server = NP::Model->server->find_server($server_ip);
    return 404, "Server not found" unless $server;

    # Determine if this is edit or save
    my $is_save = $self->request->uri =~ m{/save/?$};

    if ($is_save && $self->request->method eq 'post') {

        # Save zones
        my $zones_value = $self->req_param('zones') || '';

        # Call the existing API method
        require NTPPool::API::Staff;
        my $api = NTPPool::API::Staff->new(
            args => {
                user   => $self->user,
                params => {
                    id         => 'zone_list',
                    server     => $server_ip,
                    value      => $zones_value,
                    auth_token => $self->auth_token,
                }
            }
        );

        my $result = $api->edit_server();

        # Return view state after save
        $self->tpl_param('server'      => $server);
        $self->tpl_param('zones'       => join(' ', @$result));
        $self->tpl_param('manage_site' => 1);
        return OK, $self->evaluate_template('tpl/admin/zone_view.html');
    }
    else {
        # Check if this is a cancel request
        if ($self->req_param('cancel')) {

            # Return to view state
            my @zone_names = map { $_->name } $server->zones_display;
            $self->tpl_param('server'      => $server);
            $self->tpl_param('zones'       => join(' ', @zone_names));
            $self->tpl_param('manage_site' => 1);
            return OK, $self->evaluate_template('tpl/admin/zone_view.html');
        }

        # Show edit form
        my @zone_names = map { $_->name } $server->zones_display;
        $self->tpl_param('server' => $server);
        $self->tpl_param('zones'  => join(' ', @zone_names));
        return OK, $self->evaluate_template('tpl/admin/zone_edit.html');
    }
}

sub staff_hostname_edit {
    my $self = shift;
    $self->set_span_name("manage.admin.hostname_edit");

    # Disable caching for admin endpoints
    $self->cache_control('private, no-cache');

    # Check staff access
    unless ($self->user && $self->user->is_staff) {
        return 403, "Access denied";
    }

    my $server_ip = $self->req_param('server') || '';
    return 400, "Server IP required" unless $server_ip;

    my $server = NP::Model->server->find_server($server_ip);
    return 404, "Server not found" unless $server;

    # Determine if this is edit or save
    my $is_save = $self->request->uri =~ m{/save/?$};

    if ($is_save && $self->request->method eq 'post') {

        # Save hostname
        my $hostname_value = $self->req_param('hostname') || '';

        # Call the existing API method
        require NTPPool::API::Staff;
        my $api = NTPPool::API::Staff->new(
            args => {
                user   => $self->user,
                params => {
                    id         => 'hostname',
                    server     => $server_ip,
                    value      => $hostname_value,
                    auth_token => $self->auth_token,
                }
            }
        );

        my $result = $api->edit_server();

        # Debug logging

        # Update the server object with the returned hostname
        if ($result && ref($result) eq 'HASH' && exists $result->{hostname}) {
            $server->hostname($result->{hostname});
        }

        # Return view state after save
        $self->tpl_param('server' => $server);
        $self->tpl_param('error'  => $result->{error}) if $result->{error};
        return OK, $self->evaluate_template('tpl/admin/hostname_view.html');
    }
    else {
        # Check if this is a cancel request
        if ($self->req_param('cancel')) {

            # Return to view state
            $self->tpl_param('server' => $server);
            return OK, $self->evaluate_template('tpl/admin/hostname_view.html');
        }

        # Show edit form
        $self->tpl_param('server' => $server);
        return OK, $self->evaluate_template('tpl/admin/hostname_edit.html');
    }
}

sub account_monitor_count {
    my $self = shift;
    return $self->{_account_monitor_count}
      if defined $self->{_account_monitor_count};

    return $self->{_account_monitor_count} = 0
      unless $self->current_account;    # if we are being invited to a new account

    my $monitor_count =
      NP::Model->monitor->get_objects_count(
          query => [account_id => $self->current_account->id]);

    return $self->{_account_monitor_count} = $monitor_count;
}

sub monitor_eligibility {
    my $self = shift;
    return $self->{_monitor_eligibility}
      if exists $self->{_monitor_eligibility};

    # Default safe values if account not available
    unless ($self->current_account) {
        return $self->{_monitor_eligibility} = {
            enabled       => 0,
            can_register  => 0,
            monitor_count => 0,
        };
    }

    # Call new ConnectRPC AccountService.GetAccountStatus
    my $result = get_account_status(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->id_token,
        context => $self->_get_request_context(),
    );

    # Handle successful response
    if ($result->{data}) {
        return $self->{_monitor_eligibility} = $result->{data};
    }

    # Handle errors - return safe defaults for degraded experience
    if ($result->{error}) {
        warn
          "ConnectRPC GetAccountStatus error: $result->{error} (code: $result->{connect_code})";

        # Log detailed error for debugging
        if ($result->{trace_id}) {
            warn "  Trace ID: $result->{trace_id}";
        }
    }

    # Return safe defaults
    return $self->{_monitor_eligibility} = {
        enabled       => 0,
        can_register  => 0,
        monitor_count => 0,
        error         => $result->{connect_code} || 'api_unavailable',
    };
}

sub account_monitor_config {
    my ($self, $account) = @_;

    # Use passed account or fall back to current_account
    $account ||= $self->current_account;

    # Create a cache key that includes the account ID
    my $cache_key = '_account_monitor_config_' . ($account ? $account->id : 'none');

    if (exists $self->{$cache_key}) {
        return $self->{$cache_key};
    }

    # Default values if account not available
    unless ($account) {
        return $self->{$cache_key} = {
            monitor_enabled     => 0,
            monitor_limit       => 3,
            monitors_per_server => 1,
        };
    }

    # Parse account flags from database-loaded account object
    my $config = {};

    if ($account->flags) {

        # Check if flags is already a hash reference or a JSON string
        if (ref($account->flags) eq 'HASH') {
            $config = $account->flags;
        }
        else {
            eval { $config = decode_json($account->flags); };
            if ($@) {
                $config = {};
            }
            else {
            }
        }
    }
    else {
    }

    # Set defaults and user-friendly values
    my $monitor_config = {
        monitor_enabled     => $config->{monitor_enabled} ? 1 : 0,
        monitor_limit       => $config->{monitor_limit}             || 3,
        monitors_per_server => $config->{monitors_per_server_limit} || 1,
    };

    # Handle special case where monitor_limit is 0 (use default)
    $monitor_config->{monitor_limit} = 3 if $monitor_config->{monitor_limit} == 0;

    return $self->{$cache_key} = $monitor_config;
}

1;
