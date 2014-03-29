package NP::DB::ConventionManager;
use strict;

use base qw(Rose::DB::Object::ConventionManager);

use Rose::DB::Object::Metadata;

Rose::DB::Object::Metadata->convention_manager_classes
    (
     Rose::DB::Object::Metadata->convention_manager_classes,
     default => __PACKAGE__,
     );

my %not_a_map_table;
@not_a_map_table{qw(
   log_scores
   server_scores
   vendor_zones
   dns_roots
)} = ();

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

sub auto_relationship_name_one_to_many {
    my ($self, $table, $class) = @_;
    if ($self->meta->table eq 'users') {
        return "servers_all" if $table eq 'servers';
    }
    $self->SUPER::auto_relationship_name_one_to_many($table, $class);
}

sub xxauto_relationship {
    warn Data::Dumper->Dump([\@_], [qw(_)]);
    die;
    shift->SUPER::auto_relationship(@_);
}

1;
