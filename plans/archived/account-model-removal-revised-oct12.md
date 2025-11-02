# Plan: Remove NP::Model::Account Dependency (Revised)

**Status:** Phase 1 API Definitions Complete - Ready for Go Implementation
**Created:** 2025-10-10
**Revised:** 2025-10-12
**Goal:** Eliminate NP::Model::Account ORM dependency, making Perl purely a presentation layer and completing PostgreSQL migration for accounts.

---

## Current Status (2025-10-12)

### ✅ Completed
- Proto definitions for all 4 new/extended APIs
- SQL queries for deletion validation (CountActiveServers, CountVendorZones, CountActiveMonitors, CountActiveAccountUsers)
- Generated protobuf code with `buf generate`
- Generated SQLC code with `sqlc generate`

### 🔧 In Progress
- None

### 📋 Remaining Work
**Phase 1: Go Implementation**
- Implement ValidateSession with account context resolution
- Implement GetAccount with modes (BASIC, WITH_PERMISSIONS, MANAGEMENT, TEAM, DELETION_CHECK)
- Implement CanDeleteAccount API handler
- Implement CheckUserDeletionEligibility API handler
- Add helper functions: toAccountContext(), computeDisplayName(), computePermissions()
- Write Go unit and integration tests

**Phase 2-5: Perl Integration** (unchanged from original plan)
- Update lib/NP/CAPI/Account.pm with new API wrappers
- Update lib/NTPPool/Control/Manage.pm current_account() method
- Update lib/NTPPool/Control/Manage/Account.pm render_user_delete()
- Update templates to use plain hashrefs instead of ORM objects
- Remove NP::Model::Account and regenerate models

### 📝 Notes
- VendorZone message simplified to remove non-existent fields (was using `rt_limit` and `vendor_cluster`, now just has `vendor_zone_id`, `zone_name`, `status`)
- All deletion count queries use account_id directly (not pgtype.Int8) for consistency
- AccountContext and AccountPermissions messages are reused across ValidateSession and GetAccount responses

---

## Executive Summary

This plan migrates all Account ORM functionality to Go ConnectRPC APIs. After completion:
- ✅ All account data comes from Go APIs (PostgreSQL)
- ✅ No Perl code reads from MySQL `accounts` table
- ✅ Perl layer is pure presentation/templating
- ✅ NP::Model::Account removed from codebase
- ✅ Session API handles account resolution and permissions

**Key Architectural Changes:**
1. **Session API resolves current account** - Eliminates `current_account()` database queries
2. **Deletion validation in Go** - New `CanDeleteAccount` API moves logic from Perl
3. **Plain hashrefs for templates** - No blessed objects, simpler templates
4. **GetAccount with modes** - Group related flags for common use cases
5. **Consolidated server queries** - Single flexible endpoint

---

## Key Design Decisions

### 1. Move Account Resolution to Session API

**Current Problem:** `current_account()` in Manage.pm does:
- Token decoding (`NP::Model::Account->token_id()`)
- Database queries (`NP::Model->account->fetch()`)
- Permission checks (`$account->can_view()`)
- Default account logic (query user's first account)

**Solution:** `ValidateSession` returns account context with permissions.

**Benefits:**
- Single API call instead of multiple database queries
- Go handles token resolution (no token_id lookup in Perl)
- Permissions computed server-side
- Default account logic in one place (Go)

### 2. Account Data Modes

Instead of 7 boolean flags, use modes for common patterns:
- **BASIC** - Core fields + computed (url, display_name, public_url)
- **WITH_PERMISSIONS** - BASIC + permission flags
- **MANAGEMENT** - Everything for /manage/account page
- **TEAM** - BASIC + users list
- **DELETION_CHECK** - Full data for deletion validation

**Can still use individual flags for custom combinations.**

### 3. Deletion Validation API

**Current Problem:** `render_user_delete()` iterates ORM relationships:
```perl
for my $s ($a->servers) { ... }
for my $v ($a->vendor_zones) { ... }
for my $m ($a->monitors) { ... }
```

**Solution:** `CanDeleteAccount` API returns:
- Boolean: can_delete
- List of blockers (user-friendly messages)
- Counts for UI display

**Benefits:**
- Business logic in Go (testable, consistent)
- Perl just displays results
- Clear API contract

### 4. Plain Hashrefs in Templates

**No blessed objects** - Templates access hash keys directly.

**BEFORE:**
```html
[% IF account.can_edit(combust.user) %]
[% account.display_name %]
```

**AFTER:**
```html
[% IF account._permissions.can_edit %]
[% account.display_name %]
```

**Benefits:**
- Simpler (no magic method calls)
- Clear data flow (controller → template)
- No ORM abstraction leaking into views

---

## Phase 1: Extend Session & Account APIs

### 1.1 Extend ValidateSession with Account Context

**File:** `proto/ntppool/account/v1/account.proto`

**Extend ValidateSessionRequest:**
```protobuf
message ValidateSessionRequest {
  // session_token is the session token from the npuid cookie.
  // Required.
  string session_token = 1;

  // account_token optionally specifies which account to use (from ?a= parameter)
  // If provided, validates user has access to this account
  // If omitted, returns user's default account (first account in user's list)
  // Returns error if account_token specified but user lacks access
  optional string account_token = 2;
}
```

**Extend ValidateSessionResponse:**
```protobuf
message ValidateSessionResponse {
  // valid indicates if the session token is valid and active.
  bool valid = 1;

  // user_id is the numeric ID of the authenticated user.
  int64 user_id = 2;

  // email is the user's email address.
  string email = 3;

  // username is the user's username.
  string username = 4;

  // user_token is the user's id_token for identification.
  string user_token = 5;

  // account is the current account context (specified or default)
  // Omitted if user has no accounts or account is inaccessible
  optional AccountContext account = 6;

  // permissions for the authenticated user on this account
  // Only present if account is present
  optional AccountPermissions permissions = 7;
}
```

**Add new message types:**
```protobuf
// AccountContext contains full account information with computed fields
message AccountContext {
  // Core database fields
  int64 account_id = 1;
  string account_token = 2;
  string name = 3;
  optional string organization_name = 4;
  optional string organization_url = 5;
  optional string url_slug = 6;
  bool public_profile = 7;
  optional string flags = 8;
  string created_on = 9;
  string modified_on = 10;

  // Computed fields (always included)
  string url = 11;          // Management URL: /manage?a={token}
  string public_url = 12;   // Public profile: /a/{url_slug} (empty if no url_slug)
  string display_name = 13; // Computed: name || organization_name || url_slug
}

// AccountPermissions contains permission flags for the authenticated user
message AccountPermissions {
  // can_edit: User is in account or is staff
  bool can_edit = 1;

  // can_view: User is in account, is staff, or is monitor admin
  bool can_view = 2;

  // can_add_servers: Checks server verification status
  // - Allow if no servers yet
  // - Block if 2+ unverified servers
  // - Otherwise allow
  bool can_add_servers = 3;
}
```

**Implementation Notes:**
- **Default account logic:** First account from `GetUserAccounts` query
- **Token resolution:** Decode account_token using existing TokenID logic
- **Permission computation:**
  - can_edit: Check if user_id in account_users OR user.is_staff
  - can_view: can_edit OR user.is_monitor_admin
  - can_add_servers: Query server verification counts
- **Computed fields:**
  - display_name: `name || organization_name || url_slug || ""`
  - url: `/manage?a={account_token}`
  - public_url: `url_slug ? "/a/{url_slug}" : ""`

---

### 1.2 Add GetAccount API with Modes

**File:** `proto/ntppool/account/v1/account.proto`

**Add RPC (already exists, we're extending it):**
```protobuf
// GetAccount returns full account information.
// Authentication: Required via session middleware (sessions.GetAccount).
// Authorization: User must have access to the account.
rpc GetAccount(GetAccountRequest) returns (GetAccountResponse) {}
```

**Extend GetAccountRequest:**
```protobuf
message GetAccountRequest {
  // mode determines what data to include (defaults to BASIC)
  AccountDataMode mode = 1;

  // Custom flags for fine-grained control (override mode defaults)
  optional bool include_permissions = 10;
  optional bool include_users = 11;
  optional bool include_subscriptions = 12;
  optional bool include_monitor_config = 13;
  optional bool include_servers_summary = 14;
  optional bool include_servers = 15;        // Full server list with details
  optional bool include_vendor_zones = 16;
  optional bool include_monitors = 17;
}

enum AccountDataMode {
  BASIC = 0;           // Just account fields + computed fields (url, display_name, etc.)
  WITH_PERMISSIONS = 1; // BASIC + permissions
  MANAGEMENT = 2;      // BASIC + permissions + monitor_config + users (for /manage/account)
  TEAM = 3;            // BASIC + permissions + users + invites (for /manage/account/team)
  DELETION_CHECK = 4;  // BASIC + servers + monitors + vendor_zones (for deletion validation)
}
```

**Replace GetAccountResponse:**
```protobuf
message GetAccountResponse {
  // Core account with computed fields (always included)
  AccountContext account = 1;

  // Optional fields (based on mode or custom flags)
  optional AccountPermissions permissions = 2;
  repeated AccountUser users = 3;
  repeated AccountSubscription subscriptions = 4;
  optional MonitorConfig monitor_config = 5;
  optional ServersSummary servers_summary = 6;
  repeated ServerDetail servers = 7;         // Full server list
  repeated VendorZone vendor_zones = 8;
  repeated Monitor monitors = 9;
}
```

**Add supporting message types:**
```protobuf
// MonitorConfig contains monitor-related flags from account.flags JSON
message MonitorConfig {
  bool monitor_enabled = 1;
  int64 monitor_limit = 2;                    // Default: 3
  int64 monitors_per_server_limit = 3;       // Default: 1
}

// ServersSummary contains server counts for account
message ServersSummary {
  int64 total_servers = 1;      // All servers (including deleted)
  int64 active_servers = 2;     // deletion_on IS NULL OR deletion_on > NOW()
  int64 deleted_servers = 3;    // deletion_on IS NOT NULL AND deletion_on <= NOW()
  int64 bad_servers = 4;        // score_raw < -15 (BAD_SERVER_THRESHOLD)
}

// ServerDetail contains full server information
message ServerDetail {
  int64 id = 1;
  string ip = 2;
  string hostname = 3;
  int32 ip_version = 4;
  int32 stratum = 5;
  bool in_pool = 6;
  int32 netspeed = 7;
  double score_raw = 8;
  string deletion_on = 9;      // ISO 8601 or empty
  bool verified = 10;
  string verified_on = 11;     // ISO 8601 or empty
  repeated string zones = 12;  // Zone names only
  repeated string urls = 13;
  string created_on = 14;
  string modified_on = 15;
}

// VendorZone contains vendor zone information
message VendorZone {
  int64 vendor_zone_id = 1;
  string zone_name = 2;
  string vendor_cluster = 3;
  int32 rt_limit = 4;
  string status = 5;
}

// Monitor contains monitor information
message Monitor {
  int64 monitor_id = 1;
  string ip = 2;
  string hostname = 3;
  string status = 4;        // active, deleted, etc.
  string created_on = 5;
}

// AccountSubscription contains subscription information
message AccountSubscription {
  int64 subscription_id = 1;
  string stripe_subscription_id = 2;
  string status = 3;           // active, canceled, past_due, etc.
  bool live_subscription = 4;  // Computed: status == 'active' or 'trialing'
  string created_on = 5;
  optional string canceled_at = 6;
}
```

**Mode Behavior:**
- **BASIC (0)**: Only `account` field populated
- **WITH_PERMISSIONS (1)**: `account` + `permissions`
- **MANAGEMENT (2)**: `account` + `permissions` + `monitor_config` + `users`
- **TEAM (3)**: `account` + `permissions` + `users`
- **DELETION_CHECK (4)**: `account` + `servers` + `monitors` + `vendor_zones`

**Implementation (Go):**
```go
func (s *Server) GetAccount(ctx context.Context, req *accountv1.GetAccountRequest) (*accountv1.GetAccountResponse, error) {
    // Get account from session context
    account := sessions.GetAccount(ctx)
    user := sessions.GetUser(ctx)

    // Build base response
    resp := &accountv1.GetAccountResponse{
        Account: toAccountContext(account),
    }

    // Apply mode defaults
    includePerms := req.Mode >= accountv1.AccountDataMode_WITH_PERMISSIONS
    includeUsers := req.Mode == accountv1.AccountDataMode_MANAGEMENT ||
                    req.Mode == accountv1.AccountDataMode_TEAM
    includeMonitorConfig := req.Mode == accountv1.AccountDataMode_MANAGEMENT
    includeServers := req.Mode == accountv1.AccountDataMode_DELETION_CHECK
    includeMonitors := req.Mode == accountv1.AccountDataMode_DELETION_CHECK
    includeVendorZones := req.Mode == accountv1.AccountDataMode_DELETION_CHECK

    // Override with explicit flags if provided
    if req.IncludePermissions != nil {
        includePerms = *req.IncludePermissions
    }
    if req.IncludeUsers != nil {
        includeUsers = *req.IncludeUsers
    }
    // ... other overrides

    // Populate optional fields
    if includePerms {
        resp.Permissions = s.computePermissions(ctx, account, user)
    }
    if includeUsers {
        users, err := s.getAccountUsers(ctx, account.ID)
        if err != nil {
            return nil, err
        }
        resp.Users = users
    }
    // ... populate other fields

    return resp, nil
}

func toAccountContext(account *db.Account) *accountv1.AccountContext {
    return &accountv1.AccountContext{
        AccountId:        account.ID,
        AccountToken:     account.IDToken,
        Name:             account.Name,
        OrganizationName: nullStringToOptional(account.OrganizationName),
        OrganizationUrl:  nullStringToOptional(account.OrganizationUrl),
        UrlSlug:          nullStringToOptional(account.UrlSlug),
        PublicProfile:    account.PublicProfile,
        Flags:            nullStringToOptional(account.Flags),
        CreatedOn:        account.CreatedOn.Format(time.RFC3339),
        ModifiedOn:       account.ModifiedOn.Format(time.RFC3339),
        Url:              computeManagementURL(account),
        PublicUrl:        computePublicURL(account),
        DisplayName:      computeDisplayName(account),
    }
}

func computeDisplayName(account *db.Account) string {
    if account.Name != "" {
        return account.Name
    }
    if account.OrganizationName.Valid && account.OrganizationName.String != "" {
        return account.OrganizationName.String
    }
    if account.UrlSlug.Valid && account.UrlSlug.String != "" {
        return account.UrlSlug.String
    }
    return ""
}

func computeManagementURL(account *db.Account) string {
    return fmt.Sprintf("/manage?a=%s", account.IDToken)
}

func computePublicURL(account *db.Account) string {
    if account.UrlSlug.Valid && account.UrlSlug.String != "" {
        return fmt.Sprintf("/a/%s", account.UrlSlug.String)
    }
    return ""
}
```

---

### 1.3 Add CanDeleteAccount API

**Purpose:** Move account deletion validation logic from Perl to Go.

**File:** `proto/ntppool/account/v1/account.proto`

**Add RPC:**
```protobuf
// CanDeleteAccount checks if an account can be deleted.
// Authentication: Required via session middleware.
// Authorization: User must have access to the account being checked.
rpc CanDeleteAccount(CanDeleteAccountRequest) returns (CanDeleteAccountResponse) {}
```

**Add messages:**
```protobuf
message CanDeleteAccountRequest {
  // account_token optionally specifies which account to check
  // If omitted, checks the authenticated user's current account
  optional string account_token = 1;
}

message CanDeleteAccountResponse {
  // can_delete indicates if the account can be deleted
  bool can_delete = 1;

  // blockers lists reasons why deletion is blocked (empty if can_delete is true)
  // User-friendly messages suitable for UI display
  repeated string blockers = 2;

  // details provides structured information about deletion blockers
  optional DeletionBlockDetails details = 3;
}

message DeletionBlockDetails {
  // active_servers_count is the number of servers not scheduled for deletion
  int64 active_servers_count = 1;

  // vendor_zones_count is the number of vendor zones (any status)
  int64 vendor_zones_count = 2;

  // active_monitors_count is the number of monitors with status != 'deleted'
  int64 active_monitors_count = 3;

  // has_other_users indicates if account has other non-deleted users
  bool has_other_users = 4;
}
```

**Implementation (Go):**
```go
func (s *Server) CanDeleteAccount(ctx context.Context, req *accountv1.CanDeleteAccountRequest) (*accountv1.CanDeleteAccountResponse, error) {
    // Get account from session context or resolve token
    var account *db.Account
    if req.AccountToken != nil && *req.AccountToken != "" {
        // Resolve token to account
        accountID, err := s.tokenID(*req.AccountToken)
        if err != nil {
            return nil, connect.NewError(connect.CodeInvalidArgument, err)
        }
        account, err = s.queries.GetAccount(ctx, accountID)
        if err != nil {
            return nil, connect.NewError(connect.CodeNotFound, err)
        }
    } else {
        account = sessions.GetAccount(ctx)
    }

    resp := &accountv1.CanDeleteAccountResponse{
        CanDelete: true,
        Blockers:  []string{},
        Details: &accountv1.DeletionBlockDetails{},
    }

    // Check active servers
    activeServers, err := s.queries.CountActiveServers(ctx, account.ID)
    if err != nil {
        return nil, err
    }
    resp.Details.ActiveServersCount = activeServers
    if activeServers > 0 {
        resp.CanDelete = false
        resp.Blockers = append(resp.Blockers,
            fmt.Sprintf("Account has %d active server%s",
                activeServers, pluralize(activeServers)))
    }

    // Check vendor zones
    vendorZones, err := s.queries.CountVendorZones(ctx, account.ID)
    if err != nil {
        return nil, err
    }
    resp.Details.VendorZonesCount = vendorZones
    if vendorZones > 0 {
        resp.CanDelete = false
        resp.Blockers = append(resp.Blockers,
            fmt.Sprintf("Account has %d vendor zone%s",
                vendorZones, pluralize(vendorZones)))
    }

    // Check active monitors
    activeMonitors, err := s.queries.CountActiveMonitors(ctx, account.ID)
    if err != nil {
        return nil, err
    }
    resp.Details.ActiveMonitorsCount = activeMonitors
    if activeMonitors > 0 {
        resp.CanDelete = false
        resp.Blockers = append(resp.Blockers,
            fmt.Sprintf("Account has %d active monitor%s",
                activeMonitors, pluralize(activeMonitors)))
    }

    // Check if account has other users
    otherUsers, err := s.queries.CountActiveAccountUsers(ctx, account.ID)
    if err != nil {
        return nil, err
    }
    resp.Details.HasOtherUsers = otherUsers > 1

    return resp, nil
}
```

**SQL Queries (db/queries/account.sql):**
```sql
-- name: CountActiveServers :one
SELECT COUNT(*)
FROM servers
WHERE account_id = $1
  AND (deletion_on IS NULL OR deletion_on > NOW());

-- name: CountVendorZones :one
SELECT COUNT(*)
FROM vendor_zones
WHERE account_id = $1;

-- name: CountActiveMonitors :one
SELECT COUNT(*)
FROM monitors
WHERE account_id = $1
  AND status != 'deleted';

-- name: CountActiveAccountUsers :one
SELECT COUNT(*)
FROM account_users
WHERE account_id = $1
  AND deletion_on IS NULL;
```

---

### 1.4 Add CheckUserDeletionEligibility API

**Purpose:** Consolidate user deletion validation logic across ALL user accounts into single API call.

**Problem:** Current `render_user_delete()` code:
- Makes 1 API call to get user's accounts
- Makes N API calls to get users for each account
- **Still uses ORM queries for servers, vendor_zones, monitors**
- Business logic (filtering, iteration) scattered in Perl

**File:** `proto/ntppool/account/v1/account.proto`

**Add RPC:**
```protobuf
// CheckUserDeletionEligibility checks if a user can be deleted.
// Validates all accounts owned solely by the user and returns blocker details.
// Authentication: Required via session middleware.
// Authorization: User must be the target user or staff.
rpc CheckUserDeletionEligibility(CheckUserDeletionEligibilityRequest)
    returns (CheckUserDeletionEligibilityResponse) {}
```

**Add messages:**
```protobuf
message CheckUserDeletionEligibilityRequest {
  // user_token optionally specifies which user to check
  // If omitted, checks the authenticated user
  optional string user_token = 1;
}

message CheckUserDeletionEligibilityResponse {
  // can_delete indicates if the user can be deleted
  bool can_delete = 1;

  // blockers lists user-friendly messages for UI display
  repeated string blockers = 2;

  // affected_accounts lists all accounts where user is sole owner
  repeated AccountDeletionStatus affected_accounts = 3;
}

message AccountDeletionStatus {
  int64 account_id = 1;
  string account_token = 2;
  string account_name = 3;

  // True if user is the only non-deleted user on this account
  bool user_is_sole_owner = 4;

  // Blocker details (only populated if user_is_sole_owner = true)
  int64 active_servers_count = 5;
  int64 vendor_zones_count = 6;
  int64 active_monitors_count = 7;
}
```

**Implementation (Go):**
```go
func (s *Server) CheckUserDeletionEligibility(ctx context.Context, req *accountv1.CheckUserDeletionEligibilityRequest) (*accountv1.CheckUserDeletionEligibilityResponse, error) {
    // Get user from session or resolve token
    var userID int64
    if req.UserToken != nil && *req.UserToken != "" {
        // Resolve user token (staff only)
        user := sessions.GetUser(ctx)
        if !user.IsStaff {
            return nil, connect.NewError(connect.CodePermissionDenied,
                fmt.Errorf("only staff can check other users"))
        }
        // Resolve token to user ID
        var err error
        userID, err = s.tokenID(*req.UserToken)
        if err != nil {
            return nil, connect.NewError(connect.CodeInvalidArgument, err)
        }
    } else {
        user := sessions.GetUser(ctx)
        userID = user.ID
    }

    resp := &accountv1.CheckUserDeletionEligibilityResponse{
        CanDelete: true,
        Blockers: []string{},
        AffectedAccounts: []*accountv1.AccountDeletionStatus{},
    }

    // Get all accounts for user
    accounts, err := s.queries.GetUserAccounts(ctx, userID)
    if err != nil {
        return nil, err
    }

    // Check each account
    for _, account := range accounts {
        // Count non-deleted users on this account
        activeUsers, err := s.queries.CountActiveAccountUsers(ctx, account.ID)
        if err != nil {
            return nil, err
        }

        accountStatus := &accountv1.AccountDeletionStatus{
            AccountId:        account.ID,
            AccountToken:     account.IDToken,
            AccountName:      account.Name,
            UserIsSoleOwner:  activeUsers == 1,
        }

        // Only check blockers if user is sole owner
        if activeUsers == 1 {
            // Check active servers
            activeServers, err := s.queries.CountActiveServers(ctx, account.ID)
            if err != nil {
                return nil, err
            }
            accountStatus.ActiveServersCount = activeServers
            if activeServers > 0 {
                resp.CanDelete = false
                resp.Blockers = append(resp.Blockers,
                    fmt.Sprintf("Account '%s' has %d active server%s",
                        account.Name, activeServers, pluralize(activeServers)))
            }

            // Check vendor zones
            vendorZones, err := s.queries.CountVendorZones(ctx, account.ID)
            if err != nil {
                return nil, err
            }
            accountStatus.VendorZonesCount = vendorZones
            if vendorZones > 0 {
                resp.CanDelete = false
                resp.Blockers = append(resp.Blockers,
                    fmt.Sprintf("Account '%s' has %d vendor zone%s",
                        account.Name, vendorZones, pluralize(vendorZones)))
            }

            // Check active monitors
            activeMonitors, err := s.queries.CountActiveMonitors(ctx, account.ID)
            if err != nil {
                return nil, err
            }
            accountStatus.ActiveMonitorsCount = activeMonitors
            if activeMonitors > 0 {
                resp.CanDelete = false
                resp.Blockers = append(resp.Blockers,
                    fmt.Sprintf("Account '%s' has %d active monitor%s",
                        account.Name, activeMonitors, pluralize(activeMonitors)))
            }

            resp.AffectedAccounts = append(resp.AffectedAccounts, accountStatus)
        }
    }

    return resp, nil
}
```

**Benefits:**
- **Single API call** replaces 1 + N + database queries
- **All business logic in Go** (testable, consistent)
- **Eliminates ORM dependency** for user deletion flow
- **Comprehensive reporting** for UI display

---

### 1.5 API Endpoints to Deprecate

**Remove these after migration:**
- `GetAccountServerVerificationStatus` - Logic folded into `permissions.can_add_servers`
- (Future) `GetAccountServersManage` - Replaced by `GetAccount` with `include_servers=true`

---

## Phase 2: Update Perl CAPI Layer

### File: lib/NP/CAPI/Account.pm

**Add new functions:**

```perl
use constant CAPI_SERVICE => 'ntppool.account.v1.AccountService';

# Validate session with account context
sub validate_session_with_account {
    my %args = @_;

    my $req = {
        session_token => $args{session_token},
    };

    # Add account_token if provided (from ?a= parameter)
    if ($args{account_token}) {
        $req->{account_token} = $args{account_token};
    }

    return _capi_call(
        service => CAPI_SERVICE,
        method  => 'ValidateSession',
        request => $req,
        context => $args{context},
    );
}

# Get account with flexible options
sub get_account {
    my %args = @_;

    # Extract mode if provided
    my $mode = delete $args{mode};

    my $req = {};

    # Set mode if provided
    $req->{mode} = $mode if defined $mode;

    # Add custom flags if provided (override mode defaults)
    for my $flag (qw(include_permissions include_users include_subscriptions
                     include_monitor_config include_servers_summary include_servers
                     include_vendor_zones include_monitors)) {
        if (exists $args{$flag}) {
            $req->{$flag} = delete $args{$flag} ? JSON::XS::true : JSON::XS::false;
        }
    }

    return _capi_call(
        service => CAPI_SERVICE,
        method  => 'GetAccount',
        request => $req,
        auth    => $args{auth},
        account => $args{account},
        context => $args{context},
    );
}

# Convenience methods for common modes
sub get_account_basic {
    return get_account(@_, mode => 0);  # BASIC
}

sub get_account_with_permissions {
    return get_account(@_, mode => 1);  # WITH_PERMISSIONS
}

sub get_account_management {
    return get_account(@_, mode => 2);  # MANAGEMENT
}

sub get_account_team {
    return get_account(@_, mode => 3);  # TEAM
}

sub get_account_for_deletion {
    return get_account(@_, mode => 4);  # DELETION_CHECK
}

# Check if account can be deleted
sub can_delete_account {
    my %args = @_;

    my $req = {};

    # Add account_token if checking specific account
    if ($args{account_token}) {
        $req->{account_token} = $args{account_token};
    }

    return _capi_call(
        service => CAPI_SERVICE,
        method  => 'CanDeleteAccount',
        request => $req,
        auth    => $args{auth},
        account => $args{account},
        context => $args{context},
    );
}

# Check if user can be deleted (validates all user's accounts)
sub check_user_deletion_eligibility {
    my %args = @_;

    my $req = {};

    # Add user_token if checking specific user (staff only)
    if ($args{user_token}) {
        $req->{user_token} = $args{user_token};
    }

    return _capi_call(
        service => CAPI_SERVICE,
        method  => 'CheckUserDeletionEligibility',
        request => $req,
        auth    => $args{auth},
        context => $args{context},
    );
}
```

**Update exports:**
```perl
use Exporter 'import';
our @EXPORT_OK = qw(
    get_account_status
    process_auth0_login
    validate_session_with_account
    create_account
    update_account
    get_account
    get_account_basic
    get_account_with_permissions
    get_account_management
    get_account_team
    get_account_for_deletion
    can_delete_account
    check_user_deletion_eligibility
    remove_user_from_account
    create_user_task
    get_account_users
    get_user_accounts
    get_account_invites
);
```

---

## Phase 3: Update Perl Controllers

### File: lib/NTPPool/Control/Manage.pm

**Replace current_account() method entirely:**

```perl
sub current_account {
    my $self = shift;

    # Return cached account if already loaded
    if (exists $self->{_current_account}) {
        return $self->{_current_account};
    }

    # Get session cookie
    my $session_token = $self->plain_cookie($self->user_cookie_name);
    return $self->{_current_account} = undef unless $session_token;

    # Call ValidateSession with optional account token
    # Go API will:
    # 1. Validate session
    # 2. Resolve account_token (if provided) or use default
    # 3. Check permissions
    # 4. Return account context + permissions
    my $result = validate_session_with_account(
        session_token => $session_token,
        account_token => $self->req_param('a'),  # Optional ?a= parameter
        context       => $self->_get_request_context(),
    );

    # Handle errors (invalid session, inaccessible account, etc.)
    if ($result->{error}) {
        warn "ValidateSession error: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
        return $self->{_current_account} = undef;
    }

    my $data = $result->{data};

    # Session valid but user has no accounts
    return $self->{_current_account} = undef unless $data->{account};

    # Return account as plain hashref
    # Store permissions in _permissions key for template access
    my $account = $data->{account};
    $account->{_permissions} = $data->{permissions} if $data->{permissions};

    return $self->{_current_account} = $account;
}
```

**Remove these methods (now in Go):**
- `account_monitor_config()` - Use `get_account_management()` to get monitor_config

**Update `init()` to handle account hashref:**
```perl
sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    # ... existing init code ...

    if (my $account = $self->current_account) {
        $self->tpl_param('account' => $account);
        $span->set_attribute("account.id",       $account->{account_id});
        $span->set_attribute("account.id_token", $account->{account_token});

        $self->request->env->{REMOTE_USER} .= '|' . $account->{account_token};
    }

    # ... rest of init ...
}
```

---

### File: lib/NTPPool/Control/Manage/Account.pm

**Update imports to include new function:**

```perl
use NP::CAPI::Account qw(
    get_account_users get_user_accounts get_account_invites
    create_account get_account update_account remove_user_from_account create_user_task
    check_user_deletion_eligibility
);
```

**Update render_user_delete to use consolidated API:**

```perl
sub render_user_delete {
    my ($self, $user) = @_;

    my $tracer = NP::Tracing->tracer;
    my $span   = $tracer->create_span(
        name => "render_user_delete",
        kind => SPAN_KIND_SERVER,
    );
    dynamically otel_current_context = otel_context_with_span($span);

    $self->tpl_param('user', $user);

    # Check deletion eligibility using new consolidated API
    # Single API call replaces multiple queries and ORM iterations
    my $result = check_user_deletion_eligibility(
        auth    => $self->plain_cookie($self->user_cookie_name),
        context => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "CheckUserDeletionEligibility error: " . $result->{error};
        warn "Trace ID: " . $result->{trace_id} if $result->{trace_id};
        $self->tpl_param('delete_available', 0);
        $self->tpl_param('delete_blockers', ["Error checking deletion eligibility: " . $result->{error}]);
        return OK, $self->evaluate_template('tpl/user/delete_confirmation.html');
    }

    my $eligibility = $result->{data};

    $self->tpl_param('delete_available', $eligibility->{can_delete});
    $self->tpl_param('delete_blockers', $eligibility->{blockers}) if @{$eligibility->{blockers} || []};

    return OK, $self->evaluate_template('tpl/user/delete_confirmation.html')
      unless $eligibility->{can_delete};

    if ($self->request->method eq 'post') {
        # ... rest of deletion logic (unchanged)
    }

    return OK, $self->evaluate_template('tpl/user/delete_confirmation.html');
}
```

**Benefits of new approach:**
- **1 API call** instead of 1 + N API calls + ORM database queries
- **No ORM usage** - eliminates `$a->servers`, `$a->vendor_zones`, `$a->monitors`
- **Business logic in Go** - filtering sole-owner accounts, checking blockers
- **Cleaner Perl** - just display what the API returns

**Remove ORM relationship calls:**
```perl
# DELETE THESE LINES (no longer needed):
my $accounts = $self->_user_accounts_via_api($user);
for my $a (@$accounts) {
    for my $s ($a->servers) { ... }
    for my $v ($a->vendor_zones) { ... }
    for my $m ($a->monitors) { ... }
}
```

**Update permission checks:**

**BEFORE:**
```perl
return $self->redirect("/manage/")
  unless ($account->id == 0 or $account->can_edit($self->user));
```

**AFTER:**
```perl
# Permission already in $account->{_permissions} from current_account()
return $self->redirect("/manage/")
  unless ($account->{account_id} == 0 or $account->{_permissions}{can_edit});
```

**CRITICAL: Update helper methods to return plain hashrefs (not ORM objects):**

**Current problem:** These helper methods call the API, then **load ORM objects from MySQL**, defeating the entire purpose of the API migration!

**BEFORE (WRONG):**
```perl
sub _account_users_via_api {
    my ($self, $account) = @_;
    my $result = get_account_users(account => $account->id_token);

    # ❌ BAD: Load ORM objects from MySQL!
    my @users;
    for my $user_data (@{$result->{data}{users} || []}) {
        my $user = NP::Model->user->fetch(id => $user_data->{user_id});
        push @users, $user if $user;
    }
    return \@users;
}
```

**AFTER (CORRECT):**
```perl
sub _account_users_via_api {
    my ($self, $account) = @_;
    my $cache_key = '_account_users_' . $account->{account_id};
    return $self->{$cache_key} if exists $self->{$cache_key};

    my $result = get_account_users(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $account->{account_token},
        context => $self->_get_request_context(),
    );

    return $self->{$cache_key} = [] if $result->{error};

    # ✅ GOOD: Return API hashrefs directly (no ORM objects!)
    return $self->{$cache_key} = $result->{data}{users} || [];
}
```

**Apply same pattern to:**
- `_user_accounts_via_api()` - Return hashrefs, not ORM Account objects
- `_account_invites_via_api()` - Return hashrefs, not ORM AccountInvite objects
- `_user_invites_via_api()` - Return hashrefs, not ORM AccountInvite objects

**Remove entirely:**
- `_account_from_api_response()` - The blessed object hack is no longer needed


---

## Phase 4: Update Templates

### Pattern Changes

**BEFORE (ORM method calls):**
```html
[% IF account.can_edit(combust.user) %]
[% FOR user = account.users %]
[% account.display_name %]
[% account.url %]
[% account.public_url %]
```

**AFTER (plain hashref access):**
```html
[% IF account._permissions.can_edit %]
[% FOR user = users %]
[% account.display_name %]
[% account.url %]
[% account.public_url %]
```

### Files to Update

#### docs/manage/tpl/account/team.html

**BEFORE:**
```html
[% IF account.can_edit(combust.user) AND
     (combust.user.is_staff OR combust.user.id != user.id) %]
```

**AFTER:**
```html
[% IF account._permissions.can_edit AND
     (combust.user.is_staff OR combust.user.id != user.id) %]
```

#### docs/manage/tpl/account/form.html

**BEFORE:**
```html
[% FOR user = account.users %]
    <li>[% user.email | html %]</li>
[% END %]
```

**AFTER:**
```html
[% FOR user = users %]
    <li>[% user.email | html %]</li>
[% END %]
```

**Controller change:**
```perl
# In render_account_form():
my $users = $self->_account_users_via_api($account);
$self->tpl_param('users', $users);
```

#### docs/manage/tpl/account/monitor_config_section.html

**Update to use hashref:**
```html
[% IF monitor_config.monitor_enabled %]
    Monitor limit: [% monitor_config.monitor_limit %]
[% END %]
```

---

## Phase 5: Remove NP::Model::Account

### Step 1: Verify No References

```bash
cd /Users/ask/src/ntppool

# Check for ORM method calls
git grep 'NP::Model->account' lib/
git grep 'NP::Model::Account' lib/
git grep '->can_edit' lib/ docs/
git grep '->can_view' lib/ docs/
git grep '->display_name' lib/ docs/
git grep '->servers' lib/ | grep -v '# ' | grep -v pod

# Should return zero results (or only comments/tests)
```

### Step 2: Add to Ignored Tables

**File:** `lib/NP/DB/Scaffold.pm`

```perl
our @IGNORED_TABLES = qw(
    account              # Migrated to Go API - 2025-10-10
    account_invite       # Will migrate with account invites
    account_user         # Will migrate with account users
    # ... other ignored tables
);
```

### Step 3: Regenerate Model

```bash
cd /Users/ask/src/ntppool
perl lib/NP/DB/Scaffold.pm
```

### Step 4: Archive Old Code

```bash
mkdir -p old/model
git mv lib/NP/Model/Account.pm old/model/
git mv lib/NP/Model/TokenID.pm old/model/  # If account-specific
```

### Step 5: Commit Changes

```bash
git add lib/NP/DB/Scaffold.pm lib/NP/Model.pm old/model/
git commit -m "refactor(account): remove NP::Model::Account, fully migrated to Go APIs"
```

---

## API Consolidation Summary

### New Consolidated API: CheckUserDeletionEligibility

**Replaces:** Multiple API calls + ORM database queries in user deletion flow

**Before (WRONG approach):**
```perl
# ❌ BAD: 1 + N API calls + ORM database queries
my $accounts = $self->_user_accounts_via_api($user);      # API call 1

for my $a (@$accounts) {
    my $users = $self->_account_users_via_api($a);        # API calls 2..N
    my @other_users = grep { ... } @$users;
    next if @other_users;

    # ORM database queries (still hitting MySQL!)
    for my $s ($a->servers) { ... }                       # DB query
    for my $v ($a->vendor_zones) { ... }                  # DB query
    for my $m ($a->monitors) { ... }                      # DB query
}
```

**After (CORRECT approach):**
```perl
# ✅ GOOD: Single API call, all logic in Go
my $result = check_user_deletion_eligibility(
    auth    => $self->plain_cookie($self->user_cookie_name),
    context => $self->_get_request_context(),
);

my $can_delete = $result->{data}{can_delete};
my @blockers = @{$result->{data}{blockers} || []};
```

**Savings:**
- **Before:** 1 + N API calls + M database queries
- **After:** 1 API call
- **Eliminated:** All ORM usage for user deletion validation
- **Moved to Go:** Account filtering, sole-owner logic, blocker checks

### Helper Method Pattern Fix

**Problem identified:** Helper methods like `_account_users_via_api()` were:
1. Calling the Go API (PostgreSQL)
2. Then loading ORM objects from MySQL
3. Defeating the entire migration purpose!

**Solution:** Return plain hashrefs from API responses directly.

---

## Implementation Timeline

### Week 1: Go API Implementation
- [x] Proto definitions for ValidateSession with account context (Phase 1.1)
- [x] Proto definitions for GetAccount modes (Phase 1.2)
- [x] Proto definitions for CanDeleteAccount API (Phase 1.3)
- [x] Proto definitions for CheckUserDeletionEligibility API (Phase 1.4)
- [x] SQL queries for deletion validation (CountActive* queries)
- [x] Generate protobuf code (`buf generate`)
- [x] Generate SQLC code (`sqlc generate`)
- [ ] Implement ValidateSession Go handler
- [ ] Implement GetAccount Go handler
- [ ] Implement CanDeleteAccount Go handler
- [ ] Implement CheckUserDeletionEligibility Go handler
- [ ] Write Go unit tests for new APIs
- [ ] Run Go tests (`make test-local`)

### Week 2: Perl CAPI Integration
- [ ] Update lib/NP/CAPI/Account.pm (Phase 2)
- [ ] Test CAPI wrappers in isolation
- [ ] Update lib/NTPPool/Control/Manage.pm (Phase 3)
- [ ] Update lib/NTPPool/Control/Manage/Account.pm (Phase 3)

### Week 3: Template Updates & Testing
- [ ] Update all templates (Phase 4)
- [ ] Manual testing of account pages
- [ ] Manual testing of team page
- [ ] Manual testing of user deletion
- [ ] Test with ?a= parameter (different accounts)
- [ ] Test default account selection

### Week 4: Cleanup & Deploy
- [ ] Verify no ORM references (Phase 5)
- [ ] Add to ignored_tables (Phase 5)
- [ ] Regenerate NP::Model (Phase 5)
- [ ] Archive old Account.pm (Phase 5)
- [ ] Deploy to staging
- [ ] Deploy to production
- [ ] Monitor for errors

---

## Testing Strategy

### Go Unit Tests

**File:** `internal/api/account/account_test.go`

```go
func TestValidateSession_WithAccountToken(t *testing.T) {
    // Test: Session + valid account_token
    // Expect: Returns account with permissions
}

func TestValidateSession_DefaultAccount(t *testing.T) {
    // Test: Session without account_token
    // Expect: Returns user's first account
}

func TestValidateSession_InaccessibleAccount(t *testing.T) {
    // Test: Session + account_token for inaccessible account
    // Expect: Returns error
}

func TestGetAccount_Modes(t *testing.T) {
    tests := []struct{
        mode     accountv1.AccountDataMode
        hasPerms bool
        hasUsers bool
    }{
        {accountv1.AccountDataMode_BASIC, false, false},
        {accountv1.AccountDataMode_WITH_PERMISSIONS, true, false},
        {accountv1.AccountDataMode_MANAGEMENT, true, true},
    }
    // ...
}

func TestCanDeleteAccount_WithBlockers(t *testing.T) {
    // Test: Account with active servers
    // Expect: can_delete=false, blockers list populated
}

func TestCanDeleteAccount_Clean(t *testing.T) {
    // Test: Account with no blockers
    // Expect: can_delete=true, empty blockers
}
```

### Perl Integration Tests

**File:** `t/account_api.t`

```perl
use Test::More;
use NP::CAPI::Account qw(validate_session_with_account get_account can_delete_account);

subtest "validate_session_with_account" => sub {
    my $result = validate_session_with_account(
        session_token => $valid_session,
        account_token => $valid_token,
        context       => {},
    );

    ok(!$result->{error}, "No error");
    ok($result->{data}{account}, "Has account");
    ok($result->{data}{permissions}, "Has permissions");
    is($result->{data}{account}{account_token}, $valid_token, "Correct account");
};

subtest "get_account_modes" => sub {
    my $result = get_account_management(
        auth    => $auth,
        account => $token,
        context => {},
    );

    ok($result->{data}{permissions}, "MANAGEMENT mode includes permissions");
    ok($result->{data}{users}, "MANAGEMENT mode includes users");
    ok($result->{data}{monitor_config}, "MANAGEMENT mode includes monitor_config");
};

subtest "can_delete_account" => sub {
    my $result = can_delete_account(
        auth          => $auth,
        account_token => $account_with_servers,
        context       => {},
    );

    ok(!$result->{error}, "No error");
    is($result->{data}{can_delete}, 0, "Cannot delete");
    ok(scalar @{$result->{data}{blockers}}, "Has blockers");
};

done_testing();
```

### Manual Testing Checklist

**Account Management:**
- [ ] Login and view account form
- [ ] Edit account name, organization, URL slug
- [ ] Toggle public profile checkbox
- [ ] View computed fields (url, public_url, display_name)
- [ ] Check permissions (can_edit, can_view, can_add_servers)

**Team Page:**
- [ ] View account team members
- [ ] Invite new user
- [ ] Remove user from account
- [ ] Check permissions (only can_edit users can remove)

**Account Switching:**
- [ ] Login with ?a=token switches to specified account
- [ ] Login without ?a uses default account
- [ ] Invalid ?a= token returns error
- [ ] Inaccessible ?a= account returns error

**User Deletion:**
- [ ] View user delete page
- [ ] Check blockers display (active servers, monitors, vendor zones)
- [ ] Verify deletion allowed when clean
- [ ] Verify deletion blocked when appropriate

**Staff Features:**
- [ ] Staff can view any account
- [ ] Staff can edit any account
- [ ] Monitor admin can view accounts

---

## API Response Examples

### ValidateSession Response (with account)

```json
{
  "valid": true,
  "user_id": 123,
  "email": "user@example.com",
  "username": "user123",
  "user_token": "abc123",
  "account": {
    "account_id": 456,
    "account_token": "def456",
    "name": "My Account",
    "organization_name": "Example Org",
    "organization_url": "https://example.com",
    "url_slug": "example-org",
    "public_profile": true,
    "flags": "{\"monitor_enabled\":true}",
    "created_on": "2023-01-15T10:30:00Z",
    "modified_on": "2024-03-20T15:45:00Z",
    "url": "/manage?a=def456",
    "public_url": "/a/example-org",
    "display_name": "Example Org"
  },
  "permissions": {
    "can_edit": true,
    "can_view": true,
    "can_add_servers": true
  }
}
```

### GetAccount Response (MANAGEMENT mode)

```json
{
  "account": {
    "account_id": 456,
    "account_token": "def456",
    "name": "My Account",
    "display_name": "My Account",
    "url": "/manage?a=def456",
    "public_url": ""
  },
  "permissions": {
    "can_edit": true,
    "can_view": true,
    "can_add_servers": false
  },
  "users": [
    {
      "user_id": 123,
      "user_token": "abc123",
      "email": "user@example.com",
      "username": "user123",
      "public_profile": false
    },
    {
      "user_id": 789,
      "user_token": "xyz789",
      "email": "admin@example.com",
      "username": "admin",
      "public_profile": true
    }
  ],
  "monitor_config": {
    "monitor_enabled": true,
    "monitor_limit": 5,
    "monitors_per_server_limit": 1
  }
}
```

### CanDeleteAccount Response (blocked)

```json
{
  "can_delete": false,
  "blockers": [
    "Account has 3 active servers",
    "Account has 1 vendor zone",
    "Account has 2 active monitors"
  ],
  "details": {
    "active_servers_count": 3,
    "vendor_zones_count": 1,
    "active_monitors_count": 2,
    "has_other_users": false
  }
}
```

### CanDeleteAccount Response (allowed)

```json
{
  "can_delete": true,
  "blockers": [],
  "details": {
    "active_servers_count": 0,
    "vendor_zones_count": 0,
    "active_monitors_count": 0,
    "has_other_users": false
  }
}
```

---

## Rollback Plan

### If Issues Found in Production

1. **Revert Perl changes**
   ```bash
   git revert <commit-hash>
   ```

2. **Keep Go APIs** - They're backward compatible, just unused

3. **Database** - No schema changes, safe to revert

### Monitoring

**Key Metrics to Watch:**
- ValidateSession error rate
- GetAccount API latency
- CanDeleteAccount success rate
- Page load times for /manage/account
- MySQL query count (should decrease)

**Alerts:**
- Spike in ValidateSession errors
- Increase in "account not found" errors
- Page timeouts on /manage pages

---

## Success Criteria

✅ **Zero ORM references** - No `NP::Model->account` outside old/ directory
✅ **All data from APIs** - Every account field comes from Go
✅ **Perl is presentation only** - No database queries for accounts
✅ **Session resolves accounts** - current_account() uses single API call
✅ **Permissions server-side** - No can_edit/can_view in Perl
✅ **Deletion logic in Go** - CanDeleteAccount API handles validation
✅ **Plain hashrefs** - No blessed objects in templates
✅ **No performance regression** - Page load times unchanged or improved
✅ **All tests passing** - Unit, integration tests pass
✅ **Production stable** - No increase in error rates after deployment

---

## Future Work (Out of Scope)

### Near-term:
- Migrate `account_invite` table to Go APIs (extend existing GetAccountInvites)
- Add subscription API (table exists in PostgreSQL)
- Add vendor zones API (table exists in PostgreSQL)
- Full monitor API migration (some endpoints already exist)

### Long-term:
- Remove all Rose::DB models
- Complete MySQL decommissioning
- Migrate remaining int_api (REST) calls to ConnectRPC

---

## Notes

**PostgreSQL Migration Context:**
- During transition, Go writes to PostgreSQL, Perl reads from API (which reads PostgreSQL)
- No MySQL writes for accounts after this migration
- This is a major milestone toward full PostgreSQL migration
- Perl becomes pure presentation layer (no business logic)

**Backward Compatibility:**
- Keep existing NP::Model::Account until Phase 5 (can coexist during migration)
- Go APIs are additive (don't break existing functionality)
- Can deploy Perl changes page-by-page if needed (though not recommended)

**Performance Considerations:**
- Single ValidateSession call replaces multiple ORM queries
- Caching in Perl controller ($self->{_current_account})
- Go API optimizations (precomputed display_name, etc.)
- Reduced database connections from Perl

**Security:**
- All permission checks server-side (Go)
- Token validation in Go (not Perl)
- Session validation in Go
- No security downgrade vs ORM approach
