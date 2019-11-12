package NP::DB::Scaffold;
use strict;
use base qw(Combust::RoseDB::Scaffold);

sub db_model_class {
    my ($self, $db) = @_;
    die "unknown database [$db]" unless $db eq 'ntppool';
    "NP::Model";
}

sub convention_manager {
    'NP::DB::ConventionManager';
}

my %json_fields = (
    log_scores => 'attributes',
    monitors => 'config',
    system_settings => 'value',
    logs => 'changes',
);

sub json_columns {
    my $self = shift;
    my $meta = shift;
    my $cols = $json_fields{$meta->table} or return;

    my @cols = ref($cols) ? @$cols : ($cols);

    return grep { $meta->column($_) } @cols;
}

sub filter_tables { # Return 0 to exclude a table
  my $self  = shift;
  my $db    = shift;
  my $table = shift;

  return 0 if $table =~ m/ log_scores_archive_status /ix;
  return $self->SUPER::filter_tables($db, $table);
}

1;
