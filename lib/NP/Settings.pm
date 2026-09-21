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
my $_cache_time;

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

    # Return cached settings if they exist and are less than 2 minutes old
    if ($_cache && $_cache_time && (time() - $_cache_time) < 120) {
        return $_cache;
    }

    my $result = get_settings();

    if ($result->{error}) {
        warn "Failed to get system settings: $result->{error}\n";
        warn "Trace ID: $result->{trace_id}\n" if $result->{trace_id};
        return undef;
    }

    my %settings;

    # system_settings.value is a jsonb column, so every value arrives
    # JSON-encoded: objects ({...}), numbers (120), and quoted scalars ("prod").
    # allow_nonref lets us decode the top-level scalars too. Any legacy
    # un-encoded value falls back to its raw string.
    my $json = JSON::XS->new->utf8->allow_nonref;
    for my $setting (@{$result->{data}{settings}}) {
        my $raw_value = $setting->{value};

        my $value = eval { $json->decode($raw_value) };
        if ($@) {
            warn "Failed to decode JSON for setting '$setting->{key}': $@\n";
            $value = $raw_value;
        }

        $settings{$setting->{key}} = $value;
    }

    $_cache      = \%settings;
    $_cache_time = time();
    return $_cache;
}

=head2 clear_cache()

Clear the cached settings. Mainly useful for testing or long-running
processes that need to refresh settings.

=cut

sub clear_cache {
    $_cache      = undef;
    $_cache_time = undef;
}

1;

__END__

=head1 CACHING

Settings are cached at the process level after the first fetch and automatically
refreshed every 2 minutes. You can manually clear the cache by calling
C<clear_cache()> if needed.

For web request-scoped caching, see L<NTPPool::Control/system_setting>.

=head1 SEE ALSO

L<NP::CAPI::System>

=cut
