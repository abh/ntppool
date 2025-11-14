# Vendor Zone CAPI Migration Guide

**Status**: Phase 2A Complete, Phase 2B Partial
**Related Issue**: #3
**Last Updated**: 2025-11-13

## Overview

This guide documents the migration of vendor zone management from direct Rose::DB database access (`NP::Model->vendor_zone`) to ConnectRPC API calls (`NP::CAPI::VendorZone`).

**Goal**: Migrate `lib/NTPPool/Control/Vendor.pm` to use CAPI for all database operations, supporting both numeric IDs and token IDs during the transition.

---

## ✅ Phase 2A: Go API Implementation (COMPLETE)

### Completed Work

1. **Proto Definitions** (`../go/ntp/api/proto/ntppool/vendorzone/v1/vendor.proto`)
   - ✅ Added `ListVendorZonesAdmin` RPC for admin cross-account listing
   - ✅ Added `GetVendorZoneFormMetadata` RPC for DNS root options
   - ✅ Added `VendorZoneAdmin` message with account details
   - ✅ Added `DNSRoot` message for form metadata
   - ✅ Added `email_sent` and `user_email` fields (for future Phase 3)

2. **SQL Queries** (`../go/ntp/api/sql/vendor_zones.sql`)
   - ✅ Added `ListVendorZonesAdmin` with account/subscription joins
   - ✅ Added `ListDNSRoots` for vendor-available DNS roots

3. **Go Handlers** (`../go/ntp/api/server/api/vendorzone/`)
   - ✅ `list_admin.go` - Admin zone listing with privilege check
   - ✅ `metadata.go` - Form metadata with DNS roots
   - ✅ Updated `vendorzone.go` to support `ListVendorZonesAdminRow`

4. **Generated Code**
   - ✅ Regenerated sqlc queries (`ntpdb/vendor_zones.sql.go`)
   - ✅ Regenerated Go protobuf code
   - ✅ Regenerated Perl CAPI client (`lib/NP/CAPI/VendorZone.pm`)

### Available CAPI Methods

```perl
use NP::CAPI::VendorZone qw(
    list_vendor_zones              # List zones for account
    get_vendor_zone                # Get single zone by token
    request_vendor_zone            # Create new zone
    update_vendor_zone             # Update zone fields
    submit_vendor_zone             # Submit for approval (New -> Pending)
    update_vendor_zone_status      # Admin approve/reject
    list_vendor_zones_admin        # Admin list all zones
    get_vendor_zone_form_metadata  # DNS roots for form
);
```

---

## ⚠️ Phase 2B: Perl Controller Migration (PARTIAL)

### Completed Work

1. **Infrastructure** (`lib/NTPPool/Control/Vendor.pm`)
   - ✅ Added CAPI imports
   - ✅ Created `_resolve_zone_token()` helper for ID compatibility
   - ✅ Migrated 2 operations:
     - manage_dispatch zone count check → `list_vendor_zones()`
     - render_form DNS roots → `get_vendor_zone_form_metadata()`

### Remaining Work

#### 1. Migrate Zone Fetch Operations (6 locations)

**Pattern to follow:**

```perl
# OLD (database)
my $vz = NP::Model->vendor_zone->fetch(id => $id);
return NOT_FOUND unless $vz;
return FORBIDDEN unless $vz->can_view($self->user);

# NEW (API)
my $token = $self->_resolve_zone_token($id);
my $result = get_vendor_zone(
    auth    => $self->plain_cookie($self->user_cookie_name),
    id_token => $token,
    context => $self->_get_request_context(),
);

if ($result->{error}) {
    if ($result->{code} == 404) {
        return NOT_FOUND;
    }
    if ($result->{code} == 403) {
        return FORBIDDEN;
    }
    warn "API error: " . $result->{error};
    return $result->{code};
}

my $zone = $result->{data}{zone};  # Hashref, not blessed object
```

**Locations to migrate:**

| Method | Line | Current Code | CAPI Method |
|--------|------|--------------|-------------|
| `render_zone` | ~174 | `NP::Model->vendor_zone->fetch(id => $id)` | `get_vendor_zone(id_token => $token)` |
| `render_submit` | ~206 | `NP::Model->vendor_zone->fetch(id => $id)` | `get_vendor_zone(id_token => $token)` |
| `_edit_zone` | ~309 | `NP::Model->vendor_zone->fetch(id => $id)` | `get_vendor_zone(id_token => $token)` |
| `render_subscription` | ~412 | `NP::Model->vendor_zone->fetch(id => $id)` | `get_vendor_zone(id_token => $token)` |
| `render_admin` | ~540 | `NP::Model->vendor_zone->fetch(id => $id)` | `get_vendor_zone(id_token => $token)` |
| `render_edit_json` | ~298 | Called via `_edit_zone` | Same as above |

**After migration, update data access:**

```perl
# OLD
my $name = $vz->zone_name;
my $status = $vz->status;
if ($vz->device_count > 1000) { ... }

# NEW
my $name = $zone->{zone_name};
my $status = $zone->{status};
if ($zone->{device_count} > 1000) { ... }
```

**Remove permission checks (API handles them):**

```perl
# OLD - Delete these lines
return FORBIDDEN unless $vz->can_view($self->user);
return FORBIDDEN unless $vz->can_edit($self->user);

# NEW - API returns 403, handled above
# No explicit permission checks needed
```

---

#### 2. Migrate Zone List Operations (2 locations)

**A) render_zones - Line ~102**

```perl
# OLD
if (my @subs = $self->current_account->account_subscriptions) {
    $self->tpl_param('subscriptions', [grep { $_->live_subscription } @subs]);
}

# NEW
# Subscription data still comes from Rose::DB (not migrating in Phase 2)
# This stays the same for now

# Template already gets zones from manage_dispatch via list_vendor_zones()
# No additional migration needed here
```

**B) render_admin - Line ~581**

```perl
# OLD
my $pending = NP::Model->vendor_zone->get_vendor_zones(
    query        => [status => ['Pending']],
    sort_by      => 'account_subscriptions.created_on desc, account.id desc',
    with_objects => ['account', 'account.account_subscriptions'],
);
$self->tpl_param(pending_zones => $pending);

# NEW
my $result = list_vendor_zones_admin(
    auth    => $self->plain_cookie($self->user_cookie_name),
    context => $self->_get_request_context(),
    status  => 'Pending',
);

if ($result->{error}) {
    warn "Failed to list pending zones: " . $result->{error};
    $self->tpl_param(pending_zones => []);
} else {
    # API returns VendorZoneAdmin objects with zone + account details
    $self->tpl_param(pending_zones => $result->{data}{zones});
}
```

**Update template access:**

```html
<!-- OLD (tpl/vendor/admin.html) -->
[% FOREACH vz IN pending_zones %]
  [% vz.zone_name %]
  [% vz.account.name %]
  [% vz.user.email %]
[% END %]

<!-- NEW -->
[% FOREACH admin_zone IN pending_zones %]
  [% admin_zone.zone.zone_name %]
  [% admin_zone.account_name %]
  [% admin_zone.user_email %]
[% END %]
```

---

#### 3. Migrate Create/Update Operations (5 locations)

**A) _edit_zone Create - Line ~338**

```perl
# OLD
$vz = NP::Model->vendor_zone->create(
    zone_name  => $zone_name,
    user_id    => $self->user->{user_id},
    account_id => $self->current_account->{account_id},
    dns_root   => $dns_root->id,
    (map { $_ => ($self->req_param($_) || '') } @fields)
);

# NEW
my $result = request_vendor_zone(
    auth                => $self->plain_cookie($self->user_cookie_name),
    account             => $self->current_account->id_token,
    context             => $self->_get_request_context(),
    zone_name           => $zone_name,
    organization_name   => $self->req_param('organization_name') || '',
    request_information => $self->req_param('request_information') || '',
    device_count        => $self->req_param('device_count') || 0,
    device_information  => $self->req_param('device_information') || '',
    contact_information => $self->req_param('contact_information') || '',
    client_type         => $self->req_param('client_type') || 'sntp',
);

if ($result->{error}) {
    warn "Failed to create vendor zone: " . $result->{error};
    return (undef, [$result->{error}]);
}

my $zone = $result->{data}{zone};

# NOTE: API auto-selects default DNS root, remove dns_root lookup
```

**B) _edit_zone Update - Line ~323**

```perl
# OLD
$vz->zone_name($zone_name);
for my $f (@fields) {
    $vz->$f($self->req_param($f) || '');
}
$vz->save;

# NEW
my $token = $self->_resolve_zone_token($id);
my $result = update_vendor_zone(
    auth                => $self->plain_cookie($self->user_cookie_name),
    context             => $self->_get_request_context(),
    id_token            => $token,
    zone_name           => $zone_name,
    organization_name   => $self->req_param('organization_name'),
    request_information => $self->req_param('request_information'),
    device_count        => $self->req_param('device_count'),
    device_information  => $self->req_param('device_information'),
    contact_information => $self->req_param('contact_information'),
    client_type         => $self->req_param('client_type'),
);

if ($result->{error}) {
    warn "Failed to update vendor zone: " . $result->{error};
    return (undef, [$result->{error}]);
}

my $zone = $result->{data}{zone};
```

**C) render_submit - Line ~254**

```perl
# OLD
$vz->status('Pending');
$vz->save;

# NEW
my $token = $self->_resolve_zone_token($vz->{vendor_zone_id});
my $opensource = $self->req_param('opensource_request') ? JSON::XS::true : JSON::XS::false;
my $result = submit_vendor_zone(
    auth            => $self->plain_cookie($self->user_cookie_name),
    context         => $self->_get_request_context(),
    id_token        => $token,
    opensource      => $opensource,
    opensource_info => $self->req_param('opensource_info') || '',
);

if ($result->{error}) {
    warn "Failed to submit vendor zone: " . $result->{error};
    # Handle error
    return $self->render_zone($vz->{vendor_zone_id});
}

my $zone = $result->{data}{zone};
```

**D) render_admin Reject - Line ~549**

```perl
# OLD
$vz->status('Rejected');
$vz->save;

# NEW
my $token = $self->_resolve_zone_token($id);
my $result = update_vendor_zone_status(
    auth     => $self->plain_cookie($self->user_cookie_name),
    context  => $self->_get_request_context(),
    id_token => $token,
    status   => 'Rejected',
);

if ($result->{error}) {
    warn "Failed to reject vendor zone: " . $result->{error};
}
```

**E) render_admin Approve - Line ~556**

```perl
# OLD
$vz->status('Approved');
$vz->approved_on(DateTime->now);
$vz->save;

# NEW
my $token = $self->_resolve_zone_token($id);
my $result = update_vendor_zone_status(
    auth     => $self->plain_cookie($self->user_cookie_name),
    context  => $self->_get_request_context(),
    id_token => $token,
    status   => 'Approved',
);

if ($result->{error}) {
    warn "Failed to approve vendor zone: " . $result->{error};
}

# Note: approved_on is set automatically by the API
```

---

#### 4. Update Data Access Patterns Throughout

**Every location that accesses zone data needs updating:**

| Old Pattern | New Pattern | Example Locations |
|-------------|-------------|-------------------|
| `$vz->zone_name` | `$zone->{zone_name}` | Throughout render_zone, templates |
| `$vz->status` | `$zone->{status}` | Status checks in render_submit, render_admin |
| `$vz->device_count` | `$zone->{device_count}` | Subscription checks in render_zone |
| `$vz->id` | `$zone->{vendor_zone_id}` | Numeric ID access |
| `$vz->id_token` | `$zone->{id_token}` | Token ID access |
| `$vz->account->subscription_limits_not_exceeded()` | Still use Rose::DB for account subscriptions | Subscription checks (not migrating in Phase 2) |
| `$vz->user->email` | Fetch from API or use `$result->{data}{user_email}` | Email sending in render_submit |

**Template updates needed:**

- `tpl/vendor.html` - Zone listing
- `tpl/vendor/show.html` - Zone details
- `tpl/vendor/form.html` - Zone edit form
- `tpl/vendor/admin.html` - Admin zone list (see section 2B above)
- `tpl/vendor/submit_email.txt` - Email template (still uses `$vz` variable)
- `tpl/vendor/approved_email.txt` - Approval email template

---

#### 5. Handle Validation

**OLD approach (Rose::DB validation):**

```perl
unless ($vz->validate) {
    my $errors = $vz->validation_errors;
    return $vz, $errors;
}
$vz->save;
```

**NEW approach (API validation):**

```perl
# API performs validation automatically
# Validation errors are returned in response

my $result = request_vendor_zone(...);

if ($result->{error}) {
    # API returns validation errors in error field
    # Parse and display to user
    $self->tpl_param('errors', {general => $result->{error}});
    return $self->render_form();
}
```

**Note**: You may need to update the Go API handlers to return structured validation errors if they don't already. Current implementation returns general error messages.

---

## 🧪 Phase 2C: Testing (TODO)

### Test Checklist

#### User Workflows

- [ ] **Create New Zone**
  1. Navigate to `/manage/vendor/new`
  2. Fill form with valid data
  3. Submit form
  4. Verify zone created with status "New"
  5. Check both numeric and token IDs work in URLs

- [ ] **Edit Zone**
  1. Navigate to zone detail page (`/manage/vendor/zone?id=vz-xxx`)
  2. Click edit
  3. Modify fields
  4. Save
  5. Verify changes persisted

- [ ] **Submit Zone for Approval**
  1. Edit zone to complete all required fields
  2. Submit zone (with or without opensource)
  3. Verify status changes to "Pending"
  4. Verify email sent (manual check for now, Phase 3 will automate)

- [ ] **View Zone Details**
  1. Access zone via numeric ID (`/manage/vendor/zone?id=123`)
  2. Access zone via token ID (`/manage/vendor/zone?id=vz-xxx`)
  3. Verify all fields display correctly

#### Admin Workflows

- [ ] **List Pending Zones**
  1. Login as vendor_admin user
  2. Navigate to `/manage/vendor/admin`
  3. Verify pending zones listed with account details
  4. Check sorting (subscription created_on desc, then account id desc)

- [ ] **Approve Zone**
  1. From admin list, approve a pending zone
  2. Verify status changes to "Approved"
  3. Verify approved_on timestamp set
  4. Verify approval email sent (manual check, Phase 3 automates)

- [ ] **Reject Zone**
  1. From admin list, reject a pending zone
  2. Verify status changes to "Rejected"
  3. Verify rejection email sent (manual check, Phase 3 automates)

#### Error Handling

- [ ] **API Unavailable**
  - Stop Go API service
  - Attempt zone operations
  - Verify graceful error messages (not database errors)

- [ ] **Invalid Token ID**
  - Access `/manage/vendor/zone?id=vz-invalid`
  - Verify 404 NOT FOUND response

- [ ] **Permission Denied**
  - Attempt to access another user's zone
  - Verify 403 FORBIDDEN response

- [ ] **Validation Errors**
  - Submit form with invalid zone_name
  - Submit form with missing required fields
  - Verify validation errors displayed

#### Backward Compatibility

- [ ] **Numeric IDs**
  - Verify all URLs with numeric IDs still work
  - Verify redirects/links still use appropriate ID format

- [ ] **Token IDs**
  - Verify all URLs with token IDs work
  - Verify API calls use tokens correctly

---

## 🚧 Phase 3: Email Migration (FUTURE)

**Deferred to future work** - Email sending remains in Perl for now.

### When Ready to Migrate Emails:

1. **Create Email Infrastructure in Go**
   - Add SMTP client configuration
   - Create email templates (HTML/text)
   - Add email service to vendor zone handlers

2. **Update submit_vendor_zone Handler**
   - Send submission notification email
   - Set `email_sent` field in response

3. **Update update_vendor_zone_status Handler**
   - Send approval/rejection email
   - Set `email_sent` field in response

4. **Remove Perl Email Code**
   - Delete email sending from `render_submit` (lines ~260-268)
   - Delete email sending from `render_admin` (lines ~563-573)
   - Remove `NP::Email` and `Email::Stuffer` dependencies

5. **Update Templates**
   - Remove email template evaluation from Perl
   - Move templates to Go (`docs/tpl/vendor/*.txt` → Go email templates)

---

## 📝 Implementation Notes

### Common Pitfalls

1. **Blessed Objects vs Hashrefs**
   - API returns hashrefs, not blessed objects
   - Cannot call methods like `$zone->zone_name`
   - Use `$zone->{zone_name}` instead

2. **Permission Checks**
   - Old code: `$vz->can_view($self->user)`
   - New code: API returns 403, handle in error response
   - Don't add explicit permission checks

3. **ID Format Confusion**
   - Numeric IDs: `123` (database primary key)
   - Token IDs: `vz-abc123xyz` (API format)
   - Always use `_resolve_zone_token()` before API calls

4. **Validation**
   - Old code: `$vz->validate()` before `$vz->save()`
   - New code: API validates automatically, check `$result->{error}`

5. **Relationships**
   - Account subscriptions still use Rose::DB (not migrated)
   - `$zone->{account_token}` is a string, not object
   - Use `$self->current_account` for subscription checks

### Error Handling Pattern

```perl
my $result = some_capi_method(...);

# Always check for errors first
if ($result->{error}) {
    warn "API error (" . $result->{code} . "): " . $result->{error};

    # Handle specific error codes
    return NOT_FOUND if $result->{code} == 404;
    return FORBIDDEN if $result->{code} == 403;

    # Generic error page for others
    $self->tpl_param('error_message', $result->{error});
    return OK, $self->evaluate_template('tpl/error.html');
}

# Only access data if no error
my $data = $result->{data};
```

### Boolean Values

```perl
# OLD (Perl booleans)
$vz->opensource(1);

# NEW (JSON booleans for API)
use JSON::XS ();
my $opensource = $self->req_param('opensource_request') ? JSON::XS::true : JSON::XS::false;

my $result = submit_vendor_zone(
    opensource => $opensource,  # Sends true/false JSON boolean
    ...
);
```

### Optional Fields

```perl
# API uses Perl's undef for optional fields
# Don't send empty strings, use undef for "not provided"

my $result = update_vendor_zone(
    id_token => $token,
    zone_name => $zone_name,  # Required, always send
    device_information => $self->req_param('device_information') || undef,  # Optional
);
```

---

## 🎯 Success Criteria

Before marking Phase 2B complete:

1. ✅ All database operations use CAPI (no `NP::Model->vendor_zone` calls)
2. ✅ Both numeric and token IDs work in URLs
3. ✅ All user workflows tested and passing
4. ✅ All admin workflows tested and passing
5. ✅ Error handling graceful (no database errors exposed)
6. ✅ Templates updated to use hashref access
7. ✅ Email sending still works (stays in Perl for now)
8. ✅ No regressions in functionality

---

## 📚 Additional Resources

- **API Documentation**: `../go/ntp/api/proto/ntppool/vendorzone/v1/vendor.proto`
- **CAPI Client**: `lib/NP/CAPI/VendorZone.pm` (auto-generated)
- **Go Handlers**: `../go/ntp/api/server/api/vendorzone/`
- **Integration Tests**: `../go/ntp/api/server/api/vendorzone/*_integration_test.go`
- **Phase 1 Summary**: See git commit message for `a942849`

---

## ✅ Quick Start

To continue the migration:

```bash
# 1. Review this guide
cat docs/VENDOR_ZONE_MIGRATION_GUIDE.md

# 2. Start with one method at a time
# Begin with render_zone (line ~174)

# 3. Follow the patterns in "Migrate Zone Fetch Operations" section

# 4. Test each change:
#    - Manual testing via web UI
#    - Check error handling
#    - Verify both ID formats work

# 5. Update templates as needed

# 6. Move to next method when current method works

# 7. Complete all operations before testing admin workflows
```

---

**Last Updated**: 2025-11-13
**Contact**: See git history for contributors
