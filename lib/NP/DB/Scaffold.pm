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

1;
