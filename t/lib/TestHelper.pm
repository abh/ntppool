package TestHelper;
use strict;
use warnings;
use JSON::XS qw(encode_json);

use Exporter 'import';
our @EXPORT_OK = qw(mock_capi_success mock_capi_error MockUA MockResponse);

# Mock LWP::UserAgent for testing
{

    package TestHelper::MockUA;

    our $MOCK_RESPONSE;
    our $LAST_REQUEST;

    sub new {
        my $class = shift;
        return bless {}, $class;
    }

    sub request {
        my ($self, $req) = @_;
        $LAST_REQUEST = $req;    # Capture request for test inspection
        return $MOCK_RESPONSE if $MOCK_RESPONSE;
        die "No mock response configured";
    }

    sub default_header {
        my ($self, $header, $value) = @_;

        # No-op for testing
    }
}

{

    package TestHelper::MockResponse;

    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }
    sub code            { $_[0]->{code} }
    sub status_line     { $_[0]->{status_line} }
    sub content_type    { $_[0]->{content_type} || 'application/json' }
    sub decoded_content { $_[0]->{content} }
    sub content         { $_[0]->{content} }
    sub header          { $_[0]->{headers}{$_[1]} }
    sub is_success      { $_[0]->code >= 200 && $_[0]->code < 300 }
    sub decode          {1}    # No-op for testing (content is already decoded)
}

sub mock_capi_success {
    my ($data) = @_;
    return TestHelper::MockResponse->new(
        code        => 200,
        status_line => '200 OK',
        content     => encode_json($data),
        headers     => {TraceID => 'test-trace-' . time},
    );
}

sub mock_capi_error {
    my ($code, $message, $http_code) = @_;
    $http_code ||= 400;
    return TestHelper::MockResponse->new(
        code        => $http_code,
        status_line => "$http_code Bad Request",
        content     => encode_json(
            {   code    => $code,
                message => $message,
            }
        ),
        headers => {TraceID => 'error-trace-' . time},
    );
}

1;
