# Vendor zone E2E coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live-subscription seed to `api e2e fixture create|cleanup`, deploy it to devel, and automate the unchecked `MANUAL_TEST_PLAN.md` §5 vendor zone rows in `e2e/tests/vendor.spec.ts` and a new `e2e/tests/vendor-coverage.spec.ts`.

**Architecture:** The Go `e2efixture` package inserts one `account_subscriptions` row (`stripe_subscription_id` = `e2e_<attempt_id>`) in the fixture create transaction and removes it in cleanup, with an ownership check. The Playwright harness gains a subscription seed, a `lib/vendor.ts` helper module (moved and new helpers, including direct `GetVendorZone`/`SubmitVendorZone` ConnectRPC calls), new tests in `vendor.spec.ts`, and a new fixture-based `vendor-coverage.spec.ts`. No Perl or template changes.

**Tech Stack:** Go, PostgreSQL, sqlc (`go tool sqlc`), gowrap and mockery (`go generate ./ntpdb/`), kong, testify; TypeScript, Playwright, ConnectRPC JSON.

**Spec:** `docs/superpowers/specs/2026-09-14-vendor-zone-e2e-coverage-design.md` (in `/Users/ask/src/ntppool`). Read it before any task; test numbers 1 to 11 below are the spec's.

## Global Constraints

- Repos: `/Users/ask/src/go/ntp/api` (branch `main`) and `/Users/ask/src/ntppool` (branch `postgres`). Work in these checkouts, not in worktrees: each repo gets exactly ONE commit, made in Task 4 (API) and Task 13 (ntppool). No other task commits, stages or pushes.
- Never `git add -A`, `git add .` or `git commit -a`; stage files by name. Before each commit run `git status` and `git diff --staged`; if the staged set isn't exactly what the task lists, stop and report. Re-run `git status` right before `git commit`. Never `--no-verify`.
- The API repo has an unrelated modified file, `plans/active/perl-model-migration-status.md`, and many untracked files. The ntppool repo has many unrelated untracked files. Never stage them.
- Before the API commit: `gofumpt -w` on hand-edited `.go` files, `git diff --check` clean, and every generated file staged (`ntpdb/e2e_fixtures.sql.go`, `ntpdb/querier.go`, `ntpdb/otel.go`, `ntpdb/mocks.go`).
- API integration tests only through `./scripts/test-integration [package] [pattern]`. Never set env vars inline on any test command (Go or Playwright). Playwright reads `e2e/.env` through `playwright.config.ts`.
- Local Go builds currently fail with "You have not agreed to the Xcode license agreements" (`runtime/cgo`, `CGO_ENABLED=1`). If any Go command prints that, stop and ask the user to run `sudo xcodebuild -license`. Don't work around it with env vars.
- Harness changes are test code. Don't add unit tests for them (the user's rule: don't test the test code). Verify with `npm run typecheck`, `npm run test:unit`, `npx playwright test --list` and the live runs.
- Test emails at `example.com`; IPs from RFC 5737 and `2001:db8::/32`.
- Devel database: reads only, inside `BEGIN READ ONLY` through `kubectl --context dala -n askntp exec -i pg-1 -c postgres -- psql -d askntp`. Never read a local MySQL database.
- Never commit or push `~/src/flux-ntp`. The deploy is a local tag edit plus `./update-api`.
- If a devel E2E run shows the API needs a fix, stop and report. Don't make a second API commit.
- Don't mask errors: fail, don't fall back. The one allowed default is the harness sending no `subscription` key when a spec doesn't seed one.
- Docs and commit messages: plain words, no "comprehensive" or "business".
- Strings pinned verbatim:
  - Go submit gate: `a subscription is required, or apply as open source`
  - Whitespace justification: `opensource_info must contain non-whitespace characters`
  - Approved rename: `zone name cannot be changed after approval`
  - Perl uncovered plain submit: `Please choose a subscription plan or choose open source below`
  - Perl over-limit: `The current subscription plan doesn't support adding the new DNS zone.`
  - Seeded row: status `active`, name `E2E fixture`, `stripe_subscription_id` `e2e_<attempt_id>`
  - Billing block: `Up to 1 DNS zones`, `Up to 10,000 client devices`

## Execution order and parallel work

| Task | Track | Depends on | Can run in parallel with |
| --- | --- | --- | --- |
| 1 Subscription seed on create | API | none | 6 to 11 |
| 2 Subscription cleanup | API | 1 | 6 to 11 |
| 3 CLI help, wire format, doc fix | API | 2 | 6 to 11 |
| 4 Verify, review, commit, push | API | 3 | 6 to 11 |
| 5 Deploy the API to devel | ops | 4 | 9, 10, 11 |
| 6 Dev site freshness | ops | none | everything |
| 7 `connectMessage` and `lib/vendor.ts` | harness | none | 1 to 4, 6, 8, 11 |
| 8 Subscription seed in `lib/fixtures.ts` | harness | none | 1 to 4, 6, 7, 11 |
| 9 `vendor.spec.ts` tests 1 to 7 | harness | 7 (and 6 for its live step) | 10, 11, API track |
| 10 `vendor-coverage.spec.ts` tests 8 to 11 | harness | 7, 8 | 9, 11, API track |
| 11 `MANUAL_TEST_PLAN.md` and `e2e/README.md` | harness | none (test names are fixed below) | everything before 12 |
| 12 Devel E2E runs and ticks | ops | 5, 6, 9, 10, 11 | none |
| 13 ntppool commit | ops | 12 | none |

Tasks 7 and 9 both edit `e2e/tests/vendor.spec.ts`, so they run one after the other. The API track (1 to 4) shares files and runs in order. Everything in the harness track is independent of the deploy until Task 12.

Test titles (used by Tasks 9 to 12; keep them exact):

1. `every writable field saves on a New zone`
2. `every writable field saves on a Pending zone`
3. `a whitespace-only justification is refused by the API and the zone stays New`
4. `an uncovered plain submit is refused by the site and by the API`
5. `renaming an Approved zone shows the API's refusal`
6. `approve/reject status changes and owner resubmit` (existing title, extended)
7. `approving with Grant unchecked leaves the zone on the paid path`
8. `a covered vendor gets a plain submit and stays off the open-source path`
9. `a covered vendor over the device limit is refused by the site and by the API`
10. `a covered vendor at the zone limit is refused by the site and by the API`
11. `a vendor admin submits for a covered account, and the owner resubmits after a rejection`

---

### Task 1 [API]: Subscription seed on create

**Files:**
- Modify: `sql/e2e_fixtures.sql` (append a query)
- Modify: `e2efixture/fixture.go` (types at `:47-124`, `validateFixtureRequest` at `:156-187`, `CreateFixture` at `:282-294`)
- Test: `e2efixture/fixture_integration_test.go`
- Generated: `ntpdb/e2e_fixtures.sql.go`, `ntpdb/querier.go`, `ntpdb/otel.go`, `ntpdb/mocks.go`

**Interfaces:**
- Consumes: `ntpdb.AccountSubscriptionsStatusActive`, `subscription.AccountCoverage(ctx, ntpdb.Querier, accountID, additionalDevices int64) (Coverage, error)` with states `subscription.Covered`, `subscription.OverLimit` (`server/api/subscription/coverage.go`).
- Produces:
  - `e2efixture.SubscriptionFixtureSpec{MaxZones int64; MaxDevices int64}` (JSON `max_zones`, `max_devices`)
  - `CreateFixtureRequest.Subscription *SubscriptionFixtureSpec` (JSON `subscription`)
  - `e2efixture.FixtureSubscription{SubscriptionID int64; StripeSubscriptionID string; Status string; MaxZones int64; MaxDevices int64}` (JSON `subscription_id` encoded as a string, `stripe_subscription_id`, `status`, `max_zones`, `max_devices`)
  - `CreateFixtureResponse.Subscription *FixtureSubscription` (JSON `subscription`, no `omitempty`; `null` when not requested)
  - unexported `fixtureStripeSubscriptionID(attemptID string) pgtype.Text`, `fixtureSubscriptionName = "E2E fixture"` (Task 2 uses the first)
  - `(*ntpdb.Queries).InsertE2EFixtureSubscription(ctx, ntpdb.InsertE2EFixtureSubscriptionParams) (int64, error)`

- [ ] **Step 1: Check the toolchain**

Run (in `/Users/ask/src/go/ntp/api`): `go build -o /dev/null ./...`
Expected: no output. If it prints the Xcode license message, stop and ask the user to run `sudo xcodebuild -license`.

- [ ] **Step 2: Write the failing tests**

In `e2efixture/fixture_integration_test.go`:

Add the import `"go.ntppool.org/api/server/api/subscription"`.

After `type family = e2efixture.MonitorFamilySpec` add:

```go
	type subscriptionSpec = e2efixture.SubscriptionFixtureSpec
```

In `t.Run("validation before mutation", ...)`, append these entries to the slice literal, after the last existing entry:

```go
			{AttemptID: attempt(t), Subscription: &subscriptionSpec{}},
			{AttemptID: attempt(t), Subscription: &subscriptionSpec{MaxDevices: 10000}}, // What a missing max_zones decodes to.
			{AttemptID: attempt(t), Subscription: &subscriptionSpec{MaxZones: 1}},       // What a missing max_devices decodes to.
			{AttemptID: attempt(t), Subscription: &subscriptionSpec{MaxZones: -1, MaxDevices: 10000}},
			{AttemptID: attempt(t), Subscription: &subscriptionSpec{MaxZones: 1, MaxDevices: -1}},
			{AttemptID: attempt(t), Servers: []spec{{IPVersion: 5}}, Subscription: &subscriptionSpec{MaxZones: 1, MaxDevices: 10000}},
```

The existing `{AttemptID: attempt(t)}` entry is the "no server, monitor or subscription" case. In the loop body, after the monitors `require.Zero`, add:

```go
			require.Zero(t, count(t, "SELECT count(*) FROM account_subscriptions WHERE stripe_subscription_id = $1", "e2e_"+invalid.AttemptID))
```

In `t.Run("servers and a monitor in one attempt", ...)`, add at the end:

```go
		require.Nil(t, fixture.Subscription, "no subscription unless requested")
		require.Zero(t, count(t, "SELECT count(*) FROM account_subscriptions WHERE account_id=$1", fixture.AccountID))
```

After that subtest, add two subtests:

```go
	t.Run("subscription only attempt", func(t *testing.T) {
		id := attempt(t)
		fixture := createRequest(t, e2efixture.CreateFixtureRequest{AttemptID: id, Subscription: &subscriptionSpec{MaxZones: 1, MaxDevices: 10000}})
		require.NotNil(t, fixture.Servers)
		require.Empty(t, fixture.Servers)
		require.NotNil(t, fixture.Monitors)
		require.Empty(t, fixture.Monitors)
		validateSession(t, ctx, db, fixture.SessionToken)

		sub := fixture.Subscription
		require.NotNil(t, sub)
		require.Equal(t, "e2e_"+id, sub.StripeSubscriptionID)
		require.Equal(t, "active", sub.Status)
		require.EqualValues(t, 1, sub.MaxZones)
		require.EqualValues(t, 10000, sub.MaxDevices)
		require.Equal(t, 1, count(t, `SELECT count(*) FROM account_subscriptions
			WHERE id=$1 AND account_id=$2 AND stripe_subscription_id=$3 AND status='active'
			  AND name='E2E fixture' AND max_zones=1 AND max_devices=10000 AND ended_on IS NULL`,
			sub.SubscriptionID, fixture.AccountID, "e2e_"+id))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM accounts WHERE id=$1 AND stripe_customer_id IS NULL", fixture.AccountID))

		// The seed is only useful if the vendor zone submit gate reads it as a
		// live subscription with the requested limits.
		covered, err := subscription.AccountCoverage(ctx, q, fixture.AccountID, 10000)
		require.NoError(t, err)
		require.Equal(t, subscription.Covered, covered.State)
		over, err := subscription.AccountCoverage(ctx, q, fixture.AccountID, 10001)
		require.NoError(t, err)
		require.Equal(t, subscription.OverLimit, over.State)
	})

	t.Run("subscription and a server in one attempt", func(t *testing.T) {
		id := attempt(t)
		fixture := createRequest(t, e2efixture.CreateFixtureRequest{
			AttemptID:    id,
			Servers:      []spec{{IPVersion: 4, Netspeed: 512}},
			Subscription: &subscriptionSpec{MaxZones: 2, MaxDevices: 5000},
		})
		require.Len(t, fixture.Servers, 1)
		require.NotNil(t, fixture.Subscription)
		require.EqualValues(t, 2, fixture.Subscription.MaxZones)
		require.EqualValues(t, 5000, fixture.Subscription.MaxDevices)
		require.Equal(t, 1, count(t, "SELECT count(*) FROM servers WHERE account_id=$1", fixture.AccountID))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM account_subscriptions WHERE account_id=$1", fixture.AccountID))
	})
```

Teardown needs no change: `attempt(t)` ends in `testhelpers.RemoveFixtureIdentity`, which deletes `account_subscriptions` by account before the account (`testhelpers/integration_cleanup.go:538-548`).

- [ ] **Step 3: Run the tests to verify they fail**

Run: `./scripts/test-integration ./e2efixture TestFixtureIntegration`
Expected: build failure naming `e2efixture.SubscriptionFixtureSpec` or the unknown field `Subscription`.

- [ ] **Step 4: Add the insert query**

Append to `sql/e2e_fixtures.sql`:

```sql

-- name: InsertE2EFixtureSubscription :one
INSERT INTO account_subscriptions (account_id, stripe_subscription_id, status, name,
                                   max_zones, max_devices, created_on)
VALUES (sqlc.arg(account_id), sqlc.arg(stripe_subscription_id),
        sqlc.arg(status)::account_subscriptions_status, sqlc.arg(name),
        sqlc.arg(max_zones), sqlc.arg(max_devices), CURRENT_TIMESTAMP)
RETURNING id;
```

- [ ] **Step 5: Generate**

Run: `go tool sqlc generate && go generate ./ntpdb/`
Run: `grep -n "type InsertE2EFixtureSubscriptionParams struct" -A8 ntpdb/e2e_fixtures.sql.go`
Expected fields: `AccountID int64`, `StripeSubscriptionID pgtype.Text`, `Status AccountSubscriptionsStatus`, `Name string`, `MaxZones int64`, `MaxDevices int64`, and the method returns `(int64, error)`. If the generated names or types differ, use the generated ones in Step 6 and say so in the task report.
Run: `git status --short ntpdb/ sql/`
Expected: `sql/e2e_fixtures.sql`, `ntpdb/e2e_fixtures.sql.go`, `ntpdb/querier.go`, `ntpdb/otel.go`, `ntpdb/mocks.go` modified; nothing else under `ntpdb/`.

- [ ] **Step 6: Implement the seed in `e2efixture/fixture.go`**

Replace the `CreateFixtureRequest` type (`:68-73`) with:

```go
// SubscriptionFixtureSpec seeds one live subscription on the fixture account.
// A missing limit decodes to 0 and fails validation.
type SubscriptionFixtureSpec struct {
	MaxZones   int64 `json:"max_zones"`   // At least 1.
	MaxDevices int64 `json:"max_devices"` // At least 1.
}

// CreateFixtureRequest is the stdin JSON for `api e2e fixture create`.
type CreateFixtureRequest struct {
	AttemptID    string                   `json:"attempt_id"`   // Canonical lowercase UUID v4, generated before calling.
	Servers      []ServerFixtureSpec      `json:"servers"`      // 0..4; response order preserved.
	Monitors     []MonitorFixtureSpec     `json:"monitors"`     // 0..1.
	Subscription *SubscriptionFixtureSpec `json:"subscription"` // Optional; absent or null means none.
}
```

After the `FixtureMonitor` type (`:96-100`), add:

```go
// FixtureSubscription is the seeded account_subscriptions row.
type FixtureSubscription struct {
	SubscriptionID       int64  `json:"subscription_id,string"`
	StripeSubscriptionID string `json:"stripe_subscription_id"` // e2e_<attempt_id>.
	Status               string `json:"status"`                 // Always active.
	MaxZones             int64  `json:"max_zones"`
	MaxDevices           int64  `json:"max_devices"`
}
```

In `CreateFixtureResponse`, add after `Monitors`:

```go
	Subscription *FixtureSubscription `json:"subscription"` // null when none was requested.
```

Replace the first four lines of `validateFixtureRequest`'s body (the `invalid :=` line through the first `return invalid }`) with:

```go
	invalid := fmt.Errorf("%w: provide 0..4 servers with IP version 4 or 6, exclusive verification states and a supported netspeed, 0..1 monitors with an ipv4 and/or ipv6 entry whose status is pending, testing, active or paused, an optional subscription with max_zones and max_devices of at least 1, and at least one server, monitor or subscription", ErrInvalidRequest)
	if len(req.Servers) > 4 || len(req.Monitors) > 1 || (len(req.Servers)+len(req.Monitors) == 0 && req.Subscription == nil) {
		return invalid
	}
	if sub := req.Subscription; sub != nil && (sub.MaxZones < 1 || sub.MaxDevices < 1) {
		return invalid
	}
```

In `CreateFixture`, after the `for _, spec := range req.Monitors { ... }` loop and before `key, err := apiauth.MakeSessionKey(...)`, add:

```go
		if spec := req.Subscription; spec != nil {
			stripeID := fixtureStripeSubscriptionID(req.AttemptID)
			subscriptionID, err := q.InsertE2EFixtureSubscription(ctx, ntpdb.InsertE2EFixtureSubscriptionParams{
				AccountID:            account.ID,
				StripeSubscriptionID: stripeID,
				Status:               ntpdb.AccountSubscriptionsStatusActive,
				Name:                 fixtureSubscriptionName,
				MaxZones:             spec.MaxZones,
				MaxDevices:           spec.MaxDevices,
			})
			if err != nil {
				return err
			}
			response.Subscription = &FixtureSubscription{
				SubscriptionID:       subscriptionID,
				StripeSubscriptionID: stripeID.String,
				Status:               string(ntpdb.AccountSubscriptionsStatusActive),
				MaxZones:             spec.MaxZones,
				MaxDevices:           spec.MaxDevices,
			}
		}
```

After `fixtureMonitorTLSName` (`:344-348`), add:

```go
// fixtureSubscriptionName is the seeded subscription's plan name, which
// /manage/vendor shows under "Current plan".
const fixtureSubscriptionName = "E2E fixture"

// fixtureStripeSubscriptionID is the seeded subscription's
// stripe_subscription_id. The column's unique index makes it the durable
// record of the row: cleanup finds the row from the attempt ID alone, and
// Stripe's own IDs start with sub_, so it can't collide with one.
func fixtureStripeSubscriptionID(attemptID string) pgtype.Text {
	return pgtype.Text{String: "e2e_" + attemptID, Valid: true}
}
```

Leave `accounts.stripe_customer_id` alone; it stays NULL.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `./scripts/test-integration ./e2efixture TestFixtureIntegration`
Expected: PASS, including the two new subtests.
Run: `go build -o /dev/null ./... && go build -tags e2efixtures -o /dev/null ./...`
Expected: no output.

---

### Task 2 [API]: Subscription cleanup

**Files:**
- Modify: `sql/e2e_fixtures.sql` (append two queries)
- Modify: `e2efixture/fixture.go` (`ErrOwnershipChanged` at `:30-31`, `CleanupFixtureResponse` at `:119-124`, `CleanupFixture` at `:407-496`)
- Test: `e2efixture/fixture_integration_test.go`
- Generated: `ntpdb/e2e_fixtures.sql.go`, `ntpdb/querier.go`, `ntpdb/otel.go`, `ntpdb/mocks.go`

**Interfaces:**
- Consumes: `fixtureStripeSubscriptionID` (Task 1), `FixtureSubscription.SubscriptionID` (Task 1).
- Produces:
  - `CleanupFixtureResponse.DeletedSubscriptions int64` (JSON `deleted_subscriptions`, 0 or 1)
  - `(*ntpdb.Queries).LockE2EFixtureSubscription(ctx, stripeSubscriptionID pgtype.Text) ([]ntpdb.LockE2EFixtureSubscriptionRow, error)`, row `{ID int64; AccountID int64}`
  - `(*ntpdb.Queries).DeleteE2EFixtureSubscription(ctx, ntpdb.DeleteE2EFixtureSubscriptionParams{StripeSubscriptionID pgtype.Text; AccountID int64}) (int64, error)`
  - `ErrOwnershipChanged` message: `fixture server, monitor or subscription ownership changed; cleanup refused`

- [ ] **Step 1: Write the failing tests**

At the end of `t.Run("subscription only attempt", ...)` (Task 1), add:

```go
		cleaned, err := e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.NoError(t, err)
		require.EqualValues(t, 1, cleaned.DeletedSubscriptions)
		require.Zero(t, cleaned.DeletedServers)
		require.Zero(t, cleaned.DeletedMonitors)
		require.Zero(t, count(t, "SELECT count(*) FROM account_subscriptions WHERE id=$1", sub.SubscriptionID))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM accounts WHERE id=$1 AND deletion_on IS NULL", fixture.AccountID))

		again, err := e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.NoError(t, err)
		require.Zero(t, again.DeletedSubscriptions)
```

At the end of `t.Run("subscription and a server in one attempt", ...)`, add:

```go
		cleaned, err := e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.NoError(t, err)
		require.EqualValues(t, 1, cleaned.DeletedServers)
		require.EqualValues(t, 1, cleaned.DeletedSubscriptions)
		require.Zero(t, count(t, "SELECT count(*) FROM account_subscriptions WHERE account_id=$1", fixture.AccountID))
```

In `t.Run("cleanup removes monitors and reports counts", ...)`, after `require.EqualValues(t, 2, cleaned.DeletedMonitors)`, add:

```go
		require.Zero(t, cleaned.DeletedSubscriptions, "an attempt without a seed deletes no subscription")
```

After `t.Run("moved monitor aborts cleanup", ...)`, add:

```go
	t.Run("moved subscription aborts cleanup", func(t *testing.T) {
		id := attempt(t)
		fixture := createRequest(t, e2efixture.CreateFixtureRequest{
			AttemptID:    id,
			Servers:      []spec{{IPVersion: 4, Netspeed: 512}},
			Subscription: &subscriptionSpec{MaxZones: 1, MaxDevices: 10000},
		})
		other := create(t, attempt(t), spec{IPVersion: 6, Netspeed: 512})
		subscriptionID := fixture.Subscription.SubscriptionID
		// Restore this deliberately moved row before registered fixture teardown.
		t.Cleanup(func() {
			_, err := db.Exec(ctx, "UPDATE account_subscriptions SET account_id=$1 WHERE id=$2", fixture.AccountID, subscriptionID)
			require.NoError(t, err)
		})
		_, err := db.Exec(ctx, "UPDATE account_subscriptions SET account_id=$1 WHERE id=$2", other.AccountID, subscriptionID)
		require.NoError(t, err)

		_, err = e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.ErrorIs(t, err, e2efixture.ErrOwnershipChanged)
		require.Equal(t, 1, count(t, "SELECT count(*) FROM account_subscriptions WHERE id=$1 AND account_id=$2", subscriptionID, other.AccountID))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM servers WHERE id=$1", fixture.Servers[0].ServerID))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM e2e_fixtures WHERE attempt_id=$1 AND cleaned_on IS NULL", id))
	})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test-integration ./e2efixture TestFixtureIntegration`
Expected: build failure on `cleaned.DeletedSubscriptions` (no such field).

- [ ] **Step 3: Add the queries**

Append to `sql/e2e_fixtures.sql`:

```sql

-- name: LockE2EFixtureSubscription :many
SELECT id, account_id FROM account_subscriptions
WHERE stripe_subscription_id = sqlc.arg(stripe_subscription_id)
FOR UPDATE;

-- name: DeleteE2EFixtureSubscription :execrows
DELETE FROM account_subscriptions
WHERE stripe_subscription_id = sqlc.arg(stripe_subscription_id)
  AND account_id = sqlc.arg(account_id);
```

`:many` because the unique index allows zero or one row.

- [ ] **Step 4: Generate and check the signatures**

Run: `go tool sqlc generate && go generate ./ntpdb/`
Run: `grep -n "func (q \*Queries) LockE2EFixtureSubscription\|type LockE2EFixtureSubscriptionRow struct\|type DeleteE2EFixtureSubscriptionParams struct" -A3 ntpdb/e2e_fixtures.sql.go`
Expected: the signatures listed under Interfaces. If they differ, use the generated ones and say so in the task report.

- [ ] **Step 5: Implement cleanup in `e2efixture/fixture.go`**

Replace the `ErrOwnershipChanged` lines (`:30-31`) with:

```go
	// ErrOwnershipChanged means a recorded server or monitor, or the seeded
	// subscription, moved to another account.
	ErrOwnershipChanged = errors.New("fixture server, monitor or subscription ownership changed; cleanup refused")
```

In `CleanupFixtureResponse`, add after `DeletedMonitors`:

```go
	DeletedSubscriptions int64 `json:"deleted_subscriptions"` // 0 or 1; zero on repeated cleanup.
```

Replace the `CleanupFixture` doc comment with:

```go
// CleanupFixture uses durable recorded IDs, never account-wide deletion. Row
// locks on the recorded servers and monitors and on the seeded subscription
// prevent ownership changes between check and delete. An unknown attempt
// becomes a tombstone, so a delayed create with that ID fails.
```

In `CleanupFixture`, replace:

```go
		if len(owned) > 4 || len(monitors) > 2 || !fixture.AccountID.Valid {
			return errors.New("invalid fixture registry")
		}
```

with:

```go
		stripeID := fixtureStripeSubscriptionID(req.AttemptID)
		subscriptions, err := q.LockE2EFixtureSubscription(ctx, stripeID)
		if err != nil {
			return err
		}
		if len(owned) > 4 || len(monitors) > 2 || len(subscriptions) > 1 || !fixture.AccountID.Valid {
			return errors.New("invalid fixture registry")
		}
```

After the `for _, monitor := range monitors { ... }` ownership loop, add:

```go
		for _, subscription := range subscriptions {
			if subscription.AccountID != fixture.AccountID.Int64 {
				return ErrOwnershipChanged
			}
		}
```

After the `remainingMonitors` check and before `return q.TombstoneE2EFixture(ctx, id)`, add:

```go
		response.DeletedSubscriptions, err = q.DeleteE2EFixtureSubscription(ctx, ntpdb.DeleteE2EFixtureSubscriptionParams{
			StripeSubscriptionID: stripeID,
			AccountID:            fixture.AccountID.Int64,
		})
		if err != nil {
			return err
		}
		if response.DeletedSubscriptions != int64(len(subscriptions)) {
			return errors.New("fixture subscription delete count mismatched")
		}
```

`fixtureError` already passes `ErrOwnershipChanged` through; no change there.

- [ ] **Step 6: Check nothing else matches the old message**

Run: `grep -rn "server or monitor ownership changed" --include=*.go --include=*.ts /Users/ask/src/go/ntp/api /Users/ask/src/ntppool/e2e/lib /Users/ask/src/ntppool/e2e/tests`
Expected: no output.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `./scripts/test-integration ./e2efixture TestFixtureIntegration`
Expected: PASS.

---

### Task 3 [API]: CLI help, CLI wire format and the vendorzone doc fix

**Files:**
- Modify: `cmd/e2e.go:31,35-36`
- Modify: `cmd/e2e_integration_test.go` (`t.Run("fixture create and cleanup", ...)` at `:106-173`, `t.Run("bad input", ...)` at `:189-208`)
- Modify: `server/api/vendorzone/CLAUDE.md:51-52,80,83,139`

**Interfaces:**
- Consumes: JSON fields from Tasks 1 and 2.
- Produces: the wire format the harness parses: `"subscription":{"subscription_id":"<digits>","stripe_subscription_id":"e2e_<attempt>","status":"active","max_zones":<n>,"max_devices":<n>}` and `"deleted_subscriptions":<n>`.

- [ ] **Step 1: Extend the CLI integration test**

In `t.Run("fixture create and cleanup", ...)`:

Replace the create input string with:

```go
			`{"attempt_id":"`+attempt+`","servers":[{"ip_version":4,"netspeed":512,"pending_verification":true}],"monitors":[{"ipv4":{"status":"active"},"ipv6":{"status":"paused"}}],"subscription":{"max_zones":1,"max_devices":10000}}`,
```

Add to the `created` struct, after `Monitors`:

```go
			Subscription *struct {
				SubscriptionID       string `json:"subscription_id"`
				StripeSubscriptionID string `json:"stripe_subscription_id"`
				Status               string `json:"status"`
				MaxZones             int    `json:"max_zones"`
				MaxDevices           int    `json:"max_devices"`
			} `json:"subscription"`
```

After `require.Equal(t, "paused", created.Monitors[0].IPv6.Status)`, add:

```go
		require.NotNil(t, created.Subscription)
		require.Regexp(t, `^\d+$`, created.Subscription.SubscriptionID)
		require.Equal(t, "e2e_"+attempt, created.Subscription.StripeSubscriptionID)
		require.Equal(t, "active", created.Subscription.Status)
		require.Equal(t, 1, created.Subscription.MaxZones)
		require.Equal(t, 10000, created.Subscription.MaxDevices)
```

Add this field to the `cleaned` struct:

```go
			DeletedSubscriptions int    `json:"deleted_subscriptions"`
```

and after `require.Equal(t, 2, cleaned.DeletedMonitors)` add:

```go
		require.Equal(t, 1, cleaned.DeletedSubscriptions)
```

In `t.Run("bad input", ...)`, add this case to the table (the decoder rejects unknown fields in nested objects too, so a caller can't pick the status):

```go
			{"subscription status", `{"attempt_id":"00000000-0000-4000-8000-000000000000","subscription":{"max_zones":1,"max_devices":10000,"status":"canceled"}}`, []string{"e2e", "fixture", "create"}, "status"},
```

- [ ] **Step 2: Run the CLI tests**

Run: `./scripts/test-integration ./cmd TestE2ECommands`
Expected: PASS (Tasks 1 and 2 are in place, so this checks the wire format rather than failing first).
Run: `go test -tags e2efixtures ./cmd/`
Expected: PASS.

- [ ] **Step 3: Update the CLI help**

In `cmd/e2e.go`, replace line 31 with:

```go
	Fixture e2eFixtureCmd `cmd:"" help:"create or clean up isolated server, monitor and subscription fixtures"`
```

and lines 35-36 with:

```go
	Create  e2eFixtureCreateCmd  `cmd:"" help:"create a fixture user and account with 0 to 4 servers, 0 or 1 monitor and an optional subscription"`
	Cleanup e2eFixtureCleanupCmd `cmd:"" help:"remove a fixture attempt's servers, monitors and subscription"`
```

- [ ] **Step 4: Fix `server/api/vendorzone/CLAUDE.md`**

Replace lines 51-52:

```markdown
- Updates allowed ONLY when status=New
- Once submitted (Pending), users cannot edit
```

with:

```markdown
- Users in the zone's account can edit New, Pending and Rejected zones
- Only vendor_admin users can edit an Approved zone, and nobody can change an
  Approved zone's zone_name ("zone name cannot be changed after approval")
```

Replace `Updates vendor zone fields (ONLY when status=New).` with `Updates vendor zone fields. An Approved zone is vendor_admin only, and its zone_name is locked.`

Replace `**Authorization:** vendor_admin OR (status=New AND user in account)` with `**Authorization:** vendor_admin OR (status is not Approved AND user in account)`

Replace `- Can request, update (when New), and submit zones for their account` with `- Can request, update (unless Approved), and submit zones for their account`

Check the rule against `server/api/vendorzone/update.go:224-234` before saving.

- [ ] **Step 5: Re-run the unit test**

Run: `go test -tags e2efixtures ./cmd/`
Expected: PASS.

---

### Task 4 [API]: Verify, review, commit and push

**Files:** the ten API files from Tasks 1 to 3.

**Interfaces:**
- Produces: one pushed API commit; its first 8 characters name the CI image tag `sha-<8>` used by Task 5.

- [ ] **Step 1: Regenerate and check the file set**

Run: `go tool sqlc generate && go generate ./ntpdb/`
Run: `git status --short`
Expected modified tracked files, exactly:

```
 M cmd/e2e.go
 M cmd/e2e_integration_test.go
 M e2efixture/fixture.go
 M e2efixture/fixture_integration_test.go
 M ntpdb/e2e_fixtures.sql.go
 M ntpdb/mocks.go
 M ntpdb/otel.go
 M ntpdb/querier.go
 M plans/active/perl-model-migration-status.md
 M server/api/vendorzone/CLAUDE.md
 M sql/e2e_fixtures.sql
```

plus the untracked files that were there before (`?? ...`). `plans/active/perl-model-migration-status.md` is unrelated and stays unstaged. Any other modified file: stop and report.

- [ ] **Step 2: Format and whitespace**

Run: `gofumpt -w cmd/e2e.go cmd/e2e_integration_test.go e2efixture/fixture.go e2efixture/fixture_integration_test.go`
Run: `gofumpt -l ntpdb/ e2efixture/ cmd/`
Expected: no output.
Run: `git diff --check -- cmd e2efixture ntpdb server/api/vendorzone/CLAUDE.md sql/e2e_fixtures.sql`
Expected: no output.

- [ ] **Step 3: Full verification**

Run each; all must pass:
- `go build -o /dev/null ./... && go build -tags e2efixtures -o /dev/null ./...`
- `go vet -tags integration,e2efixtures ./...` (compiles every integration test against the regenerated `Querier` and mocks). Issues in files this plan touched must be fixed. Issues only in untouched files: list them in the report and continue.
- `go test ./...`
- `go test -tags e2efixtures ./cmd/`
- `./scripts/test-integration ./e2efixture`
- `./scripts/test-integration ./cmd`

- [ ] **Step 4: Code review**

Invoke the `code-review` skill at high effort on the API working tree. Scope it to `git diff -- cmd e2efixture ntpdb server/api/vendorzone/CLAUDE.md sql/e2e_fixtures.sql` and tell it that `plans/active/perl-model-migration-status.md` is unrelated and must be ignored. Give the reviewer the spec path. Fix correctness findings, then repeat Steps 2 and 3. List findings you didn't act on, with the reason, in the task report.

- [ ] **Step 5: Stage and check**

```bash
git add sql/e2e_fixtures.sql e2efixture/fixture.go e2efixture/fixture_integration_test.go cmd/e2e.go cmd/e2e_integration_test.go server/api/vendorzone/CLAUDE.md ntpdb/e2e_fixtures.sql.go ntpdb/querier.go ntpdb/otel.go ntpdb/mocks.go
git status
git diff --staged --stat
```

Expected: exactly those 10 files staged, `plans/active/perl-model-migration-status.md` still unstaged. Read `git diff --staged` once more. If anything else is staged, stop and report.

- [ ] **Step 6: Commit**

Run `git status` again, then:

```bash
git commit -m "feat(e2e): seed a live subscription in api e2e fixtures" -m "api e2e fixture create accepts an optional subscription with max_zones
and max_devices, and inserts one active account_subscriptions row whose
stripe_subscription_id is e2e_<attempt_id>. Cleanup locks that row,
refuses when it has moved to another account, deletes it and reports
deleted_subscriptions.

Also correct the vendorzone CLAUDE.md edit rules to match update.go."
```

If a hook fails, fix the reported problem, re-stage the same files by name and commit again (no `--no-verify`).

- [ ] **Step 7: Push**

Run: `git log --oneline origin/main..HEAD`
Expected: two commits, `bf777fe fix(monitors): count pending monitors toward account eligibility` and the new one. The push publishes both.
Run: `git push origin main`
Run: `git rev-parse --short=8 HEAD`
Record the 8 characters for Task 5.

---

### Task 5 [ops]: Deploy the API to devel

**Files:** none committed. Local, uncommitted edit to `~/src/flux-ntp/askntp/api/api-config-local.yaml`.

**Interfaces:**
- Consumes: the 8-character commit prefix from Task 4.
- Produces: devel `api-internal` running `ntporg/api-dev:sha-<8>`, with the subscription seed available through `NTP_API_CLI`.

- [ ] **Step 1: Record the current state**

Run: `grep -n "image-tag" ~/src/flux-ntp/askntp/api/api-config-local.yaml`
Run: `kubectl --context dala -n askntp exec deploy/api-internal -c main -- /ko-app/api migrate status`
Record the tag and the latest applied version (expected 29). This change has no migration.

- [ ] **Step 2: Wait for CI**

Use the `abh:woodpecker-logs` skill's commands to find the pipeline for the Task 4 commit and wait until it finishes. Expected: success, including the `docker` step that pushes `harbor.ntppool.org/ntporg/api-dev:sha-<8>`. On failure, fetch the failed step's log with the same skill, then stop and report (no second API commit).

- [ ] **Step 3: Deploy**

Edit `~/src/flux-ntp/askntp/api/api-config-local.yaml`: in the `x-image-tag: &image-tag sha-...` line, replace the tag with `sha-<8>`.
Run: `cd ~/src/flux-ntp/askntp/api && ./update-api`
Expected: the helm upgrade succeeds. Don't commit or push flux-ntp.

- [ ] **Step 4: Verify the rollout**

Run: `kubectl --context dala -n askntp get deploy api-internal -o jsonpath='{.spec.template.spec.containers[0].image}'; echo`
Expected: `harbor.ntppool.org/ntporg/api-dev:sha-<8>`.
Run: `kubectl --context dala -n askntp rollout status deploy/api-internal`
Expected: successfully rolled out.
Run: `kubectl --context dala -n askntp exec deploy/api-internal -c main -- /ko-app/api migrate status`
Expected: the same latest version as Step 1, nothing pending.
Run: `kubectl --context dala -n askntp exec deploy/api-internal -c main -- /ko-app/api e2e fixture --help`
Expected: the help names the subscription ("... server, monitor and subscription fixtures").

- [ ] **Step 5: Smoke check through the harness's CLI path**

This uses `runApiCli`, so `NTP_API_CLI` from `e2e/.env` is split exactly as in tests. It never prints the session token.

```bash
cd /Users/ask/src/ntppool/e2e && node --input-type=module - <<'NODE'
import "dotenv/config";
import { randomUUID } from "node:crypto";
import { runApiCli } from "./lib/apicli.ts";

const cwd = process.cwd();
async function roundTrip(label, seed) {
  const attemptId = randomUUID();
  console.log(`${label}: attempt ${attemptId}`);
  const created = await runApiCli("e2e fixture create", ["e2e", "fixture", "create"], { attempt_id: attemptId, ...seed }, attemptId, cwd);
  const cleaned = await runApiCli("e2e fixture cleanup", ["e2e", "fixture", "cleanup"], { attempt_id: attemptId }, attemptId, cwd);
  console.log(label, JSON.stringify({ subscription: created.subscription, cleaned }));
  return { attemptId, created, cleaned };
}

const seeded = await roundTrip("seeded", { servers: [], monitors: [], subscription: { max_zones: 1, max_devices: 10000 } });
const sub = seeded.created.subscription;
if (!sub || sub.stripe_subscription_id !== `e2e_${seeded.attemptId}` || sub.status !== "active" || !/^\d+$/.test(sub.subscription_id)) {
  throw new Error("seeded create returned an unexpected subscription");
}
if (seeded.cleaned.deleted_subscriptions !== 1) throw new Error("seeded cleanup did not delete the subscription");

const plain = await roundTrip("unseeded", { servers: [{ ip_version: 4, netspeed: 512 }], monitors: [] });
if (plain.created.subscription !== null) throw new Error("unseeded create returned a subscription");
if (plain.cleaned.deleted_servers !== 1 || plain.cleaned.deleted_subscriptions !== 0) throw new Error("unseeded cleanup counts are wrong");
console.log("smoke check passed");
NODE
```

Expected: `smoke check passed`. If create succeeded but the script failed before cleanup, clean the printed attempt with the README's cleanup snippet. If the API misbehaves, stop and report (no second API commit).

---

### Task 6 [ops]: Dev site freshness

**Files:** none.

**Interfaces:**
- Produces: the manage site runs the current `/Users/ask/src/ntppool` tree. Tasks 9 (live step) and 12 need this.

- [ ] **Step 1: Find the pod and compare**

```bash
kubectl --context dala -n askntp get pods -l app=ntppool,tier=frontend -o name
```

Expected: one `pod/...` name. None or several: stop and report.

```bash
kubectl --context dala -n askntp get <pod> -o jsonpath='{.status.containerStatuses[?(@.name=="httpd")].state.running.startedAt}'; echo
kubectl --context dala -n askntp exec <pod> -c httpd -- sh -c 'find /ntppool/lib /ntppool/docs/manage -type f -printf "%T@ %p\n" | sort -n | tail -3'
kubectl --context dala -n askntp exec <pod> -c httpd -- md5sum /ntppool/lib/NTPPool/Control/Vendor.pm /ntppool/docs/manage/tpl/vendor/show.html
md5 -r /Users/ask/src/ntppool/lib/NTPPool/Control/Vendor.pm /Users/ask/src/ntppool/docs/manage/tpl/vendor/show.html
pgrep -fl "devspace dev"
```

Convert `startedAt` with `date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "<startedAt>" +%s`. If the container lacks GNU `find -printf`, use `find /ntppool/lib /ntppool/docs/manage -type f -exec stat -c "%Y %n" {} + | sort -n | tail -3`.

The site is current when all hold: the newest pod file time is older than `startedAt`, the checksums match, and `devspace dev` is running. Otherwise it's stale.

- [ ] **Step 2: Restart when stale**

1. If `pgrep` found a `devspace dev` process, stop it with `pkill -INT -f "devspace dev"` and wait until `pgrep -fl "devspace dev"` prints nothing.
2. Start it from the repo root with the Bash tool's `run_in_background: true`: `cd /Users/ask/src/ntppool && devspace dev`. It builds the image and redeploys, which takes a while.
3. Wait with the Monitor tool (an until-loop, no foreground `sleep`) until both: the httpd container's `startedAt` is later than the restart time, and `curl -sS -o /dev/null -w '%{http_code}' https://manage.askdev.grundclock.com/manage` returns `200` or `302`.
4. Repeat Step 1. Expected: current. If `devspace dev` exits with an error, read its output, then stop and report.

---

### Task 7 [harness]: `RpcError.connectMessage` and `lib/vendor.ts`

**Files:**
- Modify: `e2e/lib/auth.ts:41-50,93-110`
- Create: `e2e/lib/vendor.ts`
- Modify: `e2e/tests/vendor.spec.ts` (remove `NewZoneData`/`freshZoneData`/`createNewZone` at `:32-82` and `loginAsVendorAdmin`/`isVendorAdmin`/`createAndSubmitPendingZone`/`adminOpenZone` at `:456-522`; import them)

**Interfaces:**
- Consumes: `connectRpc`, `loginAs`, `RpcError` (`lib/auth.ts`); `bust`, `errorAlerts`, `expectCleanPage`, `expectNoErrorBleed` (`lib/helpers.ts`); `idField`, `record`, `stringField` (`lib/json.ts`).
- Produces (`e2e/lib/vendor.ts`):
  - `SUBSCRIPTION_REQUIRED`, `UPGRADE_MESSAGE`, `OPEN_SOURCE_JUSTIFICATION` (string constants)
  - `interface NewZoneData { zoneName; organizationName; requestInformation; deviceCount; deviceInformation }` (all `string`)
  - `freshZoneData(prefix: string): NewZoneData`
  - `zonePath(idToken: string, mode?: "edit"): string`
  - `zoneUrlParams(url: string): { idToken: string; accountToken: string }`
  - `createNewZone(page: Page, data: NewZoneData): Promise<string>` (show-page URL)
  - `loginAsVendorAdmin(browser: Browser, email: string): Promise<{ context: BrowserContext; page: Page; sessionToken: string }>`
  - `isVendorAdmin(page: Page): Promise<boolean>`
  - `createAndSubmitPendingZone(page: Page, data: NewZoneData): Promise<string>` (id token)
  - `adminOpenZone(page: Page, idToken: string): Promise<void>`
  - `interface VendorZoneRead { status: string; zoneName: string; deviceCount: string; opensourceRequested: boolean; opensourceInfo?: string; opensourceApproved?: boolean }`
  - `getVendorZone(sessionToken: string, idToken: string): Promise<VendorZoneRead>`
  - `submitVendorZoneApi(sessionToken: string, accountToken: string, idToken: string): Promise<void>`
  - `expectSubmitRefused(sessionToken: string, accountToken: string, idToken: string, who: string): Promise<void>`
  - `approveZone(page: Page, idToken: string, zoneName: string, opts: { grant: boolean }): Promise<void>`
  - `rejectZone(page: Page, idToken: string, zoneName: string): Promise<void>` (the spec sketches both without `zoneName`; it's added so they can check render_admin's "<zone> approved" / "<zone> rejected" message)
  - `type ZoneFields = Partial<NewZoneData>`; `editZone(page: Page, idToken: string, fields: ZoneFields): Promise<void>`
  - `lib/auth.ts`: `RpcError.connectMessage?: string`

- [ ] **Step 1: Record the current test list**

Run (in `/Users/ask/src/ntppool/e2e`): `npx playwright test tests/vendor.spec.ts --list | tail -1`
Expected: `Total: 13 tests in 1 file`. Record the number.

- [ ] **Step 2: Add `connectMessage` to `RpcError`**

In `e2e/lib/auth.ts`, replace the `RpcError` class with:

```ts
export class RpcError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: string,
    // The Connect error JSON's `message`. It stays out of `message`, so it
    // only shows up in a report when a test asserts on it.
    readonly connectMessage?: string,
  ) {
    super(message);
    this.name = "RpcError";
  }
}
```

In `connectRpc`, replace the `if (!resp.ok) { ... }` block with:

```ts
  if (!resp.ok) {
    let code = "unknown";
    let connectMessage: string | undefined;
    try {
      const errorBody = (await resp.json()) as { code?: unknown; message?: unknown };
      if (typeof errorBody.code === "string" && errorBody.code) {
        code = errorBody.code;
      }
      if (typeof errorBody.message === "string") {
        connectMessage = errorBody.message;
      }
    } catch {
      // An HTML/empty error response is still reported by status without
      // attaching the body, which can contain credentials or fixture secrets.
    }
    throw new RpcError(
      `${label} failed${subject && ` for ${subject}`}: ` +
        `${resp.status} ${resp.statusText} (Connect code: ${code})`,
      resp.status,
      code,
      connectMessage,
    );
  }
```

- [ ] **Step 3: Create `e2e/lib/vendor.ts`**

```ts
import { expect, type Browser, type BrowserContext, type Page } from "@playwright/test";
import { connectRpc, loginAs, RpcError } from "./auth";
import { bust, errorAlerts, expectCleanPage, expectNoErrorBleed } from "./helpers";
import { idField, record, stringField } from "./json";

// Vendor zone helpers for tests/vendor.spec.ts and tests/vendor-coverage.spec.ts.
// Routes: lib/NTPPool/Control/Vendor.pm. Templates: docs/manage/tpl/vendor/.
// API: the Go repo's server/api/vendorzone/.
//
// Field names come from form.html and _opensource.html. The new-zone form
// posts to /manage/vendor/zone with a hidden id="new".

/** The Go SubmitVendorZone coverage gate's refusal (submit.go). */
export const SUBSCRIPTION_REQUIRED = "a subscription is required, or apply as open source";

/** show.html's need_upgrade text: a live subscription the zone would exceed. */
export const UPGRADE_MESSAGE = "The current subscription plan doesn't support adding the new DNS zone.";

/** The justification createAndSubmitPendingZone submits. */
export const OPEN_SOURCE_JUSTIFICATION = "Open source NTP client; AGPL-3.0; https://example.com/src ; no revenue.";

export interface NewZoneData {
  zoneName: string;
  organizationName: string;
  requestInformation: string;
  deviceCount: string; // value attribute of a <select> option, e.g. "5000"
  deviceInformation: string;
}

export function freshZoneData(prefix: string): NewZoneData {
  // Zone names are lowercased and stripped to [a-z0-9-] server-side
  // (_edit_zone), so keep the value within that charset for a stable round-trip.
  const rand = Math.random().toString(36).slice(2, 8);
  return {
    zoneName: `${prefix}${rand}`,
    organizationName: "Example Vendor",
    requestInformation: "Embedded appliances polling a few times per hour.",
    deviceCount: "5000",
    deviceInformation: "Example NTP client devices, hourly polling.",
  };
}

/** The zone's show page; mode "edit" opens the edit form when the viewer may edit. */
export function zonePath(idToken: string, mode?: "edit"): string {
  const path = `/manage/vendor/zone?id=${encodeURIComponent(idToken)}`;
  return mode ? `${path}&mode=${mode}` : path;
}

/**
 * The zone and account tokens from the show-page URL createNewZone returns.
 * render_edit redirects with id= and a= (Vendor.pm:475-481).
 */
export function zoneUrlParams(url: string): { idToken: string; accountToken: string } {
  const params = new URL(url).searchParams;
  const idToken = params.get("id");
  const accountToken = params.get("a");
  if (!idToken || !accountToken) {
    throw new Error(`zone URL is missing id= or a=: ${url}`);
  }
  return { idToken, accountToken };
}

// Fill the new-zone request form (/manage/vendor/new) and submit it. Returns
// the show-page URL the create redirects to (carries id= and a= params).
export async function createNewZone(page: Page, data: NewZoneData): Promise<string> {
  await expectCleanPage(page, "/manage/vendor/new");

  // form.html renders the DNS root origin next to the zone-name field as
  // "([name].<origin>)". On this new-zone path it comes straight from
  // get_vendor_zone_form_metadata's dns_roots (Vendor.pm render_form, issue
  // #31 commit 1 removed the NP::Model->dns_root ORM fallback here), so a
  // real domain must render, not a blank/undef.
  await expect(
    page.getByText(/\[name\]\.[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\)/i),
  ).toBeVisible();

  // Real selectors from form.html.
  await page.fill('input[name="zone_name"]', data.zoneName);
  await page.fill('input[name="organization_name"]', data.organizationName);
  await page.fill('textarea[name="request_information"]', data.requestInformation);
  await page.selectOption('select[name="device_count"]', data.deviceCount);
  await page.fill('textarea[name="device_information"]', data.deviceInformation);

  // Submit button value is "Continue →".
  await Promise.all([
    page.waitForURL(/\/manage\/vendor\/zone\?/),
    page.click('form[action="/manage/vendor/zone"] input[type="submit"]'),
  ]);

  await expectNoErrorBleed(page, page.url());
  return page.url();
}

// Mint a vendor-admin session in its own context. Returns the context, a page
// on it and the session token for API calls. The caller closes the context.
export async function loginAsVendorAdmin(
  browser: Browser,
  email: string,
): Promise<{ context: BrowserContext; page: Page; sessionToken: string }> {
  const context = await browser.newContext();
  // grantVendorAdmin sets user_privileges.vendor_admin; grantStaff is included
  // so the session is also support_staff where an admin view expects it.
  const { sessionToken } = await loginAs(context, email, { grantStaff: true, grantVendorAdmin: true });
  const page = await context.newPage();
  return { context, page, sessionToken };
}

// Probe whether the session behind `page` is a working vendor admin: load the
// admin route and check we landed on it rather than being bounced to
// /manage/vendor (render_admin redirects non-admins). Returns true only when the
// admin list page actually rendered.
export async function isVendorAdmin(page: Page): Promise<boolean> {
  const response = await page.goto("/manage/vendor/admin");
  if (!response || response.status() !== 200) {
    return false;
  }
  if (!page.url().includes("/manage/vendor/admin")) {
    return false;
  }
  const heading = page.locator('h3:has-text("Pending zones")');
  return (await heading.count()) > 0;
}

// Create + submit a zone as the owner so it lands in the Pending state, ready for
// admin action. Returns the zone's id_token (parsed from the show-page URL).
export async function createAndSubmitPendingZone(page: Page, data: NewZoneData): Promise<string> {
  const showUrl = await createNewZone(page, data);
  const idToken = new URL(showUrl).searchParams.get("id");
  expect(idToken, "create redirect should carry an id= token").toBeTruthy();

  // Submit via the open-source path (no subscription on a fresh account):
  // _opensource.html posts to /manage/vendor/submit with hidden
  // opensource_request=1 + opensource_info.
  const osForm = page.locator('form[action*="/manage/vendor/submit"]');
  await expect(osForm).toBeVisible();
  await osForm.locator('textarea[name="opensource_info"]').fill(OPEN_SOURCE_JUSTIFICATION);
  await osForm.locator('input[type="submit"]').click();
  await expectNoErrorBleed(page, page.url());
  await expect(page.locator(".alert-danger")).toHaveCount(0);

  return idToken!;
}

// The admin acts on a zone through its show page reached via the admin route:
// /manage/vendor/admin?show=1&id=<token> -> render_zone($id,'show'), which
// renders show.html with the approve/reject form (gated on vendor_admin).
export async function adminOpenZone(page: Page, idToken: string): Promise<void> {
  await page.goto(`/manage/vendor/admin?show=1&id=${encodeURIComponent(idToken)}`);
  await expectNoErrorBleed(page, page.url());
}

export interface VendorZoneRead {
  status: string;
  zoneName: string;
  /** An int64, so the API's JSON sends it as a string. */
  deviceCount: string;
  opensourceRequested: boolean;
  /** Absent when unset. */
  opensourceInfo?: string;
  /** Staff's grant. Absent means undecided. */
  opensourceApproved?: boolean;
}

/**
 * Read a zone through VendorZoneService.GetVendorZone. The UI never shows
 * opensource_approved. Any logged-in user who can see the zone may call it;
 * X-Account is optional here. The API emits default values but omits unset
 * optional fields, so a null fails the checks below.
 */
export async function getVendorZone(sessionToken: string, idToken: string): Promise<VendorZoneRead> {
  const data = record(
    await connectRpc<unknown>(
      "GetVendorZone",
      "ntppool.vendorzone.v1.VendorZoneService/GetVendorZone",
      { Authorization: `Bearer ${sessionToken}` },
      { id_token: idToken },
      idToken,
    ),
    "GetVendorZone response",
  );
  const label = `GetVendorZone ${idToken}`;
  const zone = record(data.zone, `${label} zone`);
  const requested = zone.opensource_requested;
  if (typeof requested !== "boolean") {
    throw new Error(`${label} opensource_requested is missing or malformed`);
  }
  const info = zone.opensource_info;
  if (info !== undefined && typeof info !== "string") {
    throw new Error(`${label} opensource_info is malformed`);
  }
  const approved = zone.opensource_approved;
  if (approved !== undefined && typeof approved !== "boolean") {
    throw new Error(`${label} opensource_approved is malformed`);
  }
  return {
    status: stringField(zone.status, `${label} status`),
    zoneName: stringField(zone.zone_name, `${label} zone_name`),
    deviceCount: idField(zone.device_count, `${label} device_count`),
    opensourceRequested: requested,
    opensourceInfo: info,
    opensourceApproved: approved,
  };
}

/**
 * Call VendorZoneService.SubmitVendorZone directly, as the Perl submit page
 * would. The body is only id_token, so the gate reads the claim already
 * stored on the zone. accountToken goes in X-Account.
 */
export async function submitVendorZoneApi(sessionToken: string, accountToken: string, idToken: string): Promise<void> {
  await connectRpc<unknown>(
    "SubmitVendorZone",
    "ntppool.vendorzone.v1.VendorZoneService/SubmitVendorZone",
    { Authorization: `Bearer ${sessionToken}`, "X-Account": accountToken },
    { id_token: idToken },
    idToken,
  );
}

/** SubmitVendorZone must fail with the coverage gate's failed_precondition. */
export async function expectSubmitRefused(
  sessionToken: string,
  accountToken: string,
  idToken: string,
  who: string,
): Promise<void> {
  let error: unknown;
  try {
    await submitVendorZoneApi(sessionToken, accountToken, idToken);
  } catch (err) {
    error = err;
  }
  expect(error, `SubmitVendorZone as ${who} should fail with an RPC error`).toBeInstanceOf(RpcError);
  const rpc = error as RpcError;
  expect(rpc.code, `SubmitVendorZone as ${who}: Connect code`).toBe("failed_precondition");
  expect(rpc.connectMessage, `SubmitVendorZone as ${who}: Connect message`).toBe(SUBSCRIPTION_REQUIRED);
}

const ADMIN_FORM = 'form[action="/manage/vendor/admin"]';

/**
 * Approve a Pending or Rejected zone on its admin page. `grant` sets the
 * "Grant open-source (non-revenue) plan" checkbox (#opensource_grant), which
 * show.html pre-checks when the zone carries a claim.
 */
export async function approveZone(page: Page, idToken: string, zoneName: string, opts: { grant: boolean }): Promise<void> {
  await adminOpenZone(page, idToken);
  const form = page.locator(ADMIN_FORM);
  await form.locator("#opensource_grant").setChecked(opts.grant);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    form.locator('input[name="status_change"][value="Approve"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(errorAlerts(page), `approving ${zoneName} should not show an error`).toHaveCount(0);
  // render_admin sets msg "<zone> approved" on success.
  await expect(page.locator("body")).toContainText(`${zoneName} approved`);
}

/** Reject a Pending zone on its admin page. Perl always sends opensource_approved=false. */
export async function rejectZone(page: Page, idToken: string, zoneName: string): Promise<void> {
  await adminOpenZone(page, idToken);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    page.locator(ADMIN_FORM).locator('input[name="status_change"][value="Reject"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(errorAlerts(page), `rejecting ${zoneName} should not show an error`).toHaveCount(0);
  await expect(page.locator("body")).toContainText(`${zoneName} rejected`);
}

export type ZoneFields = Partial<NewZoneData>;

/**
 * Open the edit form, change the given fields, save, and wait for the show
 * page. A successful save redirects with mode=show (render_edit); an API error
 * re-renders the form instead, which this helper treats as a failure.
 */
export async function editZone(page: Page, idToken: string, fields: ZoneFields): Promise<void> {
  await expectCleanPage(page, bust(zonePath(idToken, "edit")));
  const form = page.locator('form[action="/manage/vendor/zone"]');
  await expect(form, "the edit form should open").toBeVisible();
  if (fields.zoneName !== undefined) await form.locator('input[name="zone_name"]').fill(fields.zoneName);
  if (fields.organizationName !== undefined) await form.locator('input[name="organization_name"]').fill(fields.organizationName);
  if (fields.requestInformation !== undefined) await form.locator('textarea[name="request_information"]').fill(fields.requestInformation);
  if (fields.deviceCount !== undefined) await form.locator('select[name="device_count"]').selectOption(fields.deviceCount);
  if (fields.deviceInformation !== undefined) await form.locator('textarea[name="device_information"]').fill(fields.deviceInformation);
  await Promise.all([
    page.waitForURL(/[?&]mode=show/),
    form.locator('input[type="submit"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(errorAlerts(page), "the edit should save without an error alert").toHaveCount(0);
}
```

- [ ] **Step 4: Use the module in `e2e/tests/vendor.spec.ts`**

Delete the local `NewZoneData`, `freshZoneData` and `createNewZone` (`:32-82`) and the local `loginAsVendorAdmin`, `isVendorAdmin`, `createAndSubmitPendingZone` and `adminOpenZone` with their comments (`:456-522`). Keep the "MULTI-SESSION APPROACH" and "Privilege note" comment block above them. Replace the imports at the top with:

```ts
import { test, expect } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  bust,
  errorAlerts,
  expectCleanPage,
  expectErrorAlert,
  expectNoErrorBleed,
} from "../lib/helpers";
import {
  adminOpenZone,
  createAndSubmitPendingZone,
  createNewZone,
  freshZoneData,
  isVendorAdmin,
  loginAsVendorAdmin,
  type NewZoneData,
} from "../lib/vendor";
```

Don't change any test body in this task.

- [ ] **Step 5: Verify**

Run (in `/Users/ask/src/ntppool/e2e`): `npm run typecheck`
Expected: no errors.
Run: `npx playwright test tests/vendor.spec.ts --list | tail -1`
Expected: the same total as Step 1.
Run: `npm run test:unit`
Expected: pass.

---

### Task 8 [harness]: Subscription seed in `lib/fixtures.ts`

**Files:**
- Modify: `e2e/lib/fixtures.ts`

**Interfaces:**
- Consumes: the CLI JSON from Tasks 1 to 3 (`subscription`, `deleted_subscriptions`).
- Produces:
  - `interface SubscriptionSeed { maxZones: number; maxDevices: number }`
  - `FixtureSeed.subscription?: SubscriptionSeed`
  - `interface FixtureSubscription { subscriptionId: string; stripeSubscriptionId: string; status: "active"; maxZones: number; maxDevices: number }`
  - `Fixture.subscription: FixtureSubscription | null`

- [ ] **Step 1: Header comment**

Replace the comment block starting `// Isolated fixtures from` (`:8-11`) with:

```ts
// Isolated fixtures from `api e2e fixture create|cleanup` (api-dev build only).
// One attempt owns a fresh user and private account, 0 to 4 servers, at most
// one monitor and at most one subscription, and needs at least one of them.
// Cleanup removes the servers, monitors and subscription and leaves the
// identity behind.
```

- [ ] **Step 2: Seed and result types**

Replace `export interface FixtureSeed { ... }` (`:45-48`) with:

```ts
/** One live subscription on the fixture account (status active). */
export interface SubscriptionSeed {
  maxZones: number;
  maxDevices: number;
}

export interface FixtureSeed {
  servers?: ServerSeed[];
  monitors?: MonitorSeed[];
  subscription?: SubscriptionSeed;
}
```

After `export interface FixtureMonitor { ... }`, add:

```ts
export interface FixtureSubscription {
  subscriptionId: string;
  /** e2e_<attemptId>, which is how cleanup finds the row. */
  stripeSubscriptionId: string;
  status: "active";
  maxZones: number;
  maxDevices: number;
}
```

In `export interface Fixture`, add after `monitors: FixtureMonitor[];`:

```ts
  /** null when the seed had no subscription. */
  subscription: FixtureSubscription | null;
```

- [ ] **Step 3: Normalize and parse**

After `normalizeMonitors`, add:

```ts
function normalizeSubscription(seed: SubscriptionSeed | undefined): SubscriptionSeed | undefined {
  if (seed === undefined) return undefined;
  for (const [name, value] of [["maxZones", seed.maxZones], ["maxDevices", seed.maxDevices]] as const) {
    if (!Number.isInteger(value) || value < 1) {
      throw new Error(`subscription seed ${name} must be an integer of at least 1`);
    }
  }
  return { maxZones: seed.maxZones, maxDevices: seed.maxDevices };
}
```

After `parseMonitor`, add:

```ts
function parseSubscription(value: unknown, attemptId: string, want: SubscriptionSeed | undefined): FixtureSubscription | null {
  const label = "fixture subscription";
  if (!want) {
    if (value !== undefined && value !== null) throw new Error(`${label} was returned but not requested`);
    return null;
  }
  const item = record(value, label);
  if (item.status !== "active") throw new Error(`${label} status is not active`);
  const stripeSubscriptionId = stringField(item.stripe_subscription_id, `${label} stripe_subscription_id`);
  if (stripeSubscriptionId !== `e2e_${attemptId}`) {
    throw new Error(`${label} stripe_subscription_id did not match the attempt`);
  }
  const maxZones = intField(item.max_zones, `${label} max_zones`);
  const maxDevices = intField(item.max_devices, `${label} max_devices`);
  if (maxZones !== want.maxZones || maxDevices !== want.maxDevices) {
    throw new Error(`${label} limits mismatched`);
  }
  return {
    subscriptionId: idField(item.subscription_id, `${label} subscription_id`),
    stripeSubscriptionId,
    status: "active",
    maxZones,
    maxDevices,
  };
}
```

- [ ] **Step 4: Create**

Replace `createFixture` with:

```ts
async function createFixture(attemptId: string, seed: FixtureSeed): Promise<Fixture> {
  const servers = normalizeServers(seed.servers ?? []);
  const monitors = normalizeMonitors(seed.monitors ?? []);
  const subscription = normalizeSubscription(seed.subscription);
  if (servers.length === 0 && monitors.length === 0 && !subscription) {
    throw new Error("fixture needs at least one server, monitor or subscription");
  }

  const request: Record<string, unknown> = {
    attempt_id: attemptId,
    servers: servers.map((server) => ({
      ip_version: server.ipVersion,
      verified: server.verified ?? false,
      pending_verification: server.pendingVerification ?? false,
      scheduled_deletion: server.scheduledDeletion ?? false,
      netspeed: server.netspeed,
    })),
    monitors: monitors.map((monitor) => Object.fromEntries(
      MONITOR_FAMILIES.filter((name) => monitor[name]).map((name) => [name, { status: monitor[name] }]),
    )),
  };
  // Only a seed with a subscription sends the key. The CLI rejects unknown
  // fields, so specs without one keep working against an api-dev image from
  // before the seed.
  if (subscription) {
    request.subscription = { max_zones: subscription.maxZones, max_devices: subscription.maxDevices };
  }

  const raw = record(await runApiCli<unknown>(
    "e2e fixture create",
    ["e2e", "fixture", "create"],
    request,
    attemptId,
  ), "e2e fixture create response");

  if (stringField(raw.attempt_id, "fixture attempt_id") !== attemptId) {
    throw new Error("fixture response attempt_id did not match request");
  }
  if (!Array.isArray(raw.servers) || raw.servers.length !== servers.length) {
    throw new Error("fixture response servers did not preserve request count");
  }
  if (!Array.isArray(raw.monitors) || raw.monitors.length !== monitors.length) {
    throw new Error("fixture response monitors did not preserve request count");
  }
  return {
    attemptId,
    accountToken: stringField(raw.account_token, "fixture account_token"),
    accountId: idField(raw.account_id, "fixture account_id"),
    userId: idField(raw.user_id, "fixture user_id"),
    email: stringField(raw.email, "fixture email"),
    sessionToken: stringField(raw.session_token, "fixture session_token"),
    servers: raw.servers.map((value, index) => parseServer(value, index, servers[index])),
    monitors: raw.monitors.map((value, index) => parseMonitor(value, index, monitors[index])),
    subscription: parseSubscription(raw.subscription, attemptId, subscription),
  };
}
```

- [ ] **Step 5: Cleanup and diagnostics**

Replace `cleanupFixture` with:

```ts
async function cleanupFixture(attemptId: string, seededSubscription: boolean): Promise<void> {
  const raw = record(await runApiCli<unknown>(
    "e2e fixture cleanup",
    ["e2e", "fixture", "cleanup"],
    { attempt_id: attemptId },
    attemptId,
  ), "e2e fixture cleanup response");
  if (stringField(raw.attempt_id, "cleanup attempt_id") !== attemptId) {
    throw new Error("cleanup response attempt_id did not match request");
  }
  intField(raw.deleted_servers, "cleanup deleted_servers");
  intField(raw.deleted_monitors, "cleanup deleted_monitors");
  // Older api-dev images don't send deleted_subscriptions, so only an attempt
  // that seeded a subscription requires it. A repeat cleanup reports 0.
  if (seededSubscription) {
    const deleted = intField(raw.deleted_subscriptions, "cleanup deleted_subscriptions");
    if (deleted > 1) throw new Error("cleanup deleted_subscriptions is more than 1");
  }
}
```

Replace `interface AttemptMetadata { ... }` with:

```ts
interface AttemptMetadata {
  attemptId: string;
  seededSubscription: boolean;
  accountId?: string;
  serverIds?: string[];
  monitorIds?: string[];
  subscriptionId?: string;
  cleanupError?: string;
}
```

In the `fixtures` fixture:
- Replace `const metadata: AttemptMetadata = { attemptId };` with `const metadata: AttemptMetadata = { attemptId, seededSubscription: seed.subscription !== undefined };`
- After the `metadata.monitorIds = ...` statement, add `metadata.subscriptionId = fixture.subscription?.subscriptionId;`
- Replace `await cleanupFixture(attempt.attemptId);` with `await cleanupFixture(attempt.attemptId, attempt.seededSubscription);`
- In `results.push({...})`, add `subscriptionId: attempt.subscriptionId ?? null,` after `monitorIds`.
- In the diagnostics template string, add ` subscription=${failure.seededSubscription ? failure.subscriptionId ?? "unknown" : "none"}` after the `monitors=` part.

- [ ] **Step 6: Verify**

Run (in `/Users/ask/src/ntppool/e2e`): `npm run typecheck && npm run test:unit && npx playwright test --list | tail -1`
Expected: typecheck and unit tests pass; the list total is unchanged from before this task (Task 10 adds the new file).

---

### Task 9 [harness]: `vendor.spec.ts` tests 1 to 7

**Files:**
- Modify: `e2e/tests/vendor.spec.ts`

**Interfaces:**
- Consumes: everything `lib/vendor.ts` produces (Task 7); `loginAs` (returns `{ email, sessionToken }`), `uniqueTestEmail`; `bust`, `errorAlerts`, `expectCleanPage`, `expectErrorAlert`, `expectNoErrorBleed`.
- Produces: tests 1 to 7 with the exact titles listed at the top of this plan.

- [ ] **Step 1: Imports and header**

Replace the `../lib/vendor` import from Task 7 with:

```ts
import {
  adminOpenZone,
  approveZone,
  createAndSubmitPendingZone,
  createNewZone,
  editZone,
  expectSubmitRefused,
  freshZoneData,
  getVendorZone,
  isVendorAdmin,
  loginAsVendorAdmin,
  type NewZoneData,
  OPEN_SOURCE_JUSTIFICATION,
  rejectZone,
  zonePath,
  zoneUrlParams,
} from "../lib/vendor";
```

and change the first import to `import { test, expect, type Page } from "@playwright/test";`.

Replace the header comment, from the line `// Vendor zone flow, regular-user (non-staff) portions only.` through the comment line that ends with the `need_subscription` show.html reference and a closing parenthesis (currently line 30), with:

```ts
// Vendor zone flows for fresh, uncovered vendors, plus the vendor admin block
// at the end of the file. MANUAL_TEST_PLAN.md §5, §5a, §5b, §5c and §5e.
// Vendors with a live subscription are in vendor-coverage.spec.ts.
//
// Routes / templates this exercises (see lib/NTPPool/Control/Vendor.pm):
//   - /manage/vendor          render_zones / redirect to /new when no zones
//   - /manage/vendor/new      render_form  -> tpl/vendor/form.html
//   - POST /manage/vendor/zone render_edit -> request_vendor_zone (status New)
//                              then redirect to the show page
//   - /manage/vendor/zone?id=&mode=edit  render_form(zone) (prefilled)
//   - POST /manage/vendor/submit render_submit -> Pending (open-source path here)
//
// A fresh account has no subscription, so a New or Rejected zone's show page
// renders the open-source form (show.html:91-103). Helpers live in
// lib/vendor.ts.
```

Add after the imports and header:

```ts
const MISSING_PLAN = "Please choose a subscription plan or choose open source below";

// The list page (vendor.html) renders each zone's status plainly, and
// "Complete setup" shows only while a zone is New.
async function expectZoneListedAsNew(page: Page, idToken: string) {
  await expectCleanPage(page, bust("/manage/vendor"));
  const zoneLink = page.locator(`a[href*="id=${idToken}"]`);
  await expect(zoneLink, "the zone should still be listed").toBeVisible();
  await expect(zoneLink, "a still-New zone should offer Complete setup, not View details").toHaveText("Complete setup");
  await expect(
    page.locator("p").filter({ has: zoneLink }).locator("i"),
    "the zone must not have moved to Pending",
  ).toHaveText("New");
}

// Change every field a regular user can write, then check the show page and
// the reopened form. organization_name has its own test, and form.html only
// renders contact_information when the zone already has one, which a regular
// user can't set. The show page formats device_count, so the form's select
// value is checked instead.
async function expectEveryFieldSaves(page: Page, idToken: string, prefix: string) {
  const changed = {
    zoneName: freshZoneData(prefix).zoneName,
    requestInformation: "Edited: set-top boxes polling once a day.",
    deviceCount: "25000",
    deviceInformation: "Edited: vendor firmware 2.x with an SNTP client.",
  };
  await editZone(page, idToken, changed);

  await expect(page.locator("h3").first()).toContainText(changed.zoneName);
  await expect(page.locator("body")).toContainText(changed.requestInformation);
  await expect(page.locator("body")).toContainText(changed.deviceInformation);

  await expectCleanPage(page, bust(zonePath(idToken, "edit")));
  const form = page.locator('form[action="/manage/vendor/zone"]');
  await expect(form.locator('input[name="zone_name"]')).toHaveValue(changed.zoneName);
  await expect(form.locator('textarea[name="request_information"]')).toHaveValue(changed.requestInformation);
  await expect(form.locator('select[name="device_count"]')).toHaveValue(changed.deviceCount);
  await expect(form.locator('textarea[name="device_information"]')).toHaveValue(changed.deviceInformation);
}
```

- [ ] **Step 2: Use `expectZoneListedAsNew` in the empty-justification test**

In `open-source submit with an empty justification is refused and the zone stays New`, replace everything from the comment `// The zone must still be New. Assert it from the list` through the `toHaveText("New");` assertion with:

```ts
  // The zone must still be New.
  await expectZoneListedAsNew(page, zoneToken!);
```

- [ ] **Step 3: Update the stale comment in the uncovered test**

In the comment above `uncovered vendor submit page shows the open-source form, not a plain submit`, replace the paragraph starting `// The harness cannot mint a live subscription:` through `// integration test TestSubmitVendorZone_DoesNotForceOpensource instead.` with:

```ts
// The covered direction of #39 is in vendor-coverage.spec.ts, which seeds a
// live subscription through `api e2e fixture create`, and in the Go
// integration test TestSubmitVendorZone_DoesNotForceOpensource.
```

- [ ] **Step 4: Tests 1 to 3**

Add after the test `edit a New/Pending zone and persist a changed field`:

```ts
// §5a regular user, New.
test("every writable field saves on a New zone", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("vendor-fields-new"));
  const { idToken } = zoneUrlParams(await createNewZone(page, freshZoneData("fn")));
  await expectEveryFieldSaves(page, idToken, "fn");
});

// §5a regular user, Pending (after an open-source submit).
test("every writable field saves on a Pending zone", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("vendor-fields-pending"));
  const idToken = await createAndSubmitPendingZone(page, freshZoneData("fp"));
  await expectEveryFieldSaves(page, idToken, "fp");
});

// §5b: Perl's check is a truthiness test, so "   " reaches the API, whose
// validateOpensourceInfo refuses it before any write. render_submit shows the
// Connect message in the _errors.html alert with a Trace ID.
test("a whitespace-only justification is refused by the API and the zone stays New", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("vendor-os-blank"));
  const { idToken } = zoneUrlParams(await createNewZone(page, freshZoneData("osb")));

  const osForm = page.locator('form[action*="/manage/vendor/submit"]');
  await osForm.locator('textarea[name="opensource_info"]').fill("   ");
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    osForm.locator('input[type="submit"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expectErrorAlert(page, { requireTraceId: true });
  await expect(errorAlerts(page).first()).toContainText(
    "opensource_info must contain non-whitespace characters",
  );

  await expectZoneListedAsNew(page, idToken);
});
```

- [ ] **Step 5: Test 4, after `admin list page loads clean for a vendor admin`**

```ts
  // §5e uncovered without a claim. The normal form hides a plain submit from
  // an uncovered vendor, so the site gate is reached by removing the hidden
  // opensource_request input, and the Go gate by calling SubmitVendorZone.
  test("an uncovered plain submit is refused by the site and by the API", async ({
    page,
    context,
    browser,
  }) => {
    const { sessionToken: ownerSession } = await loginAs(context, uniqueTestEmail("vendor-uncovered-submit"));
    const { idToken, accountToken } = zoneUrlParams(await createNewZone(page, freshZoneData("ups")));

    const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-admin"));
    try {
      test.skip(
        !(await isVendorAdmin(admin.page)),
        "minted session lacks vendor_admin; cannot submit as a vendor admin",
      );

      // Site gate. locator.evaluate runs through CDP, so the page CSP doesn't apply.
      const osForm = page.locator('form[action*="/manage/vendor/submit"]');
      await osForm.locator('input[name="opensource_request"]').evaluate((el) => el.remove());
      await osForm.locator('textarea[name="opensource_info"]').fill("Plain submit without the open-source flag.");
      await Promise.all([
        page.waitForNavigation({ waitUntil: "load" }),
        osForm.locator('input[type="submit"]').click(),
      ]);
      await expectNoErrorBleed(page, page.url());
      await expect(page.locator("div.text-danger").filter({ hasText: MISSING_PLAN })).toBeVisible();
      await expectZoneListedAsNew(page, idToken);

      // Go gate, as the owner and as a vendor admin with their own account.
      await expectSubmitRefused(ownerSession, accountToken, idToken, "the owner");
      await adminOpenZone(admin.page, idToken);
      const adminAccount = await admin.page.locator('form[action="/manage/vendor/admin"] input[name="a"]').inputValue();
      expect(adminAccount, "the vendor admin's own account").not.toBe(accountToken);
      await expectSubmitRefused(admin.sessionToken, adminAccount, idToken, "a vendor admin");

      expect((await getVendorZone(ownerSession, idToken)).status).toBe("New");
    } finally {
      await admin.context.close();
    }
  });
```

- [ ] **Step 6: Test 6, replace the body of `approve/reject status changes and owner resubmit`**

Replace the whole test (comment `// 2 + 3.` through its closing `});`) with:

```ts
  // One zone walks New -> Pending -> Rejected -> Pending -> Approved. §5a
  // Rejected; §5b grant undecided, claim kept after resubmit, Rejected edit,
  // and the checked half of the Grant row.
  test("approve/reject status changes and owner resubmit", async ({
    page,
    context,
    browser,
  }) => {
    test.setTimeout(90_000);
    const { sessionToken: ownerSession } = await loginAs(context, uniqueTestEmail("vendor-owner"));
    const data = freshZoneData("ex");
    const idToken = await createAndSubmitPendingZone(page, data);

    const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-admin"));
    try {
      test.skip(
        !(await isVendorAdmin(admin.page)),
        "minted session lacks vendor_admin; cannot drive approve/reject UI",
      );

      await test.step("the open-source submit records the claim and leaves the grant undecided", async () => {
        const zone = await getVendorZone(ownerSession, idToken);
        expect(zone.status).toBe("Pending");
        expect(zone.opensourceRequested).toBe(true);
        expect(zone.opensourceApproved, "the grant is undecided").toBeUndefined();
      });

      await test.step("Reject records the grant as false", async () => {
        await rejectZone(admin.page, idToken, data.zoneName);
        const zone = await getVendorZone(ownerSession, idToken);
        expect(zone.status).toBe("Rejected");
        expect(zone.opensourceApproved).toBe(false);
      });

      await test.step("the owner edits the Rejected zone", async () => {
        const edited = {
          organizationName: "Example Vendor (rejected edit)",
          requestInformation: "Edited while Rejected: appliances polling hourly.",
        };
        await editZone(page, idToken, edited);
        const body = page.locator("body");
        await expect(body).not.toContainText("opensource_info");
        await expect(body).toContainText(edited.organizationName);
        await expect(body).toContainText(edited.requestInformation);
        await expect(body, "the stored justification still shows").toContainText(OPEN_SOURCE_JUSTIFICATION);
      });

      const resubmitted = "Resubmitted: open source NTP client; BSD-2-Clause; https://example.com/src ; no revenue.";
      await test.step("the owner resubmits with a new justification", async () => {
        await expectCleanPage(page, bust(zonePath(idToken)));
        const form = page.locator('form[action*="/manage/vendor/submit"]');
        await form.locator('textarea[name="opensource_info"]').fill(resubmitted);
        await Promise.all([
          page.waitForNavigation({ waitUntil: "load" }),
          form.locator('input[type="submit"]').click(),
        ]);
        await expectNoErrorBleed(page, page.url());
        await expect(errorAlerts(page)).toHaveCount(0);
        const zone = await getVendorZone(ownerSession, idToken);
        expect(zone.status).toBe("Pending");
        expect(zone.opensourceRequested).toBe(true);
        expect(zone.opensourceInfo).toBe(resubmitted);
        expect(zone.opensourceApproved, "a resubmit resets the grant to undecided").toBeUndefined();
      });

      await test.step("Approve with Grant left checked records the grant", async () => {
        await adminOpenZone(admin.page, idToken);
        await expect(admin.page.locator("#opensource_grant"), "Grant is pre-checked for a zone with a claim").toBeChecked();
        await approveZone(admin.page, idToken, data.zoneName, { grant: true });
        const zone = await getVendorZone(ownerSession, idToken);
        expect(zone.status).toBe("Approved");
        expect(zone.opensourceApproved).toBe(true);
      });
    } finally {
      await admin.context.close();
    }
  });

  // §5b, the unchecked half of the Grant row.
  test("approving with Grant unchecked leaves the zone on the paid path", async ({
    page,
    context,
    browser,
  }) => {
    const { sessionToken: ownerSession } = await loginAs(context, uniqueTestEmail("vendor-nogrant-owner"));
    const data = freshZoneData("ng");
    const idToken = await createAndSubmitPendingZone(page, data);

    const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-admin"));
    try {
      test.skip(
        !(await isVendorAdmin(admin.page)),
        "minted session lacks vendor_admin; cannot approve",
      );
      await approveZone(admin.page, idToken, data.zoneName, { grant: false });
      const zone = await getVendorZone(ownerSession, idToken);
      expect(zone.status).toBe("Approved");
      expect(zone.opensourceApproved).toBe(false);
      expect(zone.opensourceRequested, "the vendor's claim is kept").toBe(true);
    } finally {
      await admin.context.close();
    }
  });
```

(The second test in that block is test 7.)

- [ ] **Step 7: Test 5, replace `vendor admin cannot rename an Approved zone via the API`**

Replace that test and its comment (`// 6. Staff, Approved: changing zone_name is rejected` through its closing `});`) with:

```ts
  // §5a staff, Approved. zone_name is readonly in the form, which is only a
  // browser hint, so the test removes the attribute and submits the real
  // form. UpdateVendorZone refuses the rename (update.go:224-234), and
  // render_edit re-renders the form with the alert instead of redirecting.
  test("renaming an Approved zone shows the API's refusal", async ({
    page,
    context,
    browser,
  }) => {
    await loginAs(context, uniqueTestEmail("vendor-rename-owner"));
    const data = freshZoneData("rn");
    const idToken = await createAndSubmitPendingZone(page, data);

    const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-admin"));
    try {
      test.skip(
        !(await isVendorAdmin(admin.page)),
        "minted session lacks vendor_admin; cannot reach the Approved-rename case",
      );
      await approveZone(admin.page, idToken, data.zoneName, { grant: true });

      await expectCleanPage(admin.page, bust(zonePath(idToken, "edit")));
      const form = admin.page.locator('form[action="/manage/vendor/zone"]');
      const zoneName = form.locator('input[name="zone_name"]');
      await expect(zoneName).toHaveAttribute("readonly", "");
      // locator.evaluate runs through CDP, so the page CSP doesn't apply.
      await zoneName.evaluate((el) => el.removeAttribute("readonly"));
      await zoneName.fill(`${data.zoneName}x`);
      await Promise.all([
        admin.page.waitForNavigation({ waitUntil: "load" }),
        form.locator('input[type="submit"]').click(),
      ]);
      await expectNoErrorBleed(admin.page, admin.page.url());

      expect(new URL(admin.page.url()).search, "a refused edit re-renders the form, not the show page").toBe("");
      await expectErrorAlert(admin.page, { requireTraceId: true });
      await expect(errorAlerts(admin.page).first()).toContainText("zone name cannot be changed after approval");
      const reRendered = admin.page.locator('form[action="/manage/vendor/zone"] input[name="zone_name"]');
      await expect(reRendered, "the form shows the stored name").toHaveValue(data.zoneName);
      await expect(reRendered).toHaveAttribute("readonly", "");

      expect((await getVendorZone(admin.sessionToken, idToken)).zoneName).toBe(data.zoneName);
    } finally {
      await admin.context.close();
    }
  });
```

Leave the other admin block tests as they are. Tests 4, 5 and 7 stay inside the existing `test.describe.serial` block (the spec's decision).

- [ ] **Step 8: Static checks**

Run (in `/Users/ask/src/ntppool/e2e`): `npm run typecheck`
Expected: no errors. If `Page`, `NewZoneData` or another import is unused, remove it.
Run: `npx playwright test tests/vendor.spec.ts --list | tail -1`
Expected: `Total: 18 tests in 1 file`.

- [ ] **Step 9: One live run of the changed tests (after Task 6)**

These tests don't need the new API. Run once to catch selector mistakes before Task 12. Results here don't tick anything.

Run: `npx playwright test tests/vendor.spec.ts --project=manage --retries=0 -g "every writable field|whitespace-only|uncovered plain submit|renaming an Approved zone|approve/reject status changes|Grant unchecked"`
Expected: 7 passed (the serial block's preflight runs first). Fix harness mistakes (selectors, waits) in this task. If the site or API behaves differently from the spec, stop and report with the failing assertion and the Trace ID if one was shown.

---

### Task 10 [harness]: `vendor-coverage.spec.ts` tests 8 to 11

**Files:**
- Create: `e2e/tests/vendor-coverage.spec.ts`

**Interfaces:**
- Consumes: `test`, `expect`, `type Fixture` with `subscription` (Task 8); `approveZone`, `createNewZone`, `expectSubmitRefused`, `freshZoneData`, `getVendorZone`, `isVendorAdmin`, `loginAsVendorAdmin`, `rejectZone`, `UPGRADE_MESSAGE`, `zonePath`, `zoneUrlParams` (Task 7); `installSession`, `uniqueTestEmail` (`lib/auth.ts`).
- Produces: tests 8 to 11 with the exact titles listed at the top of this plan.

- [ ] **Step 1: Create the file**

```ts
import type { Page } from "@playwright/test";
import { installSession, uniqueTestEmail } from "../lib/auth";
import { expect, test, type Fixture } from "../lib/fixtures";
import { bust, errorAlerts, expectCleanPage, expectNoErrorBleed } from "../lib/helpers";
import {
  approveZone,
  createNewZone,
  expectSubmitRefused,
  freshZoneData,
  getVendorZone,
  isVendorAdmin,
  loginAsVendorAdmin,
  rejectZone,
  UPGRADE_MESSAGE,
  zonePath,
  zoneUrlParams,
} from "../lib/vendor";

// Vendor zones for an account with a live subscription. MANUAL_TEST_PLAN.md
// §5 (plan checks), §5b (covered rows) and §5e (coverage gate).
//
// Each test seeds a subscription-only fixture through `api e2e fixture
// create` (status active, plan name "E2E fixture") and logs in as its owner.
// The fixture user has one account, so pages without a= use it.
//
// Both gates read the zone's account (Go subscription.AccountCoverage): a live
// subscription covers a zone while the account's Approved zone count is below
// max_zones and its Approved devices plus the zone's device_count stay within
// max_devices. Only Approved zones count.
//
// show.html gives a covered New or Rejected zone one plain "Submit for
// production" / "Resubmit for production" button (:91-99), and an over-limit
// New zone the upgrade message with no submit control (:133-148). Perl
// refuses before calling the API, so the Go gate is checked with a direct
// SubmitVendorZone call.
//
// vendor.spec.ts's vendor_admin preflight doesn't run for this file, so the
// admin steps fail, rather than skip, when a minted vendor admin can't reach
// /manage/vendor/admin.

// Traces would hold the fixture's and the vendor admin's session cookies.
test.use({ trace: "off" });

// A fixture create, an admin mint and many page loads don't fit in 30 s.
test.describe.configure({ timeout: 90_000 });

const VENDOR_ADMIN_REQUIRED =
  "a freshly minted vendor_admin session could not reach /manage/vendor/admin; " +
  "the api-dev binary must honor the grant_vendor_admin flag of `api e2e session`";

const SUBMIT_CONTROL = /Submit for production|Resubmit for production/;

/**
 * Submit with the covered vendor's plain button on the zone's show page,
 * which `page` must already show, and check the confirmation. `button` is
 * anchored because "Resubmit for production" contains "submit for production".
 */
async function plainSubmit(page: Page, zoneName: string, button: RegExp) {
  await expect(page.getByRole("button", { name: SUBMIT_CONTROL }), "one plain submit control").toHaveCount(1);
  await expect(page.locator('textarea[name="opensource_info"]'), "no open-source justification form").toHaveCount(0);
  await expect(page.locator('input[name="opensource_request"]'), "no opensource_request field").toHaveCount(0);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    page.getByRole("button", { name: button }).click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(errorAlerts(page)).toHaveCount(0);
  // submitted.html names the zone. The ticket paragraph renders only for an
  // uncovered vendor.
  await expect(page.getByRole("heading", { name: "Vendor Zone Application Submitted" })).toBeVisible();
  await expect(page.locator(".block tt")).toHaveText(zoneName);
  await expect(page.locator("body")).not.toContainText("You'll get an email shortly with a ticket number");
}

/**
 * A covered New zone over its plan limits: the show page has the upgrade
 * message and no submit control, a crafted POST to /manage/vendor/submit gets
 * the upgrade message again, and the Go gate refuses SubmitVendorZone.
 */
async function expectOverLimitRefusal(page: Page, fixture: Fixture, idToken: string) {
  await expectCleanPage(page, bust(zonePath(idToken)));
  await expect(page.getByText(UPGRADE_MESSAGE)).toBeVisible();
  await expect(page.getByRole("button", { name: SUBMIT_CONTROL })).toHaveCount(0);
  await expect(page.locator('form[action*="/manage/vendor/submit"]')).toHaveCount(0);
  await expect(page.locator('textarea[name="opensource_info"]')).toHaveCount(0);

  // The show page has no submit form, and the only other form with an
  // auth_token is the sidebar's "New account" form (a=new), so take id, a and
  // auth_token from the edit form (form.html:15-17).
  await expectCleanPage(page, bust(zonePath(idToken, "edit")));
  const form = page.locator('form[action="/manage/vendor/zone"]');
  const post = await page.request.post("/manage/vendor/submit", {
    form: {
      id: await form.locator('input[name="id"]').inputValue(),
      a: await form.locator('input[name="a"]').inputValue(),
      auth_token: await form.locator('input[name="auth_token"]').inputValue(),
    },
  });
  expect(post.status(), "the crafted submit POST").toBe(200);
  expect(await post.text(), "the crafted submit gets the upgrade message again").toContain(UPGRADE_MESSAGE);

  await expectSubmitRefused(fixture.sessionToken, fixture.accountToken, idToken, "the owner");
  expect((await getVendorZone(fixture.sessionToken, idToken)).status).toBe("New");
}

// §5 subscription row, §5b covered rows, §5e covered.
test("a covered vendor gets a plain submit and stays off the open-source path", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ subscription: { maxZones: 1, maxDevices: 10000 } });
  await installSession(context, fixture.sessionToken);
  const data = freshZoneData("cv"); // 5,000 devices
  const { idToken } = zoneUrlParams(await createNewZone(page, data));

  await plainSubmit(page, data.zoneName, /^Submit for production/);

  await expectCleanPage(page, bust("/manage/vendor"));
  const zoneLink = page.locator(`a[href*="id=${idToken}"]`);
  await expect(page.locator("p").filter({ has: zoneLink }).locator("i"), "a covered Pending zone").toHaveText("Processing");
  await expect(page.getByRole("heading", { name: "Current plan" })).toBeVisible();
  // billing.html: one <div class="col"> per live subscription, with the plan
  // name in <b> and the limits in <ul class="product-details">.
  const plan = page.locator("div.col").filter({ has: page.locator(".product-details") });
  await expect(plan.locator("b")).toHaveText("E2E fixture");
  await expect(plan.locator(".product-details li")).toHaveText(["Up to 1 DNS zones", "Up to 10,000 client devices"]);

  // Blank until a product is chosen, but it must load.
  await expectCleanPage(page, bust("/manage/vendor/plan"));

  await expectCleanPage(page, bust(zonePath(idToken)));
  await expect(page.locator("body")).not.toContainText("Open Source information");

  const zone = await getVendorZone(fixture.sessionToken, idToken);
  expect(zone.status).toBe("Pending");
  expect(zone.opensourceRequested).toBe(false);
  expect(zone.opensourceApproved, "the grant is undecided").toBeUndefined();
});

// §5e over-limit, device limit.
test("a covered vendor over the device limit is refused by the site and by the API", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ subscription: { maxZones: 1, maxDevices: 5000 } });
  await installSession(context, fixture.sessionToken);
  const { idToken } = zoneUrlParams(await createNewZone(page, { ...freshZoneData("od"), deviceCount: "10000" }));

  await expectOverLimitRefusal(page, fixture, idToken);
});

// §5e over-limit, zone limit. max_devices is large, so only the zone count can
// refuse. Pending zones don't count toward max_zones, so zone A is approved
// first.
test("a covered vendor at the zone limit is refused by the site and by the API", async ({
  page,
  context,
  browser,
  fixtures,
}) => {
  const fixture = await fixtures.create({ subscription: { maxZones: 1, maxDevices: 100000 } });
  await installSession(context, fixture.sessionToken);

  const first = freshZoneData("zla");
  const { idToken: firstToken } = zoneUrlParams(await createNewZone(page, first));
  await plainSubmit(page, first.zoneName, /^Submit for production/);

  const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-coverage-admin"));
  try {
    expect(await isVendorAdmin(admin.page), VENDOR_ADMIN_REQUIRED).toBe(true);
    await approveZone(admin.page, firstToken, first.zoneName, { grant: false });
  } finally {
    await admin.context.close();
  }
  expect((await getVendorZone(fixture.sessionToken, firstToken)).status).toBe("Approved");

  const second = freshZoneData("zlb");
  const { idToken: secondToken } = zoneUrlParams(await createNewZone(page, second));
  await expectOverLimitRefusal(page, fixture, secondToken);
});

// §5e vendor admin, §5b covered resubmit of a Rejected zone.
test("a vendor admin submits for a covered account, and the owner resubmits after a rejection", async ({
  page,
  context,
  browser,
  fixtures,
}) => {
  const fixture = await fixtures.create({ subscription: { maxZones: 1, maxDevices: 10000 } });
  await installSession(context, fixture.sessionToken);
  const data = freshZoneData("as");
  const { idToken } = zoneUrlParams(await createNewZone(page, data));

  const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-coverage-admin"));
  try {
    expect(await isVendorAdmin(admin.page), VENDOR_ADMIN_REQUIRED).toBe(true);

    // The admin's own account has no subscription, and this form posts it as
    // a (show.html:96). The submit only works if both layers read coverage
    // from the zone's account.
    await expectCleanPage(admin.page, bust(zonePath(idToken)));
    const adminAccount = await admin.page.locator('form[action="/manage/vendor/submit"] input[name="a"]').inputValue();
    expect(adminAccount, "the admin submits with their own account").not.toBe(fixture.accountToken);
    await plainSubmit(admin.page, data.zoneName, /^Submit for production/);

    const zone = await getVendorZone(fixture.sessionToken, idToken);
    expect(zone.status).toBe("Pending");
    expect(zone.opensourceRequested).toBe(false);
    expect(zone.opensourceApproved).toBeUndefined();

    await rejectZone(admin.page, idToken, data.zoneName);
  } finally {
    await admin.context.close();
  }

  // need_subscription is only set for New zones, so a covered Rejected zone
  // gets a plain resubmit and no open-source form.
  await expectCleanPage(page, bust(zonePath(idToken)));
  await plainSubmit(page, data.zoneName, /^Resubmit for production/);
  expect((await getVendorZone(fixture.sessionToken, idToken)).status).toBe("Pending");
});
```

- [ ] **Step 2: Static checks**

Run (in `/Users/ask/src/ntppool/e2e`): `npm run typecheck`
Expected: no errors.
Run: `npx playwright test tests/vendor-coverage.spec.ts --list | tail -1`
Expected: `Total: 4 tests in 1 file`.

These tests need the deployed seed; the live run is Task 12.

---

### Task 11 [harness]: `MANUAL_TEST_PLAN.md` and `e2e/README.md`

**Files:**
- Modify: `MANUAL_TEST_PLAN.md` (§5 to §5e, lines ~175-282)
- Modify: `e2e/README.md`

**Interfaces:**
- Consumes: the test titles at the top of this plan. If Task 9 or 10 changed a title, use the changed one.
- Produces: rows marked `**Implemented; live-unverified:**` that Task 12 ticks.

- [ ] **Step 1: §5 intro and plan row**

Replace the §5 blockquote (the seven `>` lines right under `## 5. Vendor zones (migrated to CAPI)`) with:

```markdown
> `e2e/tests/vendor.spec.ts` covers fresh, uncovered vendors and vendor
> admins, including the issue #31 ORM-removal surface: `dns_root_origin`
> display on both the new-zone and edit forms (Vendor.pm render_form), and
> `id_token`-based edit/create routing (form.html + `_get_id`).
> `e2e/tests/vendor-coverage.spec.ts` covers vendors with a live subscription,
> which `api e2e fixture create` seeds. Together they cover §5a, §5b and §5e.
> §5c's admin failure row and §5d need a failure-injection hook in a network
> handler, which the E2E fixture rule forbids, so they stay manual; the admin
> invalid-transition test asserts a safe no-op, which isn't evidence of error
> rendering. Design:
> `docs/superpowers/specs/2026-09-14-vendor-zone-e2e-coverage-design.md`.
```

Replace `- [ ] Subscription/plan checks on vendor pages still work (no redundant account fetch errors).` with:

```markdown
- [ ] **Implemented; live-unverified:** Subscription/plan checks on vendor pages still work (no redundant account fetch errors). `/manage/vendor/plan` is blank until a product is chosen; the subscription shows on `/manage/vendor` as "Current plan" with its limits, and a Pending zone reads "Processing". (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor gets a plain submit and stays off the open-source path")
```

- [ ] **Step 2: §5a rows**

Replace each row as follows (old → new):

`- [ ] Regular user, **New**: repeat the edit/save assertion for every other writable field.` →

```markdown
- [ ] **Implemented; live-unverified:** Regular user, **New**: repeat the edit/save assertion for every other writable field (`zone_name`, `request_information`, `device_count`, `device_information`; a regular user never sees `contact_information`). (`e2e/tests/vendor.spec.ts` → "every writable field saves on a New zone")
```

`- [ ] Regular user, **Pending**: repeat the edit/save assertion for every other writable field.` →

```markdown
- [ ] **Implemented; live-unverified:** Regular user, **Pending**: repeat the edit/save assertion for every other writable field. (`e2e/tests/vendor.spec.ts` → "every writable field saves on a Pending zone")
```

`- [ ] Regular user, **Rejected**: edit fields before resubmitting.` →

```markdown
- [ ] **Implemented; live-unverified:** Regular user, **Rejected**: edit fields before resubmitting. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
```

The row starting `- [ ] Staff, **Approved**: attempting to change` →

```markdown
- [ ] **Implemented; live-unverified:** Staff, **Approved**: attempting to change `zone_name` is explicitly rejected by the API (name locked once live): the form re-renders with "zone name cannot be changed after approval" and a Trace ID, and the stored name is unchanged. (`e2e/tests/vendor.spec.ts` → "renaming an Approved zone shows the API's refusal")
```

- [ ] **Step 3: §5b**

Replace the "Known gap" paragraph (the `>` blank line before it plus the four lines from `> Known gap: a **whitespace-only** justification` through `> there. Not covered by a test, because a test for it could only fail today.`) with:

```markdown
>
> A covered submit sends an empty justification, so it clears one stored by an
> earlier open-source submit: a Rejected open-source zone resubmitted with a
> subscription loses its claim and its justification. That's current
> behavior; whether it's intended is still to be decided, so no test pins it.
```

Rows (old → new):

The row starting `- [ ] **Covered** vendor (live subscription): a New/Rejected zone shows a plain` →

```markdown
- [ ] **Implemented; live-unverified:** **Covered** vendor (live subscription): a New/Rejected zone shows a plain "Submit for production" / "Resubmit for production" button — **no** open-source justification form, no `opensource_request` field in the posted form. (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor gets a plain submit and stays off the open-source path" and "a vendor admin submits for a covered account, and the owner resubmits after a rejection")
```

`- [ ] Submitting as a covered vendor leaves the zone's open-source claim **and** grant untouched (the zone page shows no open-source justification text).` →

```markdown
- [ ] **Implemented; live-unverified:** Submitting as a covered vendor leaves the open-source claim false **and** the grant undecided (the zone page shows no open-source justification text). (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor gets a plain submit and stays off the open-source path")
```

`- [ ] Confirm separately that the staff open-source grant remains undecided after the vendor submits its claim.` →

```markdown
- [ ] **Implemented; live-unverified:** Confirm separately that the staff open-source grant remains undecided after the vendor submits its claim. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
```

After the `[x]` row for the **empty** justification, insert:

```markdown
- [ ] **Implemented; live-unverified:** Submitting the open-source form with a **whitespace-only** justification is refused by the API with "opensource_info must contain non-whitespace characters" and a Trace ID, and the zone stays New. (`e2e/tests/vendor.spec.ts` → "a whitespace-only justification is refused by the API and the zone stays New")
```

`- [ ] Confirm the open-source claim and justification remain applied after that Rejected-to-Pending resubmit.` →

```markdown
- [ ] **Implemented; live-unverified:** Confirm the open-source claim and justification remain applied after that Rejected-to-Pending resubmit (the new justification is stored and the grant resets to undecided). (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
```

`- [ ] Repeat the open-source edit assertion while the zone is **Rejected**.` →

```markdown
- [ ] **Implemented; live-unverified:** Repeat the open-source edit assertion while the zone is **Rejected**. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
```

The last §5b row (it starts `- [ ] As` and mentions **Grant open-source**) →

```markdown
- [ ] **Implemented; live-unverified:** As `vendor_admin`, approving with **Grant open-source** checked sets the grant; approving without it leaves the zone on the paid path regardless of the vendor's claim. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit" and "approving with Grant unchecked leaves the zone on the paid path")
```

- [ ] **Step 4: §5c and §5d**

Replace the row `- [ ] Same on the admin approve/reject path — failures show the alert + Trace ID rather than a silent no-op.` with:

```markdown
- [ ] Same on the admin approve/reject path — failures show the alert + Trace ID rather than a silent no-op. Stays manual: making the status RPC fail needs a failure-injection hook in a network handler, which the E2E fixture rule forbids.
```

In the §5d blockquote, after its last line (the one ending the "Decorative:" sentence with `render_subscription` and a period), add:

```markdown
>
> These rows stay manual: forcing a read to fail needs a failure-injection
> hook in a network handler, which the E2E fixture rule forbids.
```

- [ ] **Step 5: §5e**

In the §5e blockquote, after the line ending `Go API; the Go integration tests already cover the four cases below.`, add:

```markdown
>
> E2E checks both layers: the Perl gate in the browser, and the Go gate through
> a direct `SubmitVendorZone` call.
```

Replace the five §5e rows with:

```markdown
- [ ] **Implemented; live-unverified:** **Covered** vendor (live subscription within limits): plain production submit succeeds → Pending. (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor gets a plain submit and stays off the open-source path")
- [ ] **Implemented; live-unverified:** **Uncovered** vendor **with** an open-source claim + justification: submit still succeeds → Pending (open-source path is allowed through the gate). (`e2e/tests/vendor.spec.ts` → "open-source submit retains justification and edits without error")
- [ ] **Implemented; live-unverified:** **Uncovered** vendor **without** an open-source claim: submit is rejected with `a subscription is required, or apply as open source` (reachable via the resubmit path or a direct/admin submit, since the normal form hides the plain-submit button for uncovered vendors). (`e2e/tests/vendor.spec.ts` → "an uncovered plain submit is refused by the site and by the API")
- [ ] **Implemented; live-unverified:** **Over-limit** vendor (has a subscription but exceeds zone/device limits), no open-source claim: submit is rejected with the same message (a distinct OVER_LIMIT wording is a Phase 2 decision, not a bug). (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor over the device limit is refused by the site and by the API" and "a covered vendor at the zone limit is refused by the site and by the API")
- [ ] **Implemented; live-unverified:** `vendor_admin` submitting on another account's behalf is gated on **that account's** coverage, not the admin's own. (`e2e/tests/vendor-coverage.spec.ts` → "a vendor admin submits for a covered account, and the owner resubmits after a rejection")
```

- [ ] **Step 6: `e2e/README.md`**

Replace:

```
The verification, deletion, netspeed, scores-context, staff-search,
staff-server-edit and monitor-badges specs use `api e2e fixture create` and
`api e2e fixture cleanup`. A command failure is a setup failure; the tests
don't skip.
```

with:

```
The verification, deletion, netspeed, scores-context, staff-search,
staff-server-edit, monitor-badges and vendor-coverage specs use
`api e2e fixture create` and `api e2e fixture cleanup`. A command failure is a
setup failure; the tests don't skip.
```

Replace:

```
Each create call owns a fresh ordinary user, a private account, zero to four
servers and at most one monitor, and needs at least one server or monitor.
```

with:

```
Each create call owns a fresh ordinary user, a private account, zero to four
servers, at most one monitor and at most one subscription, and needs at least
one of them.
```

Before the paragraph starting `Cleanup uses the attempt ID recorded before create.`, add:

```
A subscription seed adds one `account_subscriptions` row to the fixture
account: status `active`, name `E2E fixture`, the requested `max_zones` and
`max_devices`, and `stripe_subscription_id` `e2e_<attempt_id>`. The account's
`stripe_customer_id` stays empty. The harness sends the `subscription` key
only for a seed that has one, because an api-dev image from before the seed
rejects unknown fields; deploy an image with the seed before running
`vendor-coverage.spec.ts`. Neither the account nor the user deletion task
removes subscription rows, and the row's account foreign key doesn't cascade,
so don't combine the seed with account or user deletion flows.

```

Replace:

```
Cleanup uses the attempt ID recorded before create. It deletes only the
fixture's recorded server and monitor IDs and the servers' related rows,
clears any scheduled deletion with the server rows, and leaves the generated
user/account plus the fixture tombstone as inert identities. It refuses, and
leaves the attempt uncleaned, when a recorded server or monitor has moved to
another account or a fixture monitor has score, log-score or API-key rows.
```

with:

```
Cleanup uses the attempt ID recorded before create. It deletes only the
fixture's recorded server and monitor IDs and the servers' related rows,
clears any scheduled deletion with the server rows, deletes the subscription
row whose `stripe_subscription_id` is `e2e_<attempt_id>`, and leaves the
generated user/account plus the fixture tombstone as inert identities. It
never deletes subscriptions by account. It refuses, and leaves the attempt
uncleaned, when a recorded server or monitor or the seeded subscription has
moved to another account, or a fixture monitor has score, log-score or
API-key rows.
```

In the cleanup script, replace the `console.log(...)` line with:

```js
console.log(`cleaned ${attemptId}; deleted_servers=${result.deleted_servers} deleted_monitors=${result.deleted_monitors} deleted_subscriptions=${result.deleted_subscriptions}`);
```

In the acceptance block under `## Run`, on both lines that contain `tests/monitor-badges.spec.ts --project=manage --retries=0`, insert ` tests/vendor-coverage.spec.ts` before ` --project=manage`.

In `## Coverage`, replace `` `vendor` (§5 + §5a staff/admin), `` with `` `vendor` (§5, §5a, §5b, §5c, §5e), `vendor-coverage` (§5, §5b, §5e), `` and rewrap that paragraph so no line passes 80 columns.

- [ ] **Step 7: Whitespace**

Run (in `/Users/ask/src/ntppool`): `git diff --check -- MANUAL_TEST_PLAN.md e2e/README.md`
Expected: no output.

---

### Task 12 [ops]: Devel E2E runs and ticks

**Files:**
- Modify: `MANUAL_TEST_PLAN.md` (ticks only)
- Possibly modify: harness files from Tasks 7 to 10 (harness fixes only)

**Interfaces:**
- Consumes: Tasks 5, 6, 9, 10, 11.
- Produces: two run logs in `e2e/test-logs/` (gitignored) and ticked rows.

- [ ] **Step 1: Preconditions**

Repeat Task 6 Step 1. Expected: current; if not, do Task 6 Step 2 first.
Run (in `/Users/ask/src/ntppool/e2e`): `npm run typecheck && npm run test:unit && npx playwright test --list | tail -1`
Expected: pass; the total includes 18 tests in `vendor.spec.ts` and 4 in `vendor-coverage.spec.ts`.

- [ ] **Step 2: Run 1**

```bash
cd /Users/ask/src/ntppool/e2e && mkdir -p test-logs && npx playwright test tests/vendor.spec.ts tests/vendor-coverage.spec.ts --project=manage --retries=0 --reporter=list > test-logs/vendor-run-1.log 2>&1; tail -30 test-logs/vendor-run-1.log
```

- [ ] **Step 3: Run 2**

```bash
cd /Users/ask/src/ntppool/e2e && npx playwright test tests/vendor.spec.ts tests/vendor-coverage.spec.ts --project=manage --retries=0 --reporter=list > test-logs/vendor-run-2.log 2>&1; tail -30 test-logs/vendor-run-2.log
```

- [ ] **Step 4: Triage**

For each failed, skipped or did-not-run test in either log:
- Harness mistake (selector, wait, parsing): fix it in the harness file, re-run Task 9 Step 8 or Task 10 Step 3, then repeat Steps 2 and 3 in full. Only a pair of clean runs after the last change counts.
- `Fixture cleanup failed`: read the `fixture-cleanup-failures` attachment, clean the attempt with the README cleanup script, and report it.
- The API behaves differently from the spec: stop and report the test, the assertion and any Trace ID. Don't make a second API commit.
- The Perl site behaves differently from the spec (for example the `Up to 10,000 client devices` separator, which the spec flags as unchecked outside devel): stop and report with the page text. Don't change Perl in this plan.

Record for each run: passed, failed, skipped, did not run, and teardown failures.

- [ ] **Step 5: Leftover check (read-only)**

```bash
kubectl --context dala -n askntp exec -i pg-1 -c postgres -- psql -d askntp -v ON_ERROR_STOP=1 <<'SQL'
BEGIN READ ONLY;
SELECT count(*) AS uncleaned FROM e2e_fixtures WHERE cleaned_on IS NULL;
SELECT count(*) AS fixture_subscriptions FROM account_subscriptions WHERE stripe_subscription_id LIKE 'e2e\_%';
ROLLBACK;
SQL
```

Expected: both 0. Otherwise list them in the report.

- [ ] **Step 6: Tick rows**

Only §5 to §5e rows are in scope. A row is ticked only when every test it names passed in both runs. For those rows, replace `- [ ] **Implemented; live-unverified:** ` with `- [x] `. Leave the other rows as they are, and name them in the report. The §5e "uncovered with a claim" row names an existing test; tick it under the same rule. The over-limit row needs both test 9 and test 10.

Run: `git diff --check -- MANUAL_TEST_PLAN.md`
Expected: no output.

---

### Task 13 [ops]: ntppool commit

**Files:** the ntppool files from Tasks 7 to 12, the spec and this plan.

- [ ] **Step 1: Check the file set**

Run (in `/Users/ask/src/ntppool`): `git status --short -- docs/superpowers/specs/2026-09-14-vendor-zone-e2e-coverage-design.md docs/superpowers/plans/2026-09-14-vendor-zone-e2e-coverage.md e2e MANUAL_TEST_PLAN.md`
Expected, and nothing else under `e2e/` except gitignored output:

```
 M MANUAL_TEST_PLAN.md
 M docs/superpowers/specs/2026-09-14-vendor-zone-e2e-coverage-design.md
 M e2e/README.md
 M e2e/lib/auth.ts
 M e2e/lib/fixtures.ts
 M e2e/tests/vendor.spec.ts
?? docs/superpowers/plans/2026-09-14-vendor-zone-e2e-coverage.md
?? e2e/lib/vendor.ts
?? e2e/tests/vendor-coverage.spec.ts
```

Run: `git diff --staged --stat`
Expected: empty (nothing staged yet). If something is already staged, stop and ask.

- [ ] **Step 2: Whitespace**

Run: `git diff --check -- MANUAL_TEST_PLAN.md docs/superpowers/specs/2026-09-14-vendor-zone-e2e-coverage-design.md e2e/README.md e2e/lib/auth.ts e2e/lib/fixtures.ts e2e/tests/vendor.spec.ts`
Run: `grep -n "[[:space:]]$" docs/superpowers/plans/2026-09-14-vendor-zone-e2e-coverage.md e2e/lib/vendor.ts e2e/tests/vendor-coverage.spec.ts`
Expected: no output from either.

- [ ] **Step 3: Stage and check**

```bash
git add MANUAL_TEST_PLAN.md docs/superpowers/specs/2026-09-14-vendor-zone-e2e-coverage-design.md docs/superpowers/plans/2026-09-14-vendor-zone-e2e-coverage.md e2e/README.md e2e/lib/auth.ts e2e/lib/fixtures.ts e2e/lib/vendor.ts e2e/tests/vendor.spec.ts e2e/tests/vendor-coverage.spec.ts
git status
git diff --staged --stat
```

Expected: exactly those 9 files staged. Read `git diff --staged`. Anything else staged: stop and ask.

- [ ] **Step 4: Commit**

Run `git status` again, then:

```bash
git commit -m "test(e2e): cover vendor zone coverage gates and editability" -m "Add a subscription seed to the fixture harness and vendor-coverage.spec.ts,
which checks the covered submit, the device and zone limits, and a vendor
admin submitting for a covered account, in both the Perl and the Go gate.

Extend vendor.spec.ts with the remaining editability rows, the whitespace
justification refusal, the uncovered plain submit refusal and the grant
checks, and move the shared vendor helpers to lib/vendor.ts."
```

If a hook fails, fix the problem, re-stage the same files by name and commit again. Don't push.
