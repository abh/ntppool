package NTPPool::Control::Manage::Account;
use strict;
use NTPPool::Control::Manage;
use base              qw(NTPPool::Control::Manage);
use Combust::Constant qw(OK NOT_FOUND SERVER_ERROR);
use NP::IntAPI        qw(int_api);
use NP::CAPI::Account qw(
    get_account_users get_user_accounts get_account_invites
    create_account get_account update_account remove_user_from_account create_user_task
    list_user_tasks get_user_task
    check_user_deletion_eligibility
    schedule_account_deletion cancel_account_deletion
    create_account_invite accept_account_invite resend_account_invite
);
use NP::CAPI::User qw(get_user schedule_user_deletion);
use DateTime;
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

sub _account_users {
    my ($self, $account) = @_;
    my $cache_key = '_account_users_' . $account->{account_id};
    return $self->{$cache_key} if exists $self->{$cache_key};

    my $result = get_account_users(
        $self->api_auth_params,
        account => $account->{id_token},
    );

    return $self->{$cache_key} = [] if $result->{error};

    # ✅ GOOD: Return API hashrefs directly (no ORM objects!)
    return $self->{$cache_key} = $result->{data}{users} || [];
}

sub _user_accounts {
    my ($self, $user) = @_;
    my $cache_key = '_user_accounts_' . $user->{user_id};
    return $self->{$cache_key} if exists $self->{$cache_key};

    my $result = get_user_accounts(
        $self->api_auth_params,
    );

    return $self->{$cache_key} = [] if $result->{error};

    # ✅ GOOD: Return API hashrefs directly (no ORM objects!)
    return $self->{$cache_key} = $result->{data}{accounts} || [];
}

sub _account_invites {
    my ($self, $account) = @_;
    my $cache_key = '_account_invites_' . $account->{account_id};
    return $self->{$cache_key} if exists $self->{$cache_key};

    my $result = get_account_invites(
        $self->api_auth_params,
        account  => $account->{id_token},
        for_user => JSON::XS::false,
    );

    return $self->{$cache_key} = [] if $result->{error};

    # ✅ GOOD: Return API hashrefs directly (no ORM objects!)
    return $self->{$cache_key} = $result->{data}{invites} || [];
}

sub _user_invites {
    my ($self, $user) = @_;
    my $cache_key = '_user_invites_' . $user->{user_id};
    return $self->{$cache_key} if exists $self->{$cache_key};

    my $result = get_account_invites(
        $self->api_auth_params,
        for_user => JSON::XS::true,
    );

    return $self->{$cache_key} = [] if $result->{error};

    # ✅ GOOD: Return API hashrefs directly (no ORM objects!)
    return $self->{$cache_key} = $result->{data}{invites} || [];
}

sub _create_account {
    my ($self, $name) = @_;

    $name ||= $self->user->{name} || 'My Account';

    my $data = create_account(
        $self->api_auth_params,
        name => $name,
    );

    if ($data->{error}) {
        warn "Failed to create account via API: " . $data->{error};
        warn "Trace ID: " . $data->{trace_id} if $data->{trace_id};
        return undef;
    }

    return $data->{data}{account};
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

        $account = $self->_create_account();
        unless ($account) {
            $self->tpl_param('error', 'Failed to create account. Please try again.');
            return $self->redirect("/manage/");
        }
    }

    $account = $self->current_account unless $account;

    unless ($account) {
        # A non-logged-in request can reach here with a truthy-but-invalid
        # user stub (validate_session returns valid:false at HTTP 200); send
        # those to login rather than an account error.
        return $self->login unless $self->is_logged_in;

        # The Go API auto-creates an account at login when the user has none
        # and no pending invitations. So a logged-in user with no account
        # should only get here if they have an invitation to act on...
        my $invites = $self->_user_invites($self->user);
        if ($invites && @$invites) {
            return $self->redirect("/manage/account/invites/");
        }

        # ...otherwise this is an unexpected backend state (e.g. the API
        # returned no account when one should exist). Surface it as an error
        # with the trace ID rather than a misleading "create an account" page.
        warn "no account and no invites for logged-in user "
          . ($self->user->{id_token} || '?');
        $self->tpl_param('error',
            'We could not load your account. Please try again; if this keeps happening, contact support with the trace ID below.'
        );
        return SERVER_ERROR, $self->evaluate_template('tpl/user/account_error.html');
    }

    # check access
    # Note: Account hashrefs from current_account() include permissions
    return $self->redirect("/manage/")
      unless ($account->{account_id} == 0
          or $account->{permissions}{can_edit});

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
        return 403 unless $self->user_is_monitor_admin;
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
        if ($self->request->method eq 'post' and $account->{permissions}{can_edit}) {
            return $self->render_users_invite($account, $self->req_param('invite_email'))
              if $self->req_param('invite_email');

            my $delete_user_id = $self->req_param('user_id');
            if ($delete_user_id
                and ($self->user_is_staff or $self->user->{user_id} != $delete_user_id))
            {
                return $self->_remove_user_from_account($account, $delete_user_id);
            }
        }
        return $self->render_users($account);
    }
    elsif ($self->request->uri =~ m!^/manage/account/download(/data/.*)?$!) {
        return $self->render_download($self->user);
    }
    elsif ($self->request->uri =~ m!^/manage/account/delete$!) {
        my $self_token     = $self->user->{id_token};
        my $target_token   = $self_token;
        my $is_self        = 1;
        if (my $u_token = $self->req_param('u')) {
            if ($u_token ne $self_token) {
                return 403 unless $self->user_is_staff;

                my $lookup = get_user(
                    $self->api_auth_params,
                    id_token => $u_token,
                );
                return NOT_FOUND if $lookup->{error};
                return NOT_FOUND unless $lookup->{data}{user};

                $target_token = $u_token;
                $is_self      = 0;
            }
        }
        return $self->render_user_delete($target_token, $is_self);
    }
    elsif ($self->request->uri =~ m!^/manage/account/dissolve$!) {
        return 403 unless $self->user_is_staff;
        return $self->render_account_dissolve($account);
    }

    return NOT_FOUND;
}

sub _remove_user_from_account {
    my ($self, $account, $user_id) = @_;
    my $users = $self->_account_users($account);
    my ($user) = grep { $_->{user_id} == $user_id } @$users;
    return $self->render_users($account)
      unless $user;

    my $data = remove_user_from_account(
        $self->api_auth_params,
        account  => $account->{id_token},
        id_token => $user->{id_token},
    );

    if ($data->{error}) {
        warn "Failed to remove user from account via API: " . $data->{error};
        warn "Trace ID: " . $data->{trace_id} if $data->{trace_id};
        $self->tpl_param('error', 'Failed to remove user. Please try again.');
        return $self->render_users($account);
    }

# Note: Logging moved to Go API (RemoveUserFromAccount service)
# During PostgreSQL migration, cannot log to MySQL with account_id that only exists in PostgreSQL

    # Note: No need to reload during PostgreSQL migration
    # Account data already in hashref from API

    my $param = {
        account      => $account,
        user_removed => $user,
    };

    my $msg = Combust::Template->new->process('tpl/account/account_user_removed.txt',
        $param, {site => 'manage', config => $self->config});

    my $email =
      Email::Stuffer->from(NP::Email::address("sender"))
      ->reply_to(NP::Email::address("support"))
      ->subject("NTP Pool account change")
      ->text_body($msg);

    $email->to($user->{email});
    my @cc = grep { $_->{user_id} != $user_id } @$users;
    if (@cc) {
        $email->cc(map { $_->{email} } @cc);
    }

    NP::Email::sendmail($email);

    $self->render_users($account);
}

sub handle_invitation {
    my $self = shift;

    my ($code) = ($self->request->path =~ m{^/manage/account/invite/([^/]+)});
    warn "CODE: $code -- method: ", $self->request->method;
    return 404 unless $code;

    # on post requests the auth token has already been checked, so if it's
    # something else we show a confirmation page (GET request).
    if ($self->request->method ne 'post') {

        # For GET request, we need to fetch the invite to show confirmation page
        # Use get_account_invites to check if this code exists and get details
        my $invites_result = get_account_invites(
            $self->api_auth_params,
            for_user => 1,                     # Get invites for the current user
        );

        if ($invites_result->{error}) {
            return 404;
        }

        # Find the invite with matching code
        my $invite =
          (grep { $_->{code} eq $code } @{$invites_result->{data}{invites} // []})[0];
        return 404 unless $invite;

        if ($invite->{status} ne "pending") {
            return $self->render_invite_error("Invitation code has been used or expired");
        }

        return $self->render_user_invitations($invite);
    }

    # POST request - accept the invitation via Go API
    # The API handles transaction, adding user to account, and logging
    my $result = accept_account_invite(
        $self->api_auth_params,
        code => $code,
    );

    if ($result->{error}) {

        # Map CAPI error codes to user-friendly messages
        my $code_type = $result->{connect_code} // 'internal';

        if ($code_type eq 'not_found') {
            return $self->render_invite_error("Invitation not found");
        }
        elsif ($code_type eq 'failed_precondition') {
            return $self->render_invite_error("Invitation code has been used or expired");
        }
        elsif ($code_type eq 'permission_denied') {
            return $self->render_invite_error("This invitation is not for you");
        }
        elsif ($code_type eq 'unauthenticated') {
            return $self->render_invite_error(
                "You must be logged in to accept invitations");
        }
        else {
            return $self->render_invite_error(
                "Error accepting invitation: " . ($result->{error} // 'Unknown error'));
        }
    }

    # Success - user has been added to account
    my $account_id = $result->{data}{account_id};

    # we accepted an invite for a new user that didn't have a account yet, so
    # just 'start over' ...
    unless ($self->current_account) {
        return $self->redirect($self->manage_url("/manage"));
    }

    # Fetch the account to get its id_token for the redirect
    my $account_result = get_account(
        $self->api_auth_params,
        id => $account_id,
    );

    if ($account_result->{error}) {

        # Fallback to manage page if we can't get account details
        return $self->redirect($self->manage_url("/manage"));
    }

    # go to the team page for the "new" account
    return $self->redirect(
        $self->manage_url(
            "/manage/account/team", {a => $account_result->{data}{account}{id_token}}
        )
    );
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

    # Create invitation via Go API
    # The API handles all validation, email sending, and limits
    my $result = create_account_invite(
        $self->api_auth_params,
        account => $account->{id_token},
        email   => $email_address,
    );

    if ($result->{error}) {

        # Map CAPI error codes to user-friendly messages
        my $code = $result->{connect_code} // 'internal';

        if ($code eq 'already_exists') {
            $errors{invite_email} = "User is already on this account";
        }
        elsif ($code eq 'resource_exhausted') {
            $errors{invite_email} = 'Too many recent account invitations (limit: 5)';
        }
        elsif ($code eq 'permission_denied') {
            $errors{invite_email} =
              "You don't have permission to invite users to this account";
        }
        elsif ($code eq 'invalid_argument') {
            $errors{invite_email} = "Invalid email address";
        }
        else {
            $errors{invite_email} =
              "Failed to create invitation: " . ($result->{error} // 'Unknown error');
        }

        $self->tpl_param(errors => \%errors);
        return $self->render_users($account);
    }

    # Success - invitation created and email sent by Go API
    # Note: Logging is handled by Go API (audit log)
    return $self->render_users($account);
}

sub render_user_invitations {
    my $self   = shift;
    my $invite = shift;

    my $user    = $self->user;
    my $invites = $self->_user_invites($user);

    # Note: $invite here is still an ORM object from the invitation flow
    # Only compare if it's an ORM object (has ->id method)
    if ($invite && ref($invite) !~ /HASH/ && !grep { $_->{invite_id} == $invite->id }
        @$invites)
    {
        push @$invites, $invite;
    }

    $self->tpl_param('user',    $user);
    $self->tpl_param('invites', $invites);

    return OK, $self->evaluate_template('tpl/user/invites.html');
}

sub render_users {
    my ($self, $account) = @_;

    my $invites = $self->_account_invites($account);
    my $users   = $self->_account_users($account);

    $self->tpl_param('invites', $invites);
    $self->tpl_param('users',   $users);

    if ($self->user_is_staff) {

      # Use new AuditService API (eliminates N+1 query problem: ~150 queries → ~5 queries)
        my $logs = $self->account_logs(types => ['invitation', 'account-users'],);
        $self->tpl_param('logs', $logs);
    }

    return OK, $self->evaluate_template('tpl/account/team.html');
}

sub render_account_form {
    my ($self, $account) = @_;
    $self->tpl_param('account', $account);

    # Set monitor config for admin users
    if ($self->user_is_monitor_admin && $account) {
        warn "DEBUG: Setting monitor config for admin user, account ID: "
          . $account->{account_id};
        warn "DEBUG: Account flags: " . ($account->{flags} || 'NULL');
        my $config = $self->account_monitor_config($account);
        warn "DEBUG: Monitor config data: " . Data::Dump::pp($config);
        $self->tpl_param('monitor_config', $config);
    }
    else {
        warn "DEBUG: NOT setting monitor config - is_monitor_admin: "
          . ($self->user_is_monitor_admin || 0)
          . ", has account: "
          . (defined $account ? 'yes' : 'no');
    }

    # todo: how do you end up here without an account?
    if ($self->user_is_staff && $self->current_account) {

      # Use new AuditService API (eliminates N+1 query problem: ~150 queries → ~5 queries)
        my $logs = $self->account_logs();
        $self->tpl_param('logs', $logs);
    }

    return OK, $self->evaluate_template('tpl/account/form.html');
}

sub render_account_edit {
    my $self = shift;

    my $id_token = $self->req_param('a');

    # Handle creating a new account
    if ($id_token eq 'new') {
        my $account = $self->_create_account($self->req_param('name'));
        unless ($account) {
            $self->tpl_param('error', 'Failed to create account. Please try again.');
            return $self->render_account_form(undef);
        }
        return $self->render_account_form($account);
    }

    # During PostgreSQL migration, we can't decode tokens or fetch from MySQL
    # Instead, we'll get the account from the API after updates
    return 404 unless $id_token;

    # Get account from API to populate the form before updates
    my $result = get_account(
        $self->api_auth_params,
        account => $id_token,
    );

    if ($result->{error}) {
        warn "Failed to get account via API: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
        return 404;
    }

    my $account_obj = $result->{data}{account};
    my $account     = $account_obj;

    my $old = {%$account};    # Shallow copy for logging

    my %update_data = ();
    for my $f (qw(name organization_name organization_url url_slug)) {
        my $v = $self->req_param($f) // '';
        $v =~ s/^\s+//;
        $v =~ s/\s+$//;
        $v = undef if ($f eq 'url_slug' and $v eq '');
        if (defined($v) && $v ne ($account->{$f} // '')) {
            $update_data{$f} = $v;
        }
    }

    # Handle boolean separately
    my $public_profile =
      $self->req_param('public_profile') ? JSON::XS::true : JSON::XS::false;
    if ($public_profile
        != ($account->{public_profile} ? JSON::XS::true : JSON::XS::false))
    {
        $update_data{public_profile} = $public_profile;
    }

    if (%update_data) {
        my $data = update_account(
            $self->api_auth_params,
            account => $account->{id_token},
            %update_data,
        );

        if ($data->{error}) {
            warn "Failed to update account via API: " . $data->{error};
            warn "Trace ID: " . $data->{trace_id} if $data->{trace_id};

            # Extract user-friendly error message if available
            my $error_msg =
              $data->{error} || 'Failed to update account. Please try again.';
            $self->tpl_param('error', $error_msg);
            return $self->render_account_form($account);
        }

        # Use the updated account returned by the API (no need for second call)
        $account_obj = $data->{data}{account};
        $account     = $account_obj;

# Note: Logging moved to Go API (UpdateAccount service)
# During PostgreSQL migration, cannot log to MySQL with account_id that only exists in PostgreSQL

        # Refresh account context so sidebar shows updated account name immediately
        # Without this, cached data persists and sidebar shows stale name until next page load
        $self->refresh_account_context();
    }

    return $self->render_account_form($account);
}

sub _format_task_for_template {
    my ($task) = @_;
    return unless $task;

    # Convert created_on_unix to formatted timestamp
    my $created_on = '';
    if ($task->{created_on_unix}) {
        my $dt = DateTime->from_epoch(epoch => $task->{created_on_unix});
        $created_on = $dt->ymd('-') . ' ' . $dt->hms(':');
    }

    return {
        id           => $task->{id},
        task         => $task->{task},
        status       => $task->{status},
        traceid      => $task->{traceid},
        created_on   => $created_on,
        download_url => $task->{download_url},
        status_url   => $task->{status_url},
        status_error => $task->{status_error},
    };
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

        my $result = get_user_task(
            $self->api_auth_params,
            traceid => $traceid,
        );

        return NOT_FOUND if $result->{error};
        my $task = $result->{data}{task};
        return NOT_FOUND unless $task && $task->{status_url};

        # Verify filename matches what's in the download_url
        return NOT_FOUND unless $task->{download_url} && $task->{download_url} =~ /\Q$filename\E$/;

        $self->request->header_out('Fastly-Follow' => '1');
        return $self->redirect($task->{status_url}, 302);
    }

    $self->tpl_param('user', $user);

    my $result = list_user_tasks(
        $self->api_auth_params,
        task_type => 'download',
    );

    my $requests = [];
    if (!$result->{error} && $result->{data}{tasks}) {
        $requests = [map { _format_task_for_template($_) } @{$result->{data}{tasks}}];
    }

    $self->tpl_param('requests', $requests);

    if (@$requests && grep { !$_->{status} } @$requests) {
        $self->tpl_param('pending_requests', 1);
    }
    else {
        if ($self->request->method eq 'post') {
            my $data = create_user_task(
                $self->api_auth_params,
                task_type => 'download',
                status    => '',
            );

            if ($data->{error}) {
                warn "Failed to create download task via API: " . $data->{error};
                warn "Trace ID: " . $data->{trace_id} if $data->{trace_id};
                $self->tpl_param('error',
                    'Failed to create download request. Please try again.');
                return OK, $self->evaluate_template('tpl/user/download.html');
            }

            # to a GET request so reloading the page works
            return $self->redirect($self->manage_url('/manage/account/download'));
        }
    }
    return OK, $self->evaluate_template('tpl/user/download.html');
}

sub render_user_delete {
    my ($self, $target_id_token, $is_self) = @_;

    my $tracer = NP::Tracing->tracer;
    my $span   = $tracer->create_span(
        name => "render_user_delete",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);

    # Fetch target user for template rendering. When acting on self, use the
    # already-loaded session user; otherwise look up the target via the API.
    my $user;
    if ($is_self) {
        $user = $self->user;
    }
    else {
        my $lookup = get_user(
            $self->api_auth_params,
            id_token => $target_id_token,
        );
        return NOT_FOUND if $lookup->{error};
        $user = $lookup->{data}{user} or return NOT_FOUND;
    }

    $self->tpl_param('user', $user);

    # Check deletion eligibility using new consolidated API.
    # Pass id_token only when targeting another user; the API treats the
    # caller as self when id_token is omitted.
    my $result = check_user_deletion_eligibility(
        $self->api_auth_params,
        ($is_self ? () : (id_token => $target_id_token)),
    );

    if ($result->{error}) {
        warn "CheckUserDeletionEligibility error: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
        $self->tpl_param('delete_available', 0);
        $self->tpl_param('delete_blockers',
            ["Error checking deletion eligibility: " . $result->{error}]);
        return OK, $self->evaluate_template('tpl/user/delete_confirmation.html');
    }

    my $eligibility = $result->{data};

    $self->tpl_param('delete_available', $eligibility->{can_delete});
    $self->tpl_param('delete_blockers',  $eligibility->{blockers})
      if @{$eligibility->{blockers} || []};

    return OK, $self->evaluate_template('tpl/user/delete_confirmation.html')
      unless $eligibility->{can_delete};

    if ($self->request->method eq 'post') {

        # Schedule deletion 7 days from now (minimum allowed by API)
        my $deletion_time = DateTime->now->add(days => 7);

        my $result = schedule_user_deletion(
            $self->api_auth_params,
            deletion_on_unix => $deletion_time->epoch,
            ($is_self ? () : (id_token => $target_id_token)),
        );

        if ($result->{error}) {
            warn "Failed to schedule user deletion: " . $result->{error};
            warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
            return $self->render_error(
                "Failed to schedule account deletion. Please try again.");
        }

        # Use the updated user data from API response
        my $updated_user = $result->{data}{user};

        # Create delete task via API (using same deletion time)
        my $data = create_user_task(
            $self->api_auth_params,
            task_type       => 'delete',
            status          => '',
            execute_on_unix => $deletion_time->epoch,
        );

        if ($data->{error}) {
            warn "Failed to create delete task via API: " . $data->{error};
            warn "Trace ID: " . $data->{trace_id} if $data->{trace_id};

            # Don't fail the deletion, just log the error
            # The user is already marked for deletion
        }

        my $param = {
            user     => $updated_user,
            trace_id => $span->context->hex_trace_id,
        };

        my $msg = Combust::Template->new->process('tpl/user/user_deletion_scheduled.txt',
            $param, {site => 'manage', config => $self->config});

        my $email =
          Email::Stuffer->from(NP::Email::address("sender"))
          ->reply_to(NP::Email::address("support"))
          ->subject("NTP Pool user deletion scheduled")
          ->text_body($msg);

        # Deletion-scheduled email goes to the target user, not the caller.
        $email->to($updated_user->{email});
        NP::Email::sendmail($email);

        if ($is_self) {
            return $self->redirect($self->manage_url('/manage/logout'));
        }

        $self->tpl_param('user', $updated_user);
        return OK, $self->evaluate_template('tpl/user/delete_scheduled.html');
    }

    return OK, $self->evaluate_template('tpl/user/delete_confirmation.html');
}

sub render_account_dissolve {
    my ($self, $account) = @_;

    my $tracer = NP::Tracing->tracer;
    my $span   = $tracer->create_span(
        name => "render_account_dissolve",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);

    $self->tpl_param('account', $account);

    # Cancel an already-scheduled deletion
    if ($self->request->method eq 'post' and $self->req_param('cancel')) {
        my $result = cancel_account_deletion(
            $self->api_auth_params,
            account_id_token => $account->{id_token},
        );

        if ($result->{error}) {
            warn "Failed to cancel account deletion: " . $result->{error};
            warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
            return $self->render_error(
                "Could not cancel scheduled deletion.");
        }

        return $self->redirect(
            $self->manage_url('/manage/account', {a => $account->{id_token}}));
    }

    # Schedule a deletion 7 days out
    if ($self->request->method eq 'post') {
        my $deletion_time = DateTime->now->add(days => 7);

        my $result = schedule_account_deletion(
            $self->api_auth_params,
            account_id_token => $account->{id_token},
            deletion_on_unix => $deletion_time->epoch,
        );

        if ($result->{error}) {
            warn "Failed to schedule account deletion: " . $result->{error};
            warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
            return $self->render_error(
                "Could not schedule deletion.");
        }

        my $data = $result->{data} || {};

        if ($data->{scheduled}) {
            return $self->redirect(
                $self->manage_url('/manage/account', {a => $account->{id_token}}));
        }

        # Blockers: surface them on the confirmation page. The API also
        # returns a structured details hashref but the blockers list already
        # carries the human-readable strings the template needs.
        $self->tpl_param('blockers', $data->{blockers} || []);
        $self->tpl_param('orphaned_emails',
            $data->{orphaned_user_emails} || []);

        return OK,
          $self->evaluate_template('tpl/account/dissolve_confirmation.html');
    }

    # GET: show pending state or scheduling form
    if ($account->{deletion_on}) {
        my $display = $account->{deletion_on};
        $display =~ s/T.*//;    # date-only display for RFC3339 input

        $self->tpl_param('pending',      1);
        $self->tpl_param('deletion_on',  $display);
    }

    return OK,
      $self->evaluate_template('tpl/account/dissolve_confirmation.html');
}

sub render_monitor_config_form {
    my ($self, $account) = @_;

    warn "DEBUG: render_monitor_config_form called for account " . $account->{account_id};

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
        {   a    => $account->{id_token},
            user => $self->plain_cookie($self->user_cookie_name),
            data => $json_data,
        },
        $self->_get_request_context()
    );

    my $updated_account;
    if ($data->{code} == 200) {

        # Success - refresh account data and clear cache
        my $cache_key = '_account_monitor_config_' . $account->{account_id};
        delete $self->{$cache_key};

        # Note: During PostgreSQL migration, can't reload from MySQL
        # Use the account hashref as-is
        $updated_account = $account;

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
