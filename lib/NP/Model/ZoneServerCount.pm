package NP::Model::ZoneServerCount;
use strict;
use Time::Duration;

sub ago {
    my $self = shift;
    Time::Duration::ago(DateTime->today->epoch - $self->date->epoch, 2);
}

package NP::Model::ZoneServerCount::Manager;
use strict;

sub first_stats {
    my ($class, $zone, $year) = @_;
    my $dbh = NP::Model->dbh;
    my $id;
    if ($year) {
        ($id) = $dbh->selectrow_array(q[select id from zone_server_counts where zone_id=? and year(date)=? order by date limit 1],
                                      undef,
                                      $zone->id, $year,
                                     );
    }
    else {
        ($id) = $dbh->selectrow_array(q[select id from zone_server_counts where zone_id=? order by date limit 1],
                                      undef,
                                      $zone->id,
                                     );
    }
    return unless $id;
    $class->fetch(id => $id);
} 


1;

