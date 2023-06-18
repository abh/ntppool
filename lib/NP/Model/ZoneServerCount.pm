package NP::Model::ZoneServerCount;
use strict;
use Time::Duration qw();

sub ago {
    my $self = shift;
    Time::Duration::ago(DateTime->today->epoch - $self->date->epoch, 2);
}

package NP::Model::ZoneServerCount::Manager;
use strict;

sub first_stats {
    my ($class, $zone, $year, $ip_version) = @_;

    my $dbh = NP::Model->dbh;

    my $ip_version_sql = $ip_version ? "AND ip_version=" . $dbh->quote($ip_version) : "";

    my $id;
    if ($year) {
        ($id) = $dbh->selectrow_array(
            qq[select id from zone_server_counts where zone_id=? and year(date)=?
                                         $ip_version_sql
                                         order by date limit 1],
            undef,
            $zone->id, $year,
        );
    }
    else {
        ($id) = $dbh->selectrow_array(
            qq[select id from zone_server_counts where zone_id=?
                                         $ip_version_sql
                                         order by date limit 1],
            undef,
            $zone->id,
        );
    }

    return unless $id;
    $class->fetch(id => $id);
}

1;

