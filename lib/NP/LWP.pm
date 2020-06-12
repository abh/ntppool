package NP::LWP;
use warnings;
use strict;
use LWP::UserAgent;
use Mozilla::CA;

my $ua = LWP::UserAgent->new(
    timeout  => 2,
    ssl_opts => {
        SSL_verify_mode => 0x02,
        SSL_ca_file     => Mozilla::CA::SSL_ca_file()
    }
);
sub ua { return $ua }
