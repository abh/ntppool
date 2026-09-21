package NTPPool::Control::Manage::Scores;
use strict;

# Manage site wrapper for Scores controller
# Inherits from Manage (first) to get account context setup via init()
# Inherits from Scores to get server_data and other methods

use NTPPool::Control::Manage;
use NTPPool::Control::Scores;
use parent qw(NTPPool::Control::Manage NTPPool::Control::Scores);

# init comes from Manage (sets up account context)
# Explicitly use Scores::render since Manage::render would be found first in MRO
sub render {
    my $self = shift;
    return $self->NTPPool::Control::Scores::render(@_);
}

1;
