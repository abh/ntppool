package NP::Model::ServerAlert;
use strict;

sub mark_sent {
    my $self = shift;
    $self->last_score($self->server->score);
    $self->last_email_time('now');
    $self->save;
}

1;
