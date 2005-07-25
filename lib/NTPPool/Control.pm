package NTPPool::Control;
use strict;
use Apache::Constants qw(OK);
use base qw(Combust::Control);
use NTPPool::Server;

sub count_by_continent {
  NTPPool::Server->count_by_continent;
}



package NTPPool::Control::Basic;
use base qw(Combust::Control::Basic NTPPool::Control);

package NTPPool::Control::Error;
use base qw(Combust::Control::Error NTPPool::Control);

1;
