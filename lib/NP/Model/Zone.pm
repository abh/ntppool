package NP::Model::Zone;
use strict;
use Combust::Config;
my $config = Combust::Config->new;

sub url {
  my $self = shift;
  "/zone/" . $self->name;
}

sub fqdn {
  my $self = shift;
  my $pool_name = $config->site->{ntppool}->{pool_domain} or die "pool_domain configuration not setup";
  return $pool_name if $self->name eq '@';
  join ".", $self->name, $pool_name;
}

use constant SUB_ZONE_COUNT => 3;

sub sub_zone_count {
    SUB_ZONE_COUNT;
}

sub random_subzone_ids {
    my ($class, $count) = @_;
    $count = SUB_ZONE_COUNT if $count > SUB_ZONE_COUNT;
    my %ids;

    do {
        my $id = int(rand(SUB_ZONE_COUNT));
        $ids{$id} = undef;
    } until (keys %ids == $count);

    return keys %ids;
}

# because the relationship name didn't get setup right...
sub parent { shift->zone(@_); }

sub stats_days_ago {
    my ($self, $days_ago) = @_;

    # local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    my $stats = NP::Model->zone_server_count->get_objects_from_sql
        ( args => [$self->id, $days_ago],
          sql  => q[SELECT *
                    FROM zone_server_counts
                    WHERE 
                      zone_id = ? AND
                      date = DATE_SUB(CURDATE(), INTERVAL ? DAY)
                    ]
          );
    $stats && $stats->[0];
}

sub first_stats {
    NP::Model->zone_server_count->first_stats(@_);
}

sub server_count {
  my $self = shift;
  my $dbh = $self->dbh;
  $dbh->selectrow_array(q[
    select count(*) as count
    from servers s
      inner join server_zones l on(s.id=l.server_id)
      inner join zones z on(z.id=l.zone_id)
    where z.id=? and s.score_raw >= 5 and s.in_pool = 1
  ], undef, $self->id);
}

sub server_count_all {
  my $self = shift;
  my $dbh = $self->dbh;
  $dbh->selectrow_array(q[
    select count(*) as count
    from servers s
      inner join server_zones l on(s.id=l.server_id)
      inner join zones z on(z.id=l.zone_id)
    where z.id=? and s.in_pool = 1
  ], undef, $self->id);
}


1;
