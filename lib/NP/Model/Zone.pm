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

sub children {
    my $self = shift;
    $self->{_children} ||= [sort { $a->name cmp $b->name } $self->zones];

    # the template using this gets confused if it gets an arrayref
    return @{$self->{_children}};
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

use constant deletion_grace_days => 14;

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
