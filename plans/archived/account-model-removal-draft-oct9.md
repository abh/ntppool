# Plan: Remove NP::Model::Account Dependency

**Status:** Draft
**Created:** 2025-10-09
**Goal:** Eliminate NP::Model::Account ORM dependency, making Perl purely a presentation layer and completing PostgreSQL migration for accounts.

---

## Overview

This plan migrates all Account ORM functionality to Go ConnectRPC APIs. After completion:
- ✅ All account data comes from Go APIs (PostgreSQL)
- ✅ No Perl code reads from MySQL `accounts` table
- ✅ Perl layer is pure presentation/templating
- ✅ NP::Model::Account removed from codebase

---

## Current Dependencies Analysis

### NP::Model::Account Methods Still in Use

**Object Methods** (lib/NP/Model/Account.pm:17-95):
- `url()` - Generate account management URL → **Move to Go**
- `public_url()` - Generate public profile URL → **Move to Go**
- `display_name()` - Get account display name → **Move to Go**
- `validate()` - Validate account data → **Already in Go** (CreateAccount/UpdateAccount validate)
- `can_edit()` - Check if user can edit account → **Move to Go**
- `can_view()` - Check if user can view account → **Move to Go**
- `can_add_servers()` - Calls ConnectRPC API ✅ → **Fold into permissions**
- `have_live_subscription()` / `live_subscriptions()` - Subscription checks → **Add subscription API**
- `bad_servers()` - Get bad servers → **Move to task system** (only used in bin/bad_server_notifications)
- `servers()` - Get account servers → **Use existing Server API**

**Database Relationships** (lib/NP/Model/Account.pm:173-207):
- `->servers` - Fetches server objects from MySQL → **Server API**
- `->users` - Account users relationship → **Already have get_account_users API ✅**
- `->account_subscriptions` - Subscription relationship → **New Subscription API**
- `->vendor_zones` - Vendor zones relationship → **New VendorZone API**
- `->monitors` - Monitor relationship → **New Monitor API**

**Manager Methods** (lib/NP/Model/Account.pm:215-239):
- `accounts_to_notify()` - **Already uses ConnectRPC API ✅**

**Token/ID Management** (inherited from NP::Model::TokenID):
- `token_id()` - Convert token to ID → **Replace with API calls** (used in Manage.pm:93)
- `id_token` - Get token from ID → **Always returned by APIs**
- `insert_token_id()` - Generate token on insert → **Already in Go** (CreateAccount generates token)

### Current Usage Locations

- **lib/NTPPool/Control/Manage.pm:93** - Uses `NP::Model::Account->token_id()` to decode account token
- **lib/NTPPool/Control/Manage/Account.pm:359** - Uses `$account->users` to check for duplicate invites
- **lib/NTPPool/Control/Manage/Account.pm:660-672** - Uses `$a->servers`, `$a->vendor_zones`, `$a->monitors` for deletion checks
- **lib/NTPPool/Control/Manage/Account.pm:188** - Uses `$account->can_edit($self->user)` for permission check

---

## Phase 1: Extend Account API (GetAccount with Options)

### Goal
Make GetAccount return all data needed by Perl controllers, eliminating need for separate queries.

### Go API Changes

**File:** `proto/ntppool/account/v1/account.proto`

**Add to GetAccountRequest:**
```protobuf
message GetAccountRequest {
  // Options for what data to include (all optional, default false)
  bool include_permissions = 1;     // Add can_edit, can_view, can_add_servers flags
  bool include_users = 2;            // Include account users list
  bool include_subscriptions = 3;    // Include subscription data
  bool include_monitor_config = 4;   // Include monitor limits/config from flags JSON
  bool include_servers_summary = 5;  // Include server counts (total, active, bad)
  bool include_vendor_zones = 6;     // Include vendor zone list
  bool include_monitors = 7;         // Include monitor list
}
```

**Extend GetAccountResponse:**
```protobuf
message GetAccountResponse {
  // Core account data (always included)
  Account account = 1;

  // Computed fields (always included for convenience)
  string url = 2;                    // Management URL: {base_url}/manage?a={token}
  string public_url = 3;             // Public profile URL: {base_url}/a/{url_slug} (empty if no url_slug)
  string display_name = 4;           // Computed: name || organization_name || url_slug

  // Optional fields (only included if requested)
  optional AccountPermissions permissions = 5;        // if include_permissions
  repeated AccountUser users = 6;                     // if include_users
  repeated AccountSubscription subscriptions = 7;     // if include_subscriptions
  optional MonitorConfig monitor_config = 8;          // if include_monitor_config
  optional ServersSummary servers_summary = 9;        // if include_servers_summary
  repeated VendorZone vendor_zones = 10;              // if include_vendor_zones
  repeated Monitor monitors = 11;                     // if include_monitors
}

// Permission flags for the authenticated user
message AccountPermissions {
  bool can_edit = 1;   // User is in account or is staff
  bool can_view = 2;   // User is in account, is staff, or is monitor admin
  bool can_add_servers = 3;  // Folds GetAccountServerVerificationStatus logic:
                             // - Allow if no servers yet
                             // - Block if 2+ unverified servers
                             // - Otherwise allow
}

// Monitor configuration from account.flags JSON
message MonitorConfig {
  bool monitor_enabled = 1;
  int64 monitor_limit = 2;                // Default: 3
  int64 monitors_per_server_limit = 3;    // Default: 1
}

// Summary counts for account's servers
message ServersSummary {
  int64 total_servers = 1;      // All servers (including deleted)
  int64 active_servers = 2;     // deletion_on IS NULL OR deletion_on > NOW()
  int64 deleted_servers = 3;    // deletion_on IS NOT NULL AND deletion_on <= NOW()
  int64 bad_servers = 4;        // score_raw < -15 (BAD_SERVER_THRESHOLD)
}

// Subscription info (minimal for now, expand as needed)
message AccountSubscription {
  int64 subscription_id = 1;
  string stripe_subscription_id = 2;
  string status = 3;            // active, canceled, past_due, etc.
  bool live_subscription = 4;   // Computed: status == 'active' or 'trialing'
  string created_on = 5;
  optional string canceled_at = 6;
  // Add more fields as needed
}

// Vendor zone info
message VendorZone {
  int64 vendor_zone_id = 1;
  string zone_name = 2;
  string vendor_cluster = 3;
  int32 rt_limit = 4;
  string status = 5;
  // Add more fields as needed
}

// Monitor info (reuse existing Monitor message if available)
message Monitor {
  int64 monitor_id = 1;
  string ip = 2;
  string hostname = 3;
  string status = 4;        // active, deleted, etc.
  string created_on = 5;
  // Add more fields as needed
}
```

### Implementation Details

**File:** `internal/api/account/account.go`

```go
func (s *Server) GetAccount(ctx context.Context, req *accountv1.GetAccountRequest) (*accountv1.GetAccountResponse, error) {
    // 1. Get account from auth context (session middleware)
    account := sessions.GetAccount(ctx)
    user := sessions.GetUser(ctx)

    // 2. Build base response with computed fields
    resp := &accountv1.GetAccountResponse{
        Account:     toProtoAccount(account),
        Url:         s.computeManagementURL(account),
        PublicUrl:   s.computePublicURL(account),
        DisplayName: s.computeDisplayName(account),
    }

    // 3. Add optional data based on request flags
    if req.IncludePermissions {
        resp.Permissions = s.computePermissions(ctx, account, user)
    }

    if req.IncludeUsers {
        users, err := s.getAccountUsers(ctx, account.ID)
        if err != nil {
            return nil, err
        }
        resp.Users = users
    }

    if req.IncludeSubscriptions {
        subs, err := s.getAccountSubscriptions(ctx, account.ID)
        if err != nil {
            return nil, err
        }
        resp.Subscriptions = subs
    }

    if req.IncludeMonitorConfig {
        resp.MonitorConfig = s.parseMonitorConfig(account.Flags)
    }

    if req.IncludeServersSummary {
        summary, err := s.getServersSummary(ctx, account.ID)
        if err != nil {
            return nil, err
        }
        resp.ServersSummary = summary
    }

    if req.IncludeVendorZones {
        zones, err := s.getVendorZones(ctx, account.ID)
        if err != nil {
            return nil, err
        }
        resp.VendorZones = zones
    }

    if req.IncludeMonitors {
        monitors, err := s.getMonitors(ctx, account.ID)
        if err != nil {
            return nil, err
        }
        resp.Monitors = monitors
    }

    return resp, nil
}

func (s *Server) computeDisplayName(account *db.Account) string {
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

func (s *Server) computePermissions(ctx context.Context, account *db.Account, user *db.User) *accountv1.AccountPermissions {
    canEdit := s.canEditAccount(ctx, account, user)
    canView := canEdit || user.Privileges.MonitorAdmin
    canAddServers := s.canAddServers(ctx, account)

    return &accountv1.AccountPermissions{
        CanEdit:       canEdit,
        CanView:       canView,
        CanAddServers: canAddServers,
    }
}

func (s *Server) canAddServers(ctx context.Context, account *db.Account) bool {
    // Fold GetAccountServerVerificationStatus logic here
    counts, err := s.queries.GetAccountServerVerificationCounts(ctx, account.ID)
    if err != nil {
        return false
    }

    // Allow if no servers yet
    if counts.VerifiedCount == 0 && counts.UnverifiedCount == 0 {
        return true
    }

    // Block if 2+ unverified servers
    if counts.UnverifiedCount >= 2 {
        return false
    }

    return true
}
```

### API Endpoints to Deprecate

- `GetAccountServerVerificationStatus` - Logic folded into `permissions.can_add_servers`

---

## Phase 2: Create Management Servers API

### Goal
Provide server list for account management interface (includes deleted servers, verification status, etc.)

### Go API Changes

**File:** `proto/ntppool/server/v1/server.proto`

**Add new RPC:**
```protobuf
service ServerService {
  // ... existing RPCs ...

  // GetAccountServersManage returns all servers for the authenticated account.
  // Used by management interface - includes deleted servers, full details.
  // Authentication required via session middleware.
  // Authorization: User must have access to the account.
  rpc GetAccountServersManage(GetAccountServersManageRequest)
      returns (GetAccountServersManageResponse) {
    option idempotency_level = NO_SIDE_EFFECTS;
  }
}

message GetAccountServersManageRequest {
  // No fields needed - account comes from authentication context
}

message GetAccountServersManageResponse {
  // All servers for this account, including deleted
  repeated ServerDetail servers = 1;
}

// Extended server details for management interface
message ServerDetail {
  int64 id = 1;
  string ip = 2;
  string hostname = 3;
  int32 ip_version = 4;
  int32 stratum = 5;
  bool in_pool = 6;
  int32 netspeed = 7;
  double score_raw = 8;
  string deletion_on = 9;  // ISO 8601 or empty
  ServerVerification verification = 10;
  repeated string zones = 11;  // Zone names only
  repeated string urls = 12;
  string created_on = 13;
  string modified_on = 14;

  // Management-specific fields
  optional string deletion_reason = 15;
  optional int64 account_id = 16;  // Included for consistency
}
```

### Implementation

**File:** `internal/api/server/server.go`

```go
func (s *Server) GetAccountServersManage(ctx context.Context, req *serverv1.GetAccountServersManageRequest) (*serverv1.GetAccountServersManageResponse, error) {
    // Get account from auth context
    account := sessions.GetAccount(ctx)

    // Query ALL servers for account (including deleted)
    servers, err := s.queries.GetAccountServersManage(ctx, account.ID)
    if err != nil {
        return nil, err
    }

    // Convert to proto
    protoServers := make([]*serverv1.ServerDetail, len(servers))
    for i, srv := range servers {
        protoServers[i] = toProtoServerDetail(srv)
    }

    // Sort by IP address (v4 before v6, then numeric)
    sortServersByIP(protoServers)

    return &serverv1.GetAccountServersManageResponse{
        Servers: protoServers,
    }, nil
}
```

**SQL Query (db/queries/server.sql):**
```sql
-- name: GetAccountServersManage :many
SELECT
    s.*,
    sv.verified_on
FROM servers s
LEFT JOIN server_verification sv ON s.id = sv.server_id
WHERE s.account_id = $1
ORDER BY s.ip;
```

---

## Phase 3: Create Vendor Zones & Monitor APIs

### Goal
Provide vendor zones and monitors lists for account management

### Option A: Add to AccountService (Simpler)

Since these are small collections, add them to Phase 1's GetAccount API:
- `include_vendor_zones` flag
- `include_monitors` flag

### Option B: Separate Services (Better Separation)

Create dedicated services if vendor zones and monitors grow more complex.

**Recommendation:** Start with Option A (add to GetAccount). Create separate services only if needed later.

---

## Phase 4: Update Perl CAPI Layer

### Goal
Add Perl wrappers for new Go APIs

### File: lib/NP/CAPI/Account.pm

**Add functions:**
```perl
use constant CAPI_SERVICE => 'ntppool.account.v1.AccountService';

# Get account with specific data included
sub get_account {
    my %args = @_;

    # Options: include_permissions, include_users, include_subscriptions, etc.
    my $req = {
        include_permissions     => $args{include_permissions} ? JSON::XS::true : JSON::XS::false,
        include_users           => $args{include_users} ? JSON::XS::true : JSON::XS::false,
        include_subscriptions   => $args{include_subscriptions} ? JSON::XS::true : JSON::XS::false,
        include_monitor_config  => $args{include_monitor_config} ? JSON::XS::true : JSON::XS::false,
        include_servers_summary => $args{include_servers_summary} ? JSON::XS::true : JSON::XS::false,
        include_vendor_zones    => $args{include_vendor_zones} ? JSON::XS::true : JSON::XS::false,
        include_monitors        => $args{include_monitors} ? JSON::XS::true : JSON::XS::false,
    };

    return _capi_call(
        service => CAPI_SERVICE,
        method  => 'GetAccount',
        request => $req,
        auth    => $args{auth},
        account => $args{account},
        context => $args{context},
    );
}

# Convenience: Get account with permissions
sub get_account_with_permissions {
    my %args = @_;
    return get_account(%args, include_permissions => 1);
}

# Convenience: Get full account data (everything)
sub get_account_full {
    my %args = @_;
    return get_account(
        %args,
        include_permissions     => 1,
        include_users           => 1,
        include_subscriptions   => 1,
        include_monitor_config  => 1,
        include_servers_summary => 1,
        include_vendor_zones    => 1,
        include_monitors        => 1,
    );
}
```

### File: lib/NP/CAPI/Server.pm

**Add function:**
```perl
use constant CAPI_SERVICE => 'ntppool.server.v1.ServerService';

sub get_account_servers_manage {
    my %args = @_;

    return _capi_call(
        service => CAPI_SERVICE,
        method  => 'GetAccountServersManage',
        request => {},  # Account from auth context
        auth    => $args{auth},
        account => $args{account},
        context => $args{context},
    );
}
```

---

## Phase 5: Update Perl Controllers

### File: lib/NTPPool/Control/Manage.pm

**Line 92-110: Replace current_account() logic**

**BEFORE:**
```perl
sub current_account {
    my $self = shift;

    if (exists $self->{_current_account}) {
        return $self->{_current_account};
    }

    if (my $account_token = $self->req_param('a')) {
        my $account_id = NP::Model::Account->token_id($account_token);  # ❌ ORM
        my $account = $account_id ? NP::Model->account->fetch(id => $account_id) : undef;  # ❌ ORM
        if ($account) {
            return $self->{_current_account} = $account
              if $account->can_view($self->user);  # ❌ ORM method
        }
    }

    my ($accounts) = NP::Model->account->get_accounts(  # ❌ ORM
        require_objects => ['users'],
        query           => ['users.id' => $self->user->id]
    );

    if ($accounts && @$accounts) {
        return $self->{_current_account} = $accounts->[0];
    }

    return $self->{_current_account} = undef;
}
```

**AFTER:**
```perl
sub current_account {
    my $self = shift;

    if (exists $self->{_current_account}) {
        return $self->{_current_account};
    }

    # Try to get account from 'a' parameter
    if (my $account_token = $self->req_param('a')) {
        my $result = get_account_with_permissions(
            auth    => $self->plain_cookie($self->user_cookie_name),
            account => $account_token,
            context => $self->_get_request_context(),
        );

        if (!$result->{error}) {
            my $data = $result->{data};
            # Check can_view permission
            if ($data->{permissions}{can_view}) {
                my $account = $self->_account_from_api_response($data);
                # Store permissions separately for easy access
                $account->{_permissions} = $data->{permissions};
                return $self->{_current_account} = $account;
            }
        }
    }

    # Fall back to user's first account
    my $accounts_result = get_user_accounts(
        auth    => $self->plain_cookie($self->user_cookie_name),
        context => $self->_get_request_context(),
    );

    if (!$accounts_result->{error} && $accounts_result->{data}{accounts}) {
        my @accounts = @{$accounts_result->{data}{accounts}};
        if (@accounts) {
            # Convert first account to blessed object
            my $first_account = $accounts[0];
            my $account = $self->_account_from_api_response($first_account);
            return $self->{_current_account} = $account;
        }
    }

    return $self->{_current_account} = undef;
}

# Helper to convert API response to blessed object
sub _account_from_api_response {
    my ($self, $account_data) = @_;

    # Create blessed object from API data
    # This mimics NP::Model::Account structure for template compatibility
    return bless {
        id                => $account_data->{account_id},
        id_token          => $account_data->{account_token},
        name              => $account_data->{name},
        organization_name => $account_data->{organization_name},
        organization_url  => $account_data->{organization_url},
        url_slug          => $account_data->{url_slug},
        flags             => $account_data->{flags},
        public_profile    => $account_data->{public_profile} ? 1 : 0,
        created_on        => $account_data->{created_on},
        modified_on       => $account_data->{modified_on},

        # Computed fields from API
        _url              => $account_data->{url},
        _public_url       => $account_data->{public_url},
        _display_name     => $account_data->{display_name},
    }, 'NP::Account';  # NOT NP::Model::Account - new thin class
}
```

**Remove account_monitor_config() method**

Data comes from API now. Update callers to use `$result->{data}{monitor_config}` directly.

---

### File: lib/NTPPool/Control/Manage/Account.pm

**Line 359: Replace $account->users**

**BEFORE:**
```perl
if (grep { lc $_->email eq lc $email_address } $account->users) {  # ❌ ORM relationship
    $errors{invite_email} = "User is already on this account";
}
```

**AFTER:**
```perl
my $users = $self->_account_users_via_api($account);
if (grep { lc $_->email eq lc $email_address } @$users) {
    $errors{invite_email} = "User is already on this account";
}
```

**Line 188: Replace can_edit() check**

**BEFORE:**
```perl
return $self->redirect("/manage/")
  unless ($account->id == 0 or $account->can_edit($self->user));  # ❌ ORM method
```

**AFTER:**
```perl
# Get permissions from API
my $result = get_account_with_permissions(
    auth    => $self->plain_cookie($self->user_cookie_name),
    account => $account->id_token,
    context => $self->_get_request_context(),
);

my $can_edit = $result->{data}{permissions}{can_edit} || 0;

return $self->redirect("/manage/")
  unless ($account->{id} == 0 or $can_edit);
```

**Lines 660-672: Replace relationship calls**

**BEFORE:**
```perl
for my $s ($a->servers) {  # ❌ ORM relationship
    unless ($s->deletion_on) {
        warn "account has active servers";
        $delete_ok = 0;
        last;
    }
}
for my $v ($a->vendor_zones) {  # ❌ ORM relationship
    warn "account has vendor zones";
    $delete_ok = 0;
    last;
}
for my $m ($a->monitors) {  # ❌ ORM relationship
    unless ($m->status eq 'deleted') {
        warn "account has monitors";
        $delete_ok = 0;
        last;
    }
}
```

**AFTER:**
```perl
# Get account data with all relationships
my $full_result = get_account_full(
    auth    => $self->plain_cookie($self->user_cookie_name),
    account => $a->id_token,
    context => $self->_get_request_context(),
);

if (!$full_result->{error}) {
    my $data = $full_result->{data};

    # Check servers
    for my $s (@{$data->{servers} || []}) {
        unless ($s->{deletion_on}) {
            warn "account has active servers";
            $delete_ok = 0;
            last;
        }
    }

    # Check vendor zones
    if (@{$data->{vendor_zones} || []}) {
        warn "account has vendor zones";
        $delete_ok = 0;
    }

    # Check monitors
    for my $m (@{$data->{monitors} || []}) {
        unless ($m->{status} eq 'deleted') {
            warn "account has monitors";
            $delete_ok = 0;
            last;
        }
    }
}
```

---

## Phase 6: Update Templates

### Goal
Update templates to use API response data instead of ORM method calls

### Template Patterns

**Current template usage:**
```html
[% account.display_name %]
[% account.url %]
[% account.public_url %]
[% account.can_edit(user) %]
```

**After migration - pass data from controller:**
```perl
# In controller:
my $result = get_account_full(...);
my $data = $result->{data};

$self->tpl_param('account', {
    id                => $data->{account}{account_id},
    id_token          => $data->{account}{account_token},
    name              => $data->{account}{name},
    organization_name => $data->{account}{organization_name},
    url               => $data->{url},
    public_url        => $data->{public_url},
    display_name      => $data->{display_name},
    # ... other fields
});
$self->tpl_param('permissions', $data->{permissions});
$self->tpl_param('users', $data->{users});
```

**Template updates:**
```html
[% account.display_name %]  <!-- No change - now a hash key instead of method -->
[% account.url %]            <!-- No change -->
[% account.public_url %]     <!-- No change -->
[% IF permissions.can_edit %]<!-- Changed from account.can_edit(user) -->
```

### Files to Update

Search for these patterns in `docs/manage/tpl/`:
- `account.display_name`
- `account.url`
- `account.public_url`
- `account.can_edit`
- `account.can_view`
- `account.users`

---

## Phase 7: Create NP::Account Helper Module (Optional)

### Goal
Create a thin, non-ORM utility module for account data structures

### File: lib/NP/Account.pm

```perl
package NP::Account;
use strict;
use warnings;

# This is a thin data holder, NOT an ORM class
# All data comes from APIs - this just provides accessor methods for templates

sub new {
    my ($class, $data) = @_;
    return bless $data, $class;
}

# Template-friendly accessors (allow both $account->name and $account->{name})
sub id                { $_[0]->{id} }
sub id_token          { $_[0]->{id_token} }
sub name              { $_[0]->{name} }
sub organization_name { $_[0]->{organization_name} }
sub organization_url  { $_[0]->{organization_url} }
sub url_slug          { $_[0]->{url_slug} }
sub public_profile    { $_[0]->{public_profile} }
sub flags             { $_[0]->{flags} }
sub created_on        { $_[0]->{created_on} }
sub modified_on       { $_[0]->{modified_on} }

# Computed fields from API
sub url          { $_[0]->{_url} || $_[0]->{url} }
sub public_url   { $_[0]->{_public_url} || $_[0]->{public_url} }
sub display_name { $_[0]->{_display_name} || $_[0]->{display_name} }

1;
```

**Usage in controllers:**
```perl
use NP::Account;

my $account = NP::Account->new($api_response_data);
$self->tpl_param('account', $account);
```

**Note:** This is purely for template convenience. Could also just pass raw hashrefs.

---

## Phase 8: Remove NP::Model::Account

### Goal
Clean up ORM code after full migration

### Step 1: Add to Ignored Tables

**File:** `lib/NP/DB/Scaffold.pm`

Find the `ignored_tables` configuration and add `account`:

```perl
our @IGNORED_TABLES = qw(
    account              # Migrated to Go API - 2025-10-09
    account_invite       # Will migrate with account
    account_user         # Will migrate with account
    # ... other ignored tables
);
```

### Step 2: Verify No References

Search for remaining references:
```bash
git grep 'NP::Model->account' lib/
git grep 'NP::Model::Account' lib/
git grep '->validate' lib/ | grep -v Monitor | grep -v VendorZone
```

Should find:
- ✅ Zero references to `NP::Model->account->fetch`
- ✅ Zero references to `NP::Model::Account->token_id`
- ✅ Only test files or migration scripts (acceptable)

### Step 3: Regenerate Model

Run scaffold to regenerate `lib/NP/Model.pm` without Account:
```bash
cd /Users/ask/src/ntppool
perl lib/NP/DB/Scaffold.pm
```

### Step 4: Keep for Reference (Optional)

Instead of deleting, could move to archive:
```bash
mkdir -p old/model
git mv lib/NP/Model/Account.pm old/model/
```

### Step 5: Update Database Access Logs

The Perl system should only READ from these tables now:
- `account_invite` (until invite system migrated)
- Legacy logging if any

All WRITES go through Go APIs → PostgreSQL.

---

## Implementation Timeline

### Week 1-2: Foundation APIs
- [ ] Implement GetAccount with all include flags (Phase 1)
- [ ] Implement GetAccountServersManage (Phase 2)
- [ ] Add GetAccount to CAPI layer (Phase 4)
- [ ] Write tests for new APIs

### Week 3: Perl Controller Updates
- [ ] Update lib/NTPPool/Control/Manage.pm (Phase 5)
- [ ] Update lib/NTPPool/Control/Manage/Account.pm (Phase 5)
- [ ] Create NP::Account helper if needed (Phase 7)

### Week 4: Template Updates & Testing
- [ ] Update all templates (Phase 6)
- [ ] Manual testing of all account management pages
- [ ] Playwright tests for critical flows
- [ ] Performance testing

### Week 5: Cleanup
- [ ] Verify no ORM references remain
- [ ] Add account to ignored_tables (Phase 8)
- [ ] Regenerate NP::Model
- [ ] Documentation updates
- [ ] Deploy to production

---

## Testing Strategy

### Unit Tests (Go)

Test each GetAccount option independently:
```go
func TestGetAccount_WithPermissions(t *testing.T) { ... }
func TestGetAccount_WithUsers(t *testing.T) { ... }
func TestGetAccount_Full(t *testing.T) { ... }
```

### Integration Tests (Perl)

Test CAPI wrappers:
```perl
use Test::More;
use NP::CAPI::Account;

my $result = get_account_with_permissions(...);
ok(!$result->{error}, 'API call succeeded');
ok($result->{data}{permissions}{can_edit}, 'Has permissions');
```

### Manual Testing Checklist

- [ ] View account settings page
- [ ] Edit account (name, organization, url_slug)
- [ ] View team page (list users)
- [ ] Invite user to account
- [ ] Remove user from account
- [ ] View account servers list
- [ ] Check deletion blocking (active servers/monitors/vendor zones)
- [ ] Verify permissions (can_edit, can_view, can_add_servers)
- [ ] Test as staff user
- [ ] Test as regular user
- [ ] Test as monitor admin

### Playwright Tests

Add tests for critical flows:
- Account creation
- Account editing
- User invitation flow
- Permission checks

---

## Rollback Plan

### If Issues Found in Production

1. **Revert Perl changes** - Git revert controller/CAPI changes
2. **Keep Go APIs** - They're backward compatible, just unused
3. **Database** - No schema changes, safe to revert

### Monitoring

- Watch error rates after deployment
- Monitor API latency (GetAccount with all flags)
- Check for "account not found" errors
- Verify no MySQL query errors

---

## Success Criteria

✅ **Zero ORM references:** No `NP::Model->account` outside old/ directory
✅ **All data from APIs:** Every account field comes from Go
✅ **Perl is presentation only:** No database queries for accounts
✅ **No performance regression:** Page load times unchanged
✅ **All tests passing:** Unit, integration, and Playwright tests pass
✅ **Production stable:** No increase in error rates after deployment

---

## Future Work (Out of Scope)

- Migrate `account_invite` table to Go APIs
- Migrate subscription management to Go APIs
- Migrate vendor zones fully to Go APIs
- Remove all Rose::DB models (long-term goal)

---

## Notes

- **Split-brain migration:** During transition, Go writes to PostgreSQL, Perl reads from API (which reads PostgreSQL)
- **No MySQL writes:** Account mutations only through Go APIs
- **Backward compatible:** Keep existing NP::Model::Account until Phase 8
- **Incremental rollout:** Can deploy Perl changes page-by-page if needed
