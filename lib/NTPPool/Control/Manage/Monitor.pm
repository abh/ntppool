package NTPPool::Control::Manage::Monitor;
use v5.30.0;
use warnings;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND FORBIDDEN);
use JSON ();
use MIME::Base64 qw(encode_base64);
use Data::Dump qw(pp);

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
        sort_by => "created_on desc",
    );

    $self->tpl_param('monitors' => $monitors);

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
        $mon->activate_monitor;
    }
    elsif ($status eq 'deleted') {
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

    my $setup_secret = $self->req_param('rotate') || 0;

    my $role_id = $mon->vault_role_id();

    unless ($role_id) {
        $role_id      = $mon->setup_vault_role();
        $setup_secret = 1;
    }

    unless ($mon->api_key) {
        $mon->api_key($role_id);
        $mon->save();
    }

    if ($setup_secret) {
        my ($secret_id, $secret_id_accessor) = $mon->setup_vault_secret();
        $self->tpl_param('secret_key', $secret_id);

        my $config = {
            "name" => $mon->tls_name,
            "api"  => {
                "key"    => $role_id,
                "secret" => $secret_id,
            },
        };

        my $config_base64 = encode_base64($json->encode($config));
        $self->tpl_param('config_file_content', $config_base64);
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
    $id = 0 if $id and $id eq 'new';

    my $mon = $id ? NP::Model->monitor->fetch(id => $id) : undef;

    if ($mon and !$mon->can_edit($self->user)) {
        return undef, ["Permission denied"];
    }

    my @setup_fields = qw(name);

    if ($mon) {
        for my $f (@setup_fields) {
            $mon->$f($self->req_param($f) || '');
        }
    }
    else {
        my $ip = $self->req_param('ip');
        $ip =~ s/\s+//g;

        my $codes = suggested_locationcodes($ip);
        $self->tpl_param('location_codes', $codes);

        my $location_code = $self->req_param('location_code') || '';
        ($location_code) = map { $_->{Code} } grep { $_->{Code} eq $location_code } @$codes
          if $location_code;

        $mon = NP::Model->monitor->create(
            (map { $_ => ($self->req_param($_) || '') } @setup_fields),

            user_id    => $self->user->id,
            account_id => $self->current_account->id,
            config     => '{}',
            location   => ($location_code || ''),

            # tls_name is set when the vault role is setup
            tls_name => undef,
        );
        $mon->ip($ip);    # so the ip_version gets set
    }

    unless ($mon->validate) {
        my $errors = $mon->validation_errors;
        return $mon, $errors;
    }

    $mon->save;
    return $mon;
}


sub suggested_locationcodes {

    # my $self = shift;
    my $ip = shift;

    my $ua = NP::LWP::ua();

    my $geoip = $ENV{geoip_service} || 'geoip';
    my $res   = $ua->get("http://${geoip}/api/json?ip=$ip");
    my $data  = {};

    $data = $json->decode($res->content) if $res->is_success;

    my $cc  = $data->{Country}->{IsoCode};
    my $loc = $data->{Location};

    my $radius = $loc->{AccuracyRadius} || 0;
    $radius = 100 if $radius < 100;

    my $loccode = $ENV{locationcode_service} || 'locationcode';

    my $locationcode_url = URI->new("http://$loccode/v1/code");
    $locationcode_url->query_form(
        {   cc     => $cc,
            lat    => $loc->{Latitude},
            lng    => $loc->{Longitude},
            radius => $radius,
        }
    );

    say "URL: ", $locationcode_url->as_string;

    $res = $ua->get($locationcode_url->as_string);

    my $codes = [];
    $codes = $json->decode($res->content) if $res->is_success;

    # say pp($codes);

    return $codes;
}

1;
