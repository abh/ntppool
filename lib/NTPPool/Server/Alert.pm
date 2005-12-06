package NTPPool::Server::Alert;
use strict;
use base qw(NTPPool::DBI);
use HTTP::Date qw(time2iso);

__PACKAGE__->set_up_table('server_alerts');
__PACKAGE__->add_trigger(before_create => sub{ $_[0]->set(first_email_time => time2iso) } );

sub mark_sent {
  my $self = shift;
  my $server = $self->server;
  $self->last_score($self->server->score);
  $self->last_email_time(time2iso);
  $self->update;
}

sub accessor_name {
  my ($class, $column) = @_;
  return "_$column" if $column eq 'server';
  $column;
}

sub server {
  my $self = shift;
  my $id = $self->_server(@_);
  return unless $id;
  return $id if ref $id;
  NTPPool::Server->retrieve($id);
}


1;
