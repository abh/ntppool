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
    if (($self->req_param('a') || '') eq 'new') {
        return 403 unless $self->check_auth_token;
        $account = NP::Model->account->create(users => [$self->user]);
    }

    $account = $self->current_account unless $account;

    unless ($account) {
        # TODO: check for invitations and show "accept invitations screen"...
        $account = NP::Model->account->create(users => [$self->user]);
        $account->name($self->user->name);
        NP::Model::Log->log_changes($self->user, "account", "account created",
            $account);
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
    elsif ($self->request->uri =~ m!^/manage/account/invite/!) {
        return $self->handle_invitation;
    }
    elsif ($self->request->uri =~ m!^/manage/account/team$!) {
        return $self->render_users_invite($account, $self->req_param('invite_email'))
          if ($self->request->method eq 'post'
            and ($self->req_param('invite_email')));

        if ($account->can_edit($self->user) and $self->user->is_staff) {
            return $self->remove_user_from_account($account, $self->req_param('user_id'))
                if ($self->request->method eq 'post'
                    and ($self->req_param('user_id')));
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

    NP::Model::Log->log_changes(
        $self->user,
        "account-user",
        sprintf("Removed user %s (%d)", $user->email, $user->id),
        $account,
    );

    @$users = grep { $_->id != $user_id } @$users;
    $account->users($users);
    $account->save();

    $self->render_users($account);
}

sub handle_invitation {
    my $self = shift;

    my ($code) = ($self->request->path =~ m{^/manage/account/invite/([^/]+)});
    warn "CODE: $code";
    return 404 unless $code;

    my $db = NP::Model->db;
    my $txn = $db->begin_scoped_work;

    my $invite = NP::Model->account_invite->fetch(code => $code);
    return 404 unless $invite;

    warn "got invite: ", $invite->id if $invite;

    my $error;

    if ($invite->status ne "pending") {
        return $self->render_invite_error("Invitation code has been used or expired");
    }

    warn "ADDING ", $self->user->id, " to account ", $invite->account->id;

    my $user = $self->user;

    $invite->status('accepted');
    $invite->user($user->id);

    $invite->account->add_users([$user->id])
      or return $self->render_invite_error("Error adding user to account");

    $invite->save or return $self->render_invite_error("Error saving invite update");

    $invite->account->save
      or return $self->render_invite_error("Error saving database update");

    $db->commit or return $self->render_invite_error("database commit error");

    return $self->redirect(
        $self->manage_url("/manage/account/team", {a => $self->current_account->id_token}));
}

sub render_invite_error {
    my $self = shift;
    my $error = shift;
    $self->tpl_param('invite_error', $error);
    return OK, $self->evaluate_template('tpl/account/invite_error.html');
}

sub render_users_invite {
    my ($self, $account, $email) = @_;

    my %errors = ();

    if (grep { lc $_->email eq lc $email } $account->users) {
        $errors{invite_email} = "User is already added to this account";
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
        email   => $email,
        status  => 'pending',
        sent_by => $self->user->id,
        code    => $code,
    );
    $invite->expires_on(DateTime->now()->add(hours => 49));
    if ($invite->status eq 'expired') {
        $invite->status('pending');
    }
    $invite->save;

    my $param = {invite => $invite,};

    my $tpl = Combust::Template->new;
    my $msg = $tpl->process('tpl/account_invite.txt',
        $param, {site => 'manage', config => $self->config});

    # todo: if there's a vendor zone, use the vendor address
    # for the sender?

    my $email =
      Email::Stuffer->from(NP::Email::address("sender"))->to($email)
      ->reply_to(NP::Email::address("support"))->subject("NTP Pool account invitation")
      ->text_body($msg);

    NP::Email::sendmail($email);

    return $self->render_users($account);

}

sub render_users {
    my ($self, $account) = @_;

    my $invites = NP::Model->account_invite->get_account_invites(
        query   => [status => {ne => 'accepted'},
                    account_id => $account->id,
                   ],
        sort_by => 'created_on desc'
    );

    $self->tpl_param('invites', $invites);
    $self->tpl_param('users', scalar $account->users);

    return OK, $self->evaluate_template('tpl/account/team.html');
}

sub render_account_form {
    my ($self, $account) = @_;
    $self->tpl_param('account', $account);
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

    for my $f (qw(name organization_name organization_url url_slug)) {
        warn "stting $f to [", ($self->req_param($f) || ''), "]";
        my $v = $self->req_param($f) || '';
        $v =~ s/^\s+//;
        $v =~ s/\s+$//;
        $v = undef if ($f eq 'url_slug' and $v eq '');
        $account->$f($v);
    }
    $account->public_profile($self->req_param('public_profile') ? 1 : 0);

    unless ($account->validate) {
        my $errors = $account->validation_errors;
        $self->tpl_param('errors', $errors);
        return $self->render_account_form($account);
    }

    $account->save;

    NP::Model::Log->log_changes($self->user, "account", "update account",
        $account, $old);

    return $self->render_account_form($account);
}

1;
