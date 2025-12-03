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

sub deletion_on {
    my $self = shift;
    return unless $self->{deletion_on};
    # Return DateTime object for compatibility with existing code
    require DateTime::Format::ISO8601;
    return DateTime::Format::ISO8601->parse_datetime($self->{deletion_on});
}

sub graph_uri {
    my ($self, $name) = @_;
    return unless $name;
    return "/graph/" . $self->{ip} . "/${name}.png";
}

sub url {
    my $self = shift;
    return '/scores/' . $self->{ip};
}

sub deleted {
    my $self = shift;
    return 0 unless $self->{deletion_on};
    require DateTime::Format::ISO8601;
    my $deletion = DateTime::Format::ISO8601->parse_datetime($self->{deletion_on});
    return $deletion <= DateTime->today ? 1 : 0;
}

1;
