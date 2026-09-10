# E2E manual-coverage expansion — Coverage Report (2026-09-09)

Task 9 of `docs/superpowers/plans/2026-09-09-e2e-manual-coverage.md`: validation
run and coverage report for the specs written/modified in Tasks 1-8. **No
product code was changed as part of this plan** (this task or any earlier
one) — Tasks 1-8 wrote/updated tests and docs only, and this task only ran
existing specs and read logs.

## 1. Checklist items now closed

This is a summary of `MANUAL_TEST_PLAN.md`'s current state as written by
Tasks 1-7, cross-checked against the runs in §3 below. All of the following
boxes are checked in the file and the linked test passed (at least once,
counting the built-in retry) in run-1 and/or run-2:

**§2 Account scheduled deletion / dissolve — frozen-account UI (fixed in #38):**
- As staff, the "Delete account" link is visible at the bottom of
  `/manage/account`.
- Non-staff member of a frozen account sees the red deletion banner
  (`account-frozen.spec.ts` → "a non-staff owner sees the deletion banner on
  a frozen account").
- Cancelling from that banner clears the deletion and restores edit access
  (`account-frozen.spec.ts` → "the owner cancels from the banner and the
  account is editable again").
- Staff on a frozen account see the "Account deletion scheduled — manage"
  link (`account-dissolve.spec.ts` → "staff: a frozen account still renders
  /manage/account with the scheduled-deletion link" — **not**
  `account-frozen.spec.ts`; see the known documentation inaccuracy below).
- A non-staff member's edit attempt on a frozen account is refused with the
  friendly message, not a raw API error (`account-frozen.spec.ts` → "a frozen
  account refuses a name edit from its non-staff owner").
- Staff get the same refusal on the same frozen account
  (`account-frozen.spec.ts` → "a frozen account refuses a name edit from
  staff too").

**Known minor documentation inaccuracy (not fixed, per the plan's narrow-editing
rule):** the §2 blockquote, written by Task 1 before Task 4 landed, says "All
four items below are automated in `e2e/tests/account-frozen.spec.ts`." One of
the four is actually in `account-dissolve.spec.ts` (the staff-manage-link
item, listed above). The overall claim — all four are automated — is true;
only the single-file attribution is imprecise.

**§4c Personal data download requests (issue #15):**
- `GET /manage/account/download` renders cleanly for a user with no prior
  requests, and submitting creates exactly one request via POST/redirect/GET
  (`account-download.spec.ts` → "a fresh user submits one personal data
  download request"). See §3 and §4 (defect 4) below: this test's
  no-error-state assertion passed in both runs only because the assertion
  window raced ahead of a backend task processor that is, as of this run,
  failing 100% of the time it actually runs.

**§5b Open-source claim vs staff determination (issue #39):**
- Submitting the open-source form with an empty justification is rejected
  and the zone stays New (`vendor.spec.ts` → "open-source submit with an
  empty justification is refused and the zone stays New").

**§13 Staff search (`int_api` → ConnectRPC, issue #43):**
- `id:<account-id>` exact-numeric lookup returns that account with its users
  (`staff-search.spec.ts` → "staff finds an account by exact numeric id:
  lookup").
- Free-text pattern search on an account-name substring
  (`staff-search.spec.ts` → "staff finds an account by a unique name
  substring").
- A no-match query renders cleanly, no error/404 (`staff-search.spec.ts` →
  "a no-match query replaces earlier results with the no-results message").
- An empty query clears results without an error (`staff-search.spec.ts` →
  "an empty query clears earlier results without an error").
- Non-staff users are denied (`staff-search.spec.ts` → "a non-staff user
  cannot reach staff search").

No regressions were found against these checked items — everything above ran
green (first attempt or on retry) in at least one focused run, and green in
**both** focused runs except where noted in §3. Nothing needs to be
unchecked.

## 2. Items still partially open

- **§4c download:** duplicate-POST suppression while a request is pending,
  the completed-archive download link, the mismatched-filename 404, and
  trace-ID log correlation all remain unchecked in `MANUAL_TEST_PLAN.md` —
  each needs a task held pending or force-completed on the backend, which is
  fixture blocker "Controlled download tasks" (§5). Independent of that
  fixture gap, this run found that the underlying archive-generation task is
  currently non-functional in this dev environment (see defect 4, §4) — so
  even with the fixture, "completed archive" scenarios cannot pass until
  that backend defect is fixed.
- **§5a/§5b/§5c/§5d/§5e vendor zones:** most rows are still unchecked
  (covered-vendor no-justification-form path, resubmitting a Rejected
  open-source zone, editing a Pending/Rejected open-source zone, the
  vendor-admin grant checkbox). Task 7 covered the empty-justification
  rejection and (elsewhere in the file, pre-existing) the admin
  editability/error-surfacing matrix; the whitespace-only-justification
  defect is deliberately left untested per policy (a test for it could only
  fail today — see defect 3).
- **§13 staff search:** IP lookup, hostname-substring pattern search with
  highlighting, "include deleted" toggle, `monitors:` search, and
  `zone:<zonename>` search remain unchecked — all need owned server/monitor
  fixtures (fixture blocker "Owned server fixtures" / "Monitor privileges and
  data", §5).
- **§4a/§4b invites and team removal:** partially covered; the items needing
  two real accepted members (removal side effects, self-removal-forbidden,
  accepted/expired invite states, the 3-in-24h resend cap) are `test.skip`
  in `account-team.spec.ts` and `invites.spec.ts`, pre-dating this plan, and
  remain skipped in run-existing (§3) — blocked on fixture "Invite
  acceptance and timing" (§5).

## 3. Test results

All three runs were executed from `/Users/ask/src/ntppool/e2e` with
`npx playwright test ... --project=manage --reporter=list`, output redirected
to `test-logs/*.log` (not piped through `grep`, so exit status was preserved).

### Focused run 1 (`test-logs/run-1.log`)

Command: `account-frozen`, `account-download`, `staff-search`, `vendor`,
`account-dissolve`, `staff-deletion` specs. Exit code **1**.

```
2 failed
  [manage] › tests/vendor.spec.ts:181:5 › open-source submit retains justification and edits without error
  [manage] › tests/vendor.spec.ts:672:7 › vendor admin & editability (§5a staff, §5c) › owner sees no edit on an Approved zone; edit URL is read-only
2 flaky
  [manage] › tests/account-frozen.spec.ts:149:5 › a non-staff owner sees the deletion banner on a frozen account
  [manage] › tests/vendor.spec.ts:135:5 › edit a New/Pending zone and persist a changed field
3 did not run
26 passed (47.4s)
```

33 tests total: 26 passed outright, 2 passed only after the built-in retry
(flaky), 2 failed on **both** the first attempt and the retry, and 3 "did not
run" — the remaining tests in the `vendor admin & editability` `describe`
block (`vendor.spec.ts:735`, `:825`, `:925`) are skipped by Playwright once an
earlier test in that serial block (`:672`) fails on both attempts.

All four failing/flaky-on-attempt-1 tests failed with the identical known
transient error:

```
Error: CreateTestSession failed: 500 Internal Server Error - {"code":"internal","message":"failed to create test session"}
    at mintSession (/Users/ask/src/ntppool/e2e/lib/auth.ts:90:11)
```

**Deviation from the plan's stated history worth flagging plainly:** the plan
says this flakiness "self-resolved every single time on Playwright's
automatic retry ... or a manual re-run" and "never failed to eventually
resolve." In run-1, two tests hit this 500 on **both** the initial attempt
and the single automatic retry (`retries: 1`), so it did *not* resolve within
this run — it took the full second manual run (run-2) to resolve. This is
still consistent with "not a defect in the features under test" (same error,
same code path, same dev-site session-minting endpoint, unrelated to
vendor/account-frozen logic) and with "it always resolves eventually," but
not with resolving inside a single `playwright test` invocation. Worth
knowing if CI ever runs this once and gates on it.

### Focused run 2 (`test-logs/run-2.log`)

Same command, fresh identities. Exit code **0**.

```
4 flaky
  [manage] › tests/account-download.spec.ts:39:5 › a fresh user submits one personal data download request
  [manage] › tests/account-frozen.spec.ts:204:5 › freezing one account leaves the owner's other account untouched
  [manage] › tests/account-frozen.spec.ts:291:5 › a frozen account refuses a name edit from staff too
  [manage] › tests/vendor.spec.ts:135:5 › edit a New/Pending zone and persist a changed field
29 passed (1.2m)
```

33 tests total: 29 passed outright, 4 flaky (passed on retry), 0 failed, 0
skipped. Three of the four flaky tests failed on attempt 1 with the same
`CreateTestSession failed: 500` error as run-1 — the known infra flakiness,
and this time it did resolve within the single automatic retry, matching the
plan's stated history.

**The fourth flaky test failed for a different, non-flakiness reason — full
detail, not papered over:** `account-download.spec.ts:39` ("a fresh user
submits one personal data download request") failed its first attempt with:

```
Error: the request should be pending or downloadable, never errored
Expected pattern: /Processing archive, check back later\.|Download archive/
Received string:  "Error: 66a9cd4c-5fb1-c423-0db1-2b99f2ef382e"
```

This is **not** the `CreateTestSession` error — it is a different assertion,
in a different test, with a different failure mode (the download-request
template rendered the task's real error state). This is the observed
manifestation of a newly-found defect, not one of the three pre-identified
ones. See defect 4 in §4 for the root cause, live evidence, and why the
retry passing does not mean the underlying bug resolved.

### Existing-spec run (`test-logs/run-existing.log`)

Command: `account-create`, `account-team`, `account-update`, `invites`,
`regression-smoke` specs. Exit code **0**.

```
1 flaky
  [manage] › tests/account-update.spec.ts:157:5 › reserved URL slug shows an error and is not saved
4 skipped
21 passed (17.0s)
```

27 tests total: 21 passed outright, 1 flaky (the same known
`CreateTestSession failed: 500` error, resolved on the automatic retry), 0
failed, 4 skipped. All 4 skips are pre-existing `test.skip()` calls unrelated
to Tasks 1-8's changes — `account-team.spec.ts` ("removing a second member
drops them from the team and notifies them", "a member cannot remove
themselves from a multi-member account") and `invites.spec.ts` ("exceeding 3
sends in 24h blocks resend with a limit warning", "accepted invite hides
Resend and the accept link still works"), each blocked on the same
"Invite acceptance and timing" fixture gap as §2 above. **No regression** was
found in `account-create.spec.ts`, `account-team.spec.ts`,
`account-update.spec.ts`, `invites.spec.ts`, or `regression-smoke.spec.ts`
attributable to Tasks 1-8's changes to the shared `e2e/lib/accounts.ts` or
`e2e/lib/auth.ts` — every non-skipped test in this run passed.

### Cleanup-failure check (Step 3)

```
--- test-logs/run-1.log
no cleanup failures recorded
--- test-logs/run-2.log
no cleanup failures recorded
```

Neither log contains `CLEANUP FAILED` or `cleanup-failure`. No frozen/
scheduled-deletion accounts were left behind by either run; nothing to
cancel by hand.

## 4. Product defects found

Per plan policy: assertions were left as written to characterize correct
behavior; no product code was changed. Defects 1-3 were already known
going into this task; defect 4 is new, found live during this validation
pass.

1. **`render_download` sets a create-failure error the template never
   renders.** `Account.pm:743-747` sets `$self->tpl_param('error', 'Failed
   to create download request. Please try again.')` on an API create
   failure, but `docs/manage/tpl/user/download.html` has no `[% error %]`
   output anywhere. A user whose create call fails sees a plain page with no
   indication anything went wrong. **Not triggered live** in any run in this
   task (or in Task 5's original run) — found by reading `Account.pm:743-747`
   against `download.html`, not by an observed failure.
2. **`render_download` swallows `list_user_tasks` errors into an empty
   list.** `Account.pm:722-726`: `if (!$result->{error} && ...)` means an API
   error on the GET path produces `$requests = []`, rendering identically to
   "no prior requests" rather than surfacing the failure. **Not triggered
   live** in any run in this task — found by code reading.
3. **A whitespace-only `opensource_info` passes vendor validation and
   submits the zone.** `Vendor.pm:388-397` tests `if (my $osinfo = ...)`,
   and a Perl string of only spaces is truthy, so `" "` is accepted as a
   valid justification. Per plan policy this was **not tested** — a test for
   it could only fail today, and the code already carries a
   `# todo: sanity check the data?` marking it known.
4. **NEW — the `download` background task fails 100% of the time it is
   processed, due to a MySQL-only SQL construct in a Postgres-backed query.**
   Observed live in run-2 (§3): `account-download.spec.ts`'s first attempt
   saw the request's state cell render `Error: 66a9cd4c-5fb1-c423-0db1-2b99f2ef382e`
   instead of "Processing..." or "Download archive." Cross-checking the
   `api-tasks` pod's own logs for that window confirms this is not a
   one-off:

   ```
   time=2026-09-10T04:48:58.573Z level=INFO  msg="processing task" id=155 task=download trace_id=6d98cef4e246f0c190f5b21fb80d315c
   time=2026-09-10T04:48:58.583Z level=ERROR msg="task error" id=155 task=download err="ERROR: type \"datetime\" does not exist (SQLSTATE 42704)" trace_id=6d98cef4e246f0c190f5b21fb80d315c
   time=2026-09-10T04:48:58.586Z level=INFO  msg="task completed" id=155 task=download state=failed trace_id=6d98cef4e246f0c190f5b21fb80d315c
   ```

   Over the 6 hours preceding this run, **every** `download` task the
   `api-tasks` pod (`api-tasks-8784bc47c-q8r49`) actually processed (9 of 9:
   ids 102, 103, 154, 155, 156, 157, 158, 168, 175) failed with the identical
   `SQLSTATE 42704: type "datetime" does not exist` error. Source, in the Go
   API repo (`../go/ntp/api`): `sql/user-archive.sql:10,27` —
   `cast(COALESCE(sv.verified_on, "2000-01-01 00:00:00") as datetime)
   verified_on` — MySQL's `datetime` cast, compiled by sqlc into
   `ntpdb/user-archive.sql.go`'s `GetServerVerificationHistoryByUserID`,
   which runs against a `pgx/v5` (PostgreSQL) connection where the type is
   `timestamp`, not `datetime`. This line is byte-identical on both the
   `main` and `origin/postgres` branches of that repo (`git diff main
   origin/postgres -- sql/user-archive.sql` is empty), so this is not a
   stale-build artifact — the fix has not landed on either branch.

   **Why the test still shows green most of the time:** the worker appears
   to process queued `download` tasks on a roughly-per-minute cadence, not
   synchronously on submission. `account-download.spec.ts`'s assertion
   window (10s after redirect) usually lands *before* the worker's next
   pass, so the row shows "Processing archive, check back later." (a
   passing, expected state) — this is what happened in run-1 and in run-2's
   successful retry. It only shows the real "Error: ..." outcome when the
   assertion happens to run *after* the worker's pass, which is what
   happened on run-2's first attempt. **The retry passing is not evidence
   the bug is intermittent or resolved** — it is a fresh identity's task
   that simply had not been picked up yet when the test finished checking.
   Given a 100% observed failure rate once a task is actually processed,
   this defect will keep resurfacing at this same test assertion depending
   on timing, and separately means the "personal data download" feature is
   currently non-functional end-to-end on this dev deployment (no user can
   successfully download their archive). This is unrelated to the
   `CreateTestSession` flakiness (different service — `api-tasks` vs. the
   session-minting endpoint) and unrelated to defects 1-3 above (which are
   Perl-side error-handling paths in `Account.pm`, not the underlying task's
   own SQL).

   No product code was changed to investigate or characterize this — the
   evidence above came from reading `api-tasks` pod logs (`kubectl logs`)
   and reading the Go API's `sql/user-archive.sql` / generated
   `ntpdb/user-archive.sql.go`, both read-only.

## 5. Fixture blockers

The deferred matrix is documentation only (per plan and design doc); no
placeholder tests exist for it and no owners are assigned. See:

- `docs/superpowers/specs/2026-09-09-e2e-manual-coverage-design.md`
  ("Requirements for later coverage" section, 7-row table) for what each
  fixture unlocks in terms of `MANUAL_TEST_PLAN.md` sections.
- `docs/superpowers/handoffs/2026-09-09-e2e-readiness-requirements.md`
  ("Requirements for later coverage" section, 8-row table — the same set
  plus "DNS output checks," which the design doc discusses in prose rather
  than as its own table row) for the "what we can settle now" / "ready when"
  detail per requirement.

All eight entries — invite acceptance/timing, controlled download tasks,
owned server fixtures, monitor privileges/data, subscription coverage
states, scoped upstream failures, observable email/audit side effects, and
DNS output checks — remain **deferred**, with **no owners assigned**, as of
this report. Section 2 above maps each still-open `MANUAL_TEST_PLAN.md` item
to the specific blocking row.

## 6. Environment

- **Date:** 2026-09-09 (validation runs executed 2026-09-10 early UTC, per
  pod log timestamps — local date at the time of the work was still
  2026-09-09).
- **Runner:** Playwright (`@playwright/test`), `--project=manage`, executed
  from `/Users/ask/src/ntppool/e2e` against the live dev site
  (`e2e/.env`'s `NTP_BASE_URL`/`NTP_MANAGE_URL`/`NTP_INTERNAL_API_URL`).
- **Deployment identifiers, rechecked (Step 1) against the handoff's
  recorded values:**

  | Component | Handoff (2026-09-09) | Observed (this run) | Match? |
  | --- | --- | --- | --- |
  | Web pod | `ntppool-5bd97ff76f-bf8c6`, image `ntppool-dev:bTkqIaz` | `ntppool-b5cdd5cb9-8hfmp`, image `harbor.ntppool.org/ntpdev/ntppool-dev:gVFmFEJ`, age 102m at check time | **Drifted** — new pod, new build. Consistent with the handoff's own note that a dev build was in progress when it recorded its baseline. |
  | Internal API pod | `api-internal-5b74b896f4-6x6ck`, image `api-dev:sha-3534d54a` | Same pod name `api-internal-5b74b896f4-6x6ck`, same image `harbor.ntppool.org/ntporg/api-dev:sha-3534d54a`, age 25d (not restarted) | **Match**, unchanged since the handoff. |

  Note: the plan's `kubectl ... -l app=api-internal` selector returns no
  results against this cluster — the pod's actual labels are
  `app.kubernetes.io/name=api,app.kubernetes.io/controller=internal`, not
  `app=api-internal`. Confirmed by pod name and labels directly
  (`kubectl get pod api-internal-5b74b896f4-6x6ck --show-labels`); this is a
  selector mismatch in the plan's command, not evidence of a missing or
  differently-scaled deployment.

  Because the web pod redeployed since the handoff's baseline, and Devspace
  syncs Perl source without necessarily restarting the pod, a full file-hash
  recheck (as the handoff did for `Account.pm`, `Vendor.pm`, etc.) was not
  repeated here since no test failed for a reason suggesting stale/mismatched
  source — all real failures traced to either the known session-minting
  flakiness or the newly-found Go-side SQL defect (§4, defect 4), neither of
  which a Perl file hash would explain.

## 7. Data left behind

Every test in the runs above mints a fresh identity/account per attempt
(`uniqueTestEmail()` and random account/vendor-zone names called inside the
test body, per Global Constraints), so all three runs together created on
the order of ~90 disposable users/accounts and several vendor zones on the
dev site. Per the agreed cleanup policy (handoff R4), this accumulation is
**acceptable**: Ask owns periodic cleanup of disposable dev-site data, with
a review due after two weeks of regular runs (around 2026-09-23).

**What must not be left behind — confirmed clean:** a scheduled deletion
stranded on a frozen account. Both `test-logs/run-1.log` and
`test-logs/run-2.log` were grepped for `CLEANUP FAILED|cleanup-failure` (§3)
and neither contains either string. `cleanupScheduledDeletion` verifies the
account is restored on a fresh read and fails an otherwise-passing test when
it cannot, so a clean grep across both logs is the actual evidence, not an
absence of failures alone. No accounts are left in a SCHEDULED-for-deletion
state by this task's runs, and nothing needs to be cancelled by hand.
