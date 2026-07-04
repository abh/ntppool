package NTPPool::Control::Manage::Monitor;
use v5.30.0;
use warnings;
use parent            qw(NTPPool::Control::Manage);
use Combust::Constant qw(OK NOT_FOUND FORBIDDEN SERVER_ERROR);
use JSON              ();
use MIME::Base64      qw(encode_base64);
use Data::Dump        qw(pp);
use NP::IntAPI        qw(int_api);
use NP::CAPI::Monitor
  qw(get_monitor list_monitors update_monitor_status get_monitor_metrics_summary);
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

    warn "DEBUG: All URIs being checked - actual URI: '" . $self->request->uri . "'";
    if ($self->request->uri =~ m!^/manage/monitors/monitor/confirm-delete$!) {
        warn "DEBUG: confirm-delete route matched, URI: " . $self->request->uri;
        return $self->render_confirm_delete();
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

sub _fetch_monitor_details {
    my $self = shift;
    my $name = shift;

    unless ($name) {
        warn "no name provided to _fetch_monitor_details";
        return undef, NOT_FOUND;
    }

    my $result = get_monitor(
        $self->api_auth_params,
        account => $self->current_account->{id_token},
        name    => $name,
    );

    if ($result->{code} >= 300) {
        my $code = $self->_handle_capi_error($result);
        return undef, $code;
    }

    return $result->{data}->{monitor}, undef;
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
    my ($mon, $error_code) = $self->_fetch_monitor_details($name);
    return $error_code if $error_code;

    $self->tpl_param('mon', $mon);

    # The admin status form (show.html) posts to render_admin_status, which
    # calls update_monitor_status. get_monitor does not return the allowed
    # statuses, so supply the fixed enum here.
    $self->tpl_param('status_options',
        [qw(pending testing active paused deleted)]);

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
            $self->current_account->{id_token},
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
        $self->current_account->{id_token},
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

    my $result = list_monitors(
        $self->api_auth_params,
        account => $self->current_account->{id_token},
    );

    if ($result->{code} >= 300) {
        return $self->_handle_capi_error($result);
    }

    $self->tpl_param('monitors', $result->{data}->{monitors} || []);

    # Fetch metrics for all monitors in this account
    my $metrics = $self->monitor_metrics(id_token => $self->current_account->{id_token});
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

    my $result = list_monitors(
        $self->api_auth_params,
        all_accounts => JSON::XS::true,
    );

    if ($result->{code} >= 300) {
        return $self->_handle_capi_error($result);
    }

    $self->tpl_param('monitors',   $result->{data}->{monitors} || []);
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

    my $name = $self->req_param('name') || '';
    my $result = update_monitor_status(
        $self->api_auth_params,
        account => $self->current_account->{id_token},
        name    => $name,
        ids     => [split /,/, ($self->req_param('id') || '')],
        status  => $self->req_param('status') || '',
    );
    if ($result->{code} >= 300) {
        return $self->_handle_capi_error($result);
    }

    # deletion returns to the admin list; other status changes to the monitor page
    if ($result->{data}->{deleted}) {
        return $self->redirect($self->manage_url('/manage/monitors/admin'));
    }

    my $redirect = $self->manage_url('/manage/monitors/monitor', {name => $name});
    return $self->redirect($redirect);

}

sub render_confirm_delete {
    my $self = shift;

    # Only allow GET requests for confirmation dialog
    return 405 unless $self->request->method eq 'get';

    my $name = $self->req_param('name');
    my $id   = $self->req_param('id');

    unless ($name && $id) {
        warn "Missing required parameters for delete confirmation: name=$name, id=$id";
        return NOT_FOUND;
    }

    # Get monitor details for display using shared method
    my ($mon, $error_code) = $self->_fetch_monitor_details($name);
    return $error_code if $error_code;

    $self->tpl_param('monitor', $mon);
    return OK, $self->evaluate_template('tpl/monitors/confirm_delete_modal.html');
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

    my $result = update_monitor_status(
        $self->api_auth_params,
        account => $self->current_account->{id_token},
        name    => $name,
        ids     => [split /,/, $id],
        status  => 'deleted',
    );

    if ($result->{code} < 300) {

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
        # Error case - use actual API error message
        my $error_msg = $result->{error}
          || 'Unable to delete monitor - please try again or contact support';

        if ($self->is_htmx) {
            $self->tpl_param('error',    $error_msg);
            $self->tpl_param('trace_id', $result->{trace_id}) if $result->{trace_id};
            return OK, $self->evaluate_template('tpl/monitors/delete_error.html');
        }

        # For non-HTMX, render the monitor page with error
        $self->tpl_param('error',    $error_msg);
        $self->tpl_param('trace_id', $result->{trace_id}) if $result->{trace_id};

        # Call render_monitor to show the page with error
        return $self->render_monitor();
    }
}

sub monitor_metrics {
    my $self   = shift;
    my %params = @_;

    # Determine the query mode + cache key. The Go API scopes by names, by the
    # X-Account header (account query), or across all accounts (admin).
    my $account_token;
    my $actual_names;
    my $all_accounts = 0;
    my %request;

    if ($params{id_token}) {
        $account_token = $params{id_token};
    }
    elsif ($params{names}) {
        $actual_names = $params{names};
        $request{names} = [split /,/, $params{names}];
    }
    elsif ($params{all_accounts}) {
        $all_accounts = 1;
        $request{all_accounts} = JSON::XS::true;
    }
    else {
        $account_token = $self->current_account->{id_token};
    }

    # Request-scoped caching to avoid multiple API calls
    my $cache_key =
        "_monitor_metrics_"
      . ($account_token || '') . '_'
      . ($actual_names  || '') . '_'
      . ($all_accounts ? 'all' : '');
    return $self->{$cache_key} if exists $self->{$cache_key};

    my $result = get_monitor_metrics_summary(
        $self->api_auth_params,
        ($account_token ? (account => $account_token) : ()),
        %request,
    );

    if ($result->{code} == 200) {

        # breakdown_1h/breakdown_24h strings are pre-computed by the Go API.
        return $self->{$cache_key} = {
            success => 1,
            data    => $result->{data},
        };
    }

    # Graceful degradation: the page still renders with a metrics warning.
    return $self->{$cache_key} = {
        success  => 0,
        error    => $result->{error} || 'Metrics temporarily unavailable',
        trace_id => $result->{trace_id},
    };
}

1;
