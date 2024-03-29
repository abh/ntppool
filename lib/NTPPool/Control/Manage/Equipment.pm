package NTPPool::Control::Manage::Equipment;
use strict;
use base qw(NTPPool::Control::Manage);
use Combust::Constant qw(OK NOT_FOUND);
use Sys::Hostname qw(hostname);

use NP::Model;

sub manage_dispatch {
    my $self = shift;

    return $self->render_form if $self->request->uri =~ m!^/manage/equipment/new$!;

    if ($self->request->uri =~ m!^/manage/equipment/application$!) {
        return $self->render_edit if ($self->request->method eq 'post');
        return $self->render_application($self->req_param('id'));
    }

    return $self->render_admin if $self->request->uri =~ m!^/manage/equipment/admin$!;

    return $self->redirect('/manage/equipment/new')
      unless @{$self->user->user_equipment_applications};
    return OK, $self->evaluate_template('tpl/equipment.html')
      if $self->request->uri =~ m!^/manage/equipment/?$!;
    return NOT_FOUND;
}

sub render_form {
    my $self = shift;
    my $ea   = shift;

    if (!$ea and $self->user_has_active_applications) {
        $self->redirect("/manage/equipment");
    }

    $self->tpl_param('ea', $ea) if $ea;
    return OK, $self->evaluate_template('tpl/equipment/form.html');
}

sub render_application {
    my ($self, $id, $mode) = @_;

    return $self->redirect('/manage/equipment') unless $id;

    $mode ||= '';

    my $ea = NP::Model->user_equipment_application->fetch(id => $id);

    return $self->redirect("/manage/equipment") unless $ea and $ea->can_view($self->user);

    $self->tpl_param('ea', $ea);

    return OK, $self->evaluate_template('tpl/equipment/show.html')
      if $mode eq 'show'
      or !$ea->can_edit($self->user);

    return OK, $self->evaluate_template('tpl/equipment/form.html');
}

sub render_edit {
    my $self = shift;

    my $id = $self->req_param('id');
    $id = 0 if $id and $id eq 'new';

    my $ea = $id ? NP::Model->user_equipment_application->fetch(id => $id) : undef;

    if ($ea) {
        return $self->render_application($ea->id) unless $ea->can_edit($self->user);

        if (my $status = $self->req_param('status_change')) {
            if ($ea->status eq 'New' and $status eq 'Pending') {
                $ea->status($status);
                $ea->save;
                $self->tpl_param(message => "Your application has been submitted, thanks!");
            }
        }
        else {
            for my $f (qw(application contact_information)) {
                $ea->$f($self->req_param($f) || '');
            }
        }
    }
    else {

        if ($self->user_has_active_applications) {
            $self->redirect("/manage/equipment");
        }

        $ea = NP::Model->user_equipment_application->create(
            user_id => $self->user->id,
            (map { $_ => ($self->req_param($_) || '') } qw(application contact_information))
        );
    }

    unless ($ea->validate) {
        my $errors = $ea->validation_errors;
        $self->tpl_param('errors', $errors);
        return $self->render_form($ea);
    }

    $ea->save;

    return $self->render_application($ea->id, 'show');

}

sub user_has_active_applications {
    my $self = shift;

    my $count =
      NP::Model->user_equipment_application->get_user_equipment_applications_count(
          query => [user_id => $self->user->id]);
    $count;
}

1;
