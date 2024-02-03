package NP::Model::UserTask;
use strict;
use Carp qw(croak);

sub download_url {
    my $self     = shift;
    my $filename = $self->status && $self->status->{Filename} or return;
    return "/manage/account/download/data/" . $self->traceid . "/" . $filename;
}

1;
