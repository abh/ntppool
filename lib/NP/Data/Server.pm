package NP::Data::Server;
use v5.30;
use strict;
use warnings;
use DateTime;

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

# 4 or 6
sub ip_version {
    my $self = shift;
    return $self->{ip_version};
}

sub hostname {
    my $self = shift;
    return $self->{hostname} || '';
}

sub manage_url {
    my $self = shift;
    return '/manage/servers#s-' . $self->{ip};
}

sub error {
    my $self = shift;
    return $self->{error} || '';
}

sub trace_id {
    my $self = shift;
    return $self->{trace_id} || '';
}

# YYYY-MM-DD as the API sends it, or undef when no deletion is scheduled
sub deletion_on {
    my $self = shift;
    return $self->{deletion_on} || undef;
}

# deletion_on as a UTC DateTime, or undef when no deletion is scheduled
sub deletion_date {
    my $self  = shift;
    my $value = $self->deletion_on or return undef;
    $value =~ m/^(\d{4})-(\d{2})-(\d{2})$/
      or die "unexpected deletion_on value: '$value'";
    return DateTime->new(year => $1, month => $2, day => $3, time_zone => 'UTC');
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

1;
