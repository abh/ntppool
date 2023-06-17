package NP::UA;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(
  $ua
);

# Share an LWP::UserAgent across packages

our $ua = LWP::UserAgent->new(
    agent             => 'ntppool/1',
    timeout           => 2,
    protocols_allowed => [ 'http', 'https' ],
    max_size          => ( 20 * 1024 * 1024 ),
    ssl_opts          => {
        SSL_verify_mode => 0x02,
        SSL_ca_file     => Mozilla::CA::SSL_ca_file()
    }
);
$ua->env_proxy;

1;
