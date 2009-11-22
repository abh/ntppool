use Test::More qw(no_plan);
use strict;

use_ok('NP::Model::LogScore');

is( NP::Model::LogScore::_symbol(-0.5), 'x', '-0.5');
is( NP::Model::LogScore::_symbol(-5), '_', '-5');

1;
