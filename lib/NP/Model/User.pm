package NP::Model::User;
use strict;

sub privileges {
    shift->user_privilege(@_);
}

1;
