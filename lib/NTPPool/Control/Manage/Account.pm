package NTPPool::Control::Manage::Account;
use strict;
use NTPPool::Control::Manage;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);

sub manage_dispatch {
    my $self = shift;

    my $account;
    if (($self->req_param('a') || '') eq 'new') {
        return 403 unless $self->check_auth_token;
        $account = NP::Model->account->create(users => [ $self->user ]);
    }

    $account = $self->current_account unless $account;

    unless ($account) {
        # TODO: check for invitations and show "accept invitations screen"...
        $account = NP::Model->account->create(users => [ $self->user ]);
        $account->name($self->user->name);
        NP::Model::Log->log_changes($self->user, "account", "account created", $account);
        $account->save();
    }

    # check access
    return $self->redirect("/manage/")
        unless (
            $account->id == 0
            or $account->can_edit($self->user)
        );

    if ($self->request->uri =~ m!^/manage/account$!) {
        return $self->render_account_edit
            if ($self->request->method eq 'post' and !$self->req_param('new_form'));
        return $self->render_account_form($account);
    } elsif ($self->request->uri =~ m!^/manage/account/users$!) {
        return $self->render_users($account);
    }

    return NOT_FOUND;
}

sub render_users {
    my ($self, $account) = @_;
    return $self->_render_users($account);
}


sub render_account_form {
    my ($self, $account) = @_;
    $self->tpl_param('account', $account);
    return OK, $self->evaluate_template('tpl/account/form.html');
}

sub render_account_edit {
    my $self = shift;

    my $account_token = $self->req_param('a');
    my $account_id = NP::Model::Account->token_id($account_token);
    my $account = $account_id ? NP::Model->account->fetch(id => $account_id) : undef;

    if ($account_token eq 'new') {
        $account = NP::Model->account->create(users => [ $self->user ]);
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

    NP::Model::Log->log_changes($self->user, "account", "update account", $account, $old);

    return $self->render_account_form($account);
}


1;
