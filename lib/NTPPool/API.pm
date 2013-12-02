package NTPPool::API;
use strict;
use base qw(Combust::API);

__PACKAGE__->setup_api(
    'staff' => 'Staff',
    'notes' => 'Notes',
);

1;
