# E2E Test Automation — design

Automating `MANUAL_TEST_PLAN.md` against the running dev site, with a
non-interactive login path and grey-box verification.

## Context

`MANUAL_TEST_PLAN.md` (repo root) lists ~12 sections of changes since 2025-12-01 that
are checked by hand against the live dev site `https://web.askdev.grundclock.com/`.
The plan covers browser flows (login, account dissolution, vendor zones, server
add/delete, invites) plus some API-side smoke checks. Running it manually is slow and
gets skipped.

We keep setting up the dev environment exactly as today (DevSpace against the `askntp`
namespace on the `dala` k8s cluster, reached over Tailscale) and **separately** run an
automated browser suite against that running site.

The blocker for browser automation is authentication: login goes through Auth0, and
there is no way today to obtain a logged-in session without driving the interactive
Auth0 flow. The session itself is just a cookie — so if the Go API can mint a session
token directly (in dev only), the browser suite can skip Auth0 entirely.

### How auth works today (from code exploration)

- Browser session = cookie `npuid`, value `{session_token};{unix_timestamp}`.
- Token format `nps_{secret}_{checksum}`, minted by `auth.MakeSessionKey(ctx, userID)`
  + `key.Save(...)` (`auth/keys.go`). Already used in
  `server/api/.../staff_account_access_integration_test.go`.
- The Auth0 path (`ProcessAuth0Login` in `server/api/auth/auth0_login.go`) just wraps
  this: it ensures the user + account exist (`processAuth0User`), then mints the same
  token and returns it; Perl sets the cookie.
- `ValidateSession` (internal service-auth RPC) validates `npuid` on every request.
- Emails always write a row to the `emails` table even in `devel` mode (no SMTP sent) —
  the established way to assert "email sent" (`tasks/serverremoval/...integration_test.go`).

## Decisions

1. **Mint-any-email + guards.** One scoped service key mints a session for any email
   (creating the user if missing). Best fit for the stateful / rate-limited flows because
   each run can use a fresh user.
2. **Thin vertical slice first.** Prove the whole chain end-to-end on 1–2 read-only flows,
   then expand section by section.
3. **Playwright in a separate top-level dir** (`e2e/` in the ntppool repo), independent of
   the `client/` Vite bundle tooling.
4. **Grey-box verification.** *Act* through the UI / mint-RPC (never fabricate state, so
   tests drive the real code paths); *verify* side effects through a dedicated **read-only**
   Postgres role. Many plan items are side effects with no UI surface — "email sent" (2,
   4a, 8a), "audit log written" (8a), "sessions cleaned up / monitor FKs cleared by the
   sweep" (11), "invite expiry moved to ~30 days" (4a), "soft-deleted excluded from counts"
   (11) — and a read-only query turns each into a one-line precise assertion. The thin
   slice stays pure black-box; the DB-read layer is added at the first side-effect item.

## Architecture

### A. Go API: `CreateTestSession` RPC

Add to `AuthService` (`proto/ntppool/auth/v1/auth.proto`):

- **Request**: `email` (required), `name` (optional), `create_if_missing` (default true).
- **Response**: `session_token` (the full `nps_…` string).
- **Guards (enforced in the handler, in order):**
  1. Hard environment block: if `deployment_mode != devel` → `CodePermissionDenied`.
     Prod literally cannot mint regardless of credential. This is the primary protection.
  2. Capability check: the caller's service key must carry a dedicated capability — a
     distinct audience (e.g. `test-session-api`) — so an ordinary `npd_` service key is
     refused. Reuse the existing service-key/audience check pattern from
     `server/api/sessions/auth.go`.
  3. Audit log: write an audit-log row per mint (who/what/when), same as other mutations.
- **Body**: reuse the **same** user+account provisioning helper that Auth0 onboarding uses
  (factor it out of `processAuth0User` in `server/api/auth/auth0_login.go` if not already
  shared) so a minted user lands in the identical state a real new user would — then
  `auth.MakeSessionKey` + `key.Save`. Do **not** invent separate session/user logic.
- **Mounting**: register on the internal service-auth RPC group in `server/api/api.go`
  (same group as `ValidateSession`), reachable over Tailscale.

Provisioning the key: extend the existing `service create` CLI (`cmd/cmd.go`, ~line 512)
to set the `test-session-api` capability/audience, so the developer runs it once and puts
the resulting `npd_…` key in the harness env.

### B. Harness: Playwright in `e2e/` (ntppool repo)

- `e2e/playwright.config.ts` — `baseURL` from env (default the dev site), single chromium
  project, sensible timeouts/retries.
- `e2e/lib/auth.ts` — `mintSession(email, opts)`: `fetch` POST to
  `{INTERNAL_API_URL}/ntppool.auth.v1.AuthService/CreateTestSession` with header
  `Authorization: Bearer {TEST_SESSION_KEY}` and JSON body; returns the token. A
  `loginAs(context, email)` fixture sets cookie `npuid = {token};{unix_ts}` via
  `context.addCookies(...)`. No Auth0, no DB access, no buf codegen — raw fetch + JSON.
- Config via env vars (documented in `e2e/README.md`): `NTP_BASE_URL`,
  `NTP_INTERNAL_API_URL`, `NTP_TEST_SESSION_KEY`, `NTP_TEST_DB_URL` (read-only). Loaded
  from a gitignored `e2e/.env`.
- `package.json` (new, in `e2e/`) with a `test` script; Playwright + `pg` as deps.

### C. Read-only DB verification layer (grey-box assertions)

- `e2e/lib/db.ts` — a thin read-only Postgres client (`pg`) reading `NTP_TEST_DB_URL`.
- **`assertDevelDatabase()`** runs once before any query and aborts the whole suite unless
  the connection identifies as the devel DB: database name is `askntp` **and** the
  `deployment_mode` setting reads `devel` (sentinel query against the settings table). Same
  spirit as the RPC's devel guard — refuse to even read an unexpected DB.
- Provision a dedicated **read-only** role (e.g. `ntp-test-ro`, or a read-only Vault
  dynamic-creds path) so the harness credential cannot mutate anything. Connection string
  from a gitignored `e2e/.env`.
- Helpers as needed by each section, e.g. `latestEmailTo(email)`, `auditLogFor(...)`,
  `sessionCountFor(userId)`, `inviteExpiry(...)`. Setup still goes through the API — these
  are assertion-only.
- Writes/teardown/time-travel stay out for now; if needed later they go behind a clearly
  separate, equally loud guard and a distinct read/write credential.

### D. The thin vertical slice (first deliverable)

Two read-only, non-destructive specs that exercise the full chain
(mint → cookie → real browser → assertion):

1. `e2e/tests/login.spec.ts` — mint a fresh `test-run-{rand}@example.com` user, load
   `/manage`, assert it lands on the dashboard as that user with an account context (no
   redirect to a dead-end / empty "no invitations" page). Covers the core of section 1 +
   section 12 dashboard.
2. `e2e/tests/regression-smoke.spec.ts` — as the same session, load the server list and a
   per-server page; assert HTTP 200 and that the body contains no `NP::Model::` /
   "Can't locate" errors and no 500. Covers section 12 regression smoke.

## Files to create / modify

**Go API (`../go/ntp/api`):**
- `proto/ntppool/auth/v1/auth.proto` — add `CreateTestSession` RPC + messages; regenerate
  (buf) and stage all generated files.
- `server/api/auth/test_session.go` (new) — handler with the three guards + provisioning.
- `server/api/auth/auth0_login.go` — extract the user+account ensure helper if needed.
- `server/api/api.go` — mount on the internal service-auth group.
- `server/api/sessions/auth.go` — recognize the `test-session-api` capability/audience.
- `cmd/cmd.go` — `service create` flag to grant the capability.
- Integration test for the handler: devel-only guard rejects non-devel; non-capable key
  rejected; happy path mints a token that `ValidateSession` accepts.

**Harness (this repo, new top-level `e2e/`):**
- `e2e/package.json` (Playwright + `pg`), `e2e/playwright.config.ts`, `e2e/lib/auth.ts`,
  `e2e/lib/db.ts` (read-only client + `assertDevelDatabase()`),
  `e2e/tests/login.spec.ts`, `e2e/tests/regression-smoke.spec.ts`, `e2e/README.md`,
  `e2e/.gitignore` (ignore `.env`, `node_modules`, results).
- The thin slice uses only `NTP_BASE_URL`, `NTP_INTERNAL_API_URL`, `NTP_TEST_SESSION_KEY`.

## Verification

1. **API unit/integration**: `cd ../go/ntp/api && go test ./server/api/auth/...` (and the
   integration suite via `scripts/test-integration` against the local test DB) — guards
   and happy path pass.
2. **Manual guard check**: confirm the RPC returns `PermissionDenied` when
   `deployment_mode != devel` and when called with an ordinary service key.
3. **End-to-end**: with DevSpace running the dev site, provision a `test-session-api`
   service key, fill `e2e/.env`, then `cd e2e && npm install && npm test`. Both specs pass:
   the minted user reaches `/manage` and the smoke pages load clean.

## Future expansion (not in the first cut)

Same auth fixture, section by section:
- Server add / scheduled delete + cancel (8/8a), vendor zones + editability matrix (5),
  account dissolution as staff (2/3), invite resend rate limits (4a — fresh users avoid
  cross-run counter collisions), i18n (10).
- The side-effect items — "email sent" (2, 4a, 8a), audit log (8a), session cleanup (11),
  invite expiry (4a) — use the read-only DB layer (section C); the first of these triggers
  wiring up `e2e/lib/db.ts`.
- Cleanup/teardown of minted users (delete RPC or rely on the scheduled-deletion sweep);
  unique-per-run emails keep the slice safe until then.
- Auth0 *code exchange* itself is intentionally out of scope — the harness mints sessions
  directly, so it covers the post-onboarding state, not the Auth0 round-trip.
