package NTPPool::Server::Score;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('scores');

sub accessor_name_for {
  my ($class, $column) = @_;
  return "_$column" if $column eq 'server';
  $column;
}

sub server {
  my $self = shift;
  my $id = $self->_server(@_);
  return unless $id;
  NTPPool::Server->retrieve($id);
}

1;


