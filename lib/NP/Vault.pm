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

sub _ua {
    return $ua if $ua;
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
    else {
        $ua = NP::LWP::ua();
    }
}

sub ua {
    _ua() unless $ua;
    open(my $token_fh, '<', '/vault/secrets/token')
      or die "Could not open token: $!";
    my $token = <$token_fh>;
    close $token_fh;
    $ua->default_header("X-Vault-Token" => $token);
    return $ua;
}

my $role_base = "$api/auth/monitors/${deployment_mode}";
my $kv_base   = "$api/kv/data/ntppool/${deployment_mode}";

sub monitoring_tls_domain {
    return $deployment_mode . ".mon.ntppool.dev";
}

sub get_monitoring_role_id {
    my $name = shift;
    my $url  = "${role_base}/role/${name}/role-id";
    warn "getting $url";
    my $resp = ua()->get($url);
    if ($resp->is_success) {

        # warn "MONITORING ROLE: ", $resp->decoded_content;
        my $data = $json->decode($resp->decoded_content)->{data};
        return $data->{role_id};
    }
    warn $resp->status_line,     "\n";
    warn $resp->decoded_content, "\n";
    return undef;
}

sub setup_monitoring_secret {
    my $name     = shift;
    my $metadata = shift;
    my $url      = "${role_base}/role/${name}/secret-id";

    warn "setting $url";

    my %data = ();
    $data{metadata} = $metadata if $metadata;

    my $content = $json->encode(\%data);
    warn "CONTNT: $content";

    my $resp = ua()->post(
        "$url",
        Content => $content,

    );
    if ($resp->is_success) {

        # warn "MONITORING ROLE: ", $resp->decoded_content;
        my $data = $json->decode($resp->decoded_content)->{data};
        return $data->{secret_id}, $data->{secret_id_accessor};
    }

    warn $resp->status_line,     "\n";
    warn $resp->decoded_content, "\n";

    return 0;

}

sub setup_monitoring_role {
    my $name = shift;
    my $url  = "${role_base}/role/${name}";

    # todo: bind to ip

    my %data = (

        # secret_id_bound_cidrs => ipString,
        "secret_id_ttl"      => "8760h",  # a year
        "secret_id_num_uses" => 100,

        # "token_bound_cidrs" =>       ipString,
        "token_num_uses" => 40,
        "token_ttl"      => "96h",      # this makes the cert also expire (in vault)
        "token_max_ttl"  => "168h",     # renewed at this interval by vault-agent ?
        "token_type"     => "default",
        "period"         => "96h",      # vault-agent has to check-in this often to keep the token valid
        "policies"       => "monitor-devel",
    );

    my $resp = ua()->post(
        "$url",
        Content => $json->encode(\%data),

    );
    if ($resp->is_success) {
        return 1;
    }

    warn $resp->status_line,     "\n";
    warn $resp->decoded_content, "\n";

    return 0;

}


sub get_kv {
    my $k    = shift;
    my $url  = "${kv_base}/$k";
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
        "${kv_base}/$k",
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
