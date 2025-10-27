#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 15;
use JSON::XS qw(encode_json);
use lib 't/lib';
use lib 'lib';

# Set up mock UA BEFORE loading anything else
BEGIN {
    require TestHelper;
    require NP::UA;
    $NP::UA::ua = TestHelper::MockUA->new();
}

use TestHelper qw(mock_capi_success mock_capi_error);
use NP::CAPI::User qw(
    get_user
    update_user
    cancel_user_deletion
    schedule_user_deletion
);

# Test 1: Module imports correctly
ok(1, 'NP::CAPI::User imports successfully');

### Test 2-4: get_user returns expected structure
{
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_success({
        user => {
            user_id => 123,
            user_token => 'user-test123',
            email => 'test@example.com',
            username => 'testuser',
            name => 'Test User',
            deletion_on => '',
        },
        accounts => [],
        invites => [],
    });

    my $result = get_user(auth => 'test-auth-token');
    ok(!$result->{error}, 'get_user succeeds without error');
    is($result->{code}, 200, 'get_user returns 200 status code');
    is($result->{data}{user}{email}, 'test@example.com', 'get_user returns correct email');
}

### Test 5-6: update_user validation (empty username)
{
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_error('invalid_argument', 'username cannot be empty', 400);

    my $update_result = update_user(
        auth => 'test-auth',
        username => '',
    );
    ok($update_result->{error}, 'update_user rejects empty username');
    is($update_result->{connect_code}, 'invalid_argument', 'update_user returns correct error code');
}

### Test 7: update_user success
{
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_success({
        success => JSON::XS::true,
        user => {
            user_id => 123,
            username => 'testuser',
            name => 'New Name',
        },
    });

    my $update_result = update_user(
        auth => 'test-auth',
        name => 'New Name',
    );
    ok(!$update_result->{error}, 'update_user succeeds with valid name');
}

### Test 8-9: schedule_user_deletion validation
{
    # Test rejection of dates less than 7 days out
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_error('invalid_argument', 'deletion must be at least 7 days in future', 400);

    my $now = time();
    my $schedule_result = schedule_user_deletion(
        auth => 'test-auth',
        deletion_on_unix => $now + 86400,  # Only 1 day out
    );
    ok($schedule_result->{error}, 'schedule_user_deletion rejects dates <7 days out');

    # Test acceptance of dates 7+ days out
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_success({
        success => JSON::XS::true,
        user => { deletion_on => '2025-11-03T00:00:00Z' },
    });

    $schedule_result = schedule_user_deletion(
        auth => 'test-auth',
        deletion_on_unix => $now + (8 * 24 * 60 * 60),  # 8 days out
    );
    ok(!$schedule_result->{error}, 'schedule_user_deletion accepts dates >=7 days out');
}

### Test 10-11: cancel_user_deletion idempotency
{
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_success({
        success => JSON::XS::true,
        user => { deletion_on => '' },
    });

    my $cancel_result = cancel_user_deletion(auth => 'test-auth');
    ok(!$cancel_result->{error}, 'cancel_user_deletion succeeds');
    is($cancel_result->{data}{user}{deletion_on}, '', 'deletion_on cleared after cancellation');
}

### Test 12-13: Authentication errors
{
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_error('unauthenticated', 'no valid session', 401);

    my $unauth_result = get_user(auth => 'invalid');
    ok($unauth_result->{error}, 'API returns error for invalid auth');
    is($unauth_result->{connect_code}, 'unauthenticated', 'API returns correct error code');
}

### Test 14-15: Trace ID presence
{
    # Error response includes trace_id
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_error('unauthenticated', 'no valid session', 401);
    my $error_result = get_user(auth => 'invalid');
    ok($error_result->{trace_id}, 'Error response includes trace_id');

    # Success response includes trace_id
    $TestHelper::MockUA::MOCK_RESPONSE = mock_capi_success({
        user => { user_id => 1 },
    });
    my $success_result = get_user(auth => 'valid');
    ok($success_result->{trace_id}, 'Success response includes trace_id');
}
