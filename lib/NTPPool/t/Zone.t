use Test::More tests => 5;
use strict;

BEGIN { use_ok('NTPPool::Zone'); }

ok(my ($zone) = NTPPool::Zone->search(name => 'asia'), 'search asia');
is($zone->url, '/zone/asia', 'url');
is($zone->description, 'Asia', 'url');
ok(my @children = $zone->children, 'children');

#use Data::Dumper;
#warn Dumper(\@children);

# check parent etc...



