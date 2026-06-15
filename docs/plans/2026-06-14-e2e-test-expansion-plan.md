# E2E Test Expansion Plan

Extends the committed thin slice (`e2e/`, commit 8630aa88) to cover more of
`MANUAL_TEST_PLAN.md`. Builds on the design in
[2026-06-14-e2e-test-automation-design.md](2026-06-14-e2e-test-automation-design.md)
and the original implementation plan
[2026-06-14-e2e-test-automation-plan.md](2026-06-14-e2e-test-automation-plan.md).

**Status:** the harness (mint-session auth fixture + two specs) is committed. The
`CreateTestSession` RPC and `e2e/lib/auth.ts` exist. The read-only DB layer is not
yet built. Tests are written here but **not run** — running waits on a provisioned
`test-session-api` key and a deployed dev API.

## Constraints that shape coverage

A minted user is **fresh, non-staff, with no servers/zones/subscriptions**. That
splits `MANUAL_TEST_PLAN.md` into:

- **Black-box, regular fresh user** — login/logout, i18n, vendor create/edit
  lifecycle (the New→Pending portions a regular user owns), score graphs (public),
  add-server + schedule/cancel deletion (reversible).
- **Needs a staff session** — account dissolution (§2), staff-targeted deletion
  (§3), vendor admin approve/reject (§5a-staff, §5c-admin). Obtained via a new
  `grant_staff` flag on `CreateTestSession` (Round 2).
- **Needs the read-only DB layer** (design §C) — side effects with no UI surface:
  email sent (§2, §4a, §8a), audit log (§8a), invite expiry (§4a), background
  sweep (§11).
- **API-side / out of browser scope** — DNS zone generation (§6), Stripe (§7),
  most of §11. Covered by Go tests in `../go/ntp/api`, not Playwright.

## Decisions (from the user)

1. **Staff sessions** → extend the mint RPC with an optional `grant_staff` flag so a
   fresh isolated user becomes staff. No real-account mutation.
2. **Sequencing** → land Round 1 (black-box regular user) and commit, then Round 2
   (Go API `grant_staff`, DB layer, staff specs, side-effect assertions).
3. **Stateful flows** → include reversible ones (add server, schedule/cancel
   deletion). Fresh-user isolation limits blast radius.
4. **Reuse** → pull types/helpers from `../go/ntp/api` into the harness where it
   simplifies things (e.g. generated proto JSON shape, settings sentinel query).

---

## Round 1 — black-box regular-user specs (no new Go API, no DB layer)

Shared first, then independent spec files (parallel-safe).

### Task R1.0 — shared helpers (`e2e/lib/helpers.ts`)

- `expectCleanPage(page, path)` — moved out of `regression-smoke.spec.ts`: GET → 200,
  body has no `NP::Model::` / `Can't locate`, no obvious 500. Returns the response.
- `getTraceId(page)` — extract a rendered "Trace ID: …" from an error alert (for §5c).
- `expectErrorAlert(page)` — assert a Bootstrap `.alert-danger`/`.alert-warning` with a
  trace id is present (error-surfacing items).
- Refactor `regression-smoke.spec.ts` to import `expectCleanPage`.

### Task R1.1 — login / logout (`tests/login.spec.ts`, extend) — §1

- New-user landing is not a dead-end (no "no pending invitations" empty page).
- Login page copy reflects broader scope (not just "add a server").
- Logout then log back in (re-mint) — session restored, dashboard renders, no
  duplicate-account symptom (same account context for the same email).

### Task R1.2 — i18n (`tests/i18n.spec.ts`, new) — §10

- Language is chosen by `Accept-Language` (`detect_language` in `Control.pm`); set it
  via Playwright `extraHTTPHeaders` / `locale`. (X-Varnish-Accept-Language is a
  front-proxy header; Accept-Language is the dev fallback — note this in the spec.)
- Thai (`th`), Traditional Chinese (`zh-tw`): a key page renders translated, no raw
  `[%` template bleed, page still 200.
- Portuguese (`pt`) and Czech (`cs`): spot-check layout (page loads clean).

### Task R1.3 — vendor zone lifecycle, regular user (`tests/vendor.spec.ts`, new) — §5, §5a, §5b, §5c

Controller: `lib/NTPPool/Control/Vendor.pm`; templates under `docs/manage/`.

- `/manage/vendor` and `/manage/vendor/new` load with API metadata (no ORM errors).
- Create a **New** zone request (regular user owns New→Pending); save persists.
- Edit a **Pending** zone — all fields editable, save persists (the previously
  blank-form dead-end).
- §5b open-source path: create with `opensource_request` + `opensource_info`; reopen
  and confirm the justification is retained (not blanked) on edit/save.
- §5c error surfacing: induce a duplicate zone name → red alert with message + Trace
  ID, page keeps entered context (uses `getTraceId`/`expectErrorAlert`).
- (Approved/Rejected transitions and the admin matrix are Round 2 — they need staff.)

### Task R1.4 — score graphs / PNG (`tests/scores.spec.ts`, new) — §9

Controllers: `lib/NTPPool/Control/Scores.pm`, `Graph.pm`. Public; no login needed.

- `/scores/<ip>` renders for a known dev server IP (parameterize via env, default a
  documented dev IP); 200, no ORM bleed.
- `/scores/<ip>/offset.png` returns 200 with `Content-Type: image/png`.
- `score.png` normalizes/redirects to `offset.png`.
- An unmatched/legacy graph path returns 404 (already partially covered).

### Task R1.5 — add server + scheduled deletion (`tests/server.spec.ts`, new) — §8, §8a

Controller: `lib/NTPPool/Control/Manage/Server.pm` (`/manage/server/add`,
`/manage/server/delete`). Reversible.

- Add-server form renders for a fresh user; a fresh account may need verification
  first (`can_add_servers`) — assert the precheck path renders cleanly either way.
- If a server can be added (use an env-provided test IP, RFC 5737 range), add it and
  assert success; then schedule deletion on `/manage/server/delete` (shows scheduled
  state + cancel, not the date-picker again), then cancel (returns to normal).
- Error-surfacing: a schedule attempt with an expired/absent session surfaces a red
  alert, not a silent no-op. (Audit-log + email assertions for §8a are Round 2 / DB.)

### Task R1.6 — commit Round 1

`test(e2e): expand coverage — login/logout, i18n, vendor, scores, server`.

---

## Round 2 — staff, DB verification layer, side effects

### Task R2.1 — Go API: `grant_staff` on `CreateTestSession`

In `../go/ntp/api`:

- `proto/ntppool/auth/v1/auth.proto`: add `bool grant_staff = 4;` to
  `CreateTestSessionRequest`; regenerate (buf) and stage all `gen/...` files.
- Handler `server/api/auth/test_session.go`: when `grant_staff` and devel, insert the
  `support_staff` user-privilege for the minted user (reuse the existing privilege
  insert helper; do not hand-roll SQL if a querier method exists). Still devel-only +
  capability-gated + audit-logged.
- Extend the integration test: a granted user validates as staff.
- Commit per the repo's generated-file rule (stage `gen/...` with the proto change).

Harness: `loginAs(context, email, { grantStaff: true })` threads the flag through
`mintSession`.

### Task R2.2 — read-only DB verification layer (design §C)

- `e2e/lib/db.ts`: thin `pg` read-only client on `NTP_TEST_DB_URL`.
- `assertDevelDatabase()`: refuse unless db name is `askntp` **and** the
  `deployment_mode` setting reads `devel` (sentinel query). Run once before any query.
- Helpers: `latestEmailTo(email)`, `auditLogFor(...)`, `inviteExpiry(...)`,
  `sessionCountFor(userId)`. Reuse the Go side's table/column names — copy the
  relevant `ntpdb` query text where it keeps the harness simple.
- Provision a dedicated read-only role; document `NTP_TEST_DB_URL` in `.env.example`.

### Task R2.3 — staff specs

- `tests/account-dissolve.spec.ts` (§2): staff sees the destructive delete link;
  visit `/manage/account/dissolve`, schedule (~7 days out), revisit shows pending +
  cancel, cancel clears. Non-staff fresh user gets 403 and no link.
- `tests/staff-deletion.spec.ts` (§3): staff targets another user/account via `u=` /
  account context; non-staff cannot target others.
- Extend `tests/vendor.spec.ts` (§5a-staff, §5c-admin): admin approve/reject status
  change; staff edit of Approved zone (`zone_name` read-only; name-change rejected by
  API); admin approve/reject error surfacing.

### Task R2.4 — side-effect assertions (DB layer)

- §2 deletion-scheduled email sent (`latestEmailTo`).
- §4a invite resend: email arrives, expiry moves ~30 days, rate-limit counters (fresh
  users avoid cross-run collisions). Needs an invite-create path — via UI on the team
  page as the account owner.
- §8a schedule/cancel audit-log rows written by the Go API.

### Task R2.5 — commit Round 2 (Go API and harness commits separately)

---

## Out of scope (tracked, not implemented here)

- Auth0 code-exchange round-trip (design: intentionally out — we mint directly).
- §6 DNS zone generation, §7 Stripe end-to-end, §11 infra sweeps beyond DB-visible
  effects — these are Go-side tests in `../go/ntp/api`, not Playwright.
- Teardown of minted users — rely on unique-per-run emails + the scheduled-deletion
  sweep; a delete path can come later.

## Verification (when running is enabled)

1. `cd e2e && npm install && npx playwright install chromium`.
2. Provision a `test-session-api` key (Round-2 build adds `grant_staff`); fill
   `e2e/.env` incl. `NTP_TEST_DB_URL` for the DB-backed specs.
3. `npx playwright test --list` lists every spec.
4. `npm test` against the running dev site — all specs green; staff specs require the
   `grant_staff` build deployed.
