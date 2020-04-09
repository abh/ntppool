package NP::Model::TokenID;
use strict;
use warnings;
use Crypt::Skip32::Base32Crockford ();
use Combust::Config ();

my $config  = Combust::Config->new;

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

sub token_key {
    my $self = shift;
    my $config_key = $self->token_key_config or die "missing token_key_config";
    my $key = $config->site->{ntppool}->{$config_key} or die "'${config_key}' not set in configuration";
    return pack( 'H20', uc $key);
}

sub token_id {
    my $self = shift;
    my $token = shift or return 0;
    if (my $prefix = $self->token_prefix) {
        # todo: make required if we get rid of non-prefixed account ids?
        $token =~ s/^$prefix//;
    }
    return $self->token_cipher->decrypt_number_b32_crockford($token);
}

sub id_token {
    my $self = shift;
    return $self->token_prefix . lc $self->token_cipher->encrypt_number_b32_crockford($self->id);
}

1;
