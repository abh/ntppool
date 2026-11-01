package NP::UA;
use strict;
use warnings;
use LWP::UserAgent qw();
use Mozilla::CA    qw();

use Exporter 'import';
our @EXPORT_OK = qw(
    $ua
    $ua_medium
    $ua_long
);

# Share an LWP::UserAgent across packages

sub _new_ua {
    my ($timeout) = @_;
    my $ua = LWP::UserAgent->new(
        agent             => 'ntppool/1',
        keep_alive        => 5,
        max_size          => (20 * 1024 * 1024),
        protocols_allowed => ['http', 'https'],
        timeout           => $timeout,
        ssl_opts          => {
            SSL_verify_mode => 0x02,
            SSL_ca_file     => Mozilla::CA::SSL_ca_file()
        }
    );
    $ua->env_proxy;
    return $ua;
}

our $ua = _new_ua(5);

# For API calls that can run up to the API's default 15s write deadline
# (account invites send their email synchronously). Longer than that
# deadline so we get the API's answer instead of giving up first.
our $ua_medium = _new_ua(20);

# Separate user agent for long-running operations (server precheck, etc.)
our $ua_long = _new_ua(60);

# Enable automatic decompression - requires Compress::Zlib
# This allows decoded_content() to automatically decompress gzip responses
use HTTP::Message ();
if (my $encoding = HTTP::Message::decodable()) {
    $ua->default_header('Accept-Encoding' => $encoding);
}

1;
