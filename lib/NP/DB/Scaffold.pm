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
);

sub json_columns {
    my $self = shift;
    my $meta = shift;
    my $cols = $json_fields{$meta->table} or return;

    my @cols = ref($cols) ? @$cols : ($cols);

    return grep { $meta->column($_) } @cols;
}

1;
