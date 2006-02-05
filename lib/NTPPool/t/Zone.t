use Test::More tests => 105;
use strict;

BEGIN { use_ok('NTPPool::Zone'); }

ok(my ($zone) = NTPPool::Zone->search(name => 'asia'), 'search asia');
is($zone->url, '/zone/asia', 'url');
is($zone->description, 'Asia', 'url');
ok(my @children = $zone->children, 'children');

for my $i (1..25) {
  ok(my @rand = $zone->random_subzone_ids(2), 'rand subzone ids');
  is(scalar @rand, 2, 'got the right count');

  ok(my @rand = $zone->random_subzone_ids(1), 'rand subzone ids');
  is(scalar @rand, 1, 'got the right count');
}

#use Data::Dumper;
#warn Dumper(\@children);

# check parent etc...



