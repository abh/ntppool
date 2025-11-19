# Plan: Complete Account Model Removal

**Status:** In Progress - Issues Created
**Created:** 2025-10-13
**Updated:** 2025-11-17
**Parent Plan:** account-model-removal-revised.md
**Goal:** Complete the account ORM removal by migrating all remaining Perl code to use Go APIs exclusively. Make Perl purely a presentation layer with zero database access for account-related operations.

**Tracking Issue:** [#29 - Complete Account Model Removal (Meta-Issue)](https://gitea.develooper.com/ntppool/ntppool/issues/29)

**Critical Path Issues:**
- [#22 - Migrate Stripe Billing and Subscription Validation to CAPI](https://gitea.develooper.com/ntppool/ntppool/issues/22) - **BLOCKS MODEL REMOVAL**
- [#25 - Migrate Server Permission Checks to CAPI](https://gitea.develooper.com/ntppool/ntppool/issues/25)
- [#28 - Migrate Monitor.pm from int_api to CAPI](https://gitea.develooper.com/ntppool/ntppool/issues/28) - Lower priority

---

## Current Status (2025-11-17)

### ✅ Completed (from parent plan)
- Phase 3: Updated `/manage/account` and `/manage/account/team` controllers to use API hashrefs
- Phase 4: Updated 27 template files to use hashref syntax (`account.account_id`, `account._permissions.can_edit`)
- Committed: `b1f0bd83` - "refactor(account): use API hashrefs not ORM"

### ❌ Blocking Phase 5 (Model Removal)
Phase 5 cannot proceed because significant ORM usage remains in:
- `lib/NTPPool/Control/Vendor.pm` - Vendor zone management (subscriptions, stripe) - **Issue #22**
- `lib/NTPPool/Control/Manage/Server.pm` - Server management - **Issue #25**
- `lib/NTPPool/Control/Manage/Monitor.pm` - Monitor permission checks - **Issue #28** (lower priority)
- `lib/NTPPool/API/Staff.pm` - Staff APIs (minor cleanup)
- `lib/NTPPool/Control/UserProfile.pm` - Public profile lookups (already using APIs)

### ✅ What Already Exists (2025-11-17)

**Go APIs (ConnectRPC):**
- ✅ VendorZone service (List, Get, Request, Update, Submit, UpdateStatus, ListAdmin)
- ✅ Server service (GetServer, GetAccountServers)
- ✅ Account service (GetAccount with `include_subscriptions` flag)
- ✅ AccountSubscription message type in Account proto

**Perl CAPI Wrappers:**
- ✅ NP::CAPI::VendorZone (all vendor zone operations)
- ✅ NP::CAPI::Server (get_server, get_account_servers)
- ✅ NP::CAPI::Account (get_account, update_account, etc.)

### ❌ What's Missing (Critical for #22)

**Subscription Business Logic:**
- ❌ `subscription_limits_not_exceeded(device_count)` validation API
- ❌ `have_live_subscription()` check API
- ❌ `live_subscriptions()` filtering API
- ❌ Can read subscriptions via GetAccount, but can't validate limits

**Stripe Integration:**
- ❌ `stripe_customer_id` field NOT in Account proto
- ❌ Can't update stripe_customer_id via UpdateAccount
- ❌ No API for account_subscription CRUD operations

**Permission Flags:**
- ❌ VendorZone responses don't include `_permissions` hash
- ❌ Need `can_view` and `can_edit` computed server-side

---

## Problem Analysis

### Current Architecture Issues

**The original plan assumed** that updating `/manage/account` controllers would be sufficient to remove `NP::Model::Account`. However, the Account model is deeply integrated into multiple subsystems:

1. **Relationship Access** - Many controllers call `$account->servers`, `$account->vendor_zones`, `$account->account_subscriptions`
2. **Nested Permissions** - Code like `$server->account->can_edit($user)` checks permissions through nested ORM relationships
3. **Business Logic Methods** - Methods like `subscription_limits_not_exceeded()`, `have_live_subscription()` contain business logic
4. **ORM Writes** - Stripe customer ID updates use `$account->stripe_customer_id($value); $account->save()`
5. **current_account as ORM** - Many controllers still treat `current_account()` as blessed object

### Why This Breaks Pure Presentation Layer

**Perl should only**:
- Accept HTTP requests
- Call Go APIs
- Format responses with templates
- Return HTTP responses

**Perl should NEVER**:
- Query databases (direct SQL or ORM)
- Contain business logic
- Make permission decisions
- Update database records

**Current violations**:
- ❌ `$account->servers` queries MySQL
- ❌ `$account->subscription_limits_not_exceeded()` implements business logic
- ❌ `$server->account->can_edit($user)` makes permission decision
- ❌ `$account->stripe_customer_id($value); $account->save()` writes to database

---

## Detailed Dependency Analysis

### 1. Vendor.pm Dependencies

**File:** `lib/NTPPool/Control/Vendor.pm`

#### current_account ORM Method Calls

```perl
# Line 50: Relationship access
unless @{$self->current_account->vendor_zones};

# Line 102, 511: Relationship access
if (my @subs = $self->current_account->account_subscriptions) {

# Line 129: Business logic method
my @subs = $self->current_account->live_subscriptions;

# Line 288, 423: Field access (needs hashref syntax)
a => $self->current_account->id_token,

# Line 341: Field access (needs hashref syntax)
account_id => $self->current_account->id,
```

#### Account ORM Writes

```perl
# Lines 388, 476, 477: Direct database writes
$account->stripe_customer_id($customer_id);
$account->save();
```

#### Business Logic Method Calls

```perl
# Line 146: Business logic in ORM
unless ($vz->account->subscription_limits_not_exceeded($vz->device_count)) {

# Line 220: Business logic in ORM
my $ok = $vz->account->subscription_limits_not_exceeded($vz->device_count);

# Line 245: Business logic in ORM
unless ($vz->account->have_live_subscription);
```

#### Nested ORM Relationships

```perl
# Lines 465, 488, 509, 528: Access through vendor_zone relationship
$vz->account->stripe_customer_id
$account->stripe_customer_id
```

#### VendorZone Permission Checks

```perl
# Line 119: Permission check on VendorZone ORM object
unless $vz and $vz->can_view($self->user);

# Line 125: Permission check on VendorZone ORM object
and $vz->can_edit($self->user);

# Line 209: Permission check on VendorZone ORM object
unless $vz->can_edit($self->user)

# Line 311: Permission check on VendorZone ORM object
if ($vz and !$vz->can_edit($self->user)) {
```

**What VendorZone.can_edit() does:**
```perl
sub can_edit {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if $user->privileges->vendor_admin;
    return 1
      if $self->status eq 'New'
      and grep { $_->id == $user->id } $self->account->users;  # ← queries account->users!
    return 0;
}
```

### 2. Server.pm Dependencies

**File:** `lib/NTPPool/Control/Manage/Server.pm`

#### current_account Relationship Access

```perl
# Lines 80, 653: Relationship query
my $servers = $self->current_account->servers;
```

**What Account.servers() does:**
```perl
sub servers {
    my $self = shift;
    my $s = NP::Model->server->get_servers(
        query => [
            account_id => $self->id,
            or => [
                deletion_on => undef,
                deletion_on => {'gt' => DateTime->today}
            ],
        ],
        with_objects => ['server_verification'],
    );
    # ... sorting logic ...
}
```

#### Nested Permission Checks

```perl
# Line 409: Permission check through server->account relationship
and $server->account->can_edit($self->user);

# Line 545: Permission check through server->account relationship
return 403 unless $server->account->can_edit($self->user);
```

### 3. Monitor.pm Dependencies

**File:** `lib/NTPPool/Control/Manage/Monitor.pm`

#### Monitor Permission Checks

```perl
# Line 107 (commented out):
# unless $mon->can_edit($self->user);

# Line 472: Permission check on Monitor ORM object
if ($mon and !$mon->can_edit($self->user)) {
```

**What Monitor.can_edit() does:**
```perl
sub can_edit {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if $user->privileges->support_staff;
    return 1 if grep { $_->id == $user->id } $self->account->users;  # ← queries account->users!
    return 0;
}
```

### 4. Staff.pm Dependencies

**File:** `lib/NTPPool/API/Staff.pm`

#### Relationship Access

```perl
# Line 109: Accessing servers through account relationship
} $account->servers_all
```

### 5. UserProfile.pm Dependencies

**File:** `lib/NTPPool/Control/UserProfile.pm`

#### ORM Query

```perl
# Public profile lookup by URL slug
my $account = NP::Model->account->fetch(url_slug => $account_name);
```

---

## Solution Architecture

### Core Principle: Server-Side Permissions & Data

**All permission checks and data fetching must happen in Go**, then passed to Perl as plain hashrefs.

#### Before (❌ Wrong):
```perl
# Perl queries database and makes permission decision
my $vz = NP::Model->vendor_zone->fetch(id => $id);
return 403 unless $vz->can_edit($self->user);  # ← Business logic in Perl!
```

#### After (✅ Correct):
```perl
# Go API returns data WITH permissions pre-computed
my $result = get_vendor_zone(
    auth => $session_token,
    id => $id,
);
return 403 unless $result->{data}{_permissions}{can_edit};  # ← Just checking a flag
my $vz = $result->{data};  # Plain hashref
```

### Key Architectural Patterns

1. **Include Permissions in Responses**
   - Every API that returns a resource should include `_permissions` hash
   - Permissions computed server-side based on authenticated user
   - Perl just checks boolean flags

2. **Include Related Data in Responses**
   - When fetching a VendorZone, include account context if needed
   - Avoids nested relationship access (`$vz->account->something`)
   - Single API call returns everything Perl needs

3. **Move Business Logic to Go**
   - `subscription_limits_not_exceeded()` → Go API
   - `have_live_subscription` → Go API
   - Subscription validation → Go API

4. **API Writes Instead of ORM Saves**
   - `$account->stripe_customer_id($value); $account->save()` → `update_account` API
   - Single atomic operation
   - No partial update risks

---

## Implementation Plan

### Phase 1: New Go APIs (Vendor/Subscription Support)

#### 1.1 GetAccountVendorZones API

**Purpose:** Replace `$account->vendor_zones` relationship access

**Proto:**
```protobuf
rpc GetAccountVendorZones(GetAccountVendorZonesRequest) returns (GetAccountVendorZonesResponse) {}

message GetAccountVendorZonesRequest {
  // account_token from current_account or explicit parameter
  // Authentication via session middleware
}

message GetAccountVendorZonesResponse {
  repeated VendorZoneContext vendor_zones = 1;
}

message VendorZoneContext {
  int64 vendor_zone_id = 1;
  string id_token = 2;
  int64 account_id = 3;
  string zone_name = 4;
  string status = 5;  // New, Pending, Approved, Rejected
  int64 device_count = 6;
  string organization_name = 7;
  bool opensource = 8;
  string created_on = 9;
  string modified_on = 10;

  // Permissions for current user
  VendorZonePermissions _permissions = 11;
}

message VendorZonePermissions {
  bool can_view = 1;   // vendor_admin OR account member
  bool can_edit = 2;   // vendor_admin OR (account member AND status='New')
}
```

#### 1.2 GetVendorZone API

**Purpose:** Fetch single vendor zone with permissions and account context

**Proto:**
```protobuf
rpc GetVendorZone(GetVendorZoneRequest) returns (GetVendorZoneResponse) {}

message GetVendorZoneRequest {
  string id_token = 1;  // vz-xxxxx

  // Optional includes
  bool include_account = 2;      // Include account context
  bool include_subscription_status = 3;  // Include subscription validation
}

message GetVendorZoneResponse {
  VendorZoneContext vendor_zone = 1;

  // Optional fields
  optional AccountContext account = 2;
  optional SubscriptionStatus subscription_status = 3;
}

message SubscriptionStatus {
  bool has_live_subscription = 1;
  bool limits_not_exceeded = 2;
  int64 device_limit = 3;
  repeated SubscriptionContext active_subscriptions = 4;
}

message SubscriptionContext {
  int64 subscription_id = 1;
  string stripe_subscription_id = 2;
  string status = 3;
  string name = 4;
  int64 max_zones = 5;
  int64 max_devices = 6;
  bool live_subscription = 7;  // Computed: status in ['active', 'trialing']
}
```

#### 1.3 UpdateAccountStripeCustomer API

**Purpose:** Replace `$account->stripe_customer_id($value); $account->save()`

**Proto:**
```protobuf
rpc UpdateAccountStripeCustomer(UpdateAccountStripeCustomerRequest) returns (UpdateAccountStripeCustomerResponse) {}

message UpdateAccountStripeCustomerRequest {
  // account_token from session or explicit
  string stripe_customer_id = 1;
}

message UpdateAccountStripeCustomerResponse {
  AccountContext account = 1;  // Return updated account
}
```

#### 1.4 GetAccountServers API

**Purpose:** Replace `$account->servers` relationship access

**Proto:**
```protobuf
rpc GetAccountServers(GetAccountServersRequest) returns (GetAccountServersResponse) {}

message GetAccountServersRequest {
  // account_token from session middleware

  bool include_deleted = 1;      // Include servers with deletion_on set
  bool include_verification = 2; // Include verification status
}

message GetAccountServersResponse {
  repeated ServerContext servers = 1;
}

message ServerContext {
  int64 server_id = 1;
  string ip = 2;
  string hostname = 3;
  int32 ip_version = 4;
  int32 stratum = 5;
  bool in_pool = 6;
  int32 netspeed = 7;
  double score_raw = 8;
  optional string deletion_on = 9;  // ISO 8601 or null
  bool verified = 10;
  optional string verified_on = 11;
  repeated string zones = 12;
  string created_on = 13;
  string modified_on = 14;

  // Include account context to avoid nested lookups
  optional AccountContext account = 15;  // For permission checks
}
```

#### 1.5 GetServer API (New)

**Purpose:** Fetch single server WITH account context for permission checks

**Proto:**
```protobuf
rpc GetServer(GetServerRequest) returns (GetServerResponse) {}

message GetServerRequest {
  string ip = 1;  // OR server_id
  bool include_account = 2;  // Include account with permissions
}

message GetServerResponse {
  ServerContext server = 1;
}
```

#### 1.6 GetMonitor API (Extend)

**Purpose:** Include account context and permissions when fetching monitor

**Extend existing GetMonitor to include:**
```protobuf
message MonitorContext {
  // ... existing fields ...

  optional AccountContext account = 20;  // For permission checks
  MonitorPermissions _permissions = 21;
}

message MonitorPermissions {
  bool can_edit = 1;  // support_staff OR account member
}
```

### Phase 2: Update Perl CAPI Wrappers

**File:** `lib/NP/CAPI/Account.pm`

Add new functions:
```perl
sub get_account_vendor_zones { ... }
sub get_vendor_zone { ... }
sub update_account_stripe_customer { ... }
sub get_account_servers { ... }
sub get_server { ... }
```

**File:** `lib/NP/CAPI/Monitor.pm` (new or extend existing)
```perl
sub get_monitor { ... }  # Include account context
```

### Phase 3: Update Perl Controllers

#### 3.1 Fix Vendor.pm

**Pattern 1: Replace relationship access**

```perl
# BEFORE
unless @{$self->current_account->vendor_zones};

# AFTER
my $result = get_account_vendor_zones(
    auth => $self->plain_cookie($self->user_cookie_name),
    context => $self->_get_request_context(),
);
return $self->redirect(...) unless @{$result->{data}{vendor_zones} || []};
```

**Pattern 2: Replace business logic methods**

```perl
# BEFORE
unless ($vz->account->subscription_limits_not_exceeded($vz->device_count)) {

# AFTER
my $result = get_vendor_zone(
    id_token => $vz->{id_token},
    include_subscription_status => JSON::XS::true,
    auth => $self->plain_cookie($self->user_cookie_name),
);
unless ($result->{data}{subscription_status}{limits_not_exceeded}) {
```

**Pattern 3: Replace ORM writes**

```perl
# BEFORE
$account->stripe_customer_id($customer_id);
$account->save();

# AFTER
my $result = update_account_stripe_customer(
    stripe_customer_id => $customer_id,
    auth => $self->plain_cookie($self->user_cookie_name),
    context => $self->_get_request_context(),
);
# Update local $account hashref with response
$account = $result->{data}{account};
```

**Pattern 4: Replace permission checks**

```perl
# BEFORE
return $self->redirect(...) unless $vz and $vz->can_view($self->user);

# AFTER (permission already in API response)
return $self->redirect(...) unless $vz and $vz->{_permissions}{can_view};
```

**Pattern 5: Fix hashref access**

```perl
# BEFORE
a => $self->current_account->id_token,

# AFTER
a => $self->current_account->{account_token},
```

#### 3.2 Fix Server.pm

**Replace servers relationship:**

```perl
# BEFORE
my $servers = $self->current_account->servers;

# AFTER
my $result = get_account_servers(
    auth => $self->plain_cookie($self->user_cookie_name),
    include_verification => JSON::XS::true,
    context => $self->_get_request_context(),
);
my $servers = $result->{data}{servers} || [];
```

**Replace nested permission checks:**

```perl
# BEFORE
return 403 unless $server->account->can_edit($self->user);

# AFTER (fetch server WITH account context)
my $result = get_server(
    ip => $server_ip,
    include_account => JSON::XS::true,
    auth => $self->plain_cookie($self->user_cookie_name),
);
my $server = $result->{data}{server};
return 403 unless $server->{account}{_permissions}{can_edit};
```

#### 3.3 Fix Monitor.pm

**Replace permission checks:**

```perl
# BEFORE
if ($mon and !$mon->can_edit($self->user)) {

# AFTER (fetch monitor WITH permissions)
my $result = get_monitor(
    id => $monitor_id,
    include_account => JSON::XS::true,
    auth => $self->plain_cookie($self->user_cookie_name),
);
my $mon = $result->{data}{monitor};
if ($mon and !$mon->{_permissions}{can_edit}) {
```

#### 3.4 Fix UserProfile.pm

**Replace ORM query:**

UserProfile.pm now uses `get_account_servers` from the Server service, which already provides account info and access control. No separate account lookup needed.

```perl
# CURRENT (uses get_account_servers which includes account data)
my $account_result = $self->account_data($account_slug);
my $account_data = $account_result->{data}{account};
my $servers = $account_result->{data}{servers} || [];
```

#### 3.5 Fix Staff.pm

**Replace relationship access:**

```perl
# BEFORE
} $account->servers_all

# AFTER
my $result = get_account_servers(
    account => $account->{account_token},
    include_deleted => JSON::XS::true,
    auth => $self->plain_cookie($self->user_cookie_name),
);
my $servers = $result->{data}{servers} || [];
```

### Phase 4: Update Templates (Minimal)

Most templates already updated in parent plan. Only vendor-specific templates may need adjustments for subscription status display.

### Phase 5: Remove NP::Model::Account

**Now we can actually do this:**

```bash
# Verify no references
git grep 'NP::Model->account' lib/ docs/
git grep '->can_edit' lib/ docs/ | grep -v '_permissions'
git grep '->can_view' lib/ docs/ | grep -v '_permissions'
git grep '->servers' lib/ | grep -v '# '
git grep '->vendor_zones' lib/
git grep '->account_subscriptions' lib/
git grep '->live_subscriptions' lib/

# Should return zero results (or only NP::Model::Account.pm itself)

# Add to ignored tables
# File: lib/NP/DB/Scaffold.pm
our @IGNORED_TABLES = qw(
    account              # Fully migrated to Go APIs - 2025-10-13
    account_invite       # Part of account system
    account_user         # Part of account system
    account_subscription # Part of account system
    # ... other tables
);

# Regenerate model
perl lib/NP/DB/Scaffold.pm

# Archive old code
mkdir -p old/model
git mv lib/NP/Model/Account.pm old/model/
git mv lib/NP/Model/AccountInvite.pm old/model/
git mv lib/NP/Model/AccountSubscription.pm old/model/

# Commit
git add lib/NP/DB/Scaffold.pm lib/NP/Model.pm old/model/
git commit -m "refactor(account): remove ORM models, fully migrated to Go APIs"
```

---

## API Implementation Checklist

### Go API Handlers (api/ntppool)

- [ ] Implement GetAccountVendorZones handler
- [ ] Implement GetVendorZone handler with subscription status
- [ ] Implement UpdateAccountStripeCustomer handler
- [x] Implement GetAccountServers handler (complete - already in use)
- [ ] Implement GetServer handler with account context
- [ ] Extend GetMonitor to include account context and permissions
- [ ] Add SQL queries for vendor zones, subscriptions
- [ ] Implement subscription validation logic (limits_not_exceeded)
- [ ] Implement live_subscriptions filtering
- [ ] Implement permission computation for VendorZone
- [ ] Implement permission computation for Monitor
- [ ] Write Go unit tests for all new handlers
- [ ] Write Go integration tests

### Perl CAPI Layer (lib/NP/CAPI/)

- [ ] Add get_account_vendor_zones wrapper
- [ ] Add get_vendor_zone wrapper
- [ ] Add update_account_stripe_customer wrapper
- [x] Add get_account_servers wrapper (complete - already generated)
- [ ] Add get_server wrapper
- [ ] Add get_monitor wrapper (or extend existing)
- [ ] Write Perl tests for CAPI wrappers

### Perl Controllers (lib/NTPPool/Control/)

- [ ] Update Vendor.pm: Replace all ORM access (50+ lines)
- [ ] Update Manage/Server.pm: Replace servers relationship (2 places)
- [ ] Update Manage/Server.pm: Replace nested permission checks (2 places)
- [ ] Update Manage/Monitor.pm: Replace permission checks (1 place)
- [ ] Update API/Staff.pm: Replace servers_all access
- [ ] Update UserProfile.pm: Replace ORM query
- [ ] Add error handling for all new API calls
- [ ] Test vendor zone management flow
- [ ] Test subscription flow
- [ ] Test server management flow
- [ ] Test monitor management flow

### Phase 5 (Model Removal)

- [ ] Verify zero ORM references with grep
- [ ] Add account tables to ignored tables
- [ ] Regenerate NP::Model
- [ ] Archive old Account.pm files
- [ ] Commit model removal
- [ ] Deploy to staging
- [ ] Verify staging functionality
- [ ] Deploy to production

---

## Success Criteria

### Technical Requirements

✅ **Zero Database Access from Perl**
- No `NP::Model->account` calls
- No `NP::Model->account_invite` calls
- No `NP::Model->account_subscription` calls
- No relationship access (`->servers`, `->vendor_zones`, `->account_subscriptions`)
- No ORM writes (`->save()`)

✅ **All Business Logic in Go**
- `subscription_limits_not_exceeded()` → Go API
- `have_live_subscription()` → Go API
- `can_edit()` / `can_view()` → Go API (returned as `_permissions` flags)
- Server/VendorZone/Monitor permission checks → Go API

✅ **Plain Hashrefs Only**
- No blessed objects in controllers
- All account data from API responses
- Permission checks use `$obj->{_permissions}{can_edit}`
- Field access uses `$account->{account_id}`

✅ **Single API Calls**
- No N+1 queries
- Fetch related data in one call (server with account, vendorzone with subscription status)
- Permissions computed server-side

### Functional Requirements

- [ ] Account management pages work (already done)
- [ ] Vendor zone creation/editing works
- [ ] Subscription purchase flow works
- [ ] Server management works
- [ ] Monitor management works
- [ ] Public profile pages work
- [ ] Staff APIs work
- [ ] No performance regressions
- [ ] All existing tests pass
- [ ] New tests cover API functionality

---

## Migration Strategy

### Development Order (By Issue)

**Phase 1: Issue #22 - Stripe Billing & Subscription Validation (Critical)**

**Week 1-2: Go API Development**
1. Add stripe_customer_id to Account proto
2. Extend UpdateAccount to accept stripe_customer_id
3. Create subscription validation logic:
   - Add ValidateSubscriptionLimits RPC or extend GetAccount
   - Input: account_token, device_count
   - Output: subscription_status with validation flags
4. Create subscription CRUD APIs:
   - CreateOrUpdateAccountSubscription RPC
   - UpdateSubscriptionStatus RPC
5. Add VendorZone permission computation (_permissions.can_edit, _permissions.can_view)
6. Write comprehensive tests

**Week 3: Perl Integration**
1. Update NP::CAPI::Account wrappers
2. Create NP::CAPI::Subscription (or add to Account)
3. Update Vendor.pm to use new APIs
4. Update Webhook.pm to use subscription APIs
5. Test vendor zone submission flow
6. Test Stripe checkout flow
7. Test webhook processing

**Phase 2: Issue #25 - Server Permissions (Critical)**

**Week 4: Server API Enhancement**
1. Extend GetServer to include account context
2. Add ServerPermissions computation
3. Update CAPI wrappers
4. Update Server.pm req_server method
5. Test server management flows

**Phase 3: Issue #28 - Monitor API (Lower Priority)**

**Week 5: Monitor ConnectRPC Migration**
1. Create proto/ntppool/monitor/v1/monitor.proto
2. Implement Monitor service
3. Create NP::CAPI::Monitor
4. Update Monitor.pm from int_api to CAPI
5. Test monitor flows

**Phase 4: Model Removal & Deployment**

**Week 6: Final Cleanup & Removal**
1. Verify zero ORM references
2. Add account tables to @IGNORED_TABLES
3. Archive NP::Model::Account to old/model/
4. Regenerate NP::Model
5. Test all flows end-to-end
6. Deploy to staging
7. Monitor staging for issues
8. Deploy to production

### Rollback Plan

Each API is backward compatible:
- Old code can continue using ORM while new APIs exist
- Deploy APIs first, then update Perl code incrementally
- Can revert Perl changes without breaking APIs
- No database schema changes required

---

## Risk Assessment

### High Risk Areas

1. **Vendor Subscription Flow** - Complex Stripe integration, high-value transactions
   - Mitigation: Thorough testing with Stripe test mode
   - Mitigation: Manual QA of entire flow before production

2. **Permission Checks** - Security-critical, nested relationships
   - Mitigation: Audit all permission computations in Go
   - Mitigation: Write comprehensive permission tests
   - Mitigation: Compare Go results to ORM results during migration

3. **Server Management** - Core functionality, affects pool operation
   - Mitigation: Parallel testing (ORM + API) before switching
   - Mitigation: Deploy during low-traffic period

### Medium Risk Areas

1. **Public Profile Pages** - External visibility, SEO
   - Mitigation: Test URL slug lookups thoroughly
   - Mitigation: Monitor 404 rates after deployment

2. **Business Logic Parity** - subscription_limits_not_exceeded calculations
   - Mitigation: Write property-based tests
   - Mitigation: Verify calculations match ORM behavior

---

## Related Plans

- **Parent:** account-model-removal-revised.md (Phases 1-4 complete, Phase 5 blocked)
- **Dependency:** PostgreSQL migration (postgres.md) - Ensures Go writes to correct database
- **Future:** Complete monitor API migration
- **Future:** Complete vendor zone API migration
- **Future:** Remove all Rose::DB models

---

## Notes

**Key Architectural Insight:**

The original plan underestimated how deeply Account ORM is embedded in the codebase. It's not just the `/manage/account` area - it's:

1. **Permission system** - Every resource checks `account->users` for permissions
2. **Subscription system** - Vendor zones check account subscriptions
3. **Server management** - Servers belong to accounts and check permissions
4. **Monitor management** - Monitors belong to accounts
5. **Stripe integration** - Account stores stripe_customer_id

**The solution is NOT to patch each use site** - that's whack-a-mole. **The solution is to move ALL permission checks and business logic to Go**, then have Perl just display the results.

**After this plan:**
- Perl has ZERO knowledge of database schema
- Perl has ZERO business logic
- Perl is PURELY HTTP → API → Template → HTTP
- All complexity lives in Go (testable, type-safe, fast)

This is the correct architecture for a modern web application.
