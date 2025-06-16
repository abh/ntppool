package NTPPool::Control::Manage::Monitor;
use v5.30.0;
use warnings;
use parent qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND FORBIDDEN);
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

sub manage_dispatch {
    my $self = shift;

    $self->cache_control('private, max-age=0, no-cache');

    $self->tpl_params->{page}->{is_monitors} = 1;

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;
    }

    return $self->render_instructions if $self->request->uri =~ m!^/manage/monitors/new$!;

    if ($self->request->uri =~ m!^/manage/monitors/?$!) {

        return $self->redirect($self->manage_url('/manage/monitors/new'))
          unless $self->account_monitor_count > 0;

        return $self->render_monitors;
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
        }
    );

    if ($data->{code} != 200) {
        $self->cache_control('private, max-age=0, no-cache');
        return NOT_FOUND;
    }

    my @monitor = _monitor_list($data->{data}->{Monitors} || {});
    $self->tpl_param('mon',  $monitor[0]);
    $self->tpl_param('data', $data->{data} || {});
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
        );
        if ($data->{error}) {
            $self->tpl_param('error', $data->{error});
        }
        $self->tpl_param('message', $data->{message});
        $self->tpl_param('code',    $data->{code});
        $self->tpl_param('data',    $data->{data});
        $self->tpl_param('error',   $data->{error});

        if ($status_check) {
            if ($self->is_htmx) {
                $self->tpl_param('page_style' => "none");
                $self->tpl_param('bare'       => 1);
            }
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
        }
    );

    if ($data->{code} >= 400) {
        $self->tpl_param('error', $data->{error});
        $self->tpl_param('code',  $data->{code});
    }

    my @monitors = _monitor_list($data->{data}->{Monitors} || {});
    $self->tpl_param('monitors', \@monitors);
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
        }
    );

    if ($data->{code} >= 400) {
        $self->tpl_param('error', $data->{error});
        $self->tpl_param('code',  $data->{code});
    }

    my @monitors = _monitor_list($data->{data}->{Monitors} || {});
    $self->tpl_param('monitors', \@monitors);

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
        }
    );
    if ($data->{code} >= 400) {
        $self->tpl_param('error', $data->{error});

        return $self->render_monitor();
    }

    # no content, monitor was deleted
    if ($data->{code} == 204) {
        return $self->redirect($self->manage_url('/manage/monitors/admin'));
    }

    my $redirect =
      $self->manage_url('/manage/monitors/monitor', {name => $self->req_param('name')});
    return $self->redirect($redirect);

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
