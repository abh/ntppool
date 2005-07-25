package NTPPool::Control;
use strict;
use Apache::Constants qw(OK);
use base qw(Combust::Control);




package NTPPool::Control::Basic;
use base qw(Combust::Control::Basic NTPPool::Control);

package NTPPool::Control::Error;
use base qw(Combust::Control::Error NTPPool::Control);

1;
