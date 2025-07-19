package NP::Model::TokenID;
use strict;
use warnings;
use Crypt::Skip32::Base32Crockford ();
use Math::Random::Secure           qw(irand);
use Combust::Config                ();
use NP::Vault;

my $config = Combust::Config->new;

our $tk;

sub token_cipher {
    my $self = shift;
    if (ref $self) {
        return $self->{token_cipher} if $self->{token_cipher};
    }

    my $c = Crypt::Skip32::Base32Crockford->new($self->token_key);
    $self->{token_cipher} = $c if ref $self;
    return $c;
}

sub token_prefix {
    return '';
}

sub _get_vault_kv {
    return NP::Vault::get_kv("token_keys") || {metadata => {version => 0}, data => {}};
}

sub token_key {
    my $self = shift;

    my $config_key = $self->token_key_config or die "missing token_key_config";

    for my $retry (0 .. 1) {
        if (my $key = $tk->{data}->{$config_key}) {
            return pack('H20', uc $key);
        }
        $tk = _get_vault_kv() if $retry == 0;
    }

    # only for new keys, or migrating from the legacy config
    my $key = $config->site->{ntppool}->{$config_key};
    warn "got missing $config_key from config" if $key;
    unless ($key) {
        for (1 .. 20) {
            $key .= sprintf("%X", irand(16));
        }
    }

    $self->_set_token_key($key);
    $self->_save_token_keys();

    return pack('H20', uc $key);
}

sub _set_token_key {
    my $self       = shift;
    my $key        = shift;
    my $config_key = $self->token_key_config or die "missing token_key_config";
    warn "set token_key for ", ref $self, " ($config_key)";
    $tk->{data}->{$config_key} = $key;
}

sub _save_token_keys {
    my $self = shift;
    warn "saving token_keys to vault with cas=", $tk->{metadata}->{version};
    NP::Vault::set_kv('token_keys', $tk->{data}, $tk->{metadata}->{version});
}

sub insert_token_id {
    my $self = shift;
    $self->id_token($self->id_token_generated);
    $self->save;
}

# convert a token to an id
sub token_id {
    my $self  = shift;
    my $token = shift or return 0;
    if (my $prefix = $self->token_prefix) {

        # todo: make required if we get rid of non-prefixed account ids?
        $token =~ s/^$prefix//;
    }

    return $self->token_cipher->decrypt_number_b32_crockford($token);
}

sub id_token {
    my $self = shift;
    if (my $token = shift) {
        return $self->_id_token($token);
    }
    return $self->_id_token || $self->id_token_generated;
}

sub id_token_generated {
    my $self = shift;
    return $self->token_prefix
      . lc $self->token_cipher->encrypt_number_b32_crockford($self->id);
}

1;
