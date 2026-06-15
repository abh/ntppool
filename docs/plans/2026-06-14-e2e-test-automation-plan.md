# E2E Test Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up an automated browser test harness for `MANUAL_TEST_PLAN.md` that logs in without driving Auth0, by adding a dev-only session-mint RPC to the Go API and a Playwright suite that proves the chain end-to-end on two read-only flows.

**Architecture:** A new `CreateTestSession` RPC on the Go API's `AuthService` mints a real `nps_…` session token for a given email (creating the user+account via the same path Auth0 onboarding uses), guarded by a hard devel-only check, a dedicated service-key capability, and an audit-log row. A new top-level `e2e/` Playwright project (in the ntppool repo) calls that RPC over the internal API, sets the resulting token as the `npuid` cookie, and drives the live dev site. The first cut is two black-box specs; the read-only DB verification layer is deferred to the first side-effect assertion.

**Tech Stack:** Go + ConnectRPC + buf + sqlc/ntpdb + goose (API, `../go/ntp/api`); TypeScript + Playwright (`e2e/`, this repo); PostgreSQL (CloudNativePG, dev namespace `askntp` on cluster `dala`).

**Design reference:** `docs/plans/2026-06-14-e2e-test-automation-design.md`

---

## Pre-flight: read these before starting

The executing agent must read these to get exact signatures/patterns (this plan
intentionally references symbols rather than reproducing code):

- `../go/ntp/api/proto/ntppool/auth/v1/auth.proto` — existing `AuthService`, message style, `ProcessAuth0Login` / `GetOAuthLoginURL`.
- `../go/ntp/api/server/api/auth/auth0_login.go` — `ProcessAuth0Login` and `processAuth0User` (the user+account provisioning to reuse/extract).
- `../go/ntp/api/auth/keys.go` — `MakeSessionKey(ctx, userID)` and `key.Save(ctx, q)` (the session-mint primitives; also used in `server/api/.../staff_account_access_integration_test.go`).
- `../go/ntp/api/auth/auth_types.go` — auth type constants and key prefixes (`nps_`/`npu_`/`npm_`/`npd_`) and the `service-api` audience.
- `../go/ntp/api/server/api/sessions/auth.go` — `checkAuth`, how a service key's audiences are validated and how the authenticated `[]ntpdb.Service` lands in context.
- `../go/ntp/api/server/api/api.go` — how RPCs/service groups are registered, and which group `ValidateSession` (service-auth, internal) is mounted on.
- `../go/ntp/api/cmd/cmd.go` (~line 512) — the existing `service create` command.
- `../go/ntp/api/ntpdb/` — `CreateUser`, `CreateAccount`, `AddUserToAccount` params; the `settings` table accessor (for `deployment_mode`); audit-log insert helper used by other mutations.
- `../go/ntp/api/depenv` — how `deployment_mode` / `DeployProd` / `DeployDevel` is determined at runtime.
- `../go/ntp/api/Makefile` + `buf.gen.yaml` — the proto generation command and output dirs (`gen/`).
- `lib/NTPPool/Control/Login.pm` (this repo) — exact `npuid` cookie attributes (domain, path, `Secure`, `HttpOnly`) so the harness cookie matches.

---

## File Structure

**Go API (`../go/ntp/api`):**
- `proto/ntppool/auth/v1/auth.proto` (modify) — add the RPC + two messages.
- `gen/...` (generated) — buf output; staged with the proto change.
- `server/api/auth/test_session.go` (create) — the handler + the three guards.
- `server/api/auth/auth0_login.go` (modify) — extract `ensureUserAndAccount` helper.
- `server/api/auth/test_session_integration_test.go` (create) — guard + happy-path tests.
- `server/api/api.go` (modify) — mount the RPC on the internal service-auth group.
- `server/api/sessions/auth.go` (modify, if needed) — expose the test-session audience check helper.
- `auth/auth_types.go` (modify) — add the `test-session-api` audience constant.
- `cmd/cmd.go` (modify) — `service create` flag to grant the audience.

**Harness (this repo, new `e2e/`):**
- `e2e/package.json`, `e2e/.gitignore`, `e2e/.env.example`, `e2e/playwright.config.ts`,
  `e2e/README.md` (create) — project scaffold + config.
- `e2e/lib/auth.ts` (create) — `mintSession()` + `loginAs()`.
- `e2e/tests/login.spec.ts`, `e2e/tests/regression-smoke.spec.ts` (create) — thin slice.

**Deferred (NOT in this plan — documented for later):**
- `e2e/lib/db.ts` — read-only client + `assertDevelDatabase()`; added at the first
  side-effect assertion (email/audit/sweep/expiry). See design doc §C.

---

## Part 1 — Go API: `CreateTestSession` RPC (critical path)

### Task 1: Add the proto definition

**Files:**
- Modify: `../go/ntp/api/proto/ntppool/auth/v1/auth.proto`
- Generated: `../go/ntp/api/gen/...` (whatever `buf generate` emits)

- [ ] **Step 1: Add the messages and RPC.** Following the existing message/field style in `auth.proto`, add `CreateTestSessionRequest { string email = 1; string name = 2; bool create_if_missing = 3; }` and `CreateTestSessionResponse { string session_token = 1; }`, and add `rpc CreateTestSession(CreateTestSessionRequest) returns (CreateTestSessionResponse);` to the `AuthService` service block.
- [ ] **Step 2: Regenerate.** Run the project's proto generation (Makefile `generate` target / `buf generate` — confirm in `Makefile`/`buf.gen.yaml`).
  Expected: new generated Go types for the request/response and a `CreateTestSession` method on the service interface; build still compiles the generated package.
- [ ] **Step 3: Stage generated files.** Run `git -C ../go/ntp/api status` and stage `proto/...` **and** all generated `gen/...` files together (per the repo's generated-file rule).
- [ ] **Step 4: Commit.** `feat(auth): add CreateTestSession RPC definition (dev-only session mint)`.

### Task 2: Add the `test-session-api` service-key capability

**Files:**
- Modify: `../go/ntp/api/auth/auth_types.go`
- Modify (if a shared helper fits): `../go/ntp/api/server/api/sessions/auth.go`

- [ ] **Step 1: Add the audience constant.** Add a `test-session-api` audience constant next to the existing `service-api` audience, with a short comment that it gates dev-only test-session minting.
- [ ] **Step 2: Add a capability check helper.** Add a helper that, given the request context, returns whether the authenticated service principal carries the `test-session-api` audience (read the `[]ntpdb.Service` the auth middleware places in context — see `sessions/auth.go`). Keep it next to the existing audience-checking code so the handler can call one function.
- [ ] **Step 3: Build.** Run `go -C ../go/ntp/api build ./...`. Expected: compiles.
- [ ] **Step 4: Commit.** `feat(auth): add test-session-api service capability`.

### Task 3: Extract the user+account provisioning helper

**Files:**
- Modify: `../go/ntp/api/server/api/auth/auth0_login.go`

- [ ] **Step 1: Identify the provisioning block.** In `processAuth0User`, locate the logic that ensures the user exists (`CreateUser` when missing) and that the user has an account (account creation + `AddUserToAccount`) — the post-onboarding state a real new user lands in.
- [ ] **Step 2: Extract `ensureUserAndAccount`.** Factor that block into a function (suggested signature: `ensureUserAndAccount(ctx, q, email, name string) (user, account, error)`), and call it from `processAuth0User` so `ProcessAuth0Login` behavior is byte-for-byte unchanged. Do not change onboarding semantics.
- [ ] **Step 3: Run the existing Auth0 tests.** Run `go -C ../go/ntp/api test ./server/api/auth/...` (notably `auth0_login_integration_test.go`).
  Expected: PASS — the refactor is behavior-preserving.
- [ ] **Step 4: Commit.** `refactor(auth): extract ensureUserAndAccount from processAuth0User`.

### Task 4: Implement the handler (TDD)

**Files:**
- Create: `../go/ntp/api/server/api/auth/test_session.go`
- Create: `../go/ntp/api/server/api/auth/test_session_integration_test.go`

- [ ] **Step 1: Write the failing integration test.** In `test_session_integration_test.go`, write three cases (use the existing integration-test harness / `TEST_DATABASE_URL` pattern and a reserved ID range per `testhelpers/integration_cleanup.go`):
  1. **non-devel guard** — with `deployment_mode` set to non-devel, calling the handler returns `connect.CodePermissionDenied`.
  2. **capability guard** — in devel, a request whose context carries a service principal *without* the `test-session-api` audience returns `CodePermissionDenied`.
  3. **happy path** — in devel, with a capable service principal, `CreateTestSession{email:"test-run-x@example.com", create_if_missing:true}` returns a `session_token` that begins `nps_` and that `ValidateSession` accepts (round-trip: feed the token back through the validation path and assert `valid==true`, `email` matches).
- [ ] **Step 2: Run to verify it fails.** Run `go -C ../go/ntp/api test ./server/api/auth/ -run TestCreateTestSession -v`.
  Expected: FAIL/compile error (handler not implemented).
- [ ] **Step 3: Implement the handler.** In `test_session.go`, implement `CreateTestSession`:
  1. **Guard 1** — if the runtime env is not devel (`depenv`/`deployment_mode`), return `connect.NewError(connect.CodePermissionDenied, ...)`.
  2. **Guard 2** — if the capability helper from Task 2 reports the caller lacks `test-session-api`, return `CodePermissionDenied`.
  3. Call `ensureUserAndAccount` (Task 3) with `email`/`name`; honor `create_if_missing` (if false and the user is absent, return `CodeNotFound`).
  4. Mint: `auth.MakeSessionKey(ctx, userID)` then `key.Save(ctx, q)` (mirror `staff_account_access_integration_test.go`).
  5. Write an audit-log row using the same helper other mutations use (action e.g. `test-session-mint`, subject = target user).
  6. Return `CreateTestSessionResponse{session_token: key.String()}` (the full `nps_…` value the cookie needs).
- [ ] **Step 4: Run to verify it passes.** Run `go -C ../go/ntp/api test ./server/api/auth/ -run TestCreateTestSession -v`. Expected: PASS.
- [ ] **Step 5: Commit.** `feat(auth): implement dev-only CreateTestSession handler`.

### Task 5: Mount the RPC on the internal service-auth group

**Files:**
- Modify: `../go/ntp/api/server/api/api.go`

- [ ] **Step 1: Register the method.** Mount `CreateTestSession` on the same internal, service-auth-protected RPC group that `ValidateSession` uses (so it is reachable at the internal `/int/rpc/ntppool.auth.v1.AuthService/CreateTestSession` path and the middleware populates the service principal in context). Do **not** put it on the public no-auth group.
- [ ] **Step 2: Build + full test.** Run `go -C ../go/ntp/api build ./...` then `go -C ../go/ntp/api test ./...`. Expected: compiles; tests pass.
- [ ] **Step 3: Commit.** `feat(auth): mount CreateTestSession on internal service-auth group`.

### Task 6: CLI flag to provision a capable key

**Files:**
- Modify: `../go/ntp/api/cmd/cmd.go`

- [ ] **Step 1: Add the grant option.** Extend the existing `service create` command so the operator can grant the `test-session-api` audience to the created service/api-key (follow the existing pattern for setting `service-api`). Document the flag in the command help.
- [ ] **Step 2: Smoke the CLI.** Run `go -C ../go/ntp/api run . service create --help` (or the equivalent) and confirm the new flag appears; build passes.
- [ ] **Step 3: Commit.** `feat(cmd): allow service create to grant test-session-api capability`.

---

## Part 2 — Playwright harness (`e2e/`)

> Prerequisite for running (not for writing the code): a deployed dev API including
> Part 1, and a `test-session-api` service key created via Task 6. The thin slice uses
> only `NTP_BASE_URL`, `NTP_INTERNAL_API_URL`, `NTP_TEST_SESSION_KEY`.

### Task 7: Scaffold the `e2e/` project

**Files:**
- Create: `e2e/package.json`, `e2e/.gitignore`, `e2e/.env.example`, `e2e/playwright.config.ts`, `e2e/README.md`

- [ ] **Step 1: `package.json`.** New project named `ntppool-e2e`, `"private": true`, devDependency `@playwright/test`, scripts `test` (`playwright test`) and `test:headed`. No coupling to `client/`.
- [ ] **Step 2: `.gitignore`.** Ignore `node_modules/`, `.env`, `test-results/`, `playwright-report/`.
- [ ] **Step 3: `.env.example`.** Document `NTP_BASE_URL` (default `https://web.askdev.grundclock.com`), `NTP_INTERNAL_API_URL` (the Tailscale-reachable internal API base), `NTP_TEST_SESSION_KEY`, and (commented, deferred) `NTP_TEST_DB_URL`.
- [ ] **Step 4: `playwright.config.ts`.** `baseURL` from `process.env.NTP_BASE_URL`; single chromium project; `retries: 1`; reasonable `timeout`/`expect` timeouts; reporter `list`. Load `.env` (e.g. via `dotenv` in the config or Playwright's env handling).
- [ ] **Step 5: `README.md`.** How to install (`npm install && npx playwright install chromium`), the env vars, how to provision the key (point at Task 6), and `npm test`. State clearly: **dev only; the mint RPC refuses non-devel.**
- [ ] **Step 6: Install + sanity.** `cd e2e && npm install && npx playwright install chromium` then `npx playwright test --list`. Expected: Playwright runs and lists zero tests.
- [ ] **Step 7: Commit.** `chore(e2e): scaffold Playwright harness`.

### Task 8: Auth fixture (`mintSession` + `loginAs`)

**Files:**
- Create: `e2e/lib/auth.ts`

- [ ] **Step 1: `mintSession(email, opts?)`.** `fetch` POST to `${NTP_INTERNAL_API_URL}/ntppool.auth.v1.AuthService/CreateTestSession`, header `Authorization: Bearer ${NTP_TEST_SESSION_KEY}` + `Content-Type: application/json`, JSON body `{ email, name?, create_if_missing: true }`. Parse the JSON response; return `session_token`. Throw with status + body text on non-2xx (so a missing/forbidden key fails loudly).
- [ ] **Step 2: `loginAs(context, email)`.** Call `mintSession`, then `context.addCookies([...])` with cookie name `npuid`, value `${token};${Math.floor(Date.now()/1000)}`, and the **domain/path/secure/httpOnly that match `lib/NTPPool/Control/Login.pm`** (read it; the value format `{token};{unix_ts}` is confirmed in the design doc). Return the minted email/user info for assertions.
- [ ] **Step 3: Helper for unique emails.** Add `uniqueTestEmail(prefix='test-run')` returning `${prefix}-${Date.now()}-${rand}@example.com` for fresh-user-per-run isolation.
- [ ] **Step 4: Commit.** `feat(e2e): add session-mint auth fixture`.

> No automated test for the fixture in isolation — it's exercised by Tasks 9–10 against
> the live dev site.

### Task 9: Thin slice 1 — login lands on `/manage`

**Files:**
- Create: `e2e/tests/login.spec.ts`

- [ ] **Step 1: Write the spec.** Test "minted user lands on the manage dashboard": create a `uniqueTestEmail()`, `loginAs(context, email)`, `page.goto('/manage')`. Assert: response is 200; the URL is the dashboard (not redirected to a login/dead-end); the page shows an account context (an authenticated dashboard marker — pick a stable selector/text present for a logged-in user, **not** the empty "no pending invitations" dead-end). This covers the core of `MANUAL_TEST_PLAN.md` §1 + §12 dashboard.
- [ ] **Step 2: Run against dev.** With `e2e/.env` populated and the dev site up: `cd e2e && npx playwright test tests/login.spec.ts`.
  Expected: PASS. (If it fails on the dashboard selector, adjust the selector to a stable logged-in marker — do not weaken the "not a dead-end" assertion.)
- [ ] **Step 3: Commit.** `test(e2e): minted user reaches the manage dashboard`.

### Task 10: Thin slice 2 — regression smoke

**Files:**
- Create: `e2e/tests/regression-smoke.spec.ts`

- [ ] **Step 1: Write the spec.** Test "core pages load clean as a logged-in user": `loginAs` a fresh user, then visit the server list page and a per-server page (use whatever server is reachable for a fresh account; if none, assert the empty-but-valid server list renders). For each navigation assert: HTTP 200; body does **not** contain `NP::Model::` or `Can't locate`; no HTTP 500. Covers `MANUAL_TEST_PLAN.md` §12 regression smoke.
- [ ] **Step 2: Run against dev.** `cd e2e && npx playwright test tests/regression-smoke.spec.ts`. Expected: PASS.
- [ ] **Step 3: Commit.** `test(e2e): regression smoke for core logged-in pages`.

---

## Final verification (end-to-end of the thin slice)

- [ ] **API side:** `go -C ../go/ntp/api test ./...` passes; manually confirm `CreateTestSession` returns `PermissionDenied` (a) when `deployment_mode != devel` and (b) with an ordinary (non-`test-session-api`) service key.
- [ ] **Provision:** with DevSpace running the dev site, create a `test-session-api` key via the Task 6 CLI; fill `e2e/.env`.
- [ ] **Run the suite:** `cd e2e && npm test`. Expected: both specs green — a freshly minted user reaches `/manage`, and the smoke pages load without ORM/500 errors.

---

## Spec coverage check (this plan → design doc)

- Mint RPC + 3 guards (devel-only, capability, audit) → Tasks 1, 2, 4, 5.
- Reuse onboarding user/account path → Task 3.
- Key provisioning → Task 6.
- Playwright in separate `e2e/` dir, env-driven, raw-fetch RPC client → Tasks 7, 8.
- Thin slice = two read-only black-box specs (§1 + §12) → Tasks 9, 10.
- Grey-box read-only DB layer (`assertDevelDatabase`, side-effect assertions) → **deferred**
  by design; documented under "Deferred" and design doc §C, to be added at the first
  email/audit/sweep/expiry item. No task here (out of first-cut scope).

## Notes / gotchas

- **Generated files:** Task 1 must stage `gen/...` with the proto change (repo rule).
- **No Perl changes:** the harness calls the RPC directly; the `npuid` cookie is set by
  Playwright, so no `NP::CAPI`/Perl binding is needed for the first cut.
- **Cookie fidelity:** the single most likely failure point in Task 9 is a cookie
  attribute mismatch (domain/secure/path) — read `Login.pm` and mirror it exactly.
- **Internal API reachability:** `NTP_INTERNAL_API_URL` must point at the internal
  service-auth API (Tailscale-reachable), not the public site.
