package NP::DB::ConventionManager;
use strict;

use base qw(Rose::DB::Object::ConventionManager);

use Rose::DB::Object::Metadata;

Rose::DB::Object::Metadata->convention_manager_classes
    (
     Rose::DB::Object::Metadata->convention_manager_classes,
     default => __PACKAGE__,
     );

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

#sub looks_like_map_table {
#    my ($self, $table) = @_;
#    $self->SUPER::looks_like_map_table($table) && $table !~ /^(user_privileges)/;
#}

1;
