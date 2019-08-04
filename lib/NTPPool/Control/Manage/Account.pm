package NTPPool::Control::Manage::Account;
use strict;
use NTPPool::Control::Manage;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND);

sub manage_dispatch {
    my $self = shift;

    if ($self->request->uri =~ m!^/manage/account$!) {
        my $account = $self->current_account;
        return $self->render_edit if ($self->request->method eq 'post');
        return $self->render_account($account);
    }

    return NOT_FOUND;
}

sub render_account {
    my ($self, $account) = @_;
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

    my $account_token = $self->req_param('a');
    my $account_id = NP::Model::Account->token_id($account_token);
    my $account = $account_id ? NP::Model->account->fetch(id => $account_id) : undef;

    if ($account_token eq 'new') {
        $account = NP::Model->account->create(users => [ $self->user ]);
    }

    return 404 unless $account;
    return 403 unless $account->can_edit($self->user) or $account_token eq 'new';

    for my $f (qw(name organization_name organization_url)) {
        $account->$f($self->req_param($f) || '');
    }

    warn "PP req: [", $self->req_param('public_profile'), "]";
    $account->public_profile($self->req_param('public_profile') ? 1 : 0);

    unless ($account->validate) {
        my $errors = $account->validation_errors;
        $self->tpl_param('errors', $errors);
        return $self->_render_form($account);
    }

    $account->save;

    return $self->render_account($account);
}


1;
