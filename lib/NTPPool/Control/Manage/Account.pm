package NTPPool::Control::Manage::Account;
use strict;
use NTPPool::Control::Manage;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant    qw(OK NOT_FOUND);
use Math::BaseCalc       ();
use Math::Random::Secure qw(irand);
use Combust::Template;
use NP::Email  ();
use NP::IntAPI qw(int_api);
use JSON::XS   qw(encode_json decode_json);
use Data::Dump qw(pp);
use OpenTelemetry::Trace;
use OpenTelemetry -all;
use OpenTelemetry::Constants qw( SPAN_KIND_SERVER SPAN_STATUS_ERROR SPAN_STATUS_OK );
use experimental             qw( defer );
use Syntax::Keyword::Dynamically;

my $json = JSON::XS->new->utf8;

sub _get_request_context {
    my $self            = shift;
    my $x_forwarded_for = $self->request->header_in('X-Forwarded-For');
    return $x_forwarded_for ? {x_forwarded_for => $x_forwarded_for} : undef;
}

sub manage_dispatch {
    my $self = shift;
    $self->set_span_name("manage.account");

    my $account;

    if ($self->request->uri =~ m!^/manage/account/invite/!) {
        return $self->handle_invitation;
    }
    elsif ($self->request->uri =~ m!^/manage/account/invites/!) {
        return $self->render_user_invitations;
    }

    # support for creating a new account; we deliberately
    # don't want to look for a default account
    if (($self->req_param('a') || '') eq 'new') {
        return 403 unless $self->check_auth_token;
        $account = NP::Model->account->create(users => [$self->user]);
    }

    $account = $self->current_account unless $account;

    unless ($account) {

        my $invites = $self->user->pending_invites;
        if ($invites && @$invites) {
            warn "has no account and there are pending invites...";
            return $self->redirect("/manage/account/invites/");
        }

        $account = NP::Model->account->create(users => [$self->user]);
        $account->name($self->user->name);
        NP::Model::Log->log_changes($self->user, "account", "account created", $account);
        $account->save();
    }

    # check access
    return $self->redirect("/manage/")
      unless ($account->id == 0
          or $account->can_edit($self->user));

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;
    }

    if ($self->request->uri =~ m!^/manage/account$!) {
        return $self->render_account_edit
          if ($self->request->method eq 'post' and !$self->req_param('new_form'));
        return $self->render_account_form($account);
    }
    elsif ($self->request->uri =~ m!^/manage/account/monitor-config$!) {
        warn "DEBUG: monitor-config route hit, method: " . $self->request->method;
        warn "DEBUG: request URI: " . $self->request->uri;
        return 403 unless $self->user->is_monitor_admin;
        if ($self->request->method eq 'post') {
            warn
              "DEBUG: Handling POST request for monitor config update (will use PATCH to API)";
            return $self->render_monitor_config_update($account);
        }
        else {
            warn "DEBUG: Handling GET request for monitor config form";

            # GET request - return the edit form
            return $self->render_monitor_config_form($account);
        }
    }
    elsif ($self->request->uri =~ m!^/manage/account/team$!) {
        if ($self->request->method eq 'post' and $account->can_edit($self->user)) {
            return $self->render_users_invite($account, $self->req_param('invite_email'))
              if $self->req_param('invite_email');

            my $delete_user_id = $self->req_param('user_id');
            if ($delete_user_id
                and ($self->user->is_staff or $self->user->id != $delete_user_id))
            {
                return $self->remove_user_from_account($account, $delete_user_id);
            }
        }
        return $self->render_users($account);
    }
    elsif ($self->request->uri =~ m!^/manage/account/download(/data/.*)?$!) {
        return $self->render_download($self->user);
    }
    elsif ($self->request->uri =~ m!^/manage/account/delete$!) {
        return $self->render_user_delete($self->user);
    }

    return NOT_FOUND;
}

sub remove_user_from_account {
    my ($self, $account, $user_id) = @_;
    my $users = $account->users;
    my ($user) = grep { $_->id == $user_id } @$users;
    return $self->render_users($account)
      unless $user;

    NP::Model::Log->log_changes($self->user, "account-users",
        sprintf("Removed user %s (%d)", $user->email, $user->id), $account,);

    @$users = grep { $_->id != $user_id } @$users;
    $account->users($users);
    $account->save();

    my $param = {
        account      => $account,
        user_removed => $user,
    };

    my $msg = Combust::Template->new->process('tpl/account/account_user_removed.txt',
        $param, {site => 'manage', config => $self->config});

    my $email =
      Email::Stuffer->from(NP::Email::address("sender"))
      ->reply_to(NP::Email::address("support"))->subject("NTP Pool account change")
      ->text_body($msg);

    $email->to($user->email);
    my @cc = grep { $_->id != $user_id } @$users;
    if (@cc) {
        $email->cc(map { $_->email } @cc);
    }

    NP::Email::sendmail($email);

    $self->render_users($account);
}

sub handle_invitation {
    my $self = shift;

    my ($code) = ($self->request->path =~ m{^/manage/account/invite/([^/]+)});
    warn "CODE: $code -- method: ", $self->request->method;
    return 404 unless $code;

    my $invite = NP::Model->account_invite->fetch(code => $code);
    return 404 unless $invite;

    warn "got invite: ", $invite->id if $invite;

    my $error;

    if ($invite->status ne "pending") {
        return $self->render_invite_error("Invitation code has been used or expired");
    }

    # on post requests the auth token has already been checked, so if it's
    # something else we show a confirmation page.
    if ($self->request->method ne 'post') {
        return $self->render_user_invitations($invite);
    }

    my $db  = NP::Model->db;
    my $txn = $db->begin_scoped_work;

    warn "ADDING ", $self->user->id, " to account ", $invite->account->id;

    my $user = $self->user;

    $invite->status('accepted');
    $invite->user($user->id);

    $invite->account->add_users([$user->id])
      or return $self->render_invite_error("Error adding user to account");

    $invite->save or return $self->render_invite_error("Error saving invite update");

    $invite->account->save
      or return $self->render_invite_error("Error saving database update");

    NP::Model::Log->log_changes($user, "account-users", "Accepted invitation to account",
        $invite->account);
    $db->commit or return $self->render_invite_error("database commit error");

    # we accepted an invite for a new user that didn't have a account yet, so
    # just 'start over' ...
    unless ($self->current_account) {
        return $self->redirect($self->manage_url("/manage"));
    }

    # go to the team page for the "new" account
    return $self->redirect(
        $self->manage_url("/manage/account/team", {a => $invite->account->id_token}));
}

sub render_invite_error {
    my $self  = shift;
    my $error = shift;
    $self->tpl_param('invite_error', $error);
    return OK, $self->evaluate_template('tpl/account/invite_error.html');
}

sub render_users_invite {
    my ($self, $account, $email_address) = @_;

    my %errors = ();

    if (grep { lc $_->email eq lc $email_address } $account->users) {
        $errors{invite_email} = "User is already on this account";
    }

    if (scalar(grep { $_->status eq 'pending' } $account->invites) >= 5) {
        $errors{invite_email} = 'Too many recent account invitations';
    }

    if (%errors) {
        $self->tpl_param(errors => \%errors);
        return $self->render_users($account);
    }

    my $base36 = Math::BaseCalc->new(digits => ['a' .. 'k', 'm' .. 'z', 2 .. 9]);
    my $code   = join "", map { $base36->to_base(irand) } (undef) x 2;

    my $invite = NP::Model->account_invite->fetch_or_create(
        account => $account,
        email   => $email_address,
        status  => 'pending',
        sent_by => $self->user->id,
        code    => $code,
    );
    $invite->expires_on(DateTime->now()->add(hours => 49));
    if ($invite->status ne 'pending') {
        $invite->status('pending');
        $invite->code($code);
        $invite->created_on('now');
    }
    $invite->save;

    NP::Model::Log->log_changes($self->user, "invitation",
        "Sending invitation to ${email_address}", $account,);

    my $param = {invite => $invite};

    my $tpl = Combust::Template->new;
    my $msg =
      $tpl->process('tpl/account_invite.txt', $param,
          {site => 'manage', config => $self->config});

    # todo: if there's a vendor zone, use the vendor address
    # for the sender?

    my $email =
      Email::Stuffer->from(NP::Email::address("sender"))->to($email_address)
      ->reply_to(NP::Email::address("support"))->subject("NTP Pool account invitation")
      ->text_body($msg);

    NP::Email::sendmail($email);

    return $self->render_users($account);
}

sub render_user_invitations {
    my $self   = shift;
    my $invite = shift;

    my $user    = $self->user;
    my $invites = $user->pending_invites;
    if ($invite and !grep { $_->id == $invite->id } @$invites) {
        push @$invites, $invite;
    }

    $self->tpl_param('user',    $user);
    $self->tpl_param('invites', $invites);

    return OK, $self->evaluate_template('tpl/user/invites.html');
}

sub render_users {
    my ($self, $account) = @_;

    my $invites = NP::Model->account_invite->get_account_invites(
        query => [
            status     => {ne => 'accepted'},
            account_id => $account->id,
        ],
        sort_by => 'created_on desc'
    );

    $self->tpl_param('invites', $invites);
    $self->tpl_param('users',   scalar $account->users);

    if ($self->user->is_staff) {
        my $logs = NP::Model->log->get_objects(
            query => [
                account_id => [$self->current_account->id],
                type       => ['invitation', 'account-users']
            ],
            sort_by => "created_on desc",
        );
        $self->tpl_param('logs', $logs);
    }

    return OK, $self->evaluate_template('tpl/account/team.html');
}

sub render_account_form {
    my ($self, $account) = @_;
    $self->tpl_param('account', $account);

    # Set monitor config for admin users
    if ($self->user->is_monitor_admin && $account) {
        warn "DEBUG: Setting monitor config for admin user, account ID: " . $account->id;
        warn "DEBUG: Account flags: " . ($account->flags || 'NULL');
        my $config = $self->account_monitor_config($account);
        warn "DEBUG: Monitor config data: " . Data::Dump::pp($config);
        $self->tpl_param('monitor_config', $config);
    }
    else {
        warn "DEBUG: NOT setting monitor config - is_monitor_admin: "
          . ($self->user->is_monitor_admin || 0)
          . ", has account: "
          . (defined $account ? 'yes' : 'no');
    }

    # todo: how do you end up here without an account?
    if ($self->user->is_staff && $self->current_account) {
        my $logs = NP::Model->log->get_objects(
            query   => [account_id => [$self->current_account->id],],
            sort_by => "created_on desc",
        );
        $self->tpl_param('logs', $logs);
    }

    return OK, $self->evaluate_template('tpl/account/form.html');
}

sub render_account_edit {
    my $self = shift;

    my $account_token = $self->req_param('a');
    my $account_id    = NP::Model::Account->token_id($account_token);
    my $account = $account_id ? NP::Model->account->fetch(id => $account_id) : undef;

    if ($account_token eq 'new') {
        $account = NP::Model->account->create(users => [$self->user]);
    }

    return 404 unless $account;
    return 403 unless $account->can_edit($self->user) or $account_token eq 'new';

    my $old = $account->get_data_hash;

    my %args = (public_profile => $self->req_param('public_profile') ? 1 : 0,);

    my $changed = 0;

    for my $f (qw(name organization_name organization_url url_slug public_profile)) {
        my $v = defined $args{$f} ? $args{$f} : $self->req_param($f);
        $v //= '';
        $v =~ s/^\s+//;
        $v =~ s/\s+$//;
        $v = undef if ($f eq 'url_slug' and $v eq '');
        if ($v ne $account->$f()) {
            $changed = 1;
            $account->$f($v);
        }
    }

    unless ($account->validate) {
        my $errors = $account->validation_errors;
        $self->tpl_param('errors', $errors);
        return $self->render_account_form($account);
    }

    if ($changed) {
        $account->save(changes_only => 1);

        NP::Model::Log->log_changes($self->user, "account", "update account",
            $account, $old);
    }

    return $self->render_account_form($account);
}

sub render_download {
    my ($self, $user) = @_;

    if ($self->request->uri
        =~ (m!^/manage/account/download/data/([^/]+)/([^/]+(\.tar\.gz|\.zip))$!))
    {
        my $traceid  = $1;
        my $filename = $2;
        return NOT_FOUND unless $traceid && $filename;
        warn "checking downloads for $traceid / $filename";
        my $tasks = NP::Model->user_task->get_user_tasks(
            query => [
                task    => 'download',
                user_id => $user->id,
                traceid => $traceid,
            ],
            sort_by => 'created_on desc'
        );
        return NOT_FOUND unless $tasks && @$tasks;
        my $task = $tasks->[0];
        return NOT_FOUND unless $task;
        my $task_filename = $task && $task->status->{Filename} or return NOT_FOUND;
        return NOT_FOUND unless $task_filename eq $filename;

        # warn "redirecting to fastly: ", $task->status->{URL};
        $self->request->header_out('Fastly-Follow' => '1');

        return $self->redirect($task->status->{URL}, 302);
    }

    $self->tpl_param('user', $user);

    my $requests = NP::Model->user_task->get_user_tasks(
        query => [
            task    => 'download',
            user_id => $user->id,
        ],
        sort_by => 'created_on desc'
    );

    $self->tpl_param('requests', $requests);

    if ($requests && grep { $_->status eq '' } @$requests) {
        $self->tpl_param('pending_requests', 1);
    }
    else {
        if ($self->request->method eq 'post') {
            my $task = NP::Model->user_task->create(
                user   => $user->id,
                task   => 'download',
                status => '',
            );
            $task->save;

            # to a GET request so reloading the page works
            return $self->redirect($self->manage_url('/manage/account/download'));
        }
    }
    return OK, $self->evaluate_template('tpl/user/download.html');
}

sub render_user_delete {
    my ($self, $user) = @_;

    my $tracer = NP::Tracing->tracer;
    my $span   = $tracer->create_span(
        name => "render_user_delete",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);

    # todo:
    #   if u= parameter, get user from id_token
    #   and check it's the current user; or an admin

    $self->tpl_param('user', $user);

    my $delete_ok = 1;

    # todo:
    # - check there are no active servers on the account
    # - or that there are an alternate user
    for my $a ($user->accounts) {
        my @users = grep { $_->id != $user->id && not $_->deletion_on } @{$a->users};
        next if @users;
        for my $s ($a->servers) {
            unless ($s->deletion_on) {
                warn "account has active servers";
                $delete_ok = 0;
                last;
            }
        }
        for my $v ($a->vendor_zones) {
            warn "account has vendor zones";
            $delete_ok = 0;
            last;
        }
        for my $m ($a->monitors) {
            unless ($m->status eq 'deleted') {
                warn "account has monitors";
                $delete_ok = 0;
                last;
            }
        }
    }

    $self->tpl_param('delete_available', $delete_ok);

    return OK, $self->evaluate_template('tpl/user/delete_confirmation.html')
      unless $delete_ok;

    if ($self->request->method eq 'post') {

        my $db  = NP::Model->db;
        my $txn = $db->begin_scoped_work;

        $user->deletion_on('now');
        $user->save;

        my $task = NP::Model->user_task->create(
            user       => $user->id,
            task       => 'delete',
            status     => '',
            execute_on => DateTime->now()->add(days => 7),
        );
        $task->save;

        $db->commit or die "could not mark user deleted";

        my $param = {
            user     => $user,
            trace_id => $span->context->hex_trace_id,
        };

        my $msg = Combust::Template->new->process('tpl/user/user_deletion_scheduled.txt',
            $param, {site => 'manage', config => $self->config});

        my $email =
          Email::Stuffer->from(NP::Email::address("sender"))
          ->reply_to(NP::Email::address("support"))
          ->subject("NTP Pool user deletion scheduled")->text_body($msg);

        $email->to($user->email);
        NP::Email::sendmail($email);

        return $self->redirect($self->manage_url('/manage/logout'));
    }

    return OK, $self->evaluate_template('tpl/user/delete_confirmation.html');
}

sub render_monitor_config_form {
    my ($self, $account) = @_;

    warn "DEBUG: render_monitor_config_form called for account " . $account->id;

    # Check if this is a cancel request
    if ($self->request->header('X-Cancel')) {
        warn "DEBUG: Cancel request detected, returning display template";
        return $self->render_monitor_config_display($account);
    }

    # This method returns the monitor config form for HTMX requests
    my $config = $self->account_monitor_config($account);
    warn "DEBUG: Form config data: " . Data::Dump::pp($config);
    $self->tpl_param('monitor_config', $config);
    $self->tpl_param('account',        $account);

    warn "DEBUG: About to render monitor_config_edit_form.html template";
    return OK, $self->evaluate_template('tpl/account/monitor_config_edit_form.html');
}

sub render_monitor_config_update {
    my ($self, $account) = @_;

    # Debug: Show all form parameters
    warn "DEBUG: All form parameters: " . Data::Dump::pp($self->request->param);
    warn "DEBUG: monitor_enabled param: "
      . ($self->req_param('monitor_enabled') || 'UNDEF');
    warn "DEBUG: monitor_limit param: " . ($self->req_param('monitor_limit') || 'UNDEF');
    warn "DEBUG: monitors_per_server param: "
      . ($self->req_param('monitors_per_server') || 'UNDEF');

    my %update_data = ();

    # Process form parameters
    # Always include monitor_enabled since checkboxes don't send unchecked values
    # API expects boolean values, not integers
    $update_data{monitor_enabled} =
      $self->req_param('monitor_enabled') ? JSON::XS::true : JSON::XS::false;

    if (defined $self->req_param('monitor_limit')) {
        my $limit = $self->req_param('monitor_limit');
        if ($limit =~ /^\-?\d+$/) {
            $update_data{monitor_limit} = $limit;
        }
    }

    if (defined $self->req_param('monitors_per_server')) {
        my $per_server = $self->req_param('monitors_per_server');
        if ($per_server =~ /^\d+$/ && $per_server > 0) {
            $update_data{monitors_per_server_limit} = $per_server;
        }
    }

    # Call internal API to update account flags
    warn "DEBUG: Update data being sent: " . Data::Dump::pp(\%update_data);
    for my $k (qw(monitor_limit monitors_per_server_limit)) {
        $update_data{$k} += 0 if defined $update_data{$k};
    }

    my $json_data = $json->encode(\%update_data);
    warn "DEBUG: JSON data being sent: $json_data";

    my $data = int_api(
        'patch',
        'monitor/admin/account-config',
        {   a    => $account->id_token,
            user => $self->plain_cookie($self->user_cookie_name),
            data => $json_data,
        },
        $self->_get_request_context()
    );

    my $updated_account;
    if ($data->{code} == 200) {

        # Success - refresh account data and clear cache
        my $cache_key = '_account_monitor_config_' . $account->id;
        delete $self->{$cache_key};

        # Reload account from database to get updated flags
        $updated_account = NP::Model->account->fetch(id => $account->id);
        if ($updated_account) {

            # Update the cached account
            $self->{_current_account} = $updated_account;
        }

        $self->tpl_param('success', 'Monitor configuration updated successfully');
    }
    elsif ($data->{code} == 403) {
        $self->tpl_param('error', 'Access denied - insufficient privileges');
    }
    elsif ($data->{code} == 400) {
        $self->tpl_param('error',
            'Invalid request - ' . ($data->{message} || 'bad request'));
    }
    else {
        warn "Monitor config update API error: "
          . ($data->{status_line} || 'unknown error');
        $self->tpl_param('error',
            'Unable to update monitor configuration - please try again');
    }

    return $self->render_monitor_config_display($updated_account || $account);
}

sub render_monitor_config_display {
    my ($self, $account) = @_;

    # This method returns the monitor config display section for HTMX updates
    my $config = $self->account_monitor_config($account);
    $self->tpl_param('monitor_config', $config);
    $self->tpl_param('account',        $account);

    # Use clean template for HTMX responses (no debug sections)
    return OK, $self->evaluate_template('tpl/account/monitor_config_display_clean.html');
}

1;
