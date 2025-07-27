package NTPPool::Control::Manage::Monitor;
use v5.30.0;
use warnings;
use parent qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND FORBIDDEN SERVER_ERROR);
use JSON              ();
use MIME::Base64      qw(encode_base64);
use Data::Dump        qw(pp);
use NP::IntAPI        qw(int_api);
use OpenTelemetry::Trace;
use OpenTelemetry -all;
use OpenTelemetry::Constants qw( SPAN_KIND_SERVER SPAN_STATUS_ERROR SPAN_STATUS_OK );
use experimental             qw( defer );
use Syntax::Keyword::Dynamically;

my $json = JSON::XS->new->pretty->utf8->convert_blessed;

sub _get_request_context {
    my $self            = shift;
    my $x_forwarded_for = $self->request->header_in('X-Forwarded-For');
    return $x_forwarded_for ? {x_forwarded_for => $x_forwarded_for} : undef;
}

sub _map_api_error_code {
    my ($self, $data, $context) = @_;

    my $api_code = $data->{code};
    return $api_code if $api_code == 200;

    $self->cache_control('private, max-age=0, no-cache');
    $self->tpl_param('error', $data->{error}) unless $self->tpl_param('error');
    $self->tpl_param('code',  $api_code);

    if ($api_code == 401) {
        warn "API unauthorized access in $context: user "
          . ($self->user ? $self->user->username : 'none');
        return 401;
    }
    elsif ($api_code == 404) {
        return NOT_FOUND;
    }
    elsif ($api_code >= 400 && $api_code < 500) {
        return FORBIDDEN;
    }
    elsif ($api_code >= 500) {
        return SERVER_ERROR;
    }

    return NOT_FOUND;    # fallback
}

sub manage_dispatch {
    my $self = shift;
    $self->set_span_name("manage.monitors");

    $self->cache_control('private, max-age=0, no-cache');

    $self->tpl_params->{page}->{is_monitors} = 1;

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;
    }

    return $self->render_instructions if $self->request->uri =~ m!^/manage/monitors/new$!;

    if ($self->request->uri =~ m!^/manage/monitors/?$!) {

        # If account has existing monitors, show the list
        if ($self->monitor_eligibility->{monitor_count}) {
            return $self->render_monitors;
        }

        # Otherwise redirect to instructions page
        return $self->redirect($self->manage_url('/manage/monitors/new'));
    }

    if (my ($token, $status_check) =
        ($self->request->uri =~ m!^/manage/monitors/confirm/([^/]+)(/status)?$!))
    {
        return $self->render_confirm_monitor($token, $status_check);
    }

    if ($self->request->uri =~ m!^/manage/monitors/monitor$!) {
        return $self->render_monitor;
    }

    if ($self->request->uri =~ m!^/manage/monitors/admin$!) {
        return $self->render_admin_list();
    }

    if ($self->request->uri =~ m!^/manage/monitors/monitor/status$!) {
        return $self->render_admin_status();
    }

    if ($self->request->uri =~ m!^/manage/monitors/monitor/delete$!) {
        return $self->render_delete_monitor();
    }

    # return 403, "Permission denied"
    #   unless $mon->can_edit($self->user);

    # if ($self->request->uri =~ m!^/manage/monitors/api$!) {
    #     return $self->render_api_save($mon) if $self->request->method eq 'post';
    #     return $self->render_api($mon);
    # }

    return NOT_FOUND;
}

sub render_monitor {
    my $self = shift;

    my $span = NP::Tracing->tracer->create_span(
        name => "monitor.render_monitor",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);
    defer { $span->end(); };

    my $name = $self->req_param('name');
    unless ($name) {
        warn "no name provided to render_monitor";
        return NOT_FOUND;
    }
    my $data = int_api(
        'get',
        'monitor/manage/monitor',
        {   name => $name,
            user => $self->plain_cookie($self->user_cookie_name),
            a    => $self->current_account->id_token,
        },
        $self->_get_request_context()
    );

    if ($data->{code} != 200) {
        return $self->_map_api_error_code($data, "render_monitor for $name");
    }

    my @monitor = _monitor_list($data->{data}->{Monitors} || {});
    $self->tpl_param('mon',  $monitor[0]);
    $self->tpl_param('data', $data->{data} || {});

    # Fetch metrics for this specific monitor
    my $metrics = $self->monitor_metrics(names => $name);
    $self->tpl_param('metrics', $metrics);

    return OK, $self->evaluate_template('tpl/monitors/show.html');
}

sub render_confirm_monitor {
    my $self             = shift;
    my $validation_token = shift;
    my $status_check     = shift;

    my $span = NP::Tracing->tracer->create_span(
        name => "monitor.render_confirm_monitor",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);
    defer { $span->end(); };

    $self->tpl_param('validation_token', $validation_token);

    if ($self->request->method ne 'get') {
        return 403 unless $self->check_auth_token;
    }
    else {
        # GET request
        my $data = NP::IntAPI::get_monitoring_registration_data(
            $validation_token,
            $self->plain_cookie($self->user_cookie_name),
            $self->current_account->id_token,
            $self->_get_request_context(),
        );
        if ($data->{error}) {
            $self->tpl_param('error', $data->{error});
        }
        $self->tpl_param('message', $data->{message});
        $self->tpl_param('code',    $data->{code});
        $self->tpl_param('data',    $data->{data});
        $self->tpl_param('error',   $data->{error});

        if ($status_check) {
            return OK, $self->evaluate_template('tpl/monitors/confirm_status.html');
        }

        # Check if registration is already completed or accepted
        if ($data->{code} == 201    # StatusCreated - monitor has been setup
            || $data->{code}
            == 202 # StatusAccepted - user accepted registration; waiting for monitor to confirm
            || (   $data->{data}
                && $data->{data}->{status}
                && $data->{data}->{status} ne 'pending')
          )
        {
            # Show status page instead of form for non-pending registrations
            return OK, $self->evaluate_template('tpl/monitors/confirm_status.html');
        }

        return OK, $self->evaluate_template('tpl/monitors/confirm_form.html');
    }

    unless ($self->request->method eq 'post') {
        return NOT_FOUND;
    }
    my $data = NP::IntAPI::accept_monitoring_registration(
        $validation_token,
        $self->plain_cookie($self->user_cookie_name),
        $self->current_account->id_token,
        $self->req_param("location_code"),
        $self->_get_request_context(),
    );
    if ($data->{error}) {
        $self->tpl_param('error', $data->{error});
    }
    $self->tpl_param('message', $data->{message});
    $self->tpl_param('code',    delete $data->{code});
    $self->tpl_param('data',    $data->{data});

    return OK, $self->evaluate_template('tpl/monitors/confirm_accept.html');

    # # if successful, show the monitor page
    # return $self->redirect(
    #     $self->manage_url(
    #         '/manage/monitors/monitor',

    #         # , {id => $mon->id_token}
    #     )
    # );
}

sub _get_id {
    my $self  = shift;
    my $token = $self->req_param('id') or return;
    my $id    = $token =~ m/^mon-/ ? NP::Model::Monitor->token_id($token) : $token;
    return $id;
}

sub render_instructions {
    my $self = shift;
    return OK, $self->evaluate_template('tpl/monitors/instructions.html');
}

sub render_monitors {
    my $self = shift;

    my $span = NP::Tracing->tracer->create_span(
        name => "monitor.render_monitors",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);
    defer { $span->end(); };

    my $data = int_api(
        'get',
        'monitor/manage/',
        {   account_id => $self->current_account->id,
            a          => $self->current_account->id_token,

            user => $self->plain_cookie($self->user_cookie_name),
        },
        $self->_get_request_context()
    );

    if ($data->{code} >= 400) {
        return $self->_map_api_error_code($data, "render_monitors");
    }

    my @monitors = _monitor_list($data->{data}->{Monitors} || {});
    $self->tpl_param('monitors', \@monitors);

    # Fetch metrics for all monitors in this account
    my $metrics =
      $self->monitor_metrics(account_token => $self->current_account->id_token);
    $self->tpl_param('metrics', $metrics);

    return OK, $self->evaluate_template('tpl/monitors/list.html');
}

sub render_admin_list {
    my $self = shift;

    my $span = NP::Tracing->tracer->create_span(
        name => "monitor.render_admin_list",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);
    defer { $span->end(); };

    my $data = int_api(
        'get',
        'monitor/manage/',
        {   all_accounts => 1,
            user         => $self->plain_cookie($self->user_cookie_name),
        },
        $self->_get_request_context()
    );

    if ($data->{code} >= 400) {
        return $self->_map_api_error_code($data, "render_admin_list");
    }

    my @monitors = _monitor_list($data->{data}->{Monitors} || {});
    $self->tpl_param('monitors',   \@monitors);
    $self->tpl_param('admin_list', 1);

    # Fetch metrics for all accounts (admin view)
    my $metrics = $self->monitor_metrics(all_accounts => 1);
    $self->tpl_param('metrics', $metrics);

    return OK, $self->evaluate_template('tpl/monitors/admin_list.html');
}

sub render_admin_status {
    my $self = shift;
    my $mon  = shift;

    my $span = NP::Tracing->tracer->create_span(
        name => "monitor.render_admin_status",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);
    defer { $span->end(); };

    my $data = int_api(
        'post',
        'monitor/manage/status',
        {   a      => $self->current_account->id_token,
            name   => $self->req_param('name')                     || '',
            id     => $self->req_param('id')                       || '',
            status => $self->req_param('status')                   || '',
            user   => $self->plain_cookie($self->user_cookie_name) || '',
        },
        $self->_get_request_context()
    );
    if ($data->{code} >= 400) {
        return $self->_map_api_error_code($data, "render_admin_status");
    }

    # no content, monitor was deleted
    if ($data->{code} == 204) {
        return $self->redirect($self->manage_url('/manage/monitors/admin'));
    }

    my $redirect =
      $self->manage_url('/manage/monitors/monitor', {name => $self->req_param('name')});
    return $self->redirect($redirect);

}

sub render_delete_monitor {
    my $self = shift;

    return 403 unless $self->check_auth_token;
    return 405 unless $self->request->method eq 'post';

    my $name = $self->req_param('name');
    my $id   = $self->req_param('id');

    unless ($name && $id) {
        warn "Missing required parameters for monitor deletion: name=$name, id=$id";
        if ($self->is_htmx) {
            $self->tpl_param('error', 'Unable to delete monitor');
            return OK, $self->evaluate_template('tpl/monitors/delete_error.html');
        }
        return $self->redirect($self->manage_url('/manage/monitors/'));
    }

    my $data = int_api(
        'post',
        'monitor/manage/status',
        {   name   => $name,
            id     => $id,
            status => 'deleted',
            user   => $self->plain_cookie($self->user_cookie_name),
            a      => $self->current_account->id_token,
        },
        $self->_get_request_context()
    );

    # Log exact API response for debugging
    warn "Delete monitor API response for $name: " . Data::Dump::pp($data);

    if ($data->{code} == 204) {

        # Successful deletion - redirect to monitor list
        if ($self->is_htmx) {

            # HTMX redirect header
            $self->request->header_out('HX-Redirect',
                $self->manage_url('/manage/monitors/'));
            return OK, '';
        }
        return $self->redirect($self->manage_url('/manage/monitors/'));
    }
    else {
        # Error case - log details, show generic message
        warn "Failed to delete monitor $name: " . ($data->{error} || 'Unknown error');

        if ($self->is_htmx) {
            $self->tpl_param('error',    'Unable to delete monitor');
            $self->tpl_param('trace_id', $data->{trace_id}) if $data->{trace_id};
            return OK, $self->evaluate_template('tpl/monitors/delete_error.html');
        }

        # For non-HTMX, render the monitor page with error
        $self->tpl_param('error',    'Unable to delete monitor');
        $self->tpl_param('trace_id', $data->{trace_id}) if $data->{trace_id};

        # Call render_monitor to show the page with error
        return $self->render_monitor();
    }
}

sub _edit_monitor {
    my $self = shift;

    my $id = $self->_get_id;
    $id = 0 if $id and $id eq 'new';    # 'new' isn't supported here anymore

    my $mon = $id ? NP::Model->monitor->fetch(id => $id) : undef;

    unless ($mon) {
        return undef, ["Permission denied"];
    }

    if ($mon and !$mon->can_edit($self->user)) {
        return undef, ["Permission denied"];
    }

    # todo: move this to the API and use the client to set the name?
    my @setup_fields = qw(name);

    for my $f (@setup_fields) {
        $mon->$f($self->req_param($f) || '');
    }

    unless ($mon->validate) {
        my $errors = $mon->validation_errors;
        return $mon, $errors;
    }

    $mon->save;
    return $mon;
}

sub monitor_metrics {
    my $self   = shift;
    my %params = @_;

    my $api_params = {
        user => $self->plain_cookie($self->user_cookie_name),
        a    => $self->current_account->id_token,
    };

    # Determine the actual parameters and cache key
    my $actual_account_token;
    my $actual_names;
    my $all_accounts = 0;

    if ($params{account_token}) {

        # Use 'a' parameter for account token per API specification
        $api_params->{a} = $params{account_token};
        $actual_account_token = $params{account_token};
    }
    elsif ($params{names}) {
        $api_params->{names} = $params{names};
        $actual_names = $params{names};
    }
    elsif ($params{all_accounts}) {
        $api_params->{all_accounts} = 'true';
        $all_accounts = 1;
    }
    else {
        # Default to current account using id_token with 'a' parameter
        $actual_account_token = $self->current_account->id_token;
        $api_params->{a} = $actual_account_token;
    }

    # Request-scoped caching to avoid multiple API calls
    my $cache_key =
        "_monitor_metrics_"
      . ($actual_account_token || '') . '_'
      . ($actual_names         || '') . '_'
      . ($all_accounts ? 'all' : '');
    return $self->{$cache_key} if exists $self->{$cache_key};

    my $data = int_api(
        'get',       'monitor/manage/metrics/summary',
        $api_params, $self->_get_request_context()
    );

    # Handle different response codes with graceful degradation
    if ($data->{code} == 200) {

        # The API returns data.data.monitors, so we need to extract the inner data
        my $metrics_data = $data->{data}->{data} || $data->{data};
        return $self->{$cache_key} = {
            success => 1,
            data    => $metrics_data
        };
    }
    elsif ($data->{code} == 404) {

        # No metrics available for these monitors
        return $self->{$cache_key} = {
            success  => 0,
            error    => 'No metrics available',
            trace_id => $data->{trace_id}
        };
    }
    else {
        # API error - return error info for display
        return $self->{$cache_key} = {
            success  => 0,
            error    => $data->{error} || 'Metrics temporarily unavailable',
            trace_id => $data->{trace_id}
        };
    }
}

sub _monitor_list {
    my $monitors = shift;
    my @monitors =
      sort {
             $a->{Account}->{ID} <=> $b->{Account}->{ID}
          or $a->{TLSName} cmp $b->{TLSName}
          or ($a->{IPv4} && $b->{IPv4} && $a->{IPv4}->{IP} cmp $b->{IPv4}->{IP})
          or ($a->{IPv6} && $b->{IPv6} && $a->{IPv6}->{IP} cmp $b->{IPv6}->{IP})
      }
      map {
          my $display_name =
          $_->{Name} || $_->{TLSName} || $_->{IPv4}->{IP} || $_->{IPv6}->{IP};
          $display_name =~ s{\.[^.]+\.mon\.ntppool\.dev}{};
          $_->{display_name} = $display_name;
          $_
      } values %$monitors;
    return @monitors;
}

1;
