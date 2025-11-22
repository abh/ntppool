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
use Net::IP;
use Math::BaseCalc       qw();
use Math::Random::Secure qw(irand);
use URI::URL             ();
use NP::UA;
use NP::IntAPI qw(int_api);
use NP::CAPI::Account
  qw(get_account_status get_oauth_login_url process_auth0_login validate_session get_user_accounts get_account_invites);
use NP::CAPI::ServerManagement qw(update_server);
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

=head2 api_auth_params

Returns authentication and context parameters for CAPI calls.

    my $result = create_account(
        $self->api_auth_params,
        name => "My Account",
    );

Returns: (auth => '...', context => {...})

=cut

sub api_auth_params {
    my $self = shift;
    return (
        auth    => $self->plain_cookie($self->user_cookie_name) || '',
        context => $self->_get_request_context(),
    );
}

=head2 _handle_capi_error

Handle API errors by setting template parameters and returning HTTP status codes.

    my $http_code = $self->_handle_capi_error($result);
    return $http_code if $http_code != 200;

Returns HTTP status code (200 for success, or Combust constant for errors).

Note: Does not log errors (NP::CAPI already logs all errors with trace IDs).

=cut

sub _handle_capi_error {
    my ($self, $result) = @_;

    my $code = $result->{code};
    return $code if $code >= 200 && $code < 300;

    $self->cache_control('private, max-age=0, no-cache');
    $self->tpl_param('error', $result->{error}) unless $self->tpl_param('error');
    $self->tpl_param('code',  $code);

    if ($code == 404) {
        return NOT_FOUND;
    }
    elsif ($code >= 400 && $code < 500) {
        return $code;
    }
    elsif ($code >= 500) {
        return SERVER_ERROR;
    }

    return NOT_FOUND;    # fallback
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
          $self->user->{username} . '|' . $self->user->{id_token};

        my $span =
          OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);

        # Set account/user template params (DRY: also used by refresh_account_context)
        $self->_set_account_template_params();

        # Set telemetry attributes
        if (my $account = $self->current_account) {
            $span->set_attribute("account.id",       $account->{account_id});
            $span->set_attribute("account.id_token", $account->{id_token});

            $self->request->env->{REMOTE_USER} .= '|' . $account->{id_token};
        }

        if (my $user = $self->user) {
            $span->set_attribute("user.is_staff", $self->user_is_staff ? 1 : 0);
            $span->set_attribute("user.email",    $user->{email});
            $span->set_attribute("user.username", $user->{username});
            $span->set_attribute("user.id",       $user->{user_id});
            $span->set_attribute("user.id_token", $user->{id_token});

            $self->plausible_props("user" => $user->{id_token});
            if (my $a = $self->current_account) {
                $self->plausible_props("account" => $a->{id_token});
            }
        }

        # Redirect users with scheduled deletion to logout page
        if ($self->user->{deletion_on} and $self->request->uri ne "/manage/logout") {
            return $self->redirect($self->manage_url('/manage/logout'));
        }

    }

    return OK;
}

sub _set_account_template_params {
    my $self = shift;

    if (my $account = $self->current_account) {
        $self->tpl_param('account' => $account);
    }

    if ($self->user) {
        $self->tpl_param('user_accounts' => $self->user_accounts());
        $self->tpl_param('user_invites'  => $self->user_invites());
    }
}

sub refresh_account_context {
    my $self = shift;

    # Invalidate cached account data
    delete $self->{_current_account};
    delete $self->{_user_accounts};

    # Re-fetch and update template params
    $self->_set_account_template_params();
}

sub current_account {
    my $self = shift;

    # Return cached account if already loaded
    if (exists $self->{_current_account}) {
        return $self->{_current_account};
    }

    # Get session cookie
    my $session_token = $self->plain_cookie($self->user_cookie_name);
    return $self->{_current_account} = undef unless $session_token;

    # Call ValidateSession with optional account token
    # Go API will:
    # 1. Validate session
    # 2. Resolve id_token (if provided) or use default
    # 3. Check permissions
    # 4. Return account context + permissions
    my $id_token = $self->req_param('a');
    my %params   = (
        session_token => $session_token,
        context       => $self->_get_request_context(),
    );

    # Only include id_token if defined (avoid undef causing parameter shift)
    $params{id_token} = $id_token if defined $id_token;

    my $result = validate_session(%params);

    # Handle errors (invalid session, inaccessible account, etc.)
    if ($result->{error}) {
        warn "ValidateSession error: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
        return $self->{_current_account} = undef;
    }

    my $data = $result->{data};

    # Cache user privileges from session
    $self->{_user_privileges} = $data->{privileges} || {};

    # Session valid but user has no accounts
    return $self->{_current_account} = undef unless $data->{account};

    # Return account as plain hashref
    # Store permissions for template access
    my $account = $data->{account};
    $account->{permissions} = $data->{permissions} if $data->{permissions};

    return $self->{_current_account} = $account;
}

sub user_is_staff {
    my $self = shift;
    $self->current_account();    # Ensure session data is loaded
    return $self->{_user_privileges}{support_staff} || 0;
}

sub user_is_monitor_admin {
    my $self = shift;
    $self->current_account();    # Ensure session data is loaded
    return $self->{_user_privileges}{monitor_admin} || 0;
}

sub user_is_vendor_admin {
    my $self = shift;
    $self->current_account();    # Ensure session data is loaded
    return $self->{_user_privileges}{vendor_admin} || 0;
}

sub reload_server_via_capi {
    my ($self, $server_ip) = @_;

    my $result = NP::CAPI::Server::get_server(
        $self->api_auth_params,
        ip => $server_ip,
    );

    if ($result->{error}) {
        warn "Failed to reload server via CAPI: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
        return undef;
    }

    return $result->{data};
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
            and $account_param ne $account->{id_token})
        {
            return $self->redirect($self->current_url({a => $account->{id_token}}));
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

    # Determine environment-specific audience
    my $audience = $self->_get_audience();

    # Call ConnectRPC API to process Auth0 login
    my $result = NP::CAPI::Account::process_auth0_login(
        authorization_code => $code,
        state              => $state,
        redirect_uri       => $self->callback_url,
        client_site        => "" . $self->site,   # Force to string: 'manage', 'www', etc.
        context            => $self->_get_request_context(),
        audience           => $audience,          # Environment-specific: api-dev, api-test, api-prod
    );

    if ($result->{error}) {
        $span->set_status(SPAN_STATUS_ERROR, "auth0 login failed: " . $result->{error});
        $self->_handle_capi_error($result);
        return SERVER_ERROR;    # Always return server error for login failures (security)
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

    # Set user data from API response
    # On the next request, validate_session will load deletion_on and privileges
    $self->user($data);

    # Show message if deletion was cancelled
    if ($data->{deletion_cancelled}) {
        return $self->login("Your account deletion has been cancelled.");
    }

    return;    # Will redirect via parent handler
}

sub _get_audience {
    my $self = shift;

    # Determine environment from base URL
    my $base_url = $self->config->base_url($self->site);

    # Map environment to Auth0 audience
    if ($base_url =~ m{(askdev|dev|devel)\.}) {
        return 'api-dev';
    }
    elsif ($base_url =~ m{(beta|test)\.}) {
        return 'api-test';
    }
    elsif ($base_url =~ m{ntppool\.org}) {
        return 'api-prod';
    }
    else {
        # Default to dev for unknown environments
        warn "Unknown environment from base_url: $base_url, defaulting to api-dev";
        return 'api-dev';
    }
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

    # Call Go RPC to generate OAuth login URL
    # This centralizes Auth0 configuration in the Go API
    my $result = NP::CAPI::Account::get_oauth_login_url(
        redirect_uri => $self->callback_url,
        state        => $state,
        client_site  => "" . $self->site,  # Force to string: 'manage', 'www', etc.
        context      => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "Failed to get OAuth login URL: " . $result->{error};
        return undef;
    }

    return $result->{data}{login_url};
}

sub manage_dispatch {
    my $self = shift;

    # .../servers and .../account have their own handlers

    if ($self->user_is_staff) {
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
        $redirect->query_param(a => $account->{id_token}) if $account;
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
    unless ($self->user && $self->user_is_staff) {
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
    unless ($self->user && $self->user_is_staff) {
        return 403, "Access denied";
    }

    my $server_ip = $self->req_param('server') || '';
    return 400, "Server IP required" unless $server_ip;

    # Get server via CAPI
    my $server_result = NP::CAPI::Server::get_server(
        $self->api_auth_params,
        ip => $server_ip,
    );

    # Handle CAPI errors
    if ($server_result->{error}) {
        warn "GetServer error: " . $server_result->{error};
        warn "Trace ID: " . $server_result->{trace_id} if $server_result->{trace_id};
        return 404, "Server not found";
    }

    my $server = $server_result->{data};

    # Determine if this is edit or save
    my $is_save = $self->request->uri =~ m{/save/?$};

    if ($is_save && $self->request->method eq 'post') {

        # Save zones
        my $zones_value = $self->req_param('zones') || '';

        # Parse zones from user input
        my @zones = grep { length($_) > 0 }
          map {s/^\s+|\s+$//gr}
          split(/[\s,]+/, $zones_value);

        # Call CAPI to update zones
        my $result = NP::CAPI::ServerManagement::update_server(
            $self->api_auth_params,
            ip    => $server_ip,
            zones => \@zones,
        );

        # Handle CAPI errors
        if ($result->{error}) {
            $self->tpl_param('error', $result->{error});
            $self->tpl_param('zones', $zones_value);
            return OK, $self->evaluate_template('tpl/admin/zone_edit.html');
        }

        # Reload server to get updated zones using helper
        my $server_data = $self->reload_server_via_capi($server_ip);
        if (!$server_data) {
            $self->tpl_param('error', 'Failed to reload server data');
            return OK, $self->evaluate_template('tpl/admin/zone_edit.html');
        }

        my @zone_names =
          map  { $_->{name} }
          grep { $_->{name} ne '.' }
          sort { $a->{name} cmp $b->{name} } @{$server_data->{zones} || []};

        # Return view state after save
        $self->tpl_param('server'      => $server_data);
        $self->tpl_param('zones'       => join(' ', @zone_names));
        $self->tpl_param('manage_site' => 1);
        return OK, $self->evaluate_template('tpl/admin/zone_view.html');
    }
    else {
        # Check if this is a cancel request
        if ($self->req_param('cancel')) {

            # Return to view state
            # Filter out root zone and extract names
            my @zone_names =
              map  { $_->{name} }
              grep { $_->{name} ne '.' }
              sort { $a->{name} cmp $b->{name} } @{$server->{zones} || []};
            $self->tpl_param('server'      => $server);
            $self->tpl_param('zones'       => join(' ', @zone_names));
            $self->tpl_param('manage_site' => 1);
            return OK, $self->evaluate_template('tpl/admin/zone_view.html');
        }

        # Show edit form
        # Filter out root zone and extract names
        my @zone_names =
          map  { $_->{name} }
          grep { $_->{name} ne '.' }
          sort { $a->{name} cmp $b->{name} } @{$server->{zones} || []};
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
    unless ($self->user && $self->user_is_staff) {
        return 403, "Access denied";
    }

    my $server_ip = $self->req_param('server') || '';
    return 400, "Server IP required" unless $server_ip;

    my $server = NP::Model->server->find_server($server_ip);
    return 404, "Server not found" unless $server;

    # Determine if this is edit or save
    my $is_save = $self->request->uri =~ m{/save/?$};

    if ($is_save && $self->request->method eq 'post') {

        # Save hostname via API
        my $hostname_value = $self->req_param('hostname') || '';

        # Call API to update hostname (API handles validation and normalization)
        my $result = update_server(
            $self->api_auth_params,
            ip       => $server_ip,
            hostname => $hostname_value,
        );

        # Handle API response
        if ($result->{error}) {
            # API returned an error (validation failed or other error)
            warn "Hostname update failed: "
              . $result->{error}
              . " (Trace ID: "
              . $result->{trace_id} . ")";

            $self->tpl_param('server' => $server);
            $self->tpl_param('error'  => $result->{error});
            return OK, $self->evaluate_template('tpl/admin/hostname_view.html');
        }

        # Success - use data from API response
        warn "Hostname updated successfully for server "
          . $server_ip
          . " to: "
          . ($result->{data}{server}{hostname} || '(empty)');

        # Update the server object with API response data for display
        # (Don't reload from MySQL - use API data directly)
        $server->hostname($result->{data}{server}{hostname} || '');

        $self->tpl_param('server' => $server);
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
          query => [account_id => $self->current_account->{account_id}]);

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
        $self->api_auth_params,
        account => $self->current_account->{id_token},
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
    my $cache_key =
      '_account_monitor_config_' . ($account ? $account->{account_id} : 'none');

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

    # Parse account flags from API-provided account hashref
    my $config = {};

    if ($account->{flags}) {

        # Check if flags is already a hash reference or a JSON string
        if (ref($account->{flags}) eq 'HASH') {
            $config = $account->{flags};
        }
        else {
            eval { $config = decode_json($account->{flags}); };
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

sub user_accounts {
    my $self = shift;

    # Return cached accounts if already loaded
    return $self->{_user_accounts} if exists $self->{_user_accounts};

    # Return empty array if no user
    return $self->{_user_accounts} = [] unless $self->user;

    # Call GetUserAccounts API
    my $result = get_user_accounts(
        $self->api_auth_params,
    );

    # Handle errors - return empty array for graceful degradation
    if ($result->{error}) {
        warn "GetUserAccounts error: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
        return $self->{_user_accounts} = [];
    }

    # Return account list from API
    return $self->{_user_accounts} = $result->{data}{accounts} || [];
}

sub user_invites {
    my $self = shift;

    # Return cached invites if already loaded
    return $self->{_user_invites} if exists $self->{_user_invites};

    # Return empty array if no user
    return $self->{_user_invites} = [] unless $self->user;

    # Call GetAccountInvites API for user
    my $result = get_account_invites(
        $self->api_auth_params,
        for_user => JSON::XS::true,
    );

    # Handle errors - return empty array for graceful degradation
    if ($result->{error}) {
        warn "GetAccountInvites error: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
        return $self->{_user_invites} = [];
    }

    # Return invite list from API
    return $self->{_user_invites} = $result->{data}{invites} || [];
}

=head2 account_logs

Fetch audit logs via ConnectRPC AuditService API (eliminates N+1 query problem).

    my $logs = $self->account_logs(
        account => $account,
        types   => ['invitation', 'server-delete'],  # optional filter
        limit   => 50,                               # optional (default: 50)
    );

Returns arrayref of log objects compatible with log_table.html template.
Returns empty arrayref on error (with warning logged).

=cut

sub account_logs {
    my $self = shift;
    my %args = @_;

    my $account = $args{account} || $self->current_account;
    return [] unless $account;

    # Call AuditService.GetAccountAuditLogs
    require NP::CAPI::Audit;
    my $result = NP::CAPI::Audit::get_account_audit_logs(
        $self->api_auth_params,
        account => $account->{id_token},
        ($args{types} ? (types => $args{types}) : ()),
        ($args{limit} ? (limit => $args{limit}) : ()),
    );

    # Handle errors - return empty array for graceful degradation
    if ($result->{error}) {
        warn "GetAccountAuditLogs error: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};

        # Set error info for staff users to see
        $self->tpl_param('logs_error',    $result->{error});
        $self->tpl_param('logs_trace_id', $result->{trace_id}) if $result->{trace_id};
        return [];
    }

    my $logs = $result->{data}{logs} || [];

    # Transform API response to template format
    # API returns changes as array of {field_name, new_value, old_value}
    # Template expects hash {field_name => [new_value, old_value]}
    for my $log (@$logs) {

        # Defensive check: ensure changes is an arrayref
        if ($log->{changes} && ref($log->{changes}) eq 'ARRAY' && @{$log->{changes}}) {
            my %changes_hash;
            for my $change (@{$log->{changes}}) {
                $changes_hash{$change->{field_name}} =
                  [$change->{new_value}, $change->{old_value},];
            }
            $log->{changes} = \%changes_hash;
        }
        else {
            $log->{changes} = {};
        }
    }

    return $logs;
}

1;
