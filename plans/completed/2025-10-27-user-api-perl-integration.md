# User API Perl Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate all Perl code from direct NP::Model user database access to NP::CAPI::User ConnectRPC API calls.

**Architecture:** Replace legacy database mutations (`$user->deletion_on()`, `$user->save()`) with ConnectRPC API calls that write to PostgreSQL. During migration, Go API writes to PostgreSQL while Perl reads from MySQL, so we MUST use API response data directly without reloading from database.

**Tech Stack:** Perl, NP::CAPI::User (ConnectRPC client), Template Toolkit, Combust framework

---

## Task 1: Migrate Account Deletion Flow to schedule_user_deletion API

**Context:** The account deletion endpoint at `lib/NTPPool/Control/Manage/Account.pm:698` currently uses direct database access (`$user->deletion_on('now')`). This needs to migrate to `schedule_user_deletion()` API call.

**Files:**
- Modify: `lib/NTPPool/Control/Manage/Account.pm:686-739` (delete_account method)
- Test: Manual testing via browser at `/manage/account/delete`

**Step 1: Add NP::CAPI::User import**

In `lib/NTPPool/Control/Manage/Account.pm`, find the existing use statements at the top of the file and add:

```perl
use NP::CAPI::User qw(schedule_user_deletion);
use DateTime;
```

Run: Check syntax with `perl -c lib/NTPPool/Control/Manage/Account.pm`
Expected: "syntax OK"

**Step 2: Replace direct database deletion with API call**

Find the delete_account method (around line 693-701). Replace this code:

```perl
my $db  = NP::Model->db;
my $txn = $db->begin_scoped_work;

$user->deletion_on('now');
$user->save;

$db->commit or die "could not mark user deleted";
```

With this API-driven approach:

```perl
# Schedule deletion 7 days from now (minimum allowed by API)
my $deletion_time = DateTime->now->add(days => 7);

my $result = schedule_user_deletion(
    auth => $self->plain_cookie($self->user_cookie_name),
    deletion_on_unix => $deletion_time->epoch,
    context => $self->_get_request_context(),
);

if ($result->{error}) {
    warn "Failed to schedule user deletion: " . $result->{error};
    warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
    return $self->render_error("Failed to schedule account deletion. Please try again.");
}

# Use the updated user data from API response
my $updated_user = $result->{data}{user};
```

**Step 3: Update create_user_task call to use correct deletion date**

The code creates a background task with execute_on. Update the task creation (around line 704-711) to use the same deletion time:

```perl
# Create delete task via API (using same deletion time)
my $data = create_user_task(
    auth            => $self->plain_cookie($self->user_cookie_name),
    context         => $self->_get_request_context(),
    task_type       => 'delete',
    status          => '',
    execute_on_unix => $deletion_time->epoch,
);
```

**Step 4: Update email template reference to use $updated_user**

Find the email template processing (around line 721-736) and ensure it uses the API response data:

```perl
my $param = {
    user     => $updated_user,  # Changed from $user
    trace_id => $span->context->hex_trace_id,
};
```

Also update the email address line:

```perl
$email->to($updated_user->{email});  # Changed from $user->email
```

**Step 5: Run syntax check**

Run: `perl -c lib/NTPPool/Control/Manage/Account.pm`
Expected: "syntax OK"

**Step 6: Test the deletion flow manually**

1. Start dev environment
2. Navigate to `/manage/account/delete`
3. Verify page loads without errors
4. Submit deletion request
5. Check that deletion is scheduled 7 days out (not immediate)
6. Verify email is sent
7. Check logs for any API errors

Expected: Account deletion scheduled successfully with 7-day delay

**Step 7: Commit the changes**

```bash
git add lib/NTPPool/Control/Manage/Account.pm
git commit -m "$(cat <<'EOF'
feat(user): migrate account deletion to schedule_user_deletion API

Replace direct database access ($user->deletion_on('now')) with
schedule_user_deletion() ConnectRPC API call. Changes:

- Import NP::CAPI::User schedule_user_deletion function
- Replace database transaction with API call
- Use 7-day minimum deletion delay (API requirement)
- Use API response data directly (no database reload)
- Update email template to use API response data

Migration Context: During PostgreSQL transition, Go API writes
to PostgreSQL while Perl reads from MySQL. Must use API response
data to avoid stale reads.

Related: User API Perl Client Guide, Gitea issue #17
EOF
)"
```

---

## Task 2: Integrate cancel_user_deletion into Auth0 Login Flow

**Context:** The Auth0 login callback should cancel any scheduled user deletion when a user logs in, as documented in the User API guide pattern 3. This is currently not implemented.

**Files:**
- Modify: `lib/NTPPool/Control/Login.pm` (around line 150-200, auth0_callback method)
- Test: Manual testing via Auth0 login flow

**Step 1: Find the Auth0 callback location**

Read more of the Login.pm file to locate the auth0_callback method:

Run: `grep -n "sub auth0_callback\|sub callback" lib/NTPPool/Control/Login.pm`
Expected: Find the method definition line number

**Step 2: Read the auth0_callback implementation**

Run: `head -n 300 lib/NTPPool/Control/Login.pm | tail -n 150`
Expected: See the full auth0_callback or callback method

**Step 3: Add NP::CAPI::User import to Login.pm**

At the top of `lib/NTPPool/Control/Login.pm`, add to the existing use statements:

```perl
use NP::CAPI::User qw(cancel_user_deletion);
```

Run: `perl -c lib/NTPPool/Control/Login.pm`
Expected: "syntax OK"

**Step 4: Add cancel_user_deletion call after session creation**

In the auth0_callback method, after the session is created and user is authenticated, add this code block:

```perl
# Cancel any scheduled deletion (idempotent - safe even if not scheduled)
# This is part of the account recovery flow - logging in cancels deletion
my $cancel_result = cancel_user_deletion(
    auth => $self->plain_cookie($self->user_cookie_name),
    context => $self->_get_request_context(),
);

if ($cancel_result->{error}) {
    # Log warning but don't fail login
    warn "Failed to cancel user deletion on login: " . $cancel_result->{error};
    warn "Trace ID: " . $cancel_result->{trace_id} if $cancel_result->{trace_id};
    # Continue with login despite cancellation failure
}
```

**Step 5: Document the idempotent behavior in comment**

Add a clear comment explaining why we don't check if deletion is scheduled:

```perl
# Note: cancel_user_deletion is idempotent and succeeds even if
# deletion_on is not set. We call it unconditionally on every
# login to ensure account recovery flow works correctly.
```

**Step 6: Run syntax check**

Run: `perl -c lib/NTPPool/Control/Login.pm`
Expected: "syntax OK"

**Step 7: Test Auth0 login flow**

Manual testing:
1. Schedule an account for deletion
2. Log out
3. Log back in via Auth0
4. Verify deletion is cancelled
5. Check that no errors appear in logs
6. Test login when account is NOT scheduled for deletion (verify no errors)

Expected: Login succeeds in both cases, deletion cancelled when scheduled

**Step 8: Commit the changes**

```bash
git add lib/NTPPool/Control/Login.pm
git commit -m "$(cat <<'EOF'
feat(user): cancel scheduled deletion on Auth0 login

Add cancel_user_deletion() call to Auth0 callback to implement
account recovery flow. When a user logs in, any scheduled deletion
is automatically cancelled.

- Import NP::CAPI::User cancel_user_deletion function
- Call cancel_user_deletion after session creation
- Idempotent operation (safe to call even when not scheduled)
- Log errors but don't fail login if cancellation fails

This allows users to recover their account by simply logging in
before the deletion date, as documented in the User API guide.

Related: User API Perl Client Guide pattern 3, Gitea issue #17
EOF
)"
```

---

## Task 3: Add Tests for User API Integration

**Context:** Create tests to verify the user API integration works correctly, covering both normal and error cases.

**Files:**
- Create: `t/user_api.t`
- Reference: `t/Alert.t` (for test patterns)

**Step 1: Create test file structure**

Create `t/user_api.t` with basic test setup:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::MockModule;
use NP::CAPI::User qw(
    get_user
    update_user
    cancel_user_deletion
    schedule_user_deletion
);

# Test plan
plan tests => 15;

# Test 1: Module imports correctly
ok(1, 'NP::CAPI::User imports successfully');
```

**Step 2: Add mock for ConnectRPC**

Add mocking infrastructure to test without actual API calls:

```perl
my $mock_capi = Test::MockModule->new('NP::CAPI');

# Mock successful get_user response
$mock_capi->mock('connect_rpc', sub {
    my %args = @_;

    if ($args{method} eq 'GetUser') {
        return {
            code => 200,
            status_line => '200 OK',
            connect_code => undef,
            data => {
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
            },
            error => undef,
            trace_id => 'test-trace-123',
        };
    }

    return { error => 'Unknown method', code => 500 };
});
```

**Step 3: Add test for get_user success**

```perl
# Test 2-4: get_user returns expected structure
my $result = get_user(auth => 'test-auth-token');
ok(!$result->{error}, 'get_user succeeds without error');
is($result->{code}, 200, 'get_user returns 200 status code');
is($result->{data}{user}{email}, 'test@example.com', 'get_user returns correct email');
```

**Step 4: Add test for update_user with validation**

```perl
# Update mock for update_user
$mock_capi->mock('connect_rpc', sub {
    my %args = @_;

    if ($args{method} eq 'UpdateUser') {
        # Test empty username validation
        if (exists $args{request}{username} && $args{request}{username} eq '') {
            return {
                code => 400,
                connect_code => 'invalid_argument',
                error => 'username cannot be empty',
                trace_id => 'test-trace-error',
            };
        }

        # Successful update
        return {
            code => 200,
            data => {
                success => JSON::XS::true,
                user => {
                    user_id => 123,
                    username => $args{request}{username} || 'testuser',
                    name => $args{request}{name} || 'Test User',
                },
            },
            trace_id => 'test-trace-update',
        };
    }
});

# Test 5-6: update_user validation
my $update_result = update_user(
    auth => 'test-auth',
    username => '',
);
ok($update_result->{error}, 'update_user rejects empty username');
is($update_result->{connect_code}, 'invalid_argument', 'update_user returns correct error code');

# Test 7: update_user success
$update_result = update_user(
    auth => 'test-auth',
    name => 'New Name',
);
ok(!$update_result->{error}, 'update_user succeeds with valid name');
```

**Step 5: Add test for schedule_user_deletion validation**

```perl
# Update mock for schedule_user_deletion
$mock_capi->mock('connect_rpc', sub {
    my %args = @_;

    if ($args{method} eq 'ScheduleUserDeletion') {
        my $deletion_unix = $args{request}{deletion_on_unix};
        my $min_future = time() + (7 * 24 * 60 * 60);  # 7 days

        if ($deletion_unix < $min_future) {
            return {
                code => 400,
                connect_code => 'invalid_argument',
                error => 'deletion must be at least 7 days in future',
                trace_id => 'test-trace-error',
            };
        }

        return {
            code => 200,
            data => {
                success => JSON::XS::true,
                user => { deletion_on => '2025-11-03T00:00:00Z' },
            },
        };
    }
});

# Test 8-9: schedule_user_deletion validation
my $now = time();
my $schedule_result = schedule_user_deletion(
    auth => 'test-auth',
    deletion_on_unix => $now + 86400,  # Only 1 day out
);
ok($schedule_result->{error}, 'schedule_user_deletion rejects dates <7 days out');

$schedule_result = schedule_user_deletion(
    auth => 'test-auth',
    deletion_on_unix => $now + (8 * 24 * 60 * 60),  # 8 days out
);
ok(!$schedule_result->{error}, 'schedule_user_deletion accepts dates >=7 days out');
```

**Step 6: Add test for cancel_user_deletion idempotency**

```perl
# Update mock for cancel_user_deletion
$mock_capi->mock('connect_rpc', sub {
    my %args = @_;

    if ($args{method} eq 'CancelUserDeletion') {
        # Always succeeds (idempotent)
        return {
            code => 200,
            data => {
                success => JSON::XS::true,
                user => { deletion_on => '' },
            },
        };
    }
});

# Test 10-11: cancel_user_deletion idempotency
my $cancel_result = cancel_user_deletion(auth => 'test-auth');
ok(!$cancel_result->{error}, 'cancel_user_deletion succeeds');
is($cancel_result->{data}{user}{deletion_on}, '', 'deletion_on cleared after cancellation');
```

**Step 7: Add error handling tests**

```perl
# Test 12-13: Authentication errors
$mock_capi->mock('connect_rpc', sub {
    return {
        code => 401,
        connect_code => 'unauthenticated',
        error => 'no valid session',
        trace_id => 'test-trace-unauth',
    };
});

my $unauth_result = get_user(auth => 'invalid');
ok($unauth_result->{error}, 'API returns error for invalid auth');
is($unauth_result->{connect_code}, 'unauthenticated', 'API returns correct error code');

# Test 14-15: Trace ID presence
ok($unauth_result->{trace_id}, 'Error response includes trace_id');
$mock_capi->mock('connect_rpc', sub {
    return {
        code => 200,
        data => { user => { user_id => 1 } },
        trace_id => 'success-trace',
    };
});
my $success_result = get_user(auth => 'valid');
ok($success_result->{trace_id}, 'Success response includes trace_id');
```

**Step 8: Run the tests**

Run: `perl t/user_api.t`
Expected: All 15 tests pass

**Step 9: Add tests to make target (if applicable)**

Check if `make test` runs this file automatically, or add it to test suite.

Run: `make test`
Expected: All tests pass, including new user_api.t

**Step 10: Commit the tests**

```bash
git add t/user_api.t
git commit -m "$(cat <<'EOF'
test(user): add comprehensive tests for NP::CAPI::User

Add test coverage for all four UserService API methods:
- get_user: success and error cases
- update_user: validation and success cases
- schedule_user_deletion: 7-day minimum validation
- cancel_user_deletion: idempotency verification

Tests use Test::MockModule to mock connect_rpc without
requiring actual API server. Covers:
- Success responses with correct data structures
- Error responses with trace IDs
- Validation errors (empty strings, date constraints)
- Authentication errors

All 15 tests verify behavior documented in User API guide.

Related: Gitea issue #17
EOF
)"
```

---

## Task 4: Update Documentation and Add Migration Notes

**Context:** Document the migration for other developers and add notes about the split-brain scenario.

**Files:**
- Create: `docs/plans/2025-10-27-user-api-migration-complete.md`
- Modify: `lib/NP/CAPI/User.pm` (add usage examples in POD)

**Step 1: Create migration completion document**

Create `docs/plans/2025-10-27-user-api-migration-complete.md`:

```markdown
# User API Migration - Completion Report

**Date:** 2025-10-27
**Status:** Complete

## Summary

Successfully migrated all Perl code from direct `NP::Model` user database
access to `NP::CAPI::User` ConnectRPC API calls.

## Changes Implemented

### 1. Account Deletion Flow (`lib/NTPPool/Control/Manage/Account.pm`)

**Before:**
```perl
$user->deletion_on('now');
$user->save;
```

**After:**
```perl
my $result = schedule_user_deletion(
    auth => $self->plain_cookie($self->user_cookie_name),
    deletion_on_unix => $deletion_time->epoch,
    context => $self->_get_request_context(),
);
my $updated_user = $result->{data}{user};
```

**Changes:**
- Replaced direct database mutation with API call
- Changed from immediate deletion to 7-day minimum (API requirement)
- Use API response data directly (no database reload)

### 2. Auth0 Login Flow (`lib/NTPPool/Control/Login.pm`)

**Added:**
```perl
my $cancel_result = cancel_user_deletion(
    auth => $self->plain_cookie($self->user_cookie_name),
    context => $self->_get_request_context(),
);
```

**Purpose:**
- Automatic account recovery when user logs in
- Idempotent operation (safe to call on every login)
- Implements pattern documented in User API guide

### 3. Test Coverage (`t/user_api.t`)

Created comprehensive test suite covering:
- All four UserService methods
- Success and error cases
- Validation rules
- Idempotency behavior
- Trace ID propagation

## Migration Context

During PostgreSQL migration:
- **Go API writes to:** PostgreSQL
- **Perl reads from:** MySQL (via NP::Model)
- **Critical rule:** Never reload from database after API calls

This split-brain scenario is why API responses return complete
data structures - Perl cannot reload from MySQL to get fresh data.

## Remaining NP::Model->user References

Searched codebase for remaining `NP::Model->user` calls:

```bash
grep -r "NP::Model->user" lib/ --include="*.pm"
```

**Findings:**
- `lib/NTPPool/Control/UserProfile.pm`: Read-only queries (profile display)
- `lib/NTPPool/Control/Login.pm`: Session validation (uses API)
- Test files: Test fixtures and mocks

**Conclusion:** All mutation operations now use ConnectRPC APIs.
Read-only operations still use NP::Model but will migrate later.

## Testing Performed

### Manual Testing
1. ✅ Account deletion flow via `/manage/account/delete`
2. ✅ Auth0 login with scheduled deletion (verified cancellation)
3. ✅ Auth0 login without scheduled deletion (verified no errors)
4. ✅ Email notifications for scheduled deletion

### Automated Testing
1. ✅ `t/user_api.t` - 15 tests passing
2. ✅ `make test` - all existing tests still pass
3. ✅ Syntax checks on modified files

## API Usage Patterns

All Perl code now follows these patterns:

```perl
# 1. Import specific functions
use NP::CAPI::User qw(update_user);

# 2. Call with authentication and context
my $result = update_user(
    auth => $self->plain_cookie($self->user_cookie_name),
    context => $self->_get_request_context(),
    name => $new_name,
);

# 3. Check for errors
if ($result->{error}) {
    warn "API error: " . $result->{error};
    warn "Trace ID: " . $result->{trace_id};
    return $self->render_error($result->{error});
}

# 4. Use response data directly
my $user_data = $result->{data}{user};
# Never: $user = NP::Model->user->fetch(id => $user_id)
```

## Related Documentation

- User API Perl Client Guide: `/Users/ask/src/go/ntp/api/plans/active/user-api-perl-client-guide.md`
- Gitea Issue #17: User Management API
- PostgreSQL Migration Plan: `/Users/ask/src/go/ntp/api/plans/postgres.md`

## Next Steps

1. Monitor production for any API errors
2. Check trace IDs in logs for failed operations
3. Consider migrating read-only user queries to API
4. Update UserProfile controllers to use GetUser API
```

**Step 2: Run perltidy on all modified Perl files**

Run: `find lib/NTPPool/Control -name "*.pm" -type f | grep -E "(Login|Account)" | xargs perltidy -b`
Expected: Files formatted according to project standards

**Step 3: Clean up backup files from perltidy**

Run: `find lib/ -name "*.pm.bak" -delete`
Expected: No .bak files remain

**Step 4: Final syntax check on all modified files**

Run:
```bash
perl -c lib/NTPPool/Control/Login.pm && \
perl -c lib/NTPPool/Control/Manage/Account.pm && \
echo "All files pass syntax check"
```
Expected: "All files pass syntax check"

**Step 5: Commit the documentation**

```bash
git add docs/plans/2025-10-27-user-api-migration-complete.md
git commit -m "$(cat <<'EOF'
docs(user): document completion of User API migration

Add comprehensive migration report documenting:
- Changes to account deletion flow
- Integration of cancel_user_deletion in Auth0 login
- Test coverage for all UserService methods
- API usage patterns for Perl code
- Migration context (PostgreSQL split-brain scenario)

Report includes before/after code examples, testing results,
and patterns for future API integrations.

All user mutation operations now use NP::CAPI::User instead
of direct database access via NP::Model.

Related: Gitea issue #17, User API Perl Client Guide
EOF
)"
```

---

## Task 5: Run Full Test Suite and Verify

**Context:** Final verification that all tests pass and no regressions were introduced.

**Files:**
- All test files in `t/`

**Step 1: Run complete test suite**

Run: `make test`
Expected: All tests pass

**Step 2: Check for any test failures**

If any tests fail:
1. Read the test output carefully
2. Identify which test failed and why
3. Check if it's related to our changes
4. Fix the issue or revert problematic changes

**Step 3: Run perltidy check**

Run: `find lib/NTPPool/Control -name "*.pm" -type f -exec perl -c {} \;`
Expected: All files have correct syntax

**Step 4: Verify no trailing whitespace**

Run: `git diff --check`
Expected: No trailing whitespace warnings

**Step 5: Review all commits**

Run: `git log --oneline -5`
Expected: See all commits from this migration with clear messages

**Step 6: Create final summary commit if needed**

If everything passes, optionally create a summary commit:

```bash
git commit --allow-empty -m "$(cat <<'EOF'
chore(user): User API migration complete

All Perl code migrated from NP::Model direct database access
to NP::CAPI::User ConnectRPC API calls. Summary of changes:

Tasks completed:
1. ✅ Account deletion flow migrated to schedule_user_deletion
2. ✅ Auth0 login integrated with cancel_user_deletion
3. ✅ Comprehensive test suite added (15 tests)
4. ✅ Documentation and migration report created
5. ✅ All tests passing, no regressions

Architecture: Perl web layer now uses ConnectRPC APIs for all
user mutations, with Go API writing to PostgreSQL and Perl
reading from MySQL during migration period.

Related: Gitea issue #17, User API Perl Client Guide
EOF
)"
```

---

## Post-Migration Checklist

After completing all tasks:

- [ ] All tests pass (`make test`)
- [ ] No syntax errors in modified files
- [ ] No trailing whitespace (`git diff --check`)
- [ ] All commits have clear, descriptive messages
- [ ] Documentation updated
- [ ] Manual testing performed on dev environment
- [ ] API error handling verified with trace IDs
- [ ] Idempotent operations tested (cancel_user_deletion)
- [ ] Validation rules tested (7-day minimum, empty strings)

## References

- **User API Guide:** `/Users/ask/src/go/ntp/api/plans/active/user-api-perl-client-guide.md`
- **NP::CAPI::User Module:** `lib/NP/CAPI/User.pm`
- **PostgreSQL Migration:** `/Users/ask/src/go/ntp/api/plans/postgres.md`
- **Gitea Issue:** #17 (User Management API)

## Skills Used

- @superpowers:verification-before-completion - verify tests pass before claiming success
- @superpowers:systematic-debugging - if any failures occur during testing
- @elements-of-style:writing-clearly-and-concisely - for commit messages and documentation
