package NP::Vault;
use strict;
use warnings;
use NP::UA qw();
use LWP::UserAgent;
use JSON::XS ();
use Time::HiRes qw(time);

my $config          = Combust::Config->new;
my $deployment_mode = $config->site->{ntppool}->{deployment_mode};

my $json = JSON::XS->new->utf8;

my $api = ($ENV{VAULT_ADDR} || 'https://vault.vault.svc:8200');
$api =~ s{/+$}{};
$api =~ s{/v1$}{};
$api .= '/v1';

my $ua;

sub _ua {
    return $ua if $ua;
    my $ca = $ENV{VAULT_CACERT} || '/vault/secrets/vault-ca';
    if (-e $ca) {
        $ua = LWP::UserAgent->new(
            timeout           => 2,
            protocols_allowed => ['http', 'https'],
            max_size          => (20 * 1024 * 1024),
            ssl_opts          => {
                SSL_verify_mode => 0x02,
                SSL_ca_file     => $ca,
            }
        );
    }
    else {
        $ua = $NP::UA::ua;
    }
}

sub ua {
    _ua() unless $ua;
    open(my $token_fh, '<', '/vault/secrets/token')
      or die "vault: cannot open token file '/vault/secrets/token': $!";
    my $token = <$token_fh>;
    close $token_fh;
    $ua->default_header("X-Vault-Token" => $token);
    return $ua;
}

sub _req {
    my ($method, $url, @args) = @_;
    my $t0   = time();
    my $resp = ua()->$method($url, @args);
    my $ms   = int(((time() - $t0) * 1000) + 0.5);
    my $msg  = $resp->message;
    warn sprintf("vault %s %s -> %s%s (%dms)\n",
        uc $method, $url, $resp->code, ($msg ? " $msg" : ''), $ms);
    unless ($resp->is_success) {
        warn "vault response body: ", $resp->decoded_content, "\n";
    }
    return $resp;
}

my $role_base = "$api/auth/monitors/${deployment_mode}";
my $kv_base   = "$api/kv/data/ntppool/${deployment_mode}";

sub monitoring_tls_domain {
    return $deployment_mode . ".mon.ntppool.dev";
}

sub get_monitoring_role_id {
    my $name = shift;
    my $url  = "${role_base}/role/${name}/role-id";
    my $resp = _req('get', $url);
    if ($resp->is_success) {
        my $data = $json->decode($resp->decoded_content)->{data};
        return $data->{role_id};
    }
    return undef;
}

sub get_monitoring_secret_accessors {
    my $name = shift;
    my $url  = "${role_base}/role/${name}/secret-id?list=true";

    my $resp = _req('get', $url);
    unless ($resp->is_success) {
        if ($resp->code == 404) {
            return ();    # no available secrets
        }
        return ();
    }

    my @keys = @{$json->decode($resp->decoded_content)->{data}->{keys}};
    return @keys;
}

sub get_monitoring_secret_properties {
    my $name = shift;
    my $url  = "${role_base}/role/${name}/secret-id-accessor/lookup";

    my @keys;

    for my $key (get_monitoring_secret_accessors($name)) {
        my $resp = _req('post', $url,
            Content => $json->encode({secret_id_accessor => $key}));
        unless ($resp->is_success) {
            next;
        }
        push @keys, $json->decode($resp->decoded_content)->{data};
    }

    return \@keys;
}

sub delete_monitoring_secret_accessor {
    my $name     = shift;
    my $accessor = shift;
    my $url      = "${role_base}/role/${name}/secret-id-accessor/destroy";

    my $resp = _req('post', $url,
        Content => $json->encode({secret_id_accessor => $accessor}));
    if ($resp->is_success) {
        return 1;
    }

    return 0;
}

sub delete_monitoring_role {
    my $name = shift;
    my $url  = "${role_base}/role/${name}";
    my $resp = _req('delete', $url);
    if ($resp->is_success) {
        return 1;
    }

    return 0;
}

sub setup_monitoring_secret {
    my $name     = shift;
    my $metadata = shift;
    my $url      = "${role_base}/role/${name}/secret-id";

    my %data = ();
    $data{metadata} = $metadata if $metadata;

    my $content = $json->encode(\%data);

    my $resp = _req('post', $url, Content => $content);
    if ($resp->is_success) {
        my $data = $json->decode($resp->decoded_content)->{data};
        return $data->{secret_id}, $data->{secret_id_accessor};
    }

    return 0;

}

sub setup_monitoring_role {
    my $name = shift;
    my $url  = "${role_base}/role/${name}";

    # todo: bind to ip

    my %data = (

        # secret_id_bound_cidrs => ipString,
        "secret_id_ttl"      => "26280h",    # 3 years
        "secret_id_num_uses" => 500,

        # "token_bound_cidrs" =>       ipString,
        "token_num_uses" => 200,
        "token_ttl"      => "96h",           # this makes the cert also expire (in vault)
        "token_max_ttl"  => "168h",          # renewed at this interval by vault-agent ?
        "token_type"     => "default",
        "period"         =>
          "96h",    # vault-agent has to check-in this often to keep the token valid
        "policies" => "monitor-${deployment_mode}",
    );

    my $resp = _req('post', $url, Content => $json->encode(\%data));
    if ($resp->is_success) {
        return 1;
    }

    return 0;

}

sub get_kv {
    my $k   = shift;
    my $v   = shift;
    my $url = "${kv_base}/$k";

    if ($v) {
        $url .= "?version=$v";
    }

    my $resp = _req('get', $url);
    if ($resp->is_success) {
        return $json->decode($resp->decoded_content)->{data};
    }

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

    my $url  = "${kv_base}/$k";
    my $resp = _req('post', $url, Content => $json->encode($payload));
    if ($resp->is_success) {
        my $r = $json->decode($resp->decoded_content);
        return $r->{data}->{version};
    }
    return 0;
}

1;
