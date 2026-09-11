# Server management E2E coverage report (2026-09-10)

The fixture API and 21 browser scenarios are implemented, but the new browser
coverage hasn't passed live. The devel API returned HTTP 404 for
`CreateServerTestFixture`, so the run stopped in setup before any product
assertion. Migration 027 and the matching API deployment are still required.

## Revisions and deployment state

- API source: `b3e2b5ed76580c89f9c0db83a7abb251cf92951b`
  (`Guard server fixture schema by deployment`). Its Go migration 027 creates
  fixture tables only in devel and records a no-op in test and production. It
  passed local integration, build and unit checks. It hasn't been deployed to
  devel.
- Generated web client: `27091be29c4ed929c85be8f71d6a5f5a385cdfc4`
  (`feat(api): generate server fixture client methods`).
- Browser source: `5615a015b0cb88c4f6c486c756d897858c1eeb3e`
  (`Retain cleanup evidence for every server fixture`), including the
  21-scenario commit `d5d272a7` and subsequent assertion, selector and evidence
  fixes through `cc206692`.
- Live devel revision: not established as matching either source revision.
  The authenticated fixture procedure returned HTTP 404, and no live fixture
  row or server was created.
- Environment preflight: unit tests pass. Against the current live devel
  deployment, the API environment check passed and setup then stopped on the
  missing web environment header before minting a session. This is expected
  until the matching web revision is deployed.

A live-passed claim requires migration 027 on the devel database, API source
`b3e2b5e…`, and a web deployment containing generated client `27091be2…` plus
the `X-NTPPool-Environment` response header.
Run the final browser revision against those deployed components and record the
deployed SHAs with the result.

## Implementation decisions

| Decision | Reason | Cost if wrong |
| --- | --- | --- |
| Use isolated temporary worktrees without another permission question. | Implementation was already authorized, and isolation preserved the current checkouts. | Changes need transferring to a preferred location. |
| Exercise schedule API failure with a non-zero-padded date and defer arbitrary cancellation service-failure injection. | The existing validation boundary avoided a general fault framework. | This branch needs a scoped failure capability. |
| Keep real add/re-add/DNS infrastructure and audit atomicity as documented follow-ups. | The approved fixture-first slice had no candidate address infrastructure. | Those items need another implementation and deployment scope. |
| Implement Task 2 alongside Task 1 against the fixed shared RPC contract, then review and run acceptance after integration. | The edited files were disjoint, so this avoided idle waiting. | Interface corrections require browser rework; Task 3 remains dependent on both. |
| Await the old netspeed fragment's detachment and assert its rendered label instead of the plan's sample selected value. | The existing template resets the select to a placeholder, while the requirement is that the updated value is shown. | Selectors need changing if the UI presentation changes. |

## Status meanings

- **Implemented/unverified**: the test is typechecked and discovered, but no
  product assertion has passed against the live site.
- **Live-passed**: the assertion passed live against recorded matching web/API
  revisions and schema.
- **Product-failing**: fixture setup succeeded and a specific product assertion
  failed. There are no product-failing results in this run.
- **Deferred**: the design deliberately leaves the scenario for controlled
  DNS/NTP infrastructure or server-side instrumentation.

## New coverage matrix

All rows below are **implemented/unverified**. Exact titles are from the
committed Playwright specs.

| Area | Playwright title | What it requires |
| --- | --- | --- |
| Verification | `pending verification redirects into the owner's account and completes` | Owner redirect, confirmation form and POST, persisted verified state, exhausted token and correlated audit record |
| Verification | `invalid verification token is not found` | Invalid-token 404 |
| Verification | `verification without CSRF is refused and stays pending` | 403 and unchanged pending state |
| Verification | `another account cannot complete the owner's verification` | Cross-account refusal and unchanged owner state |
| Deletion | `scheduling deletion persists the selected date` | UI date, POST redirect, scheduled page state, persisted date and audit record |
| Deletion | `cancelling deletion clears the scheduled date` | Independent scheduled fixture, redirect, cleared state and audit record |
| Deletion | `API date validation is shown on the deletion picker` | Exact upstream `YYYY-MM-DD` error in the destructive alert and no mutation |
| Deletion | `cancellation is denied with two active unverified servers` | Exact permission message and unchanged scheduled date |
| Deletion | `deletion without CSRF is refused without mutation` | 403 and no mutation |
| Deletion | `another account cannot schedule the owner's server` | Valid-CSRF cross-account 404 and no owner mutation |
| Netspeed | `verified netspeed updates replace the HTMX fragment without navigation` | `HX-Request`, fragment replacement, no document navigation and persisted effective speed |
| Netspeed | `unverified netspeed increase shows the verification error and preserves speed` | Exact verification message and unchanged effective speed |
| Netspeed | `nonnumeric netspeed is rejected without mutation` | 400 and no mutation |
| Netspeed | `netspeed without CSRF is rejected without mutation` | 403 and no mutation |
| Netspeed | `non-HTMX netspeed update redirects and persists` | `/manage/servers` redirect and persisted effective speed |
| Scores/context | `IPv6 scores normalize to the canonical fixture address` | Expanded/compressed API identity and canonical scores redirect/render |
| Scores/context | `staff scores edit targets the server's account from another active account` | Staff request and returned edit form target the server account |
| Scores/context | `owner scores omit staff controls` | Ordinary owner doesn't get staff hostname controls |
| Scores/context | `unrelated scores omit private account details and staff controls` | Private account fields and staff controls omitted for unrelated account context |
| Scores/context | `public scores omit private account details and staff controls` | Private account fields and staff controls omitted on the public host |
| Scores/context | `GetServer enforces private account visibility and edit permission` | Owner/staff visibility, unrelated/public omission, and edit-required authorization |

The successful schedule, cancellation and verification scenarios observe audit
events and correlate actor, account and server. That observation doesn't prove
the mutation and audit are in one transaction. `DeleteServer` still performs
the deletion mutation and best-effort audit separately.

## Test evidence

### API fixture support

Task 1 ran these checks from the API worktree:

```sh
./scripts/test-integration ./server/api/auth 'TestServerTestFixtureIntegration|TestCreateTestSession'
./scripts/test-integration -count 2 ./server/api/auth 'TestServerTestFixtureIntegration'
go build ./server/api/auth ./server/api
go build ./...
go test ./...
```

The first integration run passed 13 fixture subtests and all 5 existing
CreateTestSession subtests. The repeat passed the 13 fixture subtests twice
with fresh attempts. There were no failed, retried or skipped subtests and no
cleanup warnings. Both builds and the full unit suite passed. These are local
backend results; they don't establish live deployment.

### Browser static checks and blocked live probe

`npm ci` installed the lockfile's dependencies in the isolated worktree without
changing the original checkout's symlink target. Plain `npm run typecheck`
then passed with that local compiler. Focused discovery found 21 tests in the
four new spec files, and full discovery found 98 tests in 20 files. Browser
source `12a33169…` passed typecheck, the same 21-test focused discovery and
`git diff --check`; its spec and quality re-review passed. The later selector
fixes through `cc206692` passed typecheck, `git diff --check` and commit hooks
without changing the 21 focused titles or 98-test full count. A synthetic
intentional failure submitted the real verification form with a runtime-only
sentinel token; the static console diagnostic and `test-results` contained no
sentinel.

At `cc206692`, a temporary live diagnostic logged in fresh users and acquired
CSRF from the exact authenticated add form used by both cross-account tests.
Before the selector fix, both cases failed because the old selector matched no
input. After the fix, both passed (2 passed in 4.9 seconds). The diagnostic
printed no session or CSRF value and disabled traces, screenshots and video.
It did not create a server fixture or execute either fixture-backed scenario;
it validates only the two real authenticated token-acquisition prerequisites.

The live probe used the focused specs with `--retries=0`, one worker and
`--max-failures=1`. Global setup passed. Its accounting is:

| Result | Passed | Failed | Retried | Skipped | Did not run | Cleanup succeeded | Cleanup failed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| New server-management probe | 0 | 1 setup failure | 0 | 0 | 20 | 0 | 1 |

The create call returned HTTP 404 before a fixture response, account ID or
server ID existed. The harness had registered the attempt UUID before network
I/O and attempted cleanup; `CleanupServerTestFixture` was also absent. Its
diagnostic contained the attempt ID with `account=unknown servers=unknown` and
no credential or session token. No acceptance run ID or successful cleanup can
be recorded until the RPCs are deployed. The failure is a deployment blocker,
not a server-management product result.

The final browser revision now attaches `server-fixture-cleanup-results` JSON
after every fixture teardown. Each registered attempt records only attempt,
account and server identifiers plus `succeeded` or `failed`; failed creates use
null for IDs that were never returned. A local fake-transport harness first
failed on the missing evidence, then passed all 3 scenarios after the fix. It
covered successful cleanups, failed creation with an existing test failure,
cleanup failure after a passing test body, reverse cleanup order, the 60-second
budget and secret exclusion. This local harness did not call the live fixture
API and does not change the blocked-run counts above.

The whole-branch final review found this missing success evidence as its sole
Minor issue. Scoped re-review of `5615a015…` passed both spec and quality with
no remaining Critical, Important or Minor findings. The approval is for
implemented/unverified coverage: it does not establish live fixture or browser
acceptance.

The two required fresh-fixture acceptance runs have not run. After deployment,
run the 21-test command twice without `--max-failures`, with `--retries=0`, and
record each run's attempt IDs, passed/failed/retried/skipped counts and cleanup
results.

### Preserved regressions

The pre-implementation clean add-form baseline passed live once. A first
current-branch regression check then failed because the test selector omitted
the existing form action's `#add` fragment; the authenticated page and product
form were correct. After correcting that selector in `5afb1328`, the same
command passed live in 2.7 seconds: 1 passed, 0 failed, 0 retried, 0 skipped and
no teardown failure. It proves a fresh user can open the server list and see
the add form; it doesn't exercise AddServerPrecheck or create a server.

This documentation task ran the unchanged public scores suite with:

```sh
npx playwright test tests/scores.spec.ts --project=web --retries=0
```

All 6 tests passed in 12.7 seconds: 6 passed, 0 failed, 0 retried, 0 skipped,
0 did not run and no teardown failure. This catches regressions in the existing
scores page and graph routes. No fixture existed during the run, so it doesn't
prove that reserved fixture addresses can't interfere with scores or monitoring.

The existing CreateTestSession integration baseline also passed all 5 subtests
as part of Task 1. Baseline results are kept separate from the new live coverage.

## Fixture operations and cleanup

The fixture methods require both `deployment_mode=devel` and the
`test-session-api` service audience. Each attempt creates its own ordinary user,
private account and at most four servers. Callers can't nominate an identity,
account, server or address. IPv4 allocations come from `198.51.100.1..254` and
`203.0.113.1..254`; IPv6 comes from `2001:db8::/32`. Allocation is locked and
checked against active reservations.

Fixture servers start outside publication and with no zones, score rows,
log-score rows or monitor-review rows. This keeps them out of normal selection
at creation. Source review found one residual path: a concurrent monitor-admin
status update to active/testing can seed score rows for every undeleted
same-family server, regardless of publication flags or zones. This is a source
observation, not a reproduced live failure. A strict no-probe test window needs
a quiesced devel monitor stack or verified egress policy.

Source review also identified an existing `Scores.pm::server_data` account-
context omission that may make the staff scores edit target the staff user's
active account instead of the fixture server's account. The test deliberately
requires the server account. Fixture setup never completed, so this remains a
source-level expectation rather than a reproduced product failure.

Cleanup uses the durable attempt registry, removes only its recorded servers
and their dependent data, and retains the generated user/account plus tombstone
as inert identities. It works independently of product cancellation, is
idempotent, and tombstones an unknown attempt so a delayed create can't race in
after recovery. `e2e/README.md` has the env-based recovery command; it sends
only `attempt_id` and prints no request headers or secrets.

## Deferred coverage

- Real IP add, hostname add and historical re-add through AddServerPrecheck.
- Successful hostname DNS validation through UpdateServer.
- External verification challenge acquisition over NTP infrastructure.
- Arbitrary downstream cancellation failure with otherwise-valid auth and
  server state.
- Atomic initial score/review creation and rollback on audit failure.
- Audit rollback atomicity for browser mutations.
- Exact outbound RPC counts.

These need disposable routable addresses, controlled DNS/NTP behavior, scoped
failure support or server-side instrumentation. The browser scenarios don't
stand in for them.

## Remaining acceptance work

1. Deploy API `b3e2b5e…` to devel and apply migration 027 with
   `deployment_mode=devel`.
2. Deploy the matching web generated client and final E2E revision.
3. Run typecheck and discovery, then the full focused command with
   `--retries=0` and no fail-fast limit.
4. Repeat the focused command with fresh fixtures.
5. Record matching deployed revisions, each attempt ID, cleanup result, and all
   pass/fail/retry/skip/teardown counts. Run the add-form and public scores
   regressions in the same acceptance window.

Until those steps complete, every new row in the matrix remains unchecked in
`MANUAL_TEST_PLAN.md`.
