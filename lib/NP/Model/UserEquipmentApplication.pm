package NP::Model::UserEquipmentApplication;
use strict;
use NP::Util qw(convert_to_html);

sub validate {
    my $vz     = shift;
    my $errors = {};

    for my $f (qw(contact_information application)) {
        $errors->{$f} = 'Required field!' unless $vz->$f and $vz->$f =~ m/\S/;
    }

    $vz->{_validation_errors} = $errors;

    %$errors ? 0 : 1;
}

sub validation_errors {
    my $self = shift;
    $self->{_validation_errors} || {};
}

sub can_edit {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if $user->privileges->equipment_admin;
    return 1
      if $self->status eq 'New'
      and $user->id == $self->user_id;    # TODO: many<->many
    return 0;
}

sub can_view {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if $user->privileges->equipment_admin;
    return 1 if $user->id == $self->user_id;          # TODO: many<->many
    return 0;
}

sub contact_information_html { convert_to_html(shift->contact_information) }
sub application_html         { convert_to_html(shift->application) }


1;
