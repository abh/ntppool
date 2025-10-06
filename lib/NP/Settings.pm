package NP::Settings;
use strict;
use warnings;
use NP::CAPI::System qw(get_settings);
use JSON::XS;

=head1 NAME

NP::Settings - System settings interface using CAPI

=head1 SYNOPSIS

    use NP::Settings;

    # Get a single setting (returns decoded value or undef)
    my $statuspage = NP::Settings->get_setting('statuspage');

    # Get all settings as hashref
    my $all = NP::Settings->get_all_settings();

    # Clear cache (mainly for testing)
    NP::Settings->clear_cache();

=head1 DESCRIPTION

Provides a simple interface to system settings via the CAPI System service.
Settings are fetched once and cached at the process level.

=cut

my $_cache;

=head2 get_setting($key)

Retrieve a single system setting by key. Returns the decoded JSON value,
or undef if the setting doesn't exist or an error occurred.

=cut

sub get_setting {
    my ($class, $key) = @_;
    my $all = $class->get_all_settings();
    return undef unless $all;
    return $all->{$key};
}

=head2 get_all_settings()

Retrieve all system settings as a hashref. Keys are setting names,
values are the decoded JSON values. Returns undef if an error occurred.

Warnings are emitted on errors including trace IDs for debugging.

=cut

sub get_all_settings {
    my ($class) = @_;

    return $_cache if $_cache;

    my $result = get_settings();

    if ($result->{error}) {
        warn "Failed to get system settings: $result->{error}\n";
        warn "Trace ID: $result->{trace_id}\n" if $result->{trace_id};
        return undef;
    }

    my %settings;
    for my $setting (@{$result->{data}{settings}}) {
        my $value = eval { decode_json($setting->{value}) };
        if ($@) {
            warn "Failed to decode JSON for setting '$setting->{key}': $@\n";
            next;
        }
        $settings{$setting->{key}} = $value;
    }

    $_cache = \%settings;
    return $_cache;
}

=head2 clear_cache()

Clear the cached settings. Mainly useful for testing or long-running
processes that need to refresh settings.

=cut

sub clear_cache {
    $_cache = undef;
}

1;

__END__

=head1 CACHING

Settings are cached at the process level after the first fetch. For
long-running processes, you may want to periodically call C<clear_cache()>
to refresh settings.

For web request-scoped caching, see L<NTPPool::Control/system_setting>.

=head1 SEE ALSO

L<NP::CAPI::System>

=cut
