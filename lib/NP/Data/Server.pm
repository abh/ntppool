package NP::Data::Server;
use v5.30;
use strict;
use warnings;

# Lightweight data wrapper for server objects from API responses
# Provides compatibility methods for templates that expect server objects

sub new {
    my ($class, %args) = @_;
    return bless {%args, _is_api_object => 1}, $class;
}

sub id {
    my $self = shift;
    return $self->{id};
}

sub ip {
    my $self = shift;
    return $self->{ip};
}

sub hostname {
    my $self = shift;
    return $self->{hostname} || '';
}

sub manage_url {
    my $self = shift;
    return "/manage/server?server=" . $self->{ip};
}

sub error {
    my $self = shift;
    return $self->{error} || '';
}

sub trace_id {
    my $self = shift;
    return $self->{trace_id} || '';
}

1;
