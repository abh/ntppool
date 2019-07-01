package NTPPool::Control::Manage::Account;
use strict;
use NTPPool::Control::Manage;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);

sub manage_dispatch {
    my $self = shift;

    if ($self->request->uri =~ m!^/manage/account$!) {
        return $self->render_edit if ($self->request->method eq 'post');

        my $account_id = NP::Model::Account->token_id($self->req_param('a'));
        return $self->render_account($account_id);
    }

    return NOT_FOUND;
}


sub render_account {
    my ($self, $id) = @_;
    my $account = NP::Model->account->fetch(id => $id);
    return 404 unless $account;
    return $self->redirect("/manage/") unless $account and $account->can_edit($self->user);
    return $self->_render_form($account);
}

sub _render_form {
    my $self    = shift;
    my $account = shift;
    $self->tpl_param('account', $account);
    return OK, $self->evaluate_template('tpl/account/form.html');
}

sub render_edit {
    my $self = shift;

    my $id = $self->req_param('id');
    $id = 0 if $id and $id eq 'new';

    my $account = $id ? NP::Model->account->fetch(id => $id) : undef;
    return 404 unless $account;
    return 403 unless $account->can_edit($self->user);

    for my $f (qw(name organization_name organization_url)) {
        $account->$f($self->req_param($f) || '');
    }

    unless ($account->validate) {
        my $errors = $account->validation_errors;
        $self->tpl_param('errors', $errors);
        return $self->_render_form($account);
    }

    $account->save;

    return $self->render_account($account->id);
}


1;
