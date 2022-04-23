package NP::DB::ConventionManager;
use strict;

use base qw(Rose::DB::Object::ConventionManager);

use Rose::DB::Object::Metadata;

Rose::DB::Object::Metadata->convention_manager_classes(
    Rose::DB::Object::Metadata->convention_manager_classes,
    default => __PACKAGE__,);

my %not_a_map_table;
@not_a_map_table{
    qw(
      log_scores
      server_scores
      vendor_zones
      dns_roots
    )
} = ();

sub looks_like_map_table {
    my ($self, $table) = @_;
    my $r = $self->SUPER::looks_like_map_table($table) && !exists $not_a_map_table{$table};
    return $r;
}

sub plural_to_singular {
    my ($self, $word) = @_;

    if ($word eq "log_status") {
        return $word;
    }
    else {
        $self->SUPER::plural_to_singular($word);
    }
}

sub auto_column_method_name {
    my $self = shift;
    my ($type, $column, $name, $object_class) = @_;

    if ($object_class =~ m/::Monitor/ and $name eq 'ip') {
        return '_ip';
    }

    return $self->SUPER::auto_column_method_name(@_);
}

sub auto_relationship_name_one_to_many {
    my ($self, $table, $class) = @_;
    if ($self->meta->table eq 'accounts') {
        return "servers_all" if $table eq 'servers';
        return "invites"     if $table eq 'account_invites';
    }
    $self->SUPER::auto_relationship_name_one_to_many($table, $class);
}

sub xxauto_relationship {
    warn Data::Dumper->Dump([\@_], [qw(_)]);
    die;
    shift->SUPER::auto_relationship(@_);
}

1;
