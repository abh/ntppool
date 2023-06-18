package NTPPool::Control::Manage::Account;
use strict;
use NTPPool::Control::Manage;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);
use Math::BaseCalc ();
use Math::Random::Secure qw(irand);
use Combust::Template;
use NP::Email ();

sub manage_dispatch {
    my $self = shift;

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
            warn "has no account and pending invites...";
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
      Email::Stuffer->from(NP::Email::address("sender"))->reply_to(NP::Email::address("support"))
      ->subject("NTP Pool account change")->text_body($msg);

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
      $tpl->process('tpl/account_invite.txt', $param, {site => 'manage', config => $self->config});

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
    my $account       = $account_id ? NP::Model->account->fetch(id => $account_id) : undef;

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

        NP::Model::Log->log_changes($self->user, "account", "update account", $account, $old);
    }

    return $self->render_account_form($account);
}

1;
