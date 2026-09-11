# Server Management E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace conditional server tests with isolated, repeatable coverage of verification, scheduled deletion, netspeed and permission-aware scores pages.

**Architecture:** Add two narrowly guarded AuthService fixture RPCs that create their own fresh ordinary user/account and a bounded server set, with a durable attempt registry for cleanup. Browser tests use those prerequisites and real session cookies, then perform every operation under test through the deployed web application. Existing authenticated server and staff audit reads establish persistence without browser SQL.

**Tech Stack:** Go, PostgreSQL/SQLC, ConnectRPC/protobuf, Perl/Template Toolkit, TypeScript and Playwright.

**Spec:** `docs/superpowers/specs/2026-09-10-server-management-e2e-design.md`

## Global Constraints

- “No shared mutable server, arbitrary environment-provided existing IP, serial cross-test state, permissive success alternatives, fixed sleeps, or conditional skips.”
- “Do not weaken production IP/DNS/NTP validation or seed the final result of an operation being tested.”
- “A missing capability must produce a clear setup failure, never test.skip.”
- “Never log session tokens, verification secrets, or the service credential in diagnostic messages.”
- “A cleanup failure fails an otherwise passing test and never hides the original failure.”
- “Run focused Go tests through scripts/test-integration, compile the changed Go packages, typecheck/discover the Playwright suite, then run the new specs against the configured devel hosts.”
- “Re-run the focused browser suite with fresh fixtures once to verify isolation and cleanup.”
- “Separate implemented/unverified, live-passed, and deferred items. Preserve earlier evidence.”
- Read root `CLAUDE.md` and `CLAUDE.local.md`; API proto, ntpdb and testhelpers instructions apply to their respective files. Generated clients are regenerated, never hand-edited or tidied. Keep CSP intact; no product changes are implied by writing failing tests.
- Worktrees: web `/private/tmp/ntppool-server-e2e`, branch `e2e/server-management`, base `89390108`; API `/private/tmp/ntppool-api-server-e2e`, branch `e2e/server-management-fixtures`, base `a5a58ed`. Do not edit canonical checkouts or their unrelated changes. Keep commits separate between repositories and preserve hooks.
- Ask already approved design, delegation and execution. Proceed through these three tasks sequentially with agent review; there is no new user approval gate.

## Shared contracts and scope

The fixture creates its own identity instead of accepting an existing account or a reusable CreateTestSession identity. This is the specification's “equally strict association”: no session, account, email, IP or server supplied by the caller can become owned cleanup data. Separate staff and outsider identities still use existing `mintSession`/`loginAs`.

Add these methods to `ntppool.auth.v1.AuthService`, mounted at the existing `/int/rpc` prefix:

```proto
rpc CreateServerTestFixture(CreateServerTestFixtureRequest) returns (CreateServerTestFixtureResponse) {}
rpc CleanupServerTestFixture(CleanupServerTestFixtureRequest) returns (CleanupServerTestFixtureResponse) {}

message ServerTestFixtureSpec {
  int32 ip_version = 1; // exactly 4 or 6
  bool verified = 2;
  bool pending_verification = 3; // mutually exclusive with verified
  bool scheduled_deletion = 4; // API sets 2099-01-01
  int32 netspeed = 5; // bounded supported values; tests use 512
}
message CreateServerTestFixtureRequest {
  string attempt_id = 1; // lowercase UUID v4, generated before the call
  repeated ServerTestFixtureSpec servers = 2; // 1..4; response order preserved
}
message ServerTestFixtureServer {
  int64 server_id = 1;
  string ip = 2; // canonical
  int32 ip_version = 3;
  string verification_token = 4; // only pending state
  bool verified = 5;
  string deletion_on = 6; // empty or 2099-01-01
  int32 netspeed = 7;
}
message CreateServerTestFixtureResponse {
  string attempt_id = 1; // also the fixture handle
  string account_token = 2;
  int64 account_id = 3;
  int64 user_id = 4;
  string email = 5;
  string session_token = 6;
  repeated ServerTestFixtureServer servers = 7;
}
message CleanupServerTestFixtureRequest { string attempt_id = 1; }
message CleanupServerTestFixtureResponse {
  string attempt_id = 1;
  int32 deleted_servers = 2; // zero on repeated cleanup
}
```

Both RPCs require `api.Env == depenv.DeployDevel` and `sessions.HasServiceAudience(ctx, apiauth.AudienceTestSessionAPI)`. Register exact procedures on the existing authenticated RPC group like CreateTestSession, retaining handler guards even if invoked through the AuthService wildcard. No arbitrary SQL, state-update RPC, fault injection or additional production permission.

Connect JSON uses snake_case (current service codec); int64 values are strings on the wire. Fixture auth uses `NTP_TEST_SESSION_KEY`; normal server/audit reads use `Authorization: Bearer <user session>` and `X-Account: <account token>`. Secrets never appear in assertion dumps or attached HTTP bodies.

Durability: `server_test_fixtures` stores UUID attempt, fresh user/account IDs, creation and cleanup timestamps. `server_test_fixture_servers` stores attempt, ordinal and original server ID/IP. Add environment-aware Go migration 027, which creates these tables only for `deployment_mode=devel` and records a no-op in test and production. Keep an unnumbered schema-only SQL file for SQLC and exclude it from Goose's embedded SQL migration set. Serialize create and cleanup with the same transaction-scoped advisory lock on the attempt. Cleanup of an unknown attempt writes a tombstone, preventing an in-flight/delayed create from creating rows after teardown. Existing active or cleaned attempts reject create with FailedPrecondition; do not reset mutated state on a repeated request. Same-attempt concurrency is therefore deterministic and a lost response remains recoverable.

Allocate IPv4 from `198.51.100.1..254` and `203.0.113.1..254` using an allocator advisory lock and database uniqueness checks; fail ResourceExhausted if no address is free. Do not use `192.0.2.1`, which existing scores coverage treats as missing. Allocate IPv6 within `2001:db8::/32` from cryptographic randomness, canonicalize with netip, and use a bounded collision retry. Address reuse is permitted only after completed cleanup; active parallel attempts cannot overlap. Never contact DNS or NTP during provisioning. Insert both `netspeed` and `netspeed_target` at the requested initial value, `in_pool=0`, `in_server_list=0`, private account profile, and no zones, score rows, log-score rows or monitor-review rows. Verification prerequisites are rows in `server_verifications`, with non-null verified_on only for verified state and a random UUID token only for pending state. Scheduled deletion is independent of verification status.

Cleanup uses `database.WithTransaction`, registry-owned IDs and the recorded account identity; abort if an extant owned server has moved to another account. Delete server-referencing `logs` and `emails` before owned servers, then cascade-owned child records as the schema requires; never cancel through the product API. Return success only after no tracked server remains. Keep the fresh user/account and tombstone as inert test identity records, matching the existing session harness retention model; they must never remain scheduled for deletion. Cleanup is bounded to at most four servers, not an account-wide or email-pattern deletion. Integration-test teardown separately uses the central cleanup helper for its own allocated identities.

## Task 1: Guarded Go fixture provisioning and durable cleanup

**Files:**

- Modify API `proto/ntppool/auth/v1/auth.proto`, `server/api/api.go`.
- Create API `server/api/auth/server_test_fixture.go`, `server/api/auth/server_test_fixture_integration_test.go`, `sql/server_test_fixtures.sql`, `db/migrations/027_server_test_fixtures.go`, and `db/migrations/schema_server_test_fixtures.sql`.
- Modify API `testhelpers/integration_cleanup.go`, `testhelpers/CLAUDE.md` for a distinct fixture test allocation using dynamically recorded IDs / a dedicated `server-fixture-...@example.com` email pattern, following current `GetTestSessionTestIDs` rather than stale fixed-ID examples.
- Regenerate API `gen/ntppool/auth/v1/auth.pb.go`, `gen/ntppool/auth/v1/authv1connect/auth.connect.go`, generated SQLC interfaces/models/wrappers and generated Perl output. Copy only resulting `Auth.pm` into web `lib/NP/CAPI/Auth.pm`, preserving generated bytes. Do not edit `ntpdb/otel.go` manually.

**Interfaces:** Consumes existing `createDefaultAccount`, `q.CreateUser`, `auth.MakeSessionKey(...).Save`, `database.WithTransaction` and service audience helpers. Produces exactly the protobuf contract above and fixture tables/queries; Task 2 consumes these without guessing endpoint names or response fields.

- [ ] **1. Add integration cases before handler implementation.** Follow `test_session_integration_test.go` for database setup and service contexts. Name root test `TestServerTestFixtureIntegration`. Use table-driven guard cases for both RPCs (production, test environment, absent audience, ordinary user). Initial test skeleton:

```go
resp, err := api.CreateServerTestFixture(capableCtx, connect.NewRequest(&authv1.CreateServerTestFixtureRequest{
    AttemptId: attemptID,
    Servers: []*authv1.ServerTestFixtureSpec{{IpVersion: 4, PendingVerification: true, Netspeed: 512}},
}))
require.NoError(t, err)
require.Equal(t, attemptID, resp.Msg.AttemptId)
require.Len(t, resp.Msg.Servers, 1)
require.NotEmpty(t, resp.Msg.SessionToken) // never print the token
require.NotEmpty(t, resp.Msg.Servers[0].VerificationToken)
```

Run `./scripts/test-integration ./server/api/auth 'TestServerTestFixtureIntegration'`; before generation/implementation this fails to compile, then guard/state assertions fail until implemented. Do not use inline TEST_DATABASE_URL commands.

- [ ] **2. Add schema, proto and SQL source.** Implement registry/tombstone, attempt lock, address allocation, fresh-user creation, fixture server inserts, verification inserts and scoped cleanup queries. SQLC generates the query methods. Keep create in one transaction. Generate a fresh unpredictable user email internally (`server-fixture-<attempt>-<random>@example.com`) and call `q.CreateUser` directly: do not call `ensureUserAndAccount` or `getOrCreateUserByEmail`, which may return an existing identity. On unique collision, roll back and fail instead of adopting that user. Call `createDefaultAccount` only for the newly inserted user and require its profile to be private. Create the session inside the same transaction.

```sql
-- Seed-specific insert; do not reuse InsertServer, which sets in_pool=1.
INSERT INTO servers (ip, ip_version, account_id, user_id, netspeed,
                     netspeed_target, in_pool, in_server_list, created_on, deletion_on)
VALUES (sqlc.arg(ip), sqlc.arg(ip_version), sqlc.arg(account_id), sqlc.arg(user_id),
        sqlc.arg(netspeed), sqlc.arg(netspeed), 0, 0, CURRENT_TIMESTAMP,
        sqlc.narg(deletion_on)) RETURNING *;
```

Validate UUID, 1..4 servers, versions, mutually exclusive verification flags and supported netspeeds (`0,512,1500,3000,6000,12000,25000,50000,100000,250000,500000,1000000,1500000,2000000,3000000`) before mutations. Return InvalidArgument for invalid input; guard denials remain PermissionDenied; cleanup of unknown/cleaned attempt succeeds with zero count and never creates a user/account.

- [ ] **3. Implement handlers and exact registration, then generate.** Add `CreateServerTestFixture` and `CleanupServerTestFixture` methods on auth.Server. Use the guards and durable transaction rules above. Route both generated procedure constants alongside `AuthServiceCreateTestSessionProcedure`. Run `make generate`; generation writes Perl under API `ntppool/`, so locate that generated Auth.pm and copy it to the web worktree, never through the canonical web checkout. Generated output does not authorize unrelated file churn.

- [ ] **4. Complete meaningful isolation tests.** Cover malformed/oversized requests; ordinary identity without staff; minted-session validation and account association; all four prerequisite states; netspeed and target equality; IPv4/IPv6 parallel uniqueness; private account; no DNS/monitor scheduling rows; repeat-create rejection; missing/duplicate cleanup; cleanup after discarded create response; cleanup-before-create tombstone; concurrent create/cleanup; cleanup after mutation and scheduled target plus two active unverified servers; cleanup after a new auth.Server instance (durability); rollback leaves no half-created fixture; unrelated server/log/email rows survive; moved server fails cleanup instead of deleting new ownership. Register teardown before create using attemptID. Use exact allocated rows for any deliberate corruption or rollback assertion; add no production fault hook.

- [ ] **5. Verify backend acceptance and commit reviewed task.** Run:

```sh
./scripts/test-integration ./server/api/auth 'TestServerTestFixtureIntegration|TestCreateTestSession'
./scripts/test-integration -count 2 ./server/api/auth 'TestServerTestFixtureIntegration'
go build ./server/api/auth ./server/api
```

Inspect monitor selection code available in related checkout(s), especially dependence on server_scores and servers_monitor_review. Document what the absence of those rows prevents and any residual discovery that may probe reserved addresses; do not claim `in_pool=0` alone disables monitoring. Capture required migration/API deployment revision in the task report. Commit source and generated API changes separately from web generated-client changes, using hooks.

## Task 2: Shared Playwright fixture and strict browser scenarios

**Files:**

- Modify web `e2e/lib/auth.ts`, `e2e/tests/server.spec.ts`.
- Create `e2e/lib/servers.ts`, `e2e/tests/server-verification.spec.ts`, `e2e/tests/server-deletion.spec.ts`, `e2e/tests/server-netspeed.spec.ts`, `e2e/tests/server-scores-context.spec.ts`.
- Add `e2e/tsconfig.json` and a local typecheck script/dependencies in `e2e/package.json`/lockfile if the suite has no installed TypeScript compiler. This is e2e configuration, not a client frontend change.
- Leave `e2e/tests/scores.spec.ts` public graph tests intact. New context specs use manage project and explicit public URLs for public assertions; no project matching changes are necessary.

**Interfaces:** Export `installSession(context: BrowserContext, sessionToken: string): Promise<void>` from auth.ts by factoring the current cookie installation out of `loginAs` (which keeps its existing signature). Export `connectRpc` or a narrowly wrapped bounded transport; add AbortSignal.timeout(15_000) without logging secrets. `servers.ts` exports `test`, `expect`, `ServerSeed`, `ServerFixture`, `serverDeleteUrl`, `getServer`, `getAccountAuditLogs` and the test fixture `serverFixtures`:

```ts
export interface ServerSeed {
  ipVersion: 4 | 6;
  verified?: boolean;
  pendingVerification?: boolean;
  scheduledDeletion?: boolean;
  netspeed?: number; // default 512; send explicit wire value
}
export interface FixtureServer {
  serverId: string; ip: string; ipVersion: 4 | 6;
  verificationToken: string; verified: boolean;
  deletionOn: string; netspeed: number;
}
export interface ServerFixture {
  attemptId: string; accountToken: string; accountId: string;
  userId: string; email: string; sessionToken: string;
  servers: FixtureServer[];
}
export interface ServerFixtures {
  create(seeds: ServerSeed[]): Promise<ServerFixture>;
}
// serverDeleteUrl(server: FixtureServer, accountToken: string): string
// getServer(sessionToken: string | undefined, accountToken: string | undefined,
//           ip: string, requireEditPermission?: boolean): Promise<ServerRead>
// getAccountAuditLogs(staffSession: string, accountToken: string): Promise<AuditLog[]>
```

`ServerRead` maps actual `ServerService.GetServer` fields: id, ip, netspeed, deletion_on, verification.verified, optional account (id_token, display_name, public_url, public_profile). `AuditLog` maps type, message, user.user_id/email, server.server_id/ip and account.account_token. Required response data must be runtime-validated without dumping secrets. Unknown RPCs/404/malformed responses fail setup clearly.

- [ ] **1. Implement shared fixture with registered cleanup.** Generate `randomUUID()` inside each create; push it synchronously to an attempt list before HTTP. Each test/retry owns a new fixture instance. Preserve response order and normalize protobuf default omissions (`verified=false`, empty deletion/token) explicitly. Teardown has its own 60-second Playwright fixture budget and cleans every registered attempt in reverse order; continue after a cleanup failure, attach only attempt/account/server IDs and preserve the original test failure. On otherwise passing test, throw cleanup failure.

```ts
const attempts: string[] = [];
const serverFixtures: ServerFixtures = {
  async create(seeds) {
    const attemptId = randomUUID();
    attempts.push(attemptId); // before any network call
    return createFixture(attemptId, seeds); // private mapper to exact RPC above
  },
};
await use(serverFixtures);
// In fixture teardown/finally: call CleanupServerTestFixture for every attempt;
// an unknown attempt is safe even when create failed before receiving a response.
```

Use `test.extend<{serverFixtures: ServerFixtures}>` and its fixture tuple `{timeout: 60_000}`. Expose no generic seed SQL or arbitrary update function. Use service credentials for fixture calls only; owner state reads and staff audit reads exercise current product authorization.

- [ ] **2. Write verification tests.** Each row below is an independent test with its own pending fixture unless stated. Form source: `docs/manage/tpl/manage/verify_confirm.html`; token route `/manage/server/verify/<token>`, inputs `a`, `server`, `auth_token`, `verify`. Successful submission redirects to the server anchor on `/manage/servers` through `manage_url`; assert actual POST 302 Location by request/response observation, then fresh authorized read.

| Exact test title | Required assertions |
|---|---|
| `pending verification redirects into the owner's account and completes` | Begin without a=; inspect initial 302 target account, visible IP and confirmation form; submit real form; observe POST redirect and verified read; revisit token and assert no completion form; separate staff audit read requires type=server, message=Server verified, owner user_id and target server_id/account token. |
| `invalid verification token is not found` | Authenticated valid account, random nonexistent token, exact 404. |
| `verification without CSRF is refused and stays pending` | Valid pending token with explicit owner a=, missing auth_token POST, 403, verified=false on fresh owner read. |
| `another account cannot complete the owner's verification` | Separate ordinary identity/account, valid CSRF from its own form, POST owner's token with outsider a=; current completion denial re-renders at 200; no success redirect, verified=false and no success audit. Do not demand token lookup itself be hidden. |

No arbitrary-text fallback: `verify_confirm.html` currently ignores `error_message`, so lack of rendered text is a product gap, not grounds to expect a nonexistent alert. The ownership assertion is denial/no redirect plus unchanged state, as specified.

- [ ] **3. Write independent deletion tests.** URL helper returns `/manage/server/delete?server=<encoded IP>&a=<account>`. Scope form by `form[action="/manage/server/delete"]`; hidden server is numeric ID. Date-picker `select[name="deletion_date"]`, schedule input `input[name="submitbtn"]`, cancel input `input[name="cancel_deletion"]`. Capture offered date, never invent a success date. Scheduled page renders human date (`%B %d, %Y`), so compare that exact formatted date and separately ISO date from GetServer.

| Exact test title | Required assertions |
|---|---|
| `scheduling deletion persists the selected date` | Verified unscheduled fixture; real form select/click; observed POST 302 and server/account Location; fresh delete page shows correct date, cancel and no picker; owner GetServer date equals submitted date; staff audit message `Deletion scheduled for <date>` with actor/server/account. |
| `cancelling deletion clears the scheduled date` | Independently seeded future deletion; real cancel; POST redirect; fresh read cleared date/picker restored; staff audit type=server and message prefix `Deletion cancelled by `, exact actor/server/account. |
| `API date validation is shown on the deletion picker` | Valid owned unscheduled fixture, auth and CSRF; request POST `deletion_date=2099-1-01`; response 200 contains `.alert.alert-danger[role="alert"]` with `invalid deletion_date format, expected YYYY-MM-DD`; picker remains and owner deletion_on stays empty. Parse the returned HTML in a disposable page for scoped DOM assertion; exclude devel banners. This is API validation coverage only. |
| `cancellation is denied with two active unverified servers` | Three seeded servers: scheduled target plus two unverified `deletion_on=NULL`; cancel with valid CSRF; exact destructive alert `Please verify active servers in the account first.`; date unchanged. Fixture cleanup still succeeds. |
| `deletion without CSRF is refused without mutation` | Owned editable server; POST future date without auth_token; 403 and unchanged date. |
| `another account cannot schedule the owner's server` | Fresh outsider context/account, its valid CSRF, POST owner's IP with outsider a=; exact 404 and unchanged owner read. |

Cross-account CSRF comes from a real own-account form; do not accidentally test only missing CSRF or nonexistent server. Signed-out login behavior can retain an exact separately named test but does not satisfy upstream-error coverage.

- [ ] **4. Write netspeed tests.** All target a valid owned server; fixture default starts both speed fields at 512, so increase to supported 1500 exceeds the effective current value. Fragment is `#server_<serverId>`, select `select[name="netspeed"]`, endpoint `/manage/server/update/netspeed`, fields auth_token/server/a/netspeed. Negative requests assert fresh state, not only returned text.

```ts
const fragment = page.locator(`#server_${server.serverId}`);
const oldElement = await fragment.elementHandle();
const responsePromise = page.waitForResponse(r =>
  new URL(r.url()).pathname === '/manage/server/update/netspeed' &&
  r.request().method() === 'POST');
await fragment.locator('select[name="netspeed"]').selectOption('1500');
const response = await responsePromise;
expect(response.request().headers()['hx-request']).toBe('true');
expect(response.status()).toBe(200);
expect(oldElement).not.toBeNull();
await expect.poll(() => oldElement!.evaluate(node => node.isConnected)).toBe(false);
await expect(page.locator(`#netspeed_${server.serverId}`)).toHaveText('1.5 Mbit');
```

This corrects the implementation example to match the existing UI: the
template resets the select to a placeholder after HTMX replacement and renders
the effective value in `#netspeed_<serverId>`. It does not change product
semantics.

Tests: `verified netspeed updates replace the HTMX fragment without navigation` (retain an old element handle and assert detached after swap; count main-frame navigation, then check fresh owner API/UI); `unverified netspeed increase shows the verification error and preserves speed` (higher select options are disabled, so craft authenticated HX-Request POST with valid CSRF instead of selecting disabled input; response fragment contains specific case-insensitive verification message and value 512; fresh read 512); `nonnumeric netspeed is rejected without mutation` (400, valid CSRF); `netspeed without CSRF is rejected without mutation` (403, numeric value); `non-HTMX netspeed update redirects and persists` (valid request, maxRedirects:0, exact 302 and Location pathname `/manage/servers`, then fresh UI with explicit a= and API value 1500). Do not assert netspeed_target changed: production UpdateServer updates netspeed; the guard compares max(current,target).

- [ ] **5. Write IPv6, staff context and visibility tests.** Use a verified IPv6 fixture, derive its expanded representation locally (no DNS), and assert expanded/compressed API lookups have identical IDs, expanded scores path 301 to canonical IP, canonical page 200 and displayed IP.

Tests: `IPv6 scores normalize to the canonical fixture address`; `staff scores edit targets the server's account from another active account`; `owner scores omit staff controls`; `unrelated scores omit private account details and staff controls`; `public scores omit private account details and staff controls`; `GetServer enforces private account visibility and edit permission`.

For staff test, mint a separate staff session, resolve its own different account first, then open target `/scores/<ip>?a=<staff-own-account>`. The correct edit request must contain target server IP and target account token; click `#server_header_section button[hx-get]` and inspect request plus returned hostname-edit form. Existing view lives in `docs/manage/tpl/admin/hostname_view.html` and points to `/manage/admin/hostname/edit`; inspect the actual returned edit template/controller for exact hidden fields. Do not satisfy this test by starting with target a= or merely checking button visibility.

For RPC visibility contract, use owner, outsider, staff and unauthenticated calls. Private account object must be present for owner/staff and omitted for unrelated/public readers; id_token/display_name/public_url within that private account object are the named sensitive details, not every server field. With require_edit_permission=true require success for owner/staff, NotFound for outsider, Unauthenticated for anonymous. Browser asserts private fixture account email/name and token absent from unrelated/public rendered account details, while canonical server IP remains visible. Public browser context receives no manage cookie. `Scores.pm::server_data` currently omits auth/account; retain expected staff/owner behavior and report failure rather than loosening assertions.

- [ ] **6. Replace old conditional coverage and verify static checks.** Keep only truthful clean add-form coverage in server.spec.ts. Remove TEST_IP/EXISTING_SERVER_IP, beforeAll/serial shared setup, permissive outcomes and skip paths. No test claims successful add/precheck/DNS. Add dedicated e2e tsconfig (`target ES2022`, `module NodeNext`, `moduleResolution NodeNext`, `strict`, `noEmit`, `skipLibCheck`, include lib/tests/config/setup). If NodeNext existing import conventions require adjustment, use `module ESNext`/`moduleResolution Bundler`, matching project TS conventions, without editing all unrelated specs.

```sh
npm run typecheck
npx playwright test --list
npx playwright test tests/server-verification.spec.ts tests/server-deletion.spec.ts tests/server-netspeed.spec.ts tests/server-scores-context.spec.ts --project=manage --retries=0
```

Live run requires Task 1 migration and API revision deployed. On Unimplemented/404 fixture RPC, report the exact deployment prerequisite as a validation blocker, never skip or mark scenarios passed. Review strict assertions and teardown before committing this web task.

## Task 3: Coverage accounting, deployment handoff and acceptance evidence

**Files:** Modify web `MANUAL_TEST_PLAN.md`, `e2e/README.md`, `e2e/.env.example`; create `e2e/COVERAGE_REPORT-2026-09-10-server-management.md`. Preserve historical `COVERAGE_REPORT-2026-09-09.md` and prior findings verbatim. Update a pre-existing remaining-failures document only with clearly dated additions.

**Interfaces:** Consumes committed Task 1 RPC/schema contract and Task 2 exact test titles. Produces a coverage matrix with implemented/unverified, live-passed, product-failing and deferred status, separate web/API SHAs, test counts, retries/skips and cleanup evidence. No new RPC or fixture abstraction in this task.

- [ ] **1. Update setup and scope documentation.** Remove obsolete NTP_SERVER_TEST_IP/NTP_EXISTING_SERVER_IP server-mutation configuration and incorrect fresh-account permission wording. Keep NTP_SCORES_TEST_IP for existing graph tests. Explain fixture devel/audience guard, migration deployment order, reserved address allocation, no-monitor-row behavior and any confirmed residual monitoring, inert retained identities, fixture tombstone cleanup and safe recovery by attempt ID. Keep service credentials/session tokens out of examples, reports and shell commands; use the existing environment variables in a small Node/TS recovery example that invokes CleanupServerTestFixture with just attempt_id and does not print request headers.

- [ ] **2. Replace manual checklist claims with exact references.** Map verification confirmation, schedule success, independent cancellation, date-format upstream rendering, two-active-unverified denial, CSRF/authz, HTMX and non-HTMX netspeed, IPv6 normalization, staff context and private account field omission to exact Task 2 titles. Mark implemented/unverified until corresponding live runs pass. Preserve unrelated prior evidence. Explicitly defer real add/hostname-add/re-add, successful UpdateServer DNS, external challenge acquisition, arbitrary downstream cancel failure, initial scores/review atomicity, audit rollback atomicity and exact RPC counts. State observed audit events do not prove transactions; DeleteServer remains best-effort/separate mutation-and-audit.

- [ ] **3. Run acceptance once, then again with fresh fixtures.** After matching fixture support is deployed, run focused suite with retries disabled, then repeat it. Keep default retries for ordinary suite usage but report retries independently. Verify no skips; collect per-run IDs and cleanup success without secrets. Also run preserved add-form and scores graph tests to catch address interference. Commands:

```sh
npm run typecheck
npx playwright test --list
npx playwright test tests/server.spec.ts tests/server-verification.spec.ts tests/server-deletion.spec.ts tests/server-netspeed.spec.ts tests/server-scores-context.spec.ts --project=manage --retries=0
npx playwright test tests/server-verification.spec.ts tests/server-deletion.spec.ts tests/server-netspeed.spec.ts tests/server-scores-context.spec.ts --project=manage --retries=0
npx playwright test tests/scores.spec.ts --project=web --retries=0
```

These are browser commands from web/e2e; backend commands remain Task 1's integration script and build. Deployment absence does not prevent code review/static validation, but live acceptance remains incomplete. Record product regressions with request status, non-secret target identifiers and specific unmet assertion; do not fix production semantics as part of documentation work.

- [ ] **4. Review evidence and commit documentation.** Require matching web/API source revision and fixture schema deployment in a live-passed claim. Report tests passed, failed, retried and skipped separately, plus teardown failures. Current baseline before implementation: existing clean add-form test passed live (1/1), Playwright discovery lists 82 tests, existing CreateTestSession integration test passed all five subtests through scripts/test-integration; these are baseline evidence only. Final report distinguishes code delivered, backend tests, live results and any precise remaining deployment/product blocker. Run `git diff --check` in both worktrees and commit reviewed documentation with hooks intact.
