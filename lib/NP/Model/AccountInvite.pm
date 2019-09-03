package NP::Model::AccountInvite;
use strict;
use Combust::Config;

my $config  = Combust::Config->new;

sub url {
    my $self = shift;
    warn "GETTING URL!";
    return $config->base_url('manage') . '/manage/account/invite/' . $self->code;
}

1;
