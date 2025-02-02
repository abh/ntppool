package NTPPool::Control::Manage::Monitor;
use v5.30.0;
use warnings;
use parent qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND FORBIDDEN);
use JSON              ();
use MIME::Base64      qw(encode_base64);
use Data::Dump        qw(pp);
use NP::IntAPI;

my $json = JSON::XS->new->pretty->utf8->convert_blessed;

sub manage_dispatch {
    my $self = shift;

    $self->tpl_params->{page}->{is_monitors} = 1;

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;
    }

    return $self->render_form if $self->request->uri =~ m!^/manage/monitors/new$!;

    if ($self->request->uri =~ m!^/manage/monitors/?$!) {

        return $self->redirect($self->manage_url('/manage/monitors/new'))
          unless $self->account_monitor_count > 0;

        return $self->render_monitors;
    }

    if (my ($token) = ($self->request->uri =~ m!^/manage/monitors/confirm/([^/]+)$!)) {
        return $self->render_confirm_monitor($token);
    }

    my $mon;
    if (my $id = $self->_get_id) {
        $mon = NP::Model->monitor->fetch(id => $id);

        if ($mon and !$mon->can_edit($self->user)) {
            return 403, "Permission denied";
        }
        $self->tpl_param('mon', $mon);
    }

    if ($self->request->uri =~ m!^/manage/monitors/monitor$!) {
        return $self->render_save if $self->request->method eq 'post';

        # we might save a new monitor, but need one to show it
        return 404 unless $mon;
        return OK, $self->evaluate_template('tpl/monitors/show.html');
    }

    if ($self->request->uri =~ m!^/manage/monitors/monitor/status$!) {
        return 403 unless $self->user->is_staff;
        return 404 unless $mon;
        return $self->render_admin_status($mon) if $self->request->method eq 'post';
        return 404;
    }

    if ($self->request->uri =~ m!^/manage/monitors/admin$!) {
        return 403 unless $self->user->is_staff;
        return $self->render_admin_list();
    }

    return 404 unless $mon;
    return 403, "Permission denied"
      unless $mon->can_edit($self->user);

    if ($self->request->uri =~ m!^/manage/monitors/api$!) {
        return $self->render_api_save($mon) if $self->request->method eq 'post';
        return $self->render_api($mon);
    }

    return NOT_FOUND;
}

sub render_confirm_monitor {
    my $self             = shift;
    my $validation_token = shift;

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;
    }

    $self->tpl_param('validation_token', $validation_token);

    if ($self->request->method eq 'get') {
        my $data = NP::IntAPI::get_monitoring_registration_data($validation_token,
            $self->plain_cookie($self->user_cookie_name));
        if ($data->{error}) {
            $self->tpl_param('error', $data->{error});
        }
        $self->tpl_param('message', $data->{message});
        $self->tpl_param('code',    delete $data->{code});
        $self->tpl_param('data',    $data);

        return OK, $self->evaluate_template('tpl/monitors/confirm_form.html');
    }

    unless ($self->request->method eq 'post') {
        return NOT_FOUND;
    }
    my $data = NP::IntAPI::accept_monitoring_registration(
        $validation_token,          $self->plain_cookie($self->user_cookie_name),
        $self->current_account->id, $self->req_param("location_code"),
    );
    if ($data->{error}) {
        $self->tpl_param('error', $data->{error});
    }
    $self->tpl_param('message', $data->{message});
    $self->tpl_param('code',    delete $data->{code});
    $self->tpl_param('data',    $data);

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

sub render_form {
    my $self = shift;
    my $mon  = shift;

    if ($mon) {
        $self->tpl_param('monitor', $mon);
    }

    return OK, $self->evaluate_template('tpl/monitors/form.html');
}

sub render_monitors {
    my $self = shift;

    # todo: deleted parameter?

    my $monitors = NP::Model->monitor->get_objects(
        query => [
            account_id => $self->current_account->id,
            status     => {"ne" => "deleted"},
        ],
        sort_by => "tls_name, created_on desc",
    );

    my %monitors;

    for my $mon (@$monitors) {
        my $key = $mon->tls_name || $mon->ip;
        if ($monitors{$key}->{$mon->ip_version}) {
            warn "Duplicate monitor key: $key + " . $mon->ip_version;
            $key = $mon->ip . ' ' . $mon->ip_version;
        }
        $mon->{__key} = $key;
        $monitors{$key}->{name} = $key;
        $monitors{$key}->{$mon->ip_version} = $mon;
    }

    my @monitors = sort { $a->{name} cmp $b->{name} } values %monitors;

    $self->tpl_param('monitors' => \@monitors);

    return OK, $self->evaluate_template('tpl/monitors/list.html');
}

sub render_admin_list {
    my $self = shift;

    # todo: deleted parameter?

    my $monitors = NP::Model::monitor->get_objects(
        query           => [status => {"ne" => "deleted"},],
        require_objects => 'account',
        sort_by         => "account_id, monitors.created_on desc",
    );
    $self->tpl_param('monitors', $monitors);

    return OK, $self->evaluate_template('tpl/monitors/admin_list.html');
}

sub render_admin_status {
    my $self = shift;
    my $mon  = shift;

    # 'pending','testing','live','paused','deleted'
    my $status = $self->req_param('status') || '';
    return 400 unless grep { $status eq $_ } $mon->status_options;

    $mon->status($status);

    if (grep { $status eq $_ } qw(testing active)) {

        # todo: call internal API to set status
    }
    elsif ($status eq 'deleted') {

        # todo: move this to internal API
        $mon->delete_monitor;
    }

    $mon->save;

    my $redirect = $self->manage_url('/manage/monitors/monitor', {id => $mon->id_token});
    return $self->redirect($redirect);

}

sub render_api_save {
    my $self = shift;
    my $mon  = shift;

    warn "API SAVE for ", $mon->id;

    unless ($mon->tls_name) {
        warn "Setting up tls name";
        my $tls_name = $mon->generate_tls_name();
        unless ($tls_name) {
            $self->tpl_param('error', 'Could not set tls_name');
            return OK, $self->evaluate_template('tpl/monitors/api.html');
        }
        $mon->save() or die "Could not save monitor with new tls_name";
    }

    return OK, $self->evaluate_template('tpl/monitors/api.html');
}

sub render_api {
    my $self = shift;
    my $mon  = shift;
    return OK, $self->evaluate_template('tpl/monitors/api.html');
}

sub render_save {
    my $self = shift;
    my ($mon, $errors) = $self->_edit_monitor;

    if ($errors) {
        $self->tpl_param('errors', $errors);
        warn "monitor form errors: ", pp($errors);
        return $self->render_form($mon);
    }

    my $redirect = $self->manage_url('/manage/monitors/monitor', {id => $mon->id_token});
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

1;
