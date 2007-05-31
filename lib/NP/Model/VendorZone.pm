package NP::Model::VendorZone;
use strict;
use HTML::Entities qw(encode_entities);

my %reserved_zone_names = map { $_ => 1 } 
  qw(
     europe
     north-america
     south-america
     america
     asia
     africa
  );

sub validate {
    my $vz = shift;
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

    if (my $vz2 = NP::Model->vendor_zone->fetch(zone_name => $vz->zone_name)) {
        unless ($vz and $vz->id == $vz2->id) {
            $errors->{zone_name} = 'That zone name is already used in an application.';
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
    return 1 if $user->username eq 'ask';    # TODO: "vendor admin" permission 
    return 1 if $self->status eq 'New'
        and $user->id == $self->user_id; # TODO: many<->many
    return 0;
}

sub can_view {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if $user->username eq 'ask';    # TODO: "vendor admin" permission 
    return 1 if $user->id == $self->user_id; # TODO: many<->many
    return 0;
}

sub contact_information_html { convert_to_html(shift->contact_information) }
sub request_information_html { convert_to_html(shift->request_information) }


sub convert_to_html {
    my $str = shift;

    encode_entities($str, '<>&"');  # how can we encode everything without messing up UTF8?
    $str =~ s!(https?://.+?)(\s|$)!<a href="$1">$1</a>$2!g;
                             $str =~ s!\n\s*[\n\s]+!<br/><br/>!g;
                             $str =~ s!\n!<br/>\n!g;

                             $str;
                         }

1;
