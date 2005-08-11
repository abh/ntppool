package NTPPool::Server;
use strict;
use base qw(NTPPool::DBI);
use NTPPool::Server::Score;
use NTPPool::Zone;

__PACKAGE__->set_up_table('servers');
__PACKAGE__->has_a('admin' => 'NTPPool::Admin');
__PACKAGE__->has_many('log_scores' => 'NTPPool::Server::LogScore');
__PACKAGE__->has_many('locations' => 'NTPPool::Location');
__PACKAGE__->might_have('_score'  => 'NTPPool::Server::Score');

sub zones {
  my $self = shift;
  sort { $a->name cmp $b->name } map { $_->zone } $self->locations;
}

sub count_by_continent {
  my $class = shift;
  my $dbh = $class->db_Main;
  my $a = $dbh->selectall_arrayref(q[select z.name, z.id as zone_id,count(*) as count
				    from servers s
                                      inner join scores sc on (s.id=sc.server)
				      inner join locations l on(s.id=l.server)
                                      inner join zones z on(z.id=l.zone)
				    where length(z.name)>2 and sc.score >= 5
				    group by z.name with rollup],
				   { Columns => {} }
				 );
  return map { 
    $_->{zone} = NTPPool::Zone->retrieve(delete $_->{zone_id}) if $_->{zone_id} and $_->{name};
    $_;
  } @$a if $a;

}

sub score {
  my $self = shift;
  my ($score) = $self->_score;
  if (@_) {
      $score ||= NTPPool::Server::Score->create({ server => $self });
      $score->score(shift @_);
      $score->update;
  }
  $score = $score ? $score->score : 0;
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
