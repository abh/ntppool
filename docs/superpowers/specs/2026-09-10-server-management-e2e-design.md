# Server management e2e coverage

Replace the conditional server tests with repeatable tests of verification
confirmation, scheduled deletion, netspeed, and permission-aware scores pages.
Provision each attempt's prerequisites through a guarded Go fixture API. Run
the operation under test through the real web application.

Ask approved the proposed coverage split and requested this design, a delegated
implementation plan, and implementation by sub-agents on 2026-09-10. No further
design or execution approval is required. This document is a specification,
not evidence of a live test run.

## Delivery boundary

This delivery includes the Go fixture support needed for browser tests of
existing owned servers, the Playwright tests, coverage accounting, and focused
verification. The related repositories are ntppool (web and e2e) and the sibling
Go API repository. Keep their changes and validation evidence separate.

The following remain explicit follow-ups rather than conditional tests:

- Real add, hostname-add, and historical re-add through precheck. These need
  disposable candidate addresses, controlled DNS, and monitor-api NTP checks.
  No suitable address allocation or infrastructure has been identified.
- Successful hostname DNS validation through UpdateServer. A nonexistent or
  mismatching hostname rejection can be tested separately when deterministic,
  but must not stand in for the successful DNS case.
- Verification challenge acquisition over the external verification/NTP
  infrastructure. This delivery starts with a pending verification token and
  exercises the real GetServerVerification and CompleteServerVerification paths.
- Atomic initialization of scores and review schedules, rollback on audit
  failure, and exact outbound RPC counts. These belong in Go integration or
  server-side instrumentation tests. Browser success proves none of them.

Do not weaken production IP/DNS/NTP validation or seed the final result of an
operation being tested. Product defects found by these tests need failing
evidence and an explicit report; do not change product semantics to obtain a
green run. Small corrections that restore the stated existing contract may be
proposed with that evidence, but unrelated product work is outside this scope.

## Existing contracts and corrections

- Tests live in e2e, separately from client. The manage and public hosts use
  different Playwright projects and host-scoped login cookies.
- CreateTestSession already creates fresh users and can grant support_staff.
  Use ordinary owners for ordinary mutations and a separate staff identity for
  staff UI. Always carry the target account token explicitly in a=.
- The existing server.spec.ts has best-effort skips and a serial setup that
  changes identities before deletion. Replace those stateful tests. Keep the
  useful clean add-form read with truthful coverage wording.
- Fresh accounts may add servers. can_add_servers becomes false when there
  are at least two active unverified servers, or when the account is frozen.
  Scheduled servers do not count as active in that verification query.
- The pending-token confirmation route is /manage/server/verify/<token>.
  The route without a token renders instructions. Treat the checklist's
  /verify shorthand and external challenge flow separately.
- AddServerPrecheck resolves hostnames during addition. UpdateServer validates
  an existing server's hostname; they are different operations.
- Netspeed resolves an editable server before checking CSRF and numeric input.
  Those negative tests therefore need a valid owned server.
- The API currently supplies the lowercase message "please verify your server
  before increasing the netspeed". Require that specific message, allowing
  capitalization differences in the UI; do not accept arbitrary error text.
- AuditService.GetAccountAuditLogs already supplies an authenticated read
  surface. Verify its fields and authorization before using it for assertions.
- DeleteServer currently writes its mutation and best-effort audit separately.
  The checklist's same-transaction claim is an unmet backend requirement.

## Fixture support

The planner must specify exact request/response types against the current Go
schema before implementation. Use a small test-only API following the
CreateTestSession deployment and service-capability checks. Generate clients
from proto if adding RPCs; do not hand-edit generated Perl or Go files.

Required fixture behavior:

1. Create a bounded set of server prerequisites for a fresh test-owned account.
   Return a fixture handle, account token, server IPs/IDs, and pending tokens.
   Supported states are verified, unverified, pending verification, and future
   scheduled deletion, with an explicit initial netspeed. Allocate IPv4 and
   IPv6 uniquely per attempt, including retries and parallel workers.
2. Authenticate fixture administration using the existing test service
   capability, and validate ownership through the fresh user's session or an
   equally strict association. No arbitrary existing account, IP, or server
   may be claimed or mutated. Refuse non-development deployments.
3. Keep fixtures outside public DNS publication and avoid contacting third
   party NTP servers. Reserved test addresses are appropriate for seeded
   records, subject to checking existing monitor selection behavior. Explicitly
   document any remaining devel monitoring of reserved fixture addresses.
4. Delete or restore only records owned by that fixture handle. Cleanup must
   work when normal cancellation is denied, remove scheduled deletions, be
   idempotent, and remain available after the test fails. Use transactional
   fixture writes and bounded cleanup; never expose arbitrary SQL to e2e.
5. Exercise schedule errors through the existing API validation path: Perl
   accepts a future non-zero-padded date such as 2099-1-01, whereas Go requires
   YYYY-MM-DD. Send an authenticated web POST with valid CSRF and assert the
   specific API date-format error. Verify this boundary in a live run before
   claiming upstream error coverage. Do not add fault injection, stop the
   shared API, or mock the web response in Playwright. Cancellation upstream
   failure under otherwise-valid prerequisites remains a follow-up requiring
   scoped failure support; ordinary permission denial is covered here.

Register cleanup before creating or mutating fixture state where possible;
use a client-generated attempt identifier so a lost create response does not
make cleanup impossible. Establish cleanup in a Playwright fixture with its
own teardown budget. Report failures with non-secret fixture/account/server
identifiers. A cleanup failure fails an otherwise passing test and never hides
the original failure. Never log session tokens, verification secrets, or the
service credential in diagnostic messages.

Keep the fixture capability small: no arbitrary clock control, general fault
framework, background worker hold, or public API bypass. A missing capability
must produce a clear setup failure, never test.skip.

## Browser scenarios

### Verification

- Open a pending token as its owner without a=. Observe the account-context
  redirect and assert the expected IP and confirmation form in that account.
- Submit the real confirmation form with its CSRF token. Observe the POST
  redirect and confirm verified state through a fresh UI or authorized API
  read. Revisit the link and confirm it no longer offers completion.
- Invalid token is not found. Missing CSRF on a valid pending token is 403 and
  leaves it pending. Another account cannot complete the owner's verification;
  assert the failure and unchanged owner state rather than forbidding the
  authenticated token lookup, which has a different authorization contract.
- Correlate a successful completion with its server audit event when the
  existing authorized audit response exposes the needed identifiers.

### Scheduled deletion

Use independent fixtures for scheduling and cancellation so one regression
does not prevent the other test from running.

- Schedule using a date offered by the UI. Capture the submitted date and
  actual POST redirect. Reopen the deletion page with the same account and
  assert that date, the cancel control, and absence of the date picker.
- Cancel a fixture with a future deletion. Capture the redirect and verify on
  a fresh read that the deletion date cleared and the picker returned.
- With a valid session, editable server and CSRF token, submit the future
  non-zero-padded date described above. Assert the API date-format error in a
  destructive alert on the picker page and unchanged persisted state. The
  assertion must exclude the dev banner. This covers validation-error
  presentation, not arbitrary service outages or authentication expiry.
- With a scheduled target plus two active unverified servers, attempt cancel.
  Assert "Please verify active servers in the account first." and unchanged
  deletion date. Fixture cleanup must not rely on this denied user operation.
- Missing CSRF and a valid-CSRF cross-account mutation are separate denials.
  Confirm the original owner's state is unchanged. Signed-out access is login
  enforcement, not evidence of downstream error rendering.
- Observe schedule/cancel audit events through an authorized read and correlate
  actor, target server and operation using fields the API actually provides.
  Do not call these observations proof of transaction atomicity.

### Netspeed

- Increase a verified server from a known value using its HTMX select. Observe
  HX-Request and replacement of that server's fragment, with no document
  navigation. Assert the new value in the fragment and on a fresh read.
- Increase an unverified server. Assert the specific verification message
  inline and the original effective netspeed in both fragment and fresh read.
- Send a nonnumeric value with valid CSRF to the owned server: HTTP 400 and no
  mutation. Send a numeric value without CSRF: HTTP 403 and no mutation.
- Send a valid update without HX-Request, with redirects disabled. Assert the
  actual redirect to /manage/servers and persistence after a fresh read.
- Use supported select values and account for netspeed_target when choosing
  an increase and checking effective state; do not compare only one database
  field when the API exposes the effective value.

### IPv6, scores and account context

- Expanded and compressed forms look up the same fixture. The scores page
  redirects to the canonical address and renders it.
- A staff identity starts in a different account, opens the target server's
  manage-host scores page, and opens an edit control. Assert the edit request
  targets the right server and account and returns the matching form. A
  button's presence alone is insufficient.
- Regular owners, unrelated users and public-host visitors lack staff edit
  controls. Publicly documented server data remains visible where intended.
- Check permission-aware GetServer field omission and require_edit_permission
  denial in Go integration tests or an authenticated RPC contract check. Name
  the sensitive fields based on the real response contract, rather than
  treating every account field as private. Browser tests additionally assert
  that private detail is absent from rendered output.

## Test organization and acceptance

Use a focused shared server fixture helper and separate specs for verification,
deletion, netspeed and scores context. Retain the existing public graph tests.
Use the existing auth/account helpers. Keep URLs, form fields and response
contracts grounded in current source and verify them against the dev deployment.

No shared mutable server, arbitrary environment-provided existing IP, serial
cross-test state, permissive success alternatives, fixed sleeps, or conditional
skips. Required assertions must fail on a product or fixture failure. Use
bounded request/DOM waits and x= cache busting for explicit dev navigations.

Run focused Go tests through scripts/test-integration, compile the changed Go
packages, typecheck/discover the Playwright suite, then run the new specs
against the configured devel hosts. Live acceptance requires deployed fixture
support and the matching web/API revisions. Re-run the focused browser suite
with fresh fixtures once to verify isolation and cleanup. Report failures,
retries and skips independently; a local test declaration is not live coverage.

Update MANUAL_TEST_PLAN.md and e2e documentation with exact test references.
Separate implemented/unverified, live-passed, and deferred items. Preserve
earlier evidence. Provide an environment handoff for undeployed capabilities
and external NTP/DNS infrastructure; do not mark those checklist items closed.

The implementation plan should distinguish code completion from deployment
readiness. If environment access prevents a live run, complete and review the
code and report the precise missing capability and validation still required.
