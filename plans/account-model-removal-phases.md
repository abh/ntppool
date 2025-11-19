# Account Model Removal - Phased Implementation

**Meta-Issue:** [#29](https://gitea.develooper.com/ntppool/ntppool/issues/29)
**Updated:** 2025-11-17

## Overview

This document breaks down the complete account model removal into manageable phases aligned with Gitea issues.

---

## Phase 1: Stripe & Subscription APIs (CRITICAL PATH)

**Issue:** [#22 - Migrate Stripe Billing and Subscription Validation to CAPI](https://gitea.develooper.com/ntppool/ntppool/issues/22)

**Blocks:** Vendor.pm ORM removal, Account model removal

**Scope:**
- Subscription validation business logic (subscription_limits_not_exceeded, have_live_subscription)
- Stripe customer ID management (stripe_customer_id field)
- Account subscription CRUD operations
- Vendor zone permission flags (_permissions.can_edit, _permissions.can_view)

**Go API Work:**
1. Add `stripe_customer_id` to Account proto message
2. Extend `UpdateAccount` RPC to accept stripe_customer_id parameter
3. Add subscription validation (extend GetAccount or create new RPC):
   ```protobuf
   message SubscriptionStatus {
     bool has_live_subscription = 1;
     bool limits_not_exceeded = 2;
     int64 device_limit = 3;
     repeated AccountSubscription active_subscriptions = 4;
   }
   ```
4. Add subscription management RPCs:
   - `CreateOrUpdateAccountSubscription`
   - `UpdateSubscriptionStatus` (for webhooks)
5. Add VendorZone permissions to GetVendorZone response:
   ```protobuf
   message VendorZonePermissions {
     bool can_view = 1;  // vendor_admin OR account member
     bool can_edit = 2;  // vendor_admin OR (account member AND status='New')
   }
   ```

**Perl Work:**
1. Update `NP::CAPI::Account::update_account` to support stripe_customer_id
2. Add subscription validation wrapper functions
3. Create `NP::CAPI::Subscription` module (or extend Account)
4. Update `Vendor.pm`:
   - Replace 3 `NP::Model->account->fetch` calls (lines 198, 310)
   - Replace 5 subscription validation method calls
   - Replace 4 Stripe ORM write operations
5. Update `Webhook.pm` subscription status updates

**ORM Removal:**
- ❌ `NP::Model->account->fetch(id_token => $zone->{account_token})` (3 instances)
- ❌ `$account->subscription_limits_not_exceeded($device_count)` (3 instances)
- ❌ `$account->have_live_subscription()` (1 instance)
- ❌ `$account->live_subscriptions()` (1 instance)
- ❌ `NP::Model->account_subscription->fetch_or_create()` + `->save()` (2 instances)
- ❌ `$account->stripe_customer_id($value); $account->save()` (2 instances)

**Testing:**
- Vendor zone submission with/without subscription
- Subscription limit validation
- Stripe checkout completion
- Webhook subscription updates
- Account upgrade/downgrade flows

**Estimate:** 2-3 weeks

---

## Phase 2: Server Permission Checks (CRITICAL PATH)

**Issue:** [#25 - Migrate Server Permission Checks to CAPI](https://gitea.develooper.com/ntppool/ntppool/issues/25)

**Blocks:** Server.pm ORM removal, Account model removal

**Scope:**
- Server fetching with account context for permission checks
- Nested permission validation (server->account->can_edit)

**Go API Work:**
1. Extend `GetServer` RPC to include account context:
   ```protobuf
   message GetServerRequest {
     string ip = 1;
     bool include_account = 2;
   }
   ```
2. Add ServerPermissions to response (or via AccountPermissions)
3. Compute permissions server-side based on ownership + staff status

**Perl Work:**
1. Update `NP::CAPI::Server` wrappers
2. Update `Server.pm::req_server` method:
   - Replace `NP::Model->server->get_servers()` call (line 346)
   - Use CAPI with account context
   - Check `_permissions` flags instead of calling `->can_edit`

**ORM Removal:**
- ❌ `NP::Model->server->get_servers()` in req_server (1 instance)
- ❌ `$server->account->can_edit($self->user)` (2 instances)
- ❌ `$self->current_account->servers` relationship access (2 instances)

**Testing:**
- Server update operations
- Server verification flow
- Server deletion scheduling
- Permission checks for owner/staff/other users
- Both IP and numeric ID lookups

**Estimate:** 1 week

---

## Phase 3: Monitor API Modernization (LOWER PRIORITY)

**Issue:** [#28 - Migrate Monitor.pm from int_api to CAPI](https://gitea.develooper.com/ntppool/ntppool/issues/28)

**Blocks:** Nothing (Monitor.pm already ORM-free)

**Scope:**
- Migrate from legacy REST API (int_api) to ConnectRPC (CAPI)
- Standardize on modern API architecture

**Go API Work:**
1. Create `proto/ntppool/monitor/v1/monitor.proto`
2. Define MonitorService with RPCs:
   - ListMonitors
   - GetMonitor (with permissions)
   - CreateMonitor
   - UpdateMonitor
   - DeleteMonitor
   - ConfirmMonitor
3. Add MonitorPermissions:
   ```protobuf
   message MonitorPermissions {
     bool can_edit = 1;  // support_staff OR account member
   }
   ```

**Perl Work:**
1. Create `NP::CAPI::Monitor` module
2. Replace 7 `int_api()` calls in `Monitor.pm` with CAPI calls
3. Update error handling for CAPI response format

**ORM Removal:**
- None (already using APIs)

**Testing:**
- Monitor list page
- Monitor registration
- Monitor confirmation
- Permission checks
- Error handling

**Estimate:** 1 week

**Note:** Can be deferred until after Account model removal since Monitor.pm has no ORM dependencies.

---

## Phase 4: Final Model Removal & Deployment

**Issue:** [#29 - Complete Account Model Removal](https://gitea.develooper.com/ntppool/ntppool/issues/29) (Meta-Issue)

**Dependencies:** Phases 1 & 2 complete (Phase 3 optional)

**Scope:**
- Remove Account ORM models from codebase
- Verify zero database access from Perl
- Deploy to production

**Cleanup Work:**
1. Verify zero ORM references:
   ```bash
   git grep 'NP::Model->account' lib/ docs/
   git grep '->can_edit' lib/ | grep -v '_permissions'
   git grep '->servers' lib/ | grep -v '#'
   git grep '->vendor_zones' lib/
   git grep '->account_subscriptions' lib/
   git grep '->save()' lib/
   ```

2. Update ignored tables in `lib/NP/DB/Scaffold.pm`:
   ```perl
   our @IGNORED_TABLES = qw(
       account              # Migrated to Go APIs - 2025-11-17
       account_invite       # Part of account system
       account_user         # Part of account system
       account_subscription # Part of account system
       # ... other tables
   );
   ```

3. Archive old models:
   ```bash
   mkdir -p old/model
   git mv lib/NP/Model/Account.pm old/model/
   git mv lib/NP/Model/AccountInvite.pm old/model/
   git mv lib/NP/Model/AccountSubscription.pm old/model/
   git mv lib/NP/Model/AccountUser.pm old/model/
   ```

4. Regenerate NP::Model:
   ```bash
   perl lib/NP/DB/Scaffold.pm
   ```

5. Commit and tag:
   ```bash
   git add lib/NP/DB/Scaffold.pm lib/NP/Model.pm old/model/
   git commit -m "refactor(account): remove ORM models, fully migrated to Go APIs"
   git tag -a account-model-removal-complete -m "Account ORM fully removed"
   ```

**Deployment:**
1. Deploy to staging environment
2. Monitor for issues:
   - Account management pages
   - Vendor zone submission
   - Server management
   - Monitor management
   - Stripe checkout
3. Conduct smoke tests of all flows
4. Deploy to production during low-traffic window
5. Monitor production metrics

**Rollback Plan:**
- All APIs are backward compatible
- Can revert Perl code changes without touching Go APIs
- No database schema changes required
- Git tag allows easy reversion

**Estimate:** 1 week (testing + deployment)

---

## Success Criteria Checklist

### Technical Requirements
- [ ] Zero `NP::Model->account` calls in lib/ and docs/
- [ ] Zero ORM relationship access (->servers, ->vendor_zones, ->account_subscriptions)
- [ ] Zero ORM writes (->save())
- [ ] Zero permission checks via ORM methods (->can_edit, ->can_view)
- [ ] All business logic in Go APIs
- [ ] All Perl data as plain hashrefs from API responses
- [ ] Permission checks use `$obj->{_permissions}{can_edit}` pattern
- [ ] Account tables in @IGNORED_TABLES
- [ ] Old Account.pm files archived to old/model/

### Functional Requirements
- [ ] Account management pages work
- [ ] Vendor zone creation/editing works
- [ ] Subscription purchase flow works
- [ ] Vendor zone submission validation works
- [ ] Server management works
- [ ] Monitor management works
- [ ] Public profile pages work
- [ ] Staff APIs work
- [ ] No performance regressions
- [ ] All existing tests pass
- [ ] New tests cover API functionality

### Deployment Milestones
- [ ] Phase 1 complete (Issue #22 closed)
- [ ] Phase 2 complete (Issue #25 closed)
- [ ] Staging deployment successful
- [ ] Production deployment successful
- [ ] Issue #29 closed

---

## Timeline Estimate

**Conservative (6 weeks):**
- Weeks 1-2: Phase 1 (Stripe/Subscription APIs)
- Week 3: Phase 1 Perl integration + testing
- Week 4: Phase 2 (Server permissions)
- Week 5: Phase 3 (Monitor API) - OPTIONAL
- Week 6: Phase 4 (Model removal + deployment)

**Aggressive (4 weeks):**
- Weeks 1-2: Phase 1 (Stripe/Subscription)
- Week 3: Phase 2 (Server permissions)
- Week 4: Phase 4 (Skip Phase 3, deploy)

**Notes:**
- Phase 3 (Monitor) can be deferred indefinitely
- Phases 1 & 2 are the critical path
- Timeline assumes focused work without major blockers
- Add buffer for unexpected issues and testing

---

## Risk Mitigation

**High-Risk Areas:**
1. **Subscription validation** - Critical for vendor zone business logic
   - Mitigation: Extensive testing with test subscriptions
   - Mitigation: Property-based tests for limit validation
   - Mitigation: Compare API results to ORM results during development

2. **Stripe integration** - Handles real money
   - Mitigation: Test in Stripe test mode
   - Mitigation: Manual QA of entire checkout flow
   - Mitigation: Deploy during low-traffic period

3. **Permission checks** - Security-critical
   - Mitigation: Audit all permission computations in Go
   - Mitigation: Write comprehensive permission tests
   - Mitigation: Verify no permission bypasses

**Medium-Risk Areas:**
1. **Server management** - Core pool functionality
   - Mitigation: Parallel testing before switching
   - Mitigation: Gradual rollout via feature flag (optional)

2. **Public profile pages** - External visibility
   - Mitigation: Monitor 404 rates after deployment
   - Mitigation: Test URL slug lookups thoroughly

---

## Related Documentation

- [Complete Account Model Removal Plan](./account-model-complete-removal.md) - Detailed technical plan
- [PostgreSQL Migration](./postgres.md) - Database migration context
- [Issue #29](https://gitea.develooper.com/ntppool/ntppool/issues/29) - Meta-issue tracking all phases
- [Issue #22](https://gitea.develooper.com/ntppool/ntppool/issues/22) - Stripe & Subscription APIs
- [Issue #25](https://gitea.develooper.com/ntppool/ntppool/issues/25) - Server Permission Checks
- [Issue #28](https://gitea.develooper.com/ntppool/ntppool/issues/28) - Monitor API Modernization
