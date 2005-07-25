package NTPPool::Server::LogScore;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('log_scores');
__PACKAGE__->columns(Essential => __PACKAGE__->columns);

__PACKAGE__->has_a('server' => 'NTPPool::Server');


sub history_symbol {
  my $self = shift;
  my $step = $self->step;
  if    ($step >= 0)  { return '#'; }
  elsif ($step >= -1) { return 'x'; }
  elsif ($step >= -4) { return 'o'; }
  else { return '_'; }
}

sub history_css_class {
  my $self = shift;
  my $step = $self->step;
  if    ($step >= 0)  { return 's_his s_his_ok'; }
  elsif ($step >= -1) { return 's_his s_his_tol'; }
  elsif ($step >= -4) { return 's_his s_his_big'; }
  else { return 's_his s_his_down'; }
}


1;
