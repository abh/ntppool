package NTPPool::Control::Bulletin;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Apache::Constants qw(OK);

sub render {
  my $self = shift;

  my @bad_servers = NTPPool::Server->search_bad_score;
  $self->tpl_param('bad_servers' => \@bad_servers);

  return OK, $self->evaluate_template('tpl/bulletin.txt'), 'text/plain';
}
1;
