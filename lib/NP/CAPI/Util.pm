# GENERATED CODE - DO NOT EDIT
# Generator: protoc-gen-perl-capi v0.1.0

package NP::CAPI::Util;
use strict;
use warnings;
use Carp qw(cluck);
use Exporter 'import';

our @EXPORT_OK = qw(validate_key_value_args);
our $VERSION = '0.1.0';

=head1 NAME

NP::CAPI::Util - Shared utility functions for NP::CAPI modules

=head1 SYNOPSIS

    use NP::CAPI::Util qw(validate_key_value_args);

    sub my_method {
        my $validation_error = validate_key_value_args('my_method', @_);
        return $validation_error if $validation_error;

        my %args = @_;
        # ... rest of method
    }

=head1 DESCRIPTION

Shared utility functions used by auto-generated NP::CAPI::* modules.

=head1 FUNCTIONS

=head2 validate_key_value_args

Validates that a function was called with key-value pairs (even number of arguments).

    my $error = validate_key_value_args($method_name, @args);
    return $error if $error;

B<Arguments:>

=over 4

=item * $method_name - Name of the calling method (for error messages)

=item * @args - Arguments to validate

=back

B<Returns:>

=over 4

=item * undef if validation passes

=item * hashref with error response if validation fails

=back

The error response structure matches ConnectRPC response format:

    {
        code         => 400,
        status_line  => "400 Bad Request",
        connect_code => "invalid_argument",
        data         => undef,
        error        => "Invalid call: odd number of arguments to method_name",
        trace_id     => "",
    }

=cut

sub validate_key_value_args {
    my ($method_name, @args) = @_;

    if (@args % 2 != 0) {
        warn "$method_name called with odd number of arguments (" . scalar(@args) . " args)";
        warn "Arguments: " . join(", ", map { defined($_) ? "'$_'" : 'undef' } @args);
        cluck "$method_name requires key-value pairs (even number of arguments)";
        return {
            code         => 400,
            status_line  => "400 Bad Request",
            connect_code => "invalid_argument",
            data         => undef,
            error        => "Invalid call: odd number of arguments to $method_name",
            trace_id     => "",
        };
    }
    return undef;  # Validation passed
}

1;

__END__

=head1 SEE ALSO

L<NP::CAPI>

=head1 AUTHOR

NTP Pool Project

=cut
