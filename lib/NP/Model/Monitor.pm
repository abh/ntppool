package NP::Model::Monitor;
use v5.32.0;
use warnings qw(all);
use NP::Model::TokenID;
use base qw(NP::Model::TokenID);
use NP::Vault;
use Net::IP;
use Carp qw(cluck);

sub token_key_config {
    return 'monitor_id_key';
}

sub token_prefix {
    return 'mon-';
}

sub insert {
    my $self = shift;
    $self->SUPER::insert(@_);
    $self->insert_token_id();
}

sub display_name {
    my $self = shift;

    if (my $name = $self->name) {
        return $name;
    }

    if (my $tls_name = $self->tls_name) {
        $tls_name =~ m/^([^.]+)/ and return "$1";
    }

    if (my $loc = $self->location) {
        return "$loc (" . $self->id_token . ")";
    }

    return $self->id_token;
}

sub status_color {
    my $self = shift;
    my $status = $self->status;
    return {
        pending => "primary",
        testing => "info",
        active  => "success",
        paused  => "secondary",
        deleted => "dark",
    }->{$status} || "secondary";
}


sub has_api_role {
    my $self = shift;
    my $role = $self->vault_role_id();
    return 1 if $role;
    return 0;
}

sub vault_role_id {
    my $self = shift;
    return unless $self->tls_name;
    my $role_id = NP::Vault::get_monitoring_role_id($self->tls_name);
    return $role_id || undef;
}

sub setup_vault_role {
    my $self    = shift;
    my $role_id = $self->vault_role_id;
    return $role_id if $role_id;
    if (NP::Vault::setup_monitoring_role($self->tls_name)) {
        return $self->vault_role_id;
    }
    else {
        return undef;
    }
}

sub setup_vault_secret {
    my $self = shift;
    my ($secret, $accessor) = NP::Vault::setup_monitoring_secret($self->tls_name);

    if ($accessor) {
        my @old =
          grep { $_ ne $accessor } NP::Vault::get_monitoring_secret_accessors($self->tls_name);
        for my $old (@old) {
            NP::Vault::delete_monitoring_secret_accessor($self->tls_name, $old);
        }
    }

    return ($secret, $accessor);
}

sub can_edit {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if $user->privileges->support_staff;
    return 1 if grep { $_->id == $user->id } $self->account->users;
    return 0;
}

sub ip {
    my $self = shift;
    if (@_) {
        my $s = $_[0];
        $s =~ s/\s+//g;
        my $ip         = Net::IP->new($s);
        my $ip_version = 'v' . $ip->version;
        $self->ip_version($ip_version);
        $_[0] = $ip->short;
    }
    return $self->_ip(@_);
}

sub validate {
    my $mon    = shift;
    my $errors = {};

    for my $f (qw(ip ip_version account_id)) {
        $errors->{$f} = 'Required field' unless $mon->$f and $mon->$f =~ m/\S/;
    }

    unless ($mon->location) {
        $errors->{location_code} = "Choose a location code";
    }

    $mon->{_validation_errors} = $errors;

    %$errors ? 0 : 1;
}

sub validation_errors {
    my $self = shift;
    $self->{_validation_errors} || {};
}

sub delete_monitor {
    my $self = shift;

    return unless $self->status eq 'deleted';

    NP::Model->server_score->delete_server_scores(where => [monitor_id => $self->id]);

    $self->api_key(undef);

    if ($self->tls_name) {
        NP::Vault::delete_monitoring_role($self->tls_name);
    }

}

1;
