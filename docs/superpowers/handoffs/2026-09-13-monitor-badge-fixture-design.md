# Handoff: Design a bounded monitor fixture for §15 badge coverage

**Date:** 2026-09-13
**Status:** Resolved. The design is
`docs/superpowers/specs/2026-09-13-monitor-badge-fixture-design.md`; plans are
`docs/superpowers/plans/2026-09-14-e2e-fixture-monitors-api.md` and
`docs/superpowers/plans/2026-09-14-monitor-badges-e2e.md`.
**Relates to:** `docs/superpowers/specs/2026-09-12-e2e-additional-coverage-design.md`
and `MANUAL_TEST_PLAN.md` §15. The "Monitor privileges and data" row in
`docs/superpowers/handoffs/2026-09-09-e2e-readiness-requirements.md` flagged
this generically ("how monitors/configurations are created") — the privilege
half of that is now done (`grant_monitor_admin`, shipped 2026-09-13, see
`docs/superpowers/plans/2026-09-12-monitor-admin-test-session-grant.md`); this
handoff is the remaining half.

---

## TL;DR

§15 needs live E2E coverage for the account-flag badges (Bypass, Disabled,
Custom Limit, Per-Server, no-badges) that render in `/manage/monitors`. Do NOT
assume this needs new backend work to *set* the flags — it doesn't. The entire
gap is: **there is no dev-only way to create a disposable monitor row**, and
the badges render once per account only when the monitor list has at least
one monitor for that account. Design a bounded, cleanup-tracked "monitor
fixture," modeled on the existing `ServerFixture` pattern in `e2e/lib/servers.ts`.

---

## What's already solved (do not redesign this part)

The account-level flags the badges read (`monitor_enabled`, `monitor_limit`,
`monitors_per_server_limit`) can already be set through a real, already-tested
UI/RPC path shipped today:

- Route: `/manage/account/monitor-config?a=<token>` (GET renders the form, POST
  updates), handled by `render_monitor_config_form` /
  `render_monitor_config_update` in `lib/NTPPool/Control/Manage/Account.pm`
  (~lines 936–1010).
- The edit form (`docs/manage/tpl/account/monitor_config_edit_form.html`)
  exposes all three fields a test needs:
  - `monitor_enabled` checkbox → drives the green **Bypass** badge.
  - `monitor_limit` select, including `-1` ("Disabled (no new monitors)") →
    drives the red **Disabled** badge, or any other non-default value →
    blue **Custom Limit** badge.
  - `monitors_per_server_limit` select → yellow **Per-Server** badge.
- `e2e/tests/monitor-config.spec.ts` (committed today) already exercises this
  route end-to-end for `monitors_per_server_limit`; the same pattern
  (`loginAs(..., { grantMonitorAdmin: true })`, open the account page, use the
  form) extends directly to `monitor_enabled` and `monitor_limit`.

So: **no new Go RPC or Perl controller work is needed to produce the four
badge states.** A test can mint a monitor-admin session, open the target
account's monitor-config form, and set any combination of the three fields
today.

## What's actually missing

The badge itself only renders inside the monitor list, once per account, and
only when that account has at least one monitor row:

- `docs/manage/tpl/monitors/list.html` — the shared template for both the
  per-account list (`/manage/monitors`) and the admin all-accounts view
  (`/manage/monitors/admin`, which is just `list.html` processed with
  `admin_list = 1` — see `admin_list.html`). It loops `FOR mon = monitors` and
  emits the account heading + `[% INCLUDE tpl/monitors/account_flags_badge.html %]`
  **only when `last_account != mon.account.id`** — i.e., once per account,
  gated on that account actually appearing in the `monitors` list.
- `lib/NTPPool/Control/Manage/Monitor.pm`: `render_monitors` calls
  `list_monitors($self->api_auth_params, account => ...)` for the per-account
  view; `render_admin_list` calls `list_monitors($self->api_auth_params,
  all_accounts => JSON::XS::true)` for the admin view. Both go through the Go
  `ListMonitors` RPC, which is also what gates `mon.account.flags` to
  monitor-admin callers only (`account_flags_badge.html`'s own comment: "populated
  by the API for monitor admins only... otherwise unset" — this is a
  server-side check keyed off the same `auth` token, not a Perl-side filter,
  so the "non-monitor-admin sees no badges" test needs no special handling
  beyond minting a non-admin session).
- `api e2e session` (the api-dev command `loginAs` mints through) creates a
  user and a default account — **never a monitor.** There
  is no `api e2e monitor` command today.
- Real monitor creation is the full production registration flow:
  `~/src/go/ntp/api/server/api/monitorreg/` — JWT-based (`jwt/jwt.go`),
  Vault-backed (`vault.go`), with hostname validation and a user-acceptance
  step (`user_acceptance.go`). This is *not* something an E2E fixture should
  drive directly — it's slow, has external dependencies (Vault), and tests
  something else's correctness, not the badge template.

## Design questions for the brainstorm/spec

1. **Command shape.** Test-only setup goes in `api e2e` subcommands, never in
   handlers reachable over the network (see
   `docs/superpowers/specs/2026-09-13-e2e-fixtures-cli-design.md`). Most
   likely: `api e2e monitor create|cleanup` (build tag `e2efixtures`, devel
   gated like `api e2e session`) that inserts a `monitors` row directly
   — bypassing JWT/Vault/hostname-validation entirely — associated with a
   given account (probably the account from an already-minted test session,
   passed by account token). Confirm the minimal set of NOT NULL / FK columns
   `monitors` actually requires (check the schema and `ntpdb` queries) so the
   fixture doesn't have to fake a realistic monitor, just a valid row.
2. **What state must the monitor be in to be listed?** `ListMonitors` may
   filter by status (active/pending/deleted) — check
   `server/api/monitoradmin/` and the `ListMonitors` query before assuming a
   bare insert is enough to make it appear in `/manage/monitors`.
3. **Cleanup.** Mirror `ServerFixture`'s pattern exactly: an `attempt_id`
   tracked by the fixture, an `api e2e monitor cleanup` command that deletes
   the monitor row and anything FK-dependent on it
   (status history, metrics rows, etc.), Playwright `testInfo.attach()`
   diagnostics on cleanup failure, and a hard failure (not a skip) if cleanup
   doesn't succeed. See `e2e/lib/servers.ts` lines ~183–330 for the exact
   shape to copy.
4. **One monitor is probably enough.** The badge only needs *a* monitor row to
   exist for the account — the test doesn't need the monitor to be healthy,
   registered, or reporting metrics. Don't over-build this; resist adding
   monitor-status/metrics simulation unless a specific checklist row needs it
   (skim §15's rows again — none of them mention monitor health/status, only
   account-level flags).
5. **Per-account list vs. admin list.** Both use the same `list.html`, so one
   fixture (monitor + account with the target flags) should cover both "list"
   checklist rows — just visit both URLs in the test rather than building two
   fixtures.
6. **Non-monitor-admin denial.** Confirm what `list_monitors` actually returns
   to a non-monitor-admin caller for the *admin* (`all_accounts=true`) view —
   likely a 403 like `monitor-config`'s route, distinct from the per-account
   view (which a non-admin can presumably still load, just without badges,
   since it's their own account's monitor list). Nail down both cases before
   writing assertions.

## Key code locations (verified 2026-09-13)

- `docs/manage/tpl/monitors/account_flags_badge.html` — the badge template
  itself; compares pre-resolved booleans, doesn't recompute anything (don't
  touch this file for the fixture work).
- `docs/manage/tpl/monitors/list.html` (shared by `list.html` direct use and
  `admin_list.html`'s `PROCESS ... admin_list = 1`) — badge placement, once
  per account group.
- `lib/NTPPool/Control/Manage/Monitor.pm` — `render_monitors` (~220),
  `render_admin_list` (~245).
- `lib/NTPPool/Control/Manage/Account.pm` — `render_monitor_config_form` /
  `render_monitor_config_update` (~936–1010), the already-working flag-setting
  path.
- `e2e/lib/servers.ts` — the `ServerFixture` pattern to copy: `ServerSeed` /
  `FixtureServer` / `ServerFixture` interfaces, `cleanupFixture()` (~183),
  `create()` (~279), cleanup diagnostics via `testInfo.attach` (~306–324).
- `e2e/tests/monitor-config.spec.ts` — the existing test to extend once a
  monitor fixture exists; already has the `loginAs(..., { grantMonitorAdmin:
  true })` + account-page pattern this needs.
- `~/src/go/ntp/api/server/api/monitorreg/` — the real registration flow, for
  reference on what NOT to reuse directly, and to check `monitors` table
  constraints.
- `~/src/go/ntp/api/server/api/monitoradmin/` — likely home for `ListMonitors`
  and any status filtering logic relevant to question 2 above.

## How to resume

1. Run `superpowers:brainstorming` (or `abh:refine-spec`) against this
   document to resolve the design questions above — particularly #1 (command
   shape) and #2 (list-visibility requirements), which need someone to read
   the actual `monitors` schema and `ListMonitors` query before deciding.
2. Once resolved, write the spec to
   `docs/superpowers/specs/2026-09-13-monitor-badge-fixture-design.md`, then
   `superpowers:writing-plans` for the task-by-task implementation plan
   (mirroring the two-plan Go-then-Perl/E2E split used for
   `grant_monitor_admin` this week — a new `api e2e` command almost certainly
   needs its own deploy-then-test-live gate, same as that one did).
3. The devel deploy mechanism for the Go API is **not** GitOps/Flux despite
   `~/src/flux-ntp`'s docs implying otherwise — that Kustomization path is
   orphaned. Use `~/src/flux-ntp/askntp/api/update-api` (a `helm upgrade`
   wrapper) after a CI build lands the image; see the git history around
   2026-09-13 for the full discovery if needed.
