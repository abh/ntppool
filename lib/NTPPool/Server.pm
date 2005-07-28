package NTPPool::Server;
use strict;
use base qw(NTPPool::DBI);
use NTPPool::Server::Score;

__PACKAGE__->set_up_table('servers');
__PACKAGE__->has_a('admin' => 'NTPPool::Admin');
__PACKAGE__->has_many('log_scores' => 'NTPPool::Server::LogScore');

# map through the mapping table?
# __PACKAGE__->has_many(zones => 'NTPPool::(Zones|Locations)');

sub count_by_continent {
  my $class = shift;
  my $dbh = $class->db_Main;
  return $dbh->selectall_arrayref(q[select z.name,count(*) as count
				    from servers s
				      inner join locations l on(s.id=l.server)
                                      inner join zones z on(z.id=l.zone)
				    where length(z.name)>2
				    group by z.name with rollup],
				  {Columns => {} }
				 );
}

sub score {
  my $self = shift;
  my ($score) = NTPPool::Server::Score->search( server => $self->id );
  $score = $score->score || 0;
  sprintf "%0.1f", $score;
}

sub history {
  my ($self, $count) = @_;

  $count ||= 50;

  my $pager = NTPPool::Server::LogScore->pager;
  $pager->page(1);
  $pager->per_page($count);
  $pager->order_by('ts desc');
  $pager->search_where({ server => $self->id });

}

sub find_server {
  my ($class, $arg) = @_;
  my ($server) = $class->search(ip => $arg);
  ($server)    = $class->search(hostname => $arg) unless $server;
  $server;
}

1;
