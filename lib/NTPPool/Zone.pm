package NTPPool::Zone;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('zones');
__PACKAGE__->has_a('parent' => 'NTPPool::Zone');
__PACKAGE__->has_many('locations' => 'NTPPool::Location' );
__PACKAGE__->has_many('children' => 'NTPPool::Zone' => 'parent', { order_by => 'description' });

__PACKAGE__->columns(Essential => __PACKAGE__->columns);

sub retrieve_by_name {
    my ($class, $name) = @_;
    my ($zone) = $class->search(name => $name);
    $zone;
}

sub url {
  my $self = shift;
  "/zone/" . $self->name;
}

sub fqdn {
  my $self = shift;
  my $pool_name = 'pool.ntp.org';
  return $pool_name if $self->name eq '@';
  join ".", $self->name, 'pool.ntp.org';
}

sub server_count {
  my $self = shift;
  my $dbh = $self->db_Main;
  $dbh->selectrow_array(q[
    select count(*) as count
    from servers s
      inner join scores sc on(s.id=sc.server)
      inner join locations l on(s.id=l.server)
      inner join zones z on(z.id=l.zone)
    where z.id=? and sc.score >= 5;
  ], undef, $self->id);
}

sub server_count_all {
  my $self = shift;
  my $dbh = $self->db_Main;
  $dbh->selectrow_array(q[
    select count(*) as count
    from servers s
      inner join locations l on(s.id=l.server)
      inner join zones z on(z.id=l.zone)
    where z.id=?
  ], undef, $self->id);
}


1;

