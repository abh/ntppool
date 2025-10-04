use strict;
use warnings;
use Test::More tests => 12;
use Test::Deep;
use JSON::XS qw(encode_json decode_json);
use lib 't/lib';
use lib 'lib';

# Set up mock UA BEFORE loading anything else
BEGIN {
    require TestHelper;
    require NP::UA;
    $NP::UA::ua = TestHelper::MockUA->new();
}

use TestHelper qw(mock_capi_success mock_capi_error);

BEGIN { use_ok('NP::CAPI', 'connect_rpc') }

### Test 1: Successful RPC call

{
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_success({
        enabled => JSON::XS::true,
        can_register => JSON::XS::false,
        monitor_count => 3,
        monitor_limit => 5,
        server_months => 18,
    });

    my $result = connect_rpc(
        service => 'ntppool.account.v1.AccountService',
        method  => 'GetAccountStatus',
        request => {},
        auth    => 'test-token',
    );

    # Debug output
    if ($result->{error}) {
        diag("Error: " . $result->{error});
        diag("Code: " . $result->{code});
        diag("Connect code: " . ($result->{connect_code} // 'undef'));
    }

    ok(!$result->{error}, "No error on successful call");
    is($result->{code}, 200, "HTTP 200 status");
    ok($result->{data}, "Response data present");
    ok($result->{data}{enabled}, "Response has enabled field");
    like($result->{trace_id}, qr/test-trace-\d+/, "Trace ID captured");
}

### Test 2: ConnectRPC error response

{
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_error('unauthenticated', 'invalid token');

    my $result = connect_rpc(
        service => 'ntppool.account.v1.AccountService',
        method  => 'GetAccountStatus',
        request => {},
        auth    => 'bad-token',
    );

    ok($result->{error}, "Error present for failed RPC");
    is($result->{connect_code}, 'unauthenticated', "Correct error code");
}

### Test 3: X-Account header is set when account parameter provided

{
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_success({
        enabled => JSON::XS::true,
        can_register => JSON::XS::true,
    });

    my $result = connect_rpc(
        service => 'ntppool.account.v1.AccountService',
        method  => 'GetAccountStatus',
        request => {},
        auth    => 'test-token',
        account => 'test-account-token',
    );

    ok(!$result->{error}, "No error with account parameter");

    # Check that the X-Account header was set on the request
    my $last_request = $TestHelper::MockUA::LAST_REQUEST;
    ok($last_request, "Request was captured");
    is($last_request->header('X-Account'), 'test-account-token', "X-Account header set correctly");
}

### Test 4: Module import test

BEGIN { use_ok('NP::CAPI::Account', 'get_account_status') }
