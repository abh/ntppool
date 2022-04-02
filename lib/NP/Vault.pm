package NP::Vault;
use strict;
use warnings;
use NP::LWP;
use LWP::UserAgent;
use JSON::XS ();

my $config          = Combust::Config->new;
my $deployment_mode = $config->site->{ntppool}->{deployment_mode};

my $json = JSON::XS->new->utf8;

my $api = 'https://vault.ntpvault.svc:8200/v1';

my $ua;

{
    my $ca = '/vault/secrets/vault-ca';
    if (-e $ca) {
        $ua = LWP::UserAgent->new(
            timeout  => 2,
            ssl_opts => {
                SSL_verify_mode => 0x02,
                SSL_ca_file     => $ca,
            }
        );
    }
}

$ua = NP::LWP::ua() unless $ua;

sub ua {
    open(my $token_fh, '<', '/vault/secrets/token');
    unless ($token_fh) {
        warn "Could not open token file: $!";
        return;
    }
    my $token = <$token_fh>;
    close $token_fh;
    $ua->default_header("X-Vault-Token" => $token);
    return $ua;
}

sub get_kv {
    my $k    = shift;
    my $url  = "$api/kv/data/ntppool/${deployment_mode}/$k";
    my $resp = ua()->get($url);
    if ($resp->is_success) {
        return $json->decode($resp->decoded_content)->{data};
    }

    #warn $resp->status_line,     "\n";
    warn "error fetching $k from vault: ", $resp->decoded_content, "\n";
    return {};

}

sub set_kv {
    my $k    = shift;
    my $data = shift;
    my $cas  = shift;

    my $payload = {
        "options" => {"cas" => $cas || 0},
        "data"    => $data,
    };

    my $resp = ua()->post(
        "$api/kv/data/ntppool/${deployment_mode}/$k",
        Content => $json->encode($payload)

    );
    if ($resp->is_success) {
        my $r = $json->decode($resp->decoded_content);
        return $r->{data}->{version};
    }
    else {
        warn $resp->status_line,     "\n";
        warn $resp->decoded_content, "\n";
    }
    return 0;
}

1;
