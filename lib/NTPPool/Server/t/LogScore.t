use Test::More qw(no_plan);
use strict;

use_ok('NTPPool::Server::LogScore');

is(NTPPool::Server::LogScore::_symbol(-0.5), 'x', '-0.5');
is(NTPPool::Server::LogScore::_symbol(-5), '_', '-5');



1;
