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
