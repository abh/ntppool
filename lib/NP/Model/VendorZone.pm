package NP::Model::VendorZone;
use strict;
use NP::Util qw();

my %reserved_zone_names = map { $_ => 1 } qw(
  europe
  north-america
  south-america
  america
  asia
  africa

  root
  ntppool
  vendor
);

sub validate {
    my $vz     = shift;
    my $errors = {};
    unless ($vz->zone_name) {
        $errors->{zone_name} = 'A zone name is required.';
    }
    elsif (length $vz->zone_name < 4) {
        $errors->{zone_name} = 'The zone name must be 4 or more characters.';
    }

    if ($reserved_zone_names{$vz->zone_name}) {
        $errors->{zone_name} = 'That zone name is in use or reserved.';
    }

    {
        my $vz2 = NP::Model->vendor_zone->get_objects(query => [zone_name => $vz->zone_name]);
        if (@$vz2) {
            unless ($vz and grep { $vz->id == $_->id } @$vz2) {
                $errors->{zone_name} = 'That zone name is already used.';
            }
        }
    }

    for my $f (qw(contact_information device_count organization_name request_information)) {
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
    return 1 if $user->privileges->vendor_admin;
    return 1
      if $self->status eq 'New'
      and $user->id == $self->user_id;    # TODO: many<->many
    return 0;
}

sub can_view {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if $user->privileges->vendor_admin;
    return 1 if $user->id == $self->user_id;       # TODO: many<->many
    return 0;
}

sub contact_information_html { NP::Util::convert_to_html(shift->contact_information) }
sub request_information_html { NP::Util::convert_to_html(shift->request_information) }


1;
