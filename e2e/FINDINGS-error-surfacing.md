# E2E findings: gaps that need Go API changes

Two harness goals can't be met test-side because they require small,
test-only additions to the Go API (`../go/ntp/api`). The e2e suite runs against
the **deployed** dev API, so any such addition is only exercised after it ships
to dev — and should be gated behind a capability probe (like the existing
`isVendorAdmin()` skip) so the suite stays green before the deploy lands.

**Rule (2026-09-13):** test-only setup goes in `api e2e` subcommands in the
api-dev build, never in handlers reachable over the network. See
`docs/superpowers/specs/2026-09-13-e2e-fixtures-cli-design.md`. The invite
proposal below follows it; the Task 2 fault-injection idea doesn't and is kept
only as a record.

Both are documented here rather than left as best-effort assertions in the specs.

---

## Task 2 — proving the Trace-ID error-surfacing convention on the admin path

**Goal:** drive an admin approve/reject RPC to FAIL through the UI and assert the
page surfaces `.alert-danger` + "Trace ID:" (the project error convention).

**Finding: there is no naturally-reachable UI/HTTP path that forces this error.**
The vendor-admin controller mirrors the API's precondition exactly, so every call
it forwards is one the API accepts:

- `lib/NTPPool/Control/Vendor.pm` `render_admin` re-fetches the zone's **live**
  status on each POST and only forwards the status RPC when:
  - `status eq 'Pending'` and `status_change =~ /^Reject/`  → `status => 'Rejected'`
  - `status =~ /(Pending|Rejected)/` and `status_change =~ /^Approve/` → `status => 'Approved'`
- The Go RPC `UpdateVendorZoneStatus` (`server/api/vendorzone/status.go`) runs
  `UpdateVendorZoneStatus`, whose SQL is
  `UPDATE vendor_zones SET status = … WHERE id = … AND status IN ('Pending','Rejected')`
  (`sql/vendor_zones.sql`). A row outside that set returns `sql.ErrNoRows` →
  `FailedPrecondition`.

Because the Perl guard is strictly tighter-or-equal to the SQL `WHERE`, the only
way the forwarded RPC can hit `FailedPrecondition` is a TOCTOU race between the
controller's `get_vendor_zone` and its `update_vendor_zone_status` — not
reproducible from a test. Re-posting `status_change=Approve` against an
already-Approved zone is a **controller no-op** (the regex doesn't match
`Approved`), never an RPC error.

The Trace-ID convention IS already proven end-to-end by the **duplicate zone
name** edit case (`vendor.spec.ts` ~line 220, regular-user edit path): a real API
error renders `.alert-danger` + a Trace ID. What's missing is only the
*admin-path* repetition of that proof.

**What the §5c test does now:** asserts the reachable property — an invalid admin
transition is a SAFE no-op (no dead-end, no error bleed, status unchanged) — and
keeps a conditional Trace-ID check as a free regression net.

**To close the gap (option a), the Go API would need test-only fault injection.**
Every shape below puts a hook in a network-reachable handler, which the rule
above forbids:

- A devel-only way to make a specific RPC return an error on demand. Lowest-churn
  shape: have `UpdateVendorZoneStatus` (and/or a thin test RPC) recognize a
  **sentinel** in devel — e.g. `rt_ticket == -1`, or an `X-Test-Force-Error`
  header — and return `connect.CodeInternal` with a trace span, guarded by
  `api.Env == depenv.DeployDevel` so it can never fire in test/prod.
- The Perl `render_admin` path would also need to forward that sentinel
  (it currently hard-codes the status RPC args), so a header is the less-invasive
  carrier than a new form field.
- The e2e test would set the sentinel, click Approve on a genuinely Pending zone,
  and assert `.alert-danger` + "Trace ID:" via `expectErrorAlert(page, {
  requireTraceId: true })` — gated behind a capability probe that skips when the
  deployed dev API predates the hook.

This was **not implemented**: it conflicts with the rule above, and it would add
a Perl+Go+proto change to re-prove a convention already verified on the edit path.
The cost/benefit favors documenting it here.

---

## Task 5 — exceeding 3 invite sends in 24h (rate-limit warning)

**Goal:** reach 3 invite sends within 24h and assert the 4th is blocked with the
API's "limit: 3" warning (`invites.spec.ts`, currently `test.skip`).

**Finding: unreachable through the UI in one run.** Sends are gated by a 5-minute
cooldown (the API reports `can_resend=false` / `resend_available_at`), so a
single test run can't legitimately reach 3 sends without either waiting ~10
real minutes or backdating the prior sends. The harness is read-only (no DB
writes), so it can't backdate them itself. The cooldown itself IS covered (the
"immediate second resend is blocked by the 5-minute cooldown" test).

**To close the gap, the Go API would need a test-only `api e2e invite backdate`
command**, built like `api e2e session`:

- e.g. `api e2e invite backdate` reading `{account_token | invite_id, count, age}`
  on stdin and rewriting the recorded send timestamps for a pending invite to N
  minutes/hours ago, so the cooldown is satisfied while the 24h counter still
  reflects the prior sends.
- Guards: build tag `e2efixtures` (api-dev image only) plus the devel check
  every `api e2e` command runs (`deployment_mode` and the database
  `environment` both devel).
- The test would then: invite → resend → backdate(2 sends, >5min ago) → resend
  (now 3 total) → backdate again → attempt a 4th resend and assert the
  `resource_exhausted` "limit: 3" warning via
  `errorAlerts(page)` + `"limit: 3"`.

Until that command exists and is deployed, the test stays skipped (its assertion
shape is kept ready in `invites.spec.ts`). The cooldown half is the reachable
portion and is asserted today.
