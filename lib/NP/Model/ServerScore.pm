package NP::Model::ServerScore;
use strict;
use Carp qw(croak);

sub score {
  my $self = shift;
  croak "Can't set 'score' - use 'score_raw'" if @_;
  sprintf "%0.1f", $self->score_raw;
}

1;

