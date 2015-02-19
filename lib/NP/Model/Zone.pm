package NP::Model::Zone;
use strict;
use Combust::Config;
use File::Path qw(mkpath);

my $config = Combust::Config->new;

sub url {
    my $self = shift;
    "/zone/" . $self->name;
}

sub fqdn {
    my $self      = shift;
    my $pool_name = $config->site->{ntppool}->{pool_domain}
      or die "pool_domain configuration not setup";
    return $pool_name if $self->name eq '@' or $self->name eq '.';
    join ".", $self->name, $pool_name;
}

use constant SUB_ZONE_COUNT => 4;

sub sub_zone_count {
    SUB_ZONE_COUNT;
}


my $rrd_path = "$ENV{CBROOTLOCAL}/rrd/zone";
mkpath "$rrd_path/graph/" unless -e "$rrd_path/graph";

sub rrd_path {
    my $self = shift;
    "$rrd_path/" . $self->name . ".rrd";
}

sub graph_path {
    my $self       = shift;
    my $ip_version = shift;
    my $suffix     = ($ip_version eq 'v6' ? '-v6' : '');
    my $file       = $self->name . "$suffix.png";
    return "$rrd_path/graph/" . $file;
}

sub children {
    my $self = shift;
    return $self->{_children} ||= [sort { $a->name cmp $b->name } $self->zones];
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

sub stats_days_ago {
    my ($self, $days_ago, $ip_version) = @_;
    my $ip_version_sql = $self->_ip_version_sql($ip_version, "zsc");

    #local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    my $stats = NP::Model->zone_server_count->get_objects_from_sql(
        args => [$self->id, $days_ago],
        sql  => qq[SELECT *
                    FROM zone_server_counts zsc
                    WHERE 
                      zone_id = ?
                      $ip_version_sql
                      AND date = DATE_SUB(CURDATE(), INTERVAL ? DAY)
                    ]
    );
    $stats && $stats->[0];
}

sub first_stats {
    NP::Model->zone_server_count->first_stats(@_);
}

use constant deletion_grace_days => 14;

sub active_servers {
    my $self = shift;
    my $ip_version = shift or return;

    my $dbh = NP::Model->dbh;

    my $entries = $dbh->selectall_arrayref(
        qq[SELECT s.ip, s.netspeed
         FROM servers s, server_zones l
         WHERE l.server_id = s.id AND l.zone_id = ? AND s.in_pool = 1 AND s.ip_version=?
         AND s.score_raw > ?
         and (s.deletion_on IS NULL OR s.deletion_on > DATE_ADD(NOW(), interval ? day))
        ], undef,
        $self->id,
        $ip_version,
        NP::Model::Server->active_score,
        $self->deletion_grace_days
    );

    return $entries;

}

sub _ip_version_sql {
    my $self       = shift;
    my $ip_version = shift or return "";
    my $table      = shift || 's';
    return "AND $table.ip_version=" . $self->dbh->quote($ip_version);
}

sub server_count {
    my $self           = shift;
    my $ip_version_sql = $self->_ip_version_sql(shift);

    my $dbh = $self->dbh;
    $dbh->selectrow_array(
        qq[
    select count(*) as count
    from servers s
      inner join server_zones l on(s.id=l.server_id)
      inner join zones z on(z.id=l.zone_id)
    where z.id=?
      and s.score_raw > 10
      and s.in_pool = 1
      and (s.deletion_on IS NULL OR s.deletion_on > DATE_ADD(NOW(), interval ? day))
      $ip_version_sql
  ], undef, $self->id, deletion_grace_days()
    );
}

sub server_count_all {
    my $self           = shift;
    my $ip_version_sql = $self->_ip_version_sql(shift);

    my $dbh = $self->dbh;
    $dbh->selectrow_array(
        qq[
    select count(*) as count
    from servers s
      inner join server_zones l on(s.id=l.server_id)
      inner join zones z on(z.id=l.zone_id)
    where
      z.id=?
      and s.in_pool = 1
      and (s.deletion_on IS NULL OR s.deletion_on > DATE_ADD(NOW(), interval ? day))
      $ip_version_sql
  ], undef, $self->id, deletion_grace_days()
    );
}

sub netspeed_active {
    my $self           = shift;
    my $ip_version_sql = $self->_ip_version_sql(shift);

    my $dbh = $self->dbh;
    $dbh->selectrow_array(
        qq[
    select sum(s.netspeed) as netspeed
    from servers s
      inner join server_zones l on(s.id=l.server_id)
      inner join zones z on(z.id=l.zone_id)
    where z.id=?
      and s.score_raw > 10
      and s.in_pool = 1
      and (s.deletion_on IS NULL OR s.deletion_on > DATE_ADD(NOW(), interval ? day))
      $ip_version_sql
  ], undef, $self->id, deletion_grace_days()
    );
}


1;


__END__

all netspeeds:

select z.id,z.name,sum(s.netspeed) as netspeed_active 
  from servers s
    inner join server_zones l on(s.id=l.server_id)
    inner join zones z on(z.id=l.zone_id)
  where 
    s.score_raw >= 5
    and s.in_pool = 1
    and (s.deletion_on IS NULL OR s.deletion_on > DATE_ADD(NOW(), interval 15 day))
  group by z.id
  order by netspeed_active desc
;

