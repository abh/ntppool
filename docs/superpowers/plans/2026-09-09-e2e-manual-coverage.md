# E2E manual-coverage expansion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Playwright coverage for frozen-account self-service, personal data
download requests, staff search, and vendor open-source validation, and correct
the coverage claims in `MANUAL_TEST_PLAN.md` and `e2e/README.md`.

**Architecture:** Tests drive the real dev site through the browser. Identities
come from the existing `CreateTestSession` mint (`e2e/lib/auth.ts`); account
setup goes through the real UI. One new shared module (`e2e/lib/accounts.ts`)
holds the account operations more than one spec needs — scheduling, cancelling,
renaming, and resolving an account token. No new Go RPCs, no DB layer, no mocks.

**Tech Stack:** Playwright (`@playwright/test`), TypeScript, ConnectRPC dev
endpoint for session minting only.

**Spec:** `docs/superpowers/specs/2026-09-09-e2e-manual-coverage-design.md`

> **Execution note (added when running this plan via `/abh:execute-plan`):** per
> that skill's override, no per-task "Commit" step below is run individually —
> all work lands in a single commit at the end, after every task passes. Each
> task's "Commit" step checkbox is intentionally left unchecked for that
> reason; every other step checkbox reflects real, verified work.

**Environment readiness:** `docs/superpowers/handoffs/2026-09-09-e2e-readiness-requirements.md`
— R1-R3 and R5 verified live on 2026-09-09 against web pod
`ntppool-5bd97ff76f-bf8c6` and API pod `api-internal-5b74b896f4-6x6ck`. Read its
"Live readiness evidence" section before starting: it records the working
`e2e/.env`, the probes that already exercised each flow this plan tests, and the
deployment fingerprints to recheck.

## Global Constraints

- Every test-owned user, account name, and vendor zone name is unique **per
  attempt**. `uniqueTestEmail()` and any random-name generator must be called
  inside the test body, never at module scope — `playwright.config.ts` sets
  `retries: 1`, and a module-scope value is shared with the retry.
- Never mutate a real user's account or a shared server. Account context is
  always explicit through `a=<token>`.
- New tests fail on missing capabilities, failed setup, or unexpected
  application responses. They never convert those into `test.skip`.
- **This is characterization testing, not TDD.** The product code already
  exists, so a correctly written new test **passes on its first run**. A
  failure means either the test is wrong or the product is wrong. Weakening an
  assertion to make it pass is not a fix — see "Reporting product defects".
- Because a green e2e test can be green for the wrong reason (a selector that
  matches nothing, an `expect` on an empty locator set), every task includes an
  explicit **falsifiability check**: temporarily break the input and confirm the
  test fails for the stated reason. That check replaces the red step of a normal
  TDD cycle.
- Do not log session tokens or `NTP_TEST_SESSION_KEY` values.
- Trim trailing whitespace on edited lines; end files with a newline.
- Follow CLAUDE.md: no inline styles or inline JavaScript anywhere.

### Linking checklist items to tests

`MANUAL_TEST_PLAN.md` is updated **by the task that creates the test**, not in a
bulk pass at the end. Each of Tasks 1-7 checks off its own items and commits the
doc change alongside the spec, so the checklist is accurate at every commit
rather than only after the last one.

The link format is the spec path **and** the test name, so a reader can find the
assertion and knows the item needs no hand-testing:

```markdown
- [x] As a **non-staff member** of a frozen account, … (`e2e/tests/account-frozen.spec.ts` → "a non-staff owner sees the deletion banner on a frozen account")
```

Rules:

- A box gets checked only when a **live run passed** that assertion. Every task
  runs its spec before touching the doc, so the evidence exists by then.
- A test that exists but has not passed is labelled *implemented/unverified* and
  stays unchecked. A skipped test stays unchecked with its dependency named.
- Split any bullet that combines independently verifiable outcomes, and narrow
  any bullet the test only partly covers, rather than checking the whole thing.
- Existing entries in §5 and §6 carry a spec path but no test name. Upgrade
  those to the full form only in a section your task is already editing; do not
  make a separate pass over the file.
- Keep human visual judgment separate from DOM assertions.
- Do not rewrite historical failure reports (`e2e/FAILURE_TRIAGE.md`,
  `e2e/REMAINING_FAILURES.md`) as though they were current run evidence.

### Reporting product defects

Three defects are already known (details in the tasks that hit them). When a
test fails because the product is wrong:

1. Leave the assertion as written.
2. Record the failure — spec path, test name, the assertion, and the observed
   response — in the final report (Task 9).
3. Do not change product code as part of this plan.

### Conflict warning

Another session is working through the same requirements. `MANUAL_TEST_PLAN.md`,
`e2e/README.md`, `e2e/tests/invites.spec.ts`, and `e2e/tests/vendor.spec.ts`
are all in this plan's blast radius. Before editing any of them, run
`git status` and `git diff` on that file. If it already carries changes you did
not make, stop and ask rather than overwriting.

### Running the tests

```bash
cd e2e
npx playwright test tests/<spec>.spec.ts --project=manage --reporter=list
```

All new specs are authenticated `/manage` flows, so they run under the `manage`
project. `playwright.config.ts` routes anything not in `WEB_SPECS` there
automatically — no config change is needed for the new files.

Two notes from the readiness pass:

- The ignored `e2e/.env` already supplies all four required variables
  (`NTP_BASE_URL`, `NTP_MANAGE_URL`, `NTP_INTERNAL_API_URL`,
  `NTP_TEST_SESSION_KEY`) and the `global-setup.ts` preflight passed with them.
  Do not re-provision credentials, and never print `NTP_TEST_SESSION_KEY`.
- **Chromium will not launch inside a restrictive agent sandbox.** The readiness
  pass saw it fail at `MachPortRendezvousServer` with permission denied. Run
  Playwright unsandboxed.

On cache busting: `CLAUDE.local.md` requires an `x=<random>` query parameter on
dev-site URLs, so the new specs use the `bust()` helper (Task 1) on their
explicit navigations. A fresh browser context starts with an empty *browser*
cache, which says nothing about the CDN in front of the dev site — that is what
the rule is for. The 13 existing specs are unchanged; retrofitting them is out
of scope here, and if `bust()` proves worth having everywhere it belongs inside
`expectCleanPage` as a separate change.

Keep `bust()` at the navigation site. `accountFormUrl()` and `dissolveUrl()`
stay unbusted so they can still be used for `waitForURL` patterns and URL
comparisons.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `e2e/lib/accounts.ts` (new) | Account operations shared by more than one spec: resolve a user's default account token, rename an account, schedule/cancel a deletion as staff, check whether a deletion is pending, and clean up a scheduled deletion without masking a test failure. |
| `e2e/tests/account-frozen.spec.ts` (new) | §2 frozen-account behavior from the **non-staff owner's** side: banner, edit refusal (owner and staff), cancel-and-restore, and isolation from the owner's other account. |
| `e2e/tests/account-download.spec.ts` (new) | §4c personal data download request: clean first load, POST/redirect/GET, exactly one request. |
| `e2e/tests/staff-search.spec.ts` (new) | §13 staff search: account-name pattern match, no-match, empty query, non-staff denial. |
| `e2e/tests/vendor.spec.ts` (modify) | Add the §5b empty-justification refusal test next to the existing open-source tests. |
| `e2e/tests/account-dissolve.spec.ts` (modify) | Strengthen the existing staff pending-link assertion to check the link's target account and destination. |
| `e2e/tests/invites.spec.ts` (modify) | Rename two tests that claim more than they check. |
| `MANUAL_TEST_PLAN.md` (modify) | Updated by **each** of Tasks 1-7 for the section it covers — checking items off with a spec-and-test-name link — plus Task 8 for the corrections no new test covers. |
| `e2e/.gitignore` (modify) | Ignore `test-logs/`, where validation-run logs go (Playwright clears `test-results/`). |
| `e2e/README.md` (modify) | Remove the removed DB-assertion layer from the docs. |

---

## Task 1: Shared account helpers + frozen-account banner

**Files:**
- Create: `e2e/lib/accounts.ts`
- Create: `e2e/tests/account-frozen.spec.ts`
- Reference: `e2e/lib/helpers.ts`, `e2e/lib/auth.ts`, `e2e/tests/staff-deletion.spec.ts`

**Interfaces:**
- Consumes: `loginAs(context, email, opts)`, `uniqueTestEmail(prefix)` from
  `../lib/auth`; `expectCleanPage(page, path)`, `expectNoErrorBleed(page,
  label)`, `createAccount(page)` from `../lib/helpers`.
- Produces, from `e2e/lib/accounts.ts`:
  - `accountFormUrl(accountToken: string): string`
  - `dissolveUrl(accountToken: string): string`
  - `resolveDefaultAccountToken(page: Page): Promise<string>`
  - `renameAccount(page: Page, accountToken: string, newName: string): Promise<void>`
  - `uniqueAccountName(prefix?: string): string`
  - `scheduleAccountDeletion(staffPage: Page, accountToken: string): Promise<string>` — returns the rendered `YYYY-MM-DD` date
  - `deletionPending(staffPage: Page, accountToken: string): Promise<boolean>`
  - `cancelAccountDeletionAsStaff(staffPage: Page, accountToken: string): Promise<void>`
  - `cleanupScheduledDeletion(staffPage: Page, accountToken: string): Promise<Error | null>`
    — returns the failure instead of throwing, so a `finally` caller can fail an
    otherwise-passing test without masking an original failure
  - `bust(path: string): string`
- Produces, from `e2e/tests/account-frozen.spec.ts` (used by Tasks 2 and 3 in
  the same file): `setupFrozenAccount(browser: Browser, prefix: string): Promise<FrozenFixture>`
  and `interface FrozenFixture { ownerContext, ownerPage, staffContext, staffPage, accountToken, accountName, scheduledDate }`.

**Background the implementer needs:**

Scheduling an account deletion is staff-only; cancelling is not. `manage_dispatch`
in `lib/NTPPool/Control/Manage/Account.pm:250-261` allows any account member to
POST `cancel=1`. Once `deletion_on` is set, `permissions.can_edit` is false for
everyone including staff, and `/manage/account` is specifically excepted from
the redirect so the frozen page still renders (`Account.pm:163-177`).

The design's key insight, which removes the invite-helper dependency: the second
account created by `createAccount(page)` has its creator as sole member, so the
owner is a non-staff member of it **without any invite flow**. `_create_account`
(`Account.pm`) names a new account after the user's name, so rename it
explicitly to get a deterministic, unique name.

**Only the non-staff owner sees the red banner.** `docs/manage/tpl/account/form.html:3`
wraps it in `[% UNLESS combust.user_is_staff %]`; staff get the "Account
deletion scheduled — manage" link at `form.html:156-167` instead. Never assert
the banner for a staff identity.

- [x] **Step 1: Write `e2e/lib/accounts.ts`**

```typescript
import { Page, expect, test } from "@playwright/test";
import { expectNoErrorBleed } from "./helpers";

const ACCOUNT_PATH = "/manage/account";
const DISSOLVE_PATH = "/manage/account/dissolve";

/** Escape a string for safe inclusion in a RegExp (account tokens are alnum). */
function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Append a cache buster, per CLAUDE.local.md's dev-site guidance. A fresh
 * browser context starts with an empty browser cache but says nothing about
 * the CDN in front of the dev site, so explicit navigations carry `x=`.
 *
 * Keep this at the navigation site: accountFormUrl/dissolveUrl stay pure so
 * they can also be used for waitForURL patterns and URL comparisons.
 */
export function bust(path: string): string {
  const sep = path.includes("?") ? "&" : "?";
  return `${path}${sep}x=${Math.random().toString(36).slice(2, 10)}`;
}

/** The account edit form for an explicit account context. */
export function accountFormUrl(accountToken: string): string {
  return `${ACCOUNT_PATH}?a=${encodeURIComponent(accountToken)}`;
}

/** The dissolve (schedule/cancel deletion) page for an explicit account. */
export function dissolveUrl(accountToken: string): string {
  return `${DISSOLVE_PATH}?a=${encodeURIComponent(accountToken)}`;
}

/**
 * A fresh account name, unique per call so parallel runs and retries never
 * collide. Staff search matches on `a.name LIKE '%q%'` (api sql/search.sql
 * SearchAccountsByPattern), so the value doubles as a search needle.
 */
export function uniqueAccountName(prefix = "e2e-acct"): string {
  const rand = Math.random().toString(36).slice(2, 8);
  return `${prefix}-${Date.now()}-${rand}`;
}

/**
 * Resolve the logged-in user's default account id_token.
 *
 * mintSession returns only a session token, so read the account from where the
 * app itself puts it: Manage.pm routes a logged-in user from /manage to
 * /manage/servers?a=<accountToken>.
 */
export async function resolveDefaultAccountToken(page: Page): Promise<string> {
  const response = await page.goto(bust("/manage"));
  expect(response, "no response from /manage").not.toBeNull();
  expect(response!.status(), "unexpected status from /manage").toBe(200);

  const token = new URL(page.url()).searchParams.get("a");
  expect(
    token,
    `/manage should redirect to an account context: ${page.url()}`,
  ).toBeTruthy();
  return token!;
}

/**
 * Rename an account through the real edit form and confirm it persisted on a
 * fresh read (the controller re-renders the same form, so reading the response
 * alone would not prove a write).
 *
 * Selectors from docs/manage/tpl/account/form.html.
 */
export async function renameAccount(
  page: Page,
  accountToken: string,
  newName: string,
): Promise<void> {
  await page.goto(bust(accountFormUrl(accountToken)));
  const form = page.locator("#account-form");
  await expect(form, "account edit form not found").toBeVisible();

  await form.locator('input[name="name"]').fill(newName);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    form.locator('input[type="submit"][value="Update"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());

  await page.goto(bust(accountFormUrl(accountToken)));
  await expect(
    page.locator('#account-form input[name="name"]'),
    "account rename did not persist",
  ).toHaveValue(newName);
}

/**
 * Schedule an account's deletion as staff and return the rendered date.
 *
 * On success the controller redirects back to the dissolve page, which then
 * shows the pending state (dissolve_confirmation.html `[% ELSIF pending %]`).
 */
export async function scheduleAccountDeletion(
  staffPage: Page,
  accountToken: string,
): Promise<string> {
  await staffPage.goto(bust(dissolveUrl(accountToken)));
  await expect(
    staffPage.getByRole("heading", { name: /^Delete account:/ }),
    "dissolve confirmation page did not render",
  ).toBeVisible();

  await Promise.all([
    staffPage.waitForURL(
      new RegExp(`/manage/account/dissolve\\?a=${escapeRegExp(accountToken)}`),
    ),
    staffPage
      .getByRole("button", { name: "Schedule account deletion" })
      .click(),
  ]);
  await expectNoErrorBleed(staffPage, staffPage.url());

  await expect(
    staffPage.getByRole("button", { name: "Cancel scheduled deletion" }),
    "scheduling did not produce a pending state",
  ).toBeVisible();

  const body = await staffPage.content();
  const match = body.match(/scheduled for deletion on\s*<b>(\d{4}-\d{2}-\d{2})/);
  expect(
    match,
    "pending dissolve page should render the scheduled date",
  ).not.toBeNull();
  return match![1];
}

/**
 * Load the staff dissolve page and classify the account's deletion state.
 *
 * Throws unless the response is genuinely this account's dissolve confirmation.
 * A login page, an error page, or an unrecognised layout must NOT be read as
 * "no deletion scheduled" — that is how cleanup skips a still-frozen account
 * and then reports success.
 *
 * On a GET the confirmation renders exactly one of the two buttons (the
 * blockers branch only appears in a POST response), so anything else is an
 * unknown state worth refusing rather than guessing at.
 */
async function readDissolveState(
  staffPage: Page,
  accountToken: string,
): Promise<"pending" | "not-scheduled"> {
  const target = dissolveUrl(accountToken);
  const response = await staffPage.goto(bust(target));
  expect(response, `no response from ${target}`).not.toBeNull();
  expect(
    response!.status(),
    `unexpected status for the dissolve page of ${accountToken}`,
  ).toBe(200);

  // "Delete account: <name>" is the confirmation page's own heading. A login
  // page or an error page does not have it.
  await expect(
    staffPage.getByRole("heading", { name: /^Delete account:/ }),
    `not the dissolve confirmation page for ${accountToken}`,
  ).toBeVisible();

  const cancelButtons = await staffPage
    .getByRole("button", { name: "Cancel scheduled deletion" })
    .count();
  const scheduleButtons = await staffPage
    .getByRole("button", { name: "Schedule account deletion" })
    .count();

  if (cancelButtons === 1 && scheduleButtons === 0) return "pending";
  if (cancelButtons === 0 && scheduleButtons === 1) return "not-scheduled";

  throw new Error(
    `dissolve page for ${accountToken} is in an unrecognised state ` +
      `(cancel buttons: ${cancelButtons}, schedule buttons: ${scheduleButtons})`,
  );
}

/** True when the account currently has a scheduled deletion. */
export async function deletionPending(
  staffPage: Page,
  accountToken: string,
): Promise<boolean> {
  return (await readDissolveState(staffPage, accountToken)) === "pending";
}

/**
 * Cancel a scheduled deletion from the staff dissolve page, then confirm on a
 * FRESH read that it actually cleared. The redirect landing on /manage/account
 * is not evidence the write happened.
 */
export async function cancelAccountDeletionAsStaff(
  staffPage: Page,
  accountToken: string,
): Promise<void> {
  const before = await readDissolveState(staffPage, accountToken);
  if (before !== "pending") {
    throw new Error(
      `cannot cancel: ${accountToken} has no scheduled deletion to cancel`,
    );
  }

  await Promise.all([
    staffPage.waitForURL(/\/manage\/account(\?|$)/),
    staffPage
      .getByRole("button", { name: "Cancel scheduled deletion" })
      .click(),
  ]);
  await expectNoErrorBleed(staffPage, staffPage.url());

  const after = await readDissolveState(staffPage, accountToken);
  if (after !== "not-scheduled") {
    throw new Error(
      `cancel did not clear the scheduled deletion for ${accountToken}`,
    );
  }
}

/**
 * Teardown: cancel a still-pending deletion so no test leaves an account for
 * the purge worker to delete.
 *
 * Returns the error instead of throwing, so a `finally` caller can apply the
 * right policy: a cleanup failure must fail an otherwise-passing test, but it
 * must never replace an original failure. Returns null when there was nothing
 * to clean up, or when cleanup succeeded and was verified.
 *
 * The message carries the account token because the agreed cleanup policy
 * (readiness handoff R4) requires reporting it so the account can be cancelled
 * by hand.
 */
export async function cleanupScheduledDeletion(
  staffPage: Page,
  accountToken: string,
): Promise<Error | null> {
  try {
    if (await deletionPending(staffPage, accountToken)) {
      await cancelAccountDeletionAsStaff(staffPage, accountToken);
    }
    return null;
  } catch (err) {
    const error = new Error(
      `CLEANUP FAILED: account ${accountToken} may still be scheduled for ` +
        `deletion and needs manual cancellation — ${(err as Error).message}`,
    );
    console.error(error.message);
    test.info().annotations.push({
      type: "cleanup-failure",
      description: error.message,
    });
    return error;
  }
}
```

- [x] **Step 2: Write `e2e/tests/account-frozen.spec.ts` with the fixture and the first two tests**

Some imports and helpers here (`errorAlerts`, `expectNoErrorBleed`,
`dissolveUrl`) are used by the tests appended in Tasks 2 and 3, not by this
task's two tests. Leave them in — Playwright transpiles without typechecking, so
they are harmless, and removing them just means re-adding them next task.

```typescript
import { test, expect, Browser, BrowserContext, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  expectCleanPage,
  expectNoErrorBleed,
  createAccount,
  errorAlerts,
} from "../lib/helpers";
import {
  accountFormUrl,
  bust,
  cleanupScheduledDeletion,
  dissolveUrl,
  renameAccount,
  resolveDefaultAccountToken,
  scheduleAccountDeletion,
  uniqueAccountName,
} from "../lib/accounts";

// Frozen-account behavior from the NON-STAFF OWNER's side
// (MANUAL_TEST_PLAN.md §2, "Frozen-account UI", issue #38).
//
// account-dissolve.spec.ts covers the staff half. The four checklist items
// here need a non-staff *member* of a frozen account, which the plan
// previously assumed required an accept-invite helper. It does not: the second
// account from createAccount() has its creator as sole member, so the creator
// is already a non-staff member of it. A separate staff identity freezes that
// account; the owner never accepts an invitation.
//
// Product behavior this pins (lib/NTPPool/Control/Manage/Account.pm):
//   - :163-177  /manage/account is excepted from the can_edit redirect for a
//               frozen account, so the member's cancel banner is reachable.
//   - :184-194  a frozen-account edit POST is refused with a specific message
//               instead of a raw API error.
//   - :250-261  any member may POST cancel=1; scheduling stays staff-only.
//
// Template facts that shape the assertions:
//   - form.html:3   the red banner is inside [% UNLESS combust.user_is_staff %],
//                   so STAFF NEVER SEE IT. Only the owner asserts the banner.
//   - form.html:5   the banner is .alert-danger, and so is the edit-error alert
//                   (tpl/common/error_alert.html). Both would match a bare
//                   .alert-danger selector, so error assertions filter on the
//                   exact message text — the two strings differ:
//                     banner: "...scheduled for permanent deletion on"
//                     error:  "...scheduled for deletion and cannot be changed"
//   - form.html has no can_edit gate on the form itself, so the Update button
//     still renders while frozen. That is what makes the refusal testable.

const FROZEN_EDIT_ERROR =
  "This account is scheduled for deletion and cannot be changed. " +
  "Cancel the scheduled deletion first.";

// Two browser contexts, several round-trips against the live dev site, and a
// cancel cycle do not fit the 30s global timeout in playwright.config.ts.
test.describe.configure({ timeout: 120_000 });

interface FrozenFixture {
  ownerContext: BrowserContext;
  ownerPage: Page;
  staffContext: BrowserContext;
  staffPage: Page;
  /** The account to freeze; the owner is its sole, non-staff member. */
  accountToken: string;
  accountName: string;
  /** The owner's original account, which must stay untouched. */
  originalAccountToken: string;
}

/**
 * Build the frozen-account scenario UP TO but NOT INCLUDING the freeze: a
 * non-staff owner with two accounts, plus a separate staff identity.
 *
 * Scheduling deliberately does NOT happen here. Every caller schedules inside
 * its own try block, so the finally that cancels the deletion is already
 * registered before anything can leave an account frozen. If setup itself
 * scheduled, a failure between the schedule and the caller's try would strand
 * a frozen account with no cleanup path.
 *
 * Caller must call teardownFrozenAccount() in a finally.
 */
async function setupFrozenAccount(
  browser: Browser,
  prefix: string,
): Promise<FrozenFixture> {
  const ownerContext = await browser.newContext();
  let staffContext: BrowserContext | undefined;

  try {
    await loginAs(ownerContext, uniqueTestEmail(`${prefix}-owner`));
    const ownerPage = await ownerContext.newPage();

    // The owner's original account. Dissolution refuses to orphan a member, so
    // this one is what lets the second account be dissolved at all.
    const originalAccountToken = await resolveDefaultAccountToken(ownerPage);

    // The account to freeze, created and named through the real UI.
    const accountToken = await createAccount(ownerPage);
    const accountName = uniqueAccountName(`${prefix}-frozen`);
    await renameAccount(ownerPage, accountToken, accountName);

    staffContext = await browser.newContext();
    await loginAs(staffContext, uniqueTestEmail(`${prefix}-staff`), {
      grantStaff: true,
    });
    const staffPage = await staffContext.newPage();

    return {
      ownerContext,
      ownerPage,
      staffContext,
      staffPage,
      accountToken,
      accountName,
      originalAccountToken,
    };
  } catch (err) {
    // Nothing is scheduled yet, so there is no deletion to cancel — but the
    // contexts would otherwise leak.
    await ownerContext.close();
    if (staffContext) {
      await staffContext.close();
    }
    throw err;
  }
}

/**
 * Cancel anything the test scheduled, then close both contexts.
 *
 * `bodyFailed` decides what a cleanup failure means: when the test body
 * succeeded, a failed cleanup must fail the test (a leftover frozen account is
 * a real problem the run has to surface). When the body already failed, the
 * cleanup error is annotated but not thrown, so the original failure survives.
 */
async function teardownFrozenAccount(
  f: FrozenFixture,
  bodyFailed: boolean,
): Promise<void> {
  const cleanupError = await cleanupScheduledDeletion(f.staffPage, f.accountToken);

  await f.ownerContext.close();
  await f.staffContext.close();

  if (cleanupError && !bodyFailed) {
    throw cleanupError;
  }
}

test("a non-staff owner sees the deletion banner on a frozen account", async ({
  browser,
}) => {
  const f = await setupFrozenAccount(browser, "frozen-banner");
  let bodyFailed = false;

  try {
    // Freeze INSIDE the try: the finally that cancels it is already registered,
    // so a failure anywhere below still leaves the account restored.
    const scheduledDate = await scheduleAccountDeletion(
      f.staffPage,
      f.accountToken,
    );

    // #38: before the fix this redirected to /manage/ (can_edit is false on a
    // frozen account), so the member could never reach the cancel control.
    await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));

    const banner = f.ownerPage.locator(".alert-danger").filter({
      hasText: "Account scheduled for deletion",
    });
    // Locating on .alert-danger is itself the destructive-styling assertion:
    // if the banner were downgraded to a neutral notice this would not match.
    await expect(
      banner,
      "non-staff member should see the frozen-account banner",
    ).toBeVisible();

    // The banner names the scheduled date the API picked.
    await expect(banner).toContainText(scheduledDate);

    // ...and carries a cancel form scoped to THIS account.
    const cancelForm = banner.locator(
      'form[action*="/manage/account/dissolve"]',
    );
    await expect(cancelForm).toBeVisible();
    await expect(
      cancelForm.locator('input[name="a"]'),
      "cancel form must target the frozen account",
    ).toHaveValue(f.accountToken);
    await expect(
      cancelForm.locator('input[name="cancel"]'),
      "cancel form must carry cancel=1",
    ).toHaveValue("1");
    await expect(
      cancelForm.getByRole("button", { name: "Cancel scheduled deletion" }),
    ).toBeVisible();
  } catch (err) {
    bodyFailed = true;
    throw err;
  } finally {
    await teardownFrozenAccount(f, bodyFailed);
  }
});

test("freezing one account leaves the owner's other account untouched", async ({
  browser,
}) => {
  const f = await setupFrozenAccount(browser, "frozen-isolation");
  let bodyFailed = false;

  try {
    // Freeze INSIDE the try: the finally that cancels it is already registered,
    // so a failure anywhere below still leaves the account restored.
    await scheduleAccountDeletion(f.staffPage, f.accountToken);

    // The original account is unaffected: it loads, has no banner, and is
    // still editable.
    await expectCleanPage(
      f.ownerPage,
      bust(accountFormUrl(f.originalAccountToken)),
    );
    await expect(
      f.ownerPage
        .locator(".alert-danger")
        .filter({ hasText: "Account scheduled for deletion" }),
      "the owner's other account must not be marked for deletion",
    ).toHaveCount(0);

    const renamed = uniqueAccountName("frozen-isolation-ok");
    await renameAccount(f.ownerPage, f.originalAccountToken, renamed);

    // And the frozen account still carries its own, unchanged name.
    await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));
    await expect(
      f.ownerPage.locator('#account-form input[name="name"]'),
    ).toHaveValue(f.accountName);
  } catch (err) {
    bodyFailed = true;
    throw err;
  } finally {
    await teardownFrozenAccount(f, bodyFailed);
  }
});
```

- [x] **Step 3: Run the two tests**

Run:

```bash
cd e2e && npx playwright test tests/account-frozen.spec.ts --project=manage --reporter=list
```

Expected: 2 passed. These are characterization tests — the product already
behaves this way, so green on the first run is correct.

If the banner assertion fails with "expected visible, found 0", check first
whether the owner identity accidentally has staff privileges (it must be minted
without `grantStaff`), since `form.html:3` hides the banner from staff.

- [x] **Step 4: Falsifiability check**

The banner test's risk is that `.alert-danger` filtered by text silently matches
nothing and some other assertion carries the test. Prove it does not:

1. Change `hasText: "Account scheduled for deletion"` to
   `hasText: "Account scheduled for demolition"`.
2. Re-run. Expected: FAIL on `"non-staff member should see the frozen-account
   banner"` — not on a later line.
3. Revert the string.

- [x] **Step 5: Confirm no account was left frozen**

Cleanup now verifies its own result and fails an otherwise-passing test, so a
green run is the evidence. Capture the run so its exit status survives —
`playwright … | grep … || echo ok` reports success even when Playwright fails,
because grep simply finds nothing.

**Do not write logs into `test-results/`.** That is Playwright's `outputDir`,
and the runner clears it at the start of every run — it would unlink the log
being written and delete earlier runs'. Use `e2e/test-logs/`, created first and
added to `e2e/.gitignore`:

```bash
cd e2e
grep -qxF 'test-logs/' .gitignore || echo 'test-logs/' >> .gitignore
mkdir -p test-logs

npx playwright test tests/account-frozen.spec.ts --project=manage --reporter=list \
  > test-logs/frozen-run.log 2>&1
echo "playwright exit: $?"
grep -i "CLEANUP FAILED\|cleanup-failure" test-logs/frozen-run.log \
  && echo "^^ leftover frozen accounts — cancel them by hand" \
  || echo "no cleanup failures recorded"
```

Expected: `playwright exit: 0` **and** `no cleanup failures recorded`. A
non-zero exit means the run failed; read the log rather than the grep line.

- [x] **Step 6: Check off §2's banner item and add the linking convention**

In `MANUAL_TEST_PLAN.md`, add this to the intro bullets near the top (after the
"Test as both a regular logged-in user and a staff/admin user" line), so a
reader knows which items no longer need hand-testing:

```markdown
- Items marked with a spec path and test name — e.g. (`e2e/tests/foo.spec.ts` →
  "test name") — are covered by the automated Playwright suite in `e2e/` and
  need no manual run. Everything else is manual.
```

Then in **§2 → "Frozen-account UI (fixed in #38)"**, replace the last paragraph
of the blockquote. It currently reads:

```markdown
> The staff half is covered by `e2e/tests/account-dissolve.spec.ts`. The two
> non-staff items below are manual until the accept-invite helper in #46 lands —
> they need a second member on the account, invited *before* it is frozen.
```

That dependency does not exist. The owner of a second account is already a
non-staff member of it, so no invite is needed. Replace with:

```markdown
> All four items below are automated in `e2e/tests/account-frozen.spec.ts`,
> which pairs a non-staff owner with a separate staff identity. The owner's
> *second* account supplies the non-staff membership, so no accept-invite
> helper is needed (this section previously said otherwise, blocking on #46).
```

Then check off the first item:

```markdown
- [x] As a **non-staff member** of a frozen account, `/manage/account` renders and shows the red "Account scheduled for deletion" banner with the scheduled date. (`e2e/tests/account-frozen.spec.ts` → "a non-staff owner sees the deletion banner on a frozen account")
```

Leave the other three unchecked — Tasks 2, 3 and 4 check them as they land.

- [ ] **Step 7: Commit**

```bash
git add e2e/lib/accounts.ts e2e/tests/account-frozen.spec.ts e2e/.gitignore MANUAL_TEST_PLAN.md
git commit -m "test(e2e): cover the frozen-account banner for a non-staff owner"
```

---

## Task 2: Frozen account refuses edits, for owner and staff alike

**Files:**
- Modify: `e2e/tests/account-frozen.spec.ts` (append two tests)

**Interfaces:**
- Consumes: `setupFrozenAccount`, `teardownFrozenAccount`, `FrozenFixture`,
  `FROZEN_EDIT_ERROR` from Task 1; `scheduleAccountDeletion`, `bust`,
  `uniqueAccountName` from `../lib/accounts`.
- Produces: nothing new.

**Cleanup shape (same as Task 1, and required):** schedule inside the `try`,
set `bodyFailed = true` in a `catch` that rethrows, and call
`teardownFrozenAccount(f, bodyFailed)` in the `finally`. Never schedule before
the `try`.

**Background the implementer needs:**

`Account.pm:184-194` refuses the edit POST on a frozen account and sets
`tpl_param('error', ...)`, rendered by `tpl/common/error_alert.html` as an
`.alert-danger`. The Go API returns `FailedPrecondition` regardless; the Perl
message exists so the user sees a sentence instead of a raw API error.

**The refusal is an HTTP 200, not a 403.** The readiness pass crafted edit POSTs
with each identity's valid CSRF token and got 200 back from both owner and
staff, with a fresh GET still showing the original name. Assert unchanged state
and the message; do not add a status-code assertion — one would fail against
correct behavior.

One caveat that pass leaves open: it verified the name was unchanged, but not
that the specific message rendered. That assertion is read from
`Account.pm:191-193` and `error_alert.html`, not from a live probe. If the
message assertion is the only thing that fails here, treat it as new
information — check what the page actually rendered before assuming the
selector is wrong.

The owner's page has **two** `.alert-danger` blocks at this point (the deletion
banner and the edit error), so the assertion must filter on the exact message
text. Staff have only one, because staff never get the banner.

- [x] **Step 1: Append both tests to `e2e/tests/account-frozen.spec.ts`**

```typescript
test("a frozen account refuses a name edit from its non-staff owner", async ({
  browser,
}) => {
  const f = await setupFrozenAccount(browser, "frozen-edit-owner");
  let bodyFailed = false;

  try {
    // Freeze INSIDE the try: the finally that cancels it is already registered.
    await scheduleAccountDeletion(f.staffPage, f.accountToken);

    await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));

    // The form still renders while frozen (form.html has no can_edit gate),
    // which is exactly why the POST needs its own refusal.
    const form = f.ownerPage.locator("#account-form");
    await expect(form).toBeVisible();

    const attempted = uniqueAccountName("frozen-edit-attempt");
    await form.locator('input[name="name"]').fill(attempted);
    await Promise.all([
      f.ownerPage.waitForNavigation({ waitUntil: "load" }),
      form.locator('input[type="submit"][value="Update"]').click(),
    ]);
    await expectNoErrorBleed(f.ownerPage, f.ownerPage.url());

    // Filter on the exact message: the deletion banner is also .alert-danger
    // and must not be able to satisfy this assertion. The banner's text is
    // "...scheduled for permanent deletion on", which does not contain this.
    await expect(
      errorAlerts(f.ownerPage).filter({ hasText: FROZEN_EDIT_ERROR }),
      "frozen edit should render the specific refusal message",
    ).toBeVisible();

    // A fresh read proves nothing was written.
    await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));
    await expect(
      f.ownerPage.locator('#account-form input[name="name"]'),
      "the account name must be unchanged after a refused edit",
    ).toHaveValue(f.accountName);
  } catch (err) {
    bodyFailed = true;
    throw err;
  } finally {
    await teardownFrozenAccount(f, bodyFailed);
  }
});

test("a frozen account refuses a name edit from staff too", async ({
  browser,
}) => {
  const f = await setupFrozenAccount(browser, "frozen-edit-staff");
  let bodyFailed = false;

  try {
    // Freeze INSIDE the try: the finally that cancels it is already registered.
    await scheduleAccountDeletion(f.staffPage, f.accountToken);

    // Freezing removes can_edit for everyone: AccountWritable is
    // !deletion_on, with no staff exemption.
    await expectCleanPage(f.staffPage, bust(accountFormUrl(f.accountToken)));

    // Staff get the manage link, never the member banner (form.html:3 vs :156).
    await expect(
      f.staffPage
        .locator(".alert-danger")
        .filter({ hasText: "Account scheduled for deletion" }),
      "staff should not see the member cancel banner",
    ).toHaveCount(0);
    await expect(
      f.staffPage.locator("a.text-danger", {
        hasText: "Account deletion scheduled",
      }),
    ).toBeVisible();

    const form = f.staffPage.locator("#account-form");
    await expect(form).toBeVisible();

    const attempted = uniqueAccountName("frozen-staff-attempt");
    await form.locator('input[name="name"]').fill(attempted);
    await Promise.all([
      f.staffPage.waitForNavigation({ waitUntil: "load" }),
      form.locator('input[type="submit"][value="Update"]').click(),
    ]);
    await expectNoErrorBleed(f.staffPage, f.staffPage.url());

    await expect(
      errorAlerts(f.staffPage).filter({ hasText: FROZEN_EDIT_ERROR }),
      "frozen edit should be refused for staff with the same message",
    ).toBeVisible();

    await expectCleanPage(f.staffPage, bust(accountFormUrl(f.accountToken)));
    await expect(
      f.staffPage.locator('#account-form input[name="name"]'),
    ).toHaveValue(f.accountName);
  } catch (err) {
    bodyFailed = true;
    throw err;
  } finally {
    await teardownFrozenAccount(f, bodyFailed);
  }
});
```

- [x] **Step 2: Run the spec**

Run:

```bash
cd e2e && npx playwright test tests/account-frozen.spec.ts --project=manage --reporter=list
```

Expected: 4 passed.

- [x] **Step 3: Falsifiability check — prove the banner cannot satisfy the error assertion**

This is the assertion the design specifically warned about, so verify it
directly:

1. In the owner test, change `FROZEN_EDIT_ERROR` in the
   `errorAlerts(...).filter({ hasText: ... })` call to
   `"This account is scheduled for permanent deletion on"` (the **banner's**
   wording).
2. Re-run just that test:
   `npx playwright test tests/account-frozen.spec.ts --project=manage -g "non-staff owner" --reporter=list`
3. Expected: it still passes — that is the banner matching, and it is exactly
   the false positive being guarded against. This confirms the two strings are
   distinguishable and that the real assertion is the narrower one.
4. Revert to `FROZEN_EDIT_ERROR`.
5. Now change it to `"This account is scheduled for deletion and cannot be edited"`
   (wrong verb). Re-run. Expected: FAIL. Revert.

- [x] **Step 4: Split and check off §2's edit-refusal item**

That checklist bullet combines two independently verifiable outcomes (a member
is refused, and staff are refused), so split it. In `MANUAL_TEST_PLAN.md` §2,
replace:

```markdown
- [ ] A member of a frozen account still **cannot edit** it: submitting the account form shows "This account is scheduled for deletion and cannot be changed", not a raw API error.
```

with:

```markdown
- [x] A **member** of a frozen account still cannot edit it: submitting the account form shows "This account is scheduled for deletion and cannot be changed", not a raw API error. (`e2e/tests/account-frozen.spec.ts` → "a frozen account refuses a name edit from its non-staff owner")
- [x] **Staff** are refused the same edit with the same message — `can_edit` is false for everyone on a frozen account. (`e2e/tests/account-frozen.spec.ts` → "a frozen account refuses a name edit from staff too")
```

Both tests assert the message *and* that the name is unchanged on a fresh read,
so the bullets cover what they claim.

- [ ] **Step 5: Commit**

```bash
git add e2e/tests/account-frozen.spec.ts MANUAL_TEST_PLAN.md
git commit -m "test(e2e): cover frozen-account edit refusal for owner and staff"
```

---

## Task 3: Owner cancels from the banner and the account works again

**Files:**
- Modify: `e2e/tests/account-frozen.spec.ts` (append one test)

**Interfaces:**
- Consumes: `setupFrozenAccount`, `teardownFrozenAccount`, `FrozenFixture` from
  Task 1; `scheduleAccountDeletion`, `dissolveUrl`, `bust`, `renameAccount`,
  `uniqueAccountName` from `../lib/accounts`.
- Produces: nothing new.

**Cleanup shape:** identical to Tasks 1 and 2 — schedule inside the `try`,
`teardownFrozenAccount(f, bodyFailed)` in the `finally`.

**Background the implementer needs:**

The banner's cancel POST goes to `/manage/account/dissolve` with hidden `a=` and
`cancel=1`. `manage_dispatch` lets a non-staff member through on exactly that
shape (`Account.pm:250-261`), and `render_account_dissolve` redirects to
`/manage/account?a=<token>` on success.

After the cancel, the staff dissolve page has **no literal "cleared" string** —
it falls back to the scheduling form. So the assertion is: the "Schedule account
deletion" button is present and "scheduled for deletion on" is absent.

The final rename is the one assertion in this plan that depends on the account
context being re-read rather than cached. The cancel issues a redirect and the
rename issues a fresh `goto`, so each request re-runs `current_account`; if this
step fails with the frozen refusal message, that is a cache-invalidation defect
to report, not an assertion to relax.

- [x] **Step 1: Append the test to `e2e/tests/account-frozen.spec.ts`**

```typescript
test("the owner cancels from the banner and the account is editable again", async ({
  browser,
}) => {
  const f = await setupFrozenAccount(browser, "frozen-cancel");
  let bodyFailed = false;

  try {
    // Freeze INSIDE the try: the finally that cancels it is already registered.
    await scheduleAccountDeletion(f.staffPage, f.accountToken);

    await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));

    const banner = f.ownerPage.locator(".alert-danger").filter({
      hasText: "Account scheduled for deletion",
    });
    await expect(banner).toBeVisible();

    // Any member may cancel (Account.pm: $member_cancel), and the controller
    // redirects back to the account page on success.
    await Promise.all([
      f.ownerPage.waitForURL(/\/manage\/account(\?|$)/),
      banner
        .getByRole("button", { name: "Cancel scheduled deletion" })
        .click(),
    ]);
    await expectNoErrorBleed(f.ownerPage, f.ownerPage.url());

    // A fresh navigation, not just the redirect response, shows the banner gone.
    await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));
    await expect(
      f.ownerPage
        .locator(".alert-danger")
        .filter({ hasText: "Account scheduled for deletion" }),
      "the deletion banner should be gone after cancelling",
    ).toHaveCount(0);

    // The account is genuinely writable again, not merely un-bannered.
    const restoredName = uniqueAccountName("frozen-cancel-ok");
    await renameAccount(f.ownerPage, f.accountToken, restoredName);

    // ...and the staff view agrees: back to the scheduling form, no pending
    // state (dissolve_confirmation.html falls through to the [% ELSE %] branch).
    await expectCleanPage(f.staffPage, bust(dissolveUrl(f.accountToken)));
    await expect(
      f.staffPage.getByRole("button", { name: "Schedule account deletion" }),
      "staff dissolve page should offer scheduling again",
    ).toBeVisible();
    await expect(f.staffPage.locator("body")).not.toContainText(
      "scheduled for deletion on",
    );
    await expect(
      f.staffPage.getByRole("button", { name: "Cancel scheduled deletion" }),
    ).toHaveCount(0);
  } catch (err) {
    bodyFailed = true;
    throw err;
  } finally {
    // Already cancelled in the happy path, so this is a no-op then, and a real
    // cleanup if the test failed partway through.
    await teardownFrozenAccount(f, bodyFailed);
  }
});
```

- [x] **Step 2: Run the spec**

Run:

```bash
cd e2e && npx playwright test tests/account-frozen.spec.ts --project=manage --reporter=list
```

Expected: 5 passed.

- [x] **Step 3: Falsifiability check**

Confirm the post-cancel rename is really exercising a write:

1. In `renameAccount` (`e2e/lib/accounts.ts`), temporarily comment out the
   `form.locator('input[name="name"]').fill(newName);` line.
2. Re-run: `npx playwright test tests/account-frozen.spec.ts --project=manage -g "editable again" --reporter=list`
3. Expected: FAIL on `"account rename did not persist"`.
4. Restore the line.

- [x] **Step 4: Check off §2's banner-cancel item**

In `MANUAL_TEST_PLAN.md` §2, replace:

```markdown
- [ ] Clicking **Cancel scheduled deletion** in that banner clears the deletion and returns the account to normal.
```

with:

```markdown
- [x] Clicking **Cancel scheduled deletion** in that banner clears the deletion and returns the account to normal — the account is editable again, and the staff dissolve page offers scheduling once more. (`e2e/tests/account-frozen.spec.ts` → "the owner cancels from the banner and the account is editable again")
```

- [ ] **Step 5: Commit**

```bash
git add e2e/tests/account-frozen.spec.ts MANUAL_TEST_PLAN.md
git commit -m "test(e2e): cover member cancel of a scheduled account deletion"
```

---

## Task 4: Protect and strengthen the existing deletion tests

**Files:**
- Modify: `e2e/tests/account-dissolve.spec.ts:178-212` (the test
  `"staff: a frozen account still renders /manage/account with the scheduled-deletion link"`)
- Modify: `e2e/tests/staff-deletion.spec.ts:232-289` (the test
  `"staff schedules another ACCOUNT's deletion, scoped to that account"`)

**Interfaces:**
- Consumes: `cleanupScheduledDeletion` from `../lib/accounts` (Task 1).
- Produces: nothing new.

**Why this task exists at all.**

Two existing tests schedule an account deletion and cancel it — or don't — only
on the happy path, outside any `finally`:

- `account-dissolve.spec.ts` cancels at the very end. Step 3 of this task
  *deliberately breaks an assertion above that line*, so every run of the
  falsifiability check strands a frozen account.
- `staff-deletion.spec.ts` never cancels at all, and Task 9 runs it twice.

The agreed cleanup policy (readiness handoff R4) says tests must cancel every
deletion they schedule, *including when a test fails*. It grants no exemption
for pre-existing tests, and this plan is what executes them. So cleanup goes in
first, before anything is deliberately failed.

Note `account-dissolve.spec.ts` already has a local `const dissolveUrl` inside
that test. Import only `cleanupScheduledDeletion`, not the module's
`dissolveUrl`, or the local will shadow it confusingly.

**Background for the assertion change:**

The existing test asserts the "Account deletion scheduled — manage" link is
visible but never checks where it points. `form.html:159-161` renders it as
`manage_url('/manage/account/dissolve', { a => account.id_token })`, so the
href must carry both the dissolve path and the frozen account's token. A link
pointing at the wrong account would pass the current assertion.

`combust.manage_url` produces an absolute URL on the manage host, so match on
substrings rather than an exact value.

Check `git status e2e/tests/account-dissolve.spec.ts` before editing — see the
conflict warning in Global Constraints.

- [x] **Step 1: Wrap the account-dissolve schedule/cancel cycle in cleanup**

In `e2e/tests/account-dissolve.spec.ts`, add the import:

```typescript
import { cleanupScheduledDeletion } from "../lib/accounts";
```

Then, in `"staff: schedule, see pending state, then cancel back to normal"`,
move everything from `await scheduleDeletion(page);` onward into a `try`. The
existing mid-test `await cancelDeletion(page);` stays exactly where it is — the
`finally` is a no-op on the happy path, and a real cleanup when any assertion
before *or after* that cancel fails:

```typescript
  await expectCleanPage(page, dissolveUrl);

  let bodyFailed = false;
  try {
    await scheduleDeletion(page);

    // ...existing pending-state assertions, the existing cancelDeletion(page)
    // call, and the existing post-cancel assertions, all unchanged...
  } catch (err) {
    bodyFailed = true;
    throw err;
  } finally {
    const cleanupError = await cleanupScheduledDeletion(page, acct);
    if (cleanupError && !bodyFailed) {
      throw cleanupError;
    }
  }
```

- [x] **Step 2: Wrap the account-dissolve frozen test in cleanup**

In the same file, in `"staff: a frozen account still renders /manage/account
with the scheduled-deletion link"`, move everything from
`await scheduleDeletion(page);` onward into a `try`, and replace the trailing
manual cancel:

```typescript
  await expectCleanPage(page, dissolveUrl);

  let bodyFailed = false;
  try {
    await scheduleDeletion(page);

    // ...existing assertions, unchanged...
  } catch (err) {
    bodyFailed = true;
    throw err;
  } finally {
    // Replaces the old trailing "Don't leave the account frozen" cancel, which
    // never ran when an assertion above it failed.
    const cleanupError = await cleanupScheduledDeletion(page, acct);
    if (cleanupError && !bodyFailed) {
      throw cleanupError;
    }
  }
```

Delete the old final two lines (`await expectCleanPage(page, dissolveUrl);` and
`await cancelDeletion(page);`) — `cleanupScheduledDeletion` does both, and
verifies the result.

- [x] **Step 3: Add cleanup to the staff-deletion account test**

In `e2e/tests/staff-deletion.spec.ts`, add the same import, then in
`"staff schedules another ACCOUNT's deletion, scoped to that account"`:

1. Hoist the account token so the `finally` can see it, and add the failure
   flag. The token is currently declared inside the `try` at line 240:

```typescript
  let dissolveAcct: string | undefined;
  let bodyFailed = false;
  try {
    const targetPage = await targetContext.newPage();
    dissolveAcct = await createAccount(targetPage);
    await targetPage.close();
```

   (Remove the `const` from the existing assignment; leave every following use
   of `dissolveAcct` as it is.)

2. Extend the existing `finally`, which currently only closes the context:

```typescript
  } catch (err) {
    bodyFailed = true;
    throw err;
  } finally {
    // This test asserts the pending state, then must not leave it pending.
    let cleanupError: Error | null = null;
    if (dissolveAcct) {
      cleanupError = await cleanupScheduledDeletion(page, dissolveAcct);
    }
    await targetContext.close();
    if (cleanupError && !bodyFailed) {
      throw cleanupError;
    }
  }
```

   Declare `let bodyFailed = false;` next to `dissolveAcct`, above the `try`.

   `page` here is the staff context, which is what cleanup needs. Use the same
   `bodyFailed` handling as every other test in this plan: preserve an existing
   failure, but fail an otherwise-green test when cancellation fails. A silently
   swallowed cleanup error is exactly the "green test, stranded account" case
   the policy exists to prevent.

- [x] **Step 4: Verify all three still pass before changing anything else**

Run:

```bash
cd e2e && npx playwright test tests/account-dissolve.spec.ts tests/staff-deletion.spec.ts --project=manage --reporter=list
```

Expected: all pass. Cleanup is now in place, so the deliberate failure in
Step 5 will not strand an account.

- [x] **Step 5: Replace the link assertion**

Find this block:

```typescript
  await expect(
    page.locator("a.text-danger", {
      hasText: "Account deletion scheduled",
    }),
  ).toBeVisible();
```

Replace it with:

```typescript
  const pendingLink = page.locator("a.text-danger", {
    hasText: "Account deletion scheduled",
  });
  await expect(pendingLink).toBeVisible();

  // The link must point at the dissolve page FOR THIS ACCOUNT. Asserting only
  // that a link is visible would pass even if it targeted a different account
  // (form.html:159-161 builds it from account.id_token).
  const pendingHref = await pendingLink.getAttribute("href");
  expect(pendingHref, "pending-deletion link should have an href").toBeTruthy();
  const pendingUrl = new URL(pendingHref!, page.url());
  expect(
    pendingUrl.pathname,
    `pending-deletion link should go to the dissolve page: ${pendingHref}`,
  ).toBe("/manage/account/dissolve");
  expect(
    pendingUrl.searchParams.get("a"),
    `pending-deletion link should target the frozen account: ${pendingHref}`,
  ).toBe(acct);
```

- [x] **Step 6: Run the spec**

Run:

```bash
cd e2e && npx playwright test tests/account-dissolve.spec.ts --project=manage --reporter=list
```

Expected: all tests in the file pass (5 at time of writing).

- [x] **Step 7: Falsifiability check**

Cleanup is now in a `finally`, so this deliberate failure restores the account
instead of stranding it. Confirm that in the output.

1. Change the final `.toBe(acct)` to `.toBe(acct + "x")`.
2. Re-run that test. Expected: FAIL on `"pending-deletion link should target
   the frozen account"`.
3. Revert.

- [x] **Step 8: Check off §2's staff pending-link item**

In `MANUAL_TEST_PLAN.md` §2, replace:

```markdown
- [ ] As **staff** on a frozen account, `/manage/account` renders and shows the "Account deletion scheduled — manage" link pointing at the dissolve page.
```

with:

```markdown
- [x] As **staff** on a frozen account, `/manage/account` renders and shows the "Account deletion scheduled — manage" link, pointing at the dissolve page for that account. (`e2e/tests/account-dissolve.spec.ts` → "staff: a frozen account still renders /manage/account with the scheduled-deletion link")
```

This completes §2's frozen-account block — all four items are now automated.

- [ ] **Step 9: Commit**

```bash
git add e2e/tests/account-dissolve.spec.ts e2e/tests/staff-deletion.spec.ts MANUAL_TEST_PLAN.md
git commit -m "test(e2e): cancel scheduled deletions on failure and pin the pending link"
```

---

## Task 5: Personal data download request

**Files:**
- Create: `e2e/tests/account-download.spec.ts`

**Interfaces:**
- Consumes: `loginAs`, `uniqueTestEmail` from `../lib/auth`; `expectCleanPage`,
  `expectNoErrorBleed`, `errorAlerts` from `../lib/helpers`; `bust` from
  `../lib/accounts` (Task 1).
- Produces: nothing new.

**Background the implementer needs:**

`render_download` (`lib/NTPPool/Control/Manage/Account.pm:693-754`):

- GET lists the user's `download` tasks via `list_user_tasks`.
- A POST creates a task **only when no request is pending**, then redirects to
  `/manage/account/download` (POST/redirect/GET).
- The form (`docs/manage/tpl/user/download.html`) is hidden entirely once
  `pending_requests` is set, so a duplicate POST cannot be produced through the
  UI at all. That case is deferred by the design and is not tested here.

**Two known product defects live in this handler. Do not work around them:**

1. `Account.pm:743-747` sets `tpl_param('error', 'Failed to create download
   request. Please try again.')`, but `download.html` has no error output and
   no `PROCESS tpl/common/error_alert.html`. A failed create renders a blank
   page with no message.
2. `Account.pm:722-726` swallows `list_user_tasks` errors — on failure the page
   renders an empty list with no indication.

Together these mean an API failure shows up as "the row is missing", not as an
error. If this test fails on the row-count assertion with no visible error,
that is the symptom; report it (Task 9) rather than relaxing the count.

(`request_submitted` in the template is dead — the controller never sets it.
Do not assert on it.)

- [x] **Step 1: Write `e2e/tests/account-download.spec.ts`**

```typescript
import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  expectCleanPage,
  expectNoErrorBleed,
  errorAlerts,
} from "../lib/helpers";
import { bust } from "../lib/accounts";

// Personal data download requests (MANUAL_TEST_PLAN.md §4c, issue #15).
//
// Controller: lib/NTPPool/Control/Manage/Account.pm render_download (:693-754).
//   GET  /manage/account/download   lists the user's `download` tasks.
//   POST /manage/account/download   creates a task when none is pending, then
//                                   redirects back (POST/redirect/GET).
//
// Template: docs/manage/tpl/user/download.html
//   - <h3>[% user.email %]</h3>
//   - the request list is a bare <table> of <tr><td>created_on</td><td>state</td>
//   - the request form (#download-form) is hidden once a request is pending
//   - a failed task renders "Error: <traceid>" in the state cell
//
// NOT covered here (deferred by the design; each needs a task held pending or
// completed on the backend): duplicate-POST suppression, archive contents,
// download delivery, filename validation, worker-log correlation.

const DOWNLOAD_PATH = "/manage/account/download";

/**
 * Rows of the request list. Scoped away from the audit-log table (#logs) that
 * other manage pages include, so a layout change there cannot inflate the count.
 */
function requestRows(page: Page) {
  return page
    .locator("table:not(#logs) tr")
    .filter({ has: page.locator("td") });
}

test("a fresh user submits one personal data download request", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("download-req");
  await loginAs(context, email);

  // --- First load: identity, an enabled form, and nothing left over ---------
  await expectCleanPage(page, bust(DOWNLOAD_PATH));
  await expect(
    page.getByRole("heading", { name: email }),
    "the download page should name the requesting user",
  ).toBeVisible();

  await expect(requestRows(page), "a fresh user has no prior requests").toHaveCount(
    0,
  );
  await expect(errorAlerts(page), "no error bleed on first load").toHaveCount(0);

  const submit = page.locator('#download-form button[type="submit"]');
  await expect(submit, "the request form should be offered").toBeVisible();
  await expect(submit).toBeEnabled();

  // --- Submit: a real POST, a real redirect, then a GET --------------------
  // Landing on a 200 page proves nothing on its own, so observe the POST
  // response and its Location header directly.
  const [postResponse] = await Promise.all([
    page.waitForResponse(
      (r) =>
        r.request().method() === "POST" && r.url().includes(DOWNLOAD_PATH),
    ),
    page.waitForURL(/\/manage\/account\/download(\?|$)/),
    submit.click(),
  ]);

  expect(
    postResponse.status(),
    "the request POST should redirect, not render in place",
  ).toBe(302);
  expect(
    postResponse.headers()["location"],
    "the redirect should return to the download page",
  ).toContain(DOWNLOAD_PATH);

  await expectNoErrorBleed(page, page.url());
  expect(
    page.url(),
    "the browser should land on the download page via GET",
  ).toContain(DOWNLOAD_PATH);

  // --- Result: exactly one request for this fresh identity -----------------
  await expect(
    requestRows(page),
    "exactly one download request should exist after one submission",
  ).toHaveCount(1);
  await expect(errorAlerts(page)).toHaveCount(0);

  // Worker timing is external, so pending and already-completed are both
  // acceptable — but a task error is a failure to report, not completion.
  const stateCell = requestRows(page).first().locator("td").nth(1);
  await expect(
    stateCell,
    "the request should be pending or downloadable, never errored",
  ).toHaveText(/Processing archive, check back later\.|Download archive/);
  await expect(page.locator("body")).not.toContainText("Error:");

  // --- Reload is a GET and creates nothing --------------------------------
  await expectCleanPage(page, bust(DOWNLOAD_PATH));
  await expect(
    requestRows(page),
    "reloading the download page must not create a second request",
  ).toHaveCount(1);
});
```

- [x] **Step 2: Run the spec**

Run:

```bash
cd e2e && npx playwright test tests/account-download.spec.ts --project=manage --reporter=list
```

Expected: 1 passed.

If it fails on `toHaveCount(1)` with no error alert visible, re-read the two
known defects above before touching the assertion — an API failure presents
exactly that way.

- [x] **Step 3: Falsifiability check**

`requestRows` is the load-bearing selector; prove it is not always empty:

1. Change the final `toHaveCount(1)` to `toHaveCount(2)`.
2. Re-run. Expected: FAIL reporting `Expected: 2, Received: 1` — which confirms
   the locator found exactly one real row rather than matching nothing.
3. Revert to `toHaveCount(1)`.

- [x] **Step 4: Update §4c**

In `MANUAL_TEST_PLAN.md` §4c, check off the two items this test covers:

```markdown
- [x] `GET /manage/account/download` renders cleanly for a user with no prior requests. (`e2e/tests/account-download.spec.ts` → "a fresh user submits one personal data download request")
- [x] Submit a request — POST redirects back to the download page (POST/redirect/GET) and the new request appears in the list. (`e2e/tests/account-download.spec.ts` → "a fresh user submits one personal data download request")
```

Leave the remaining four unchecked, each naming its dependency rather than
sitting bare:

- duplicate submission while pending — needs a task held pending for the
  duration of the test; the worker could otherwise finish between the two POSTs
  and make a second request legitimate
- completed download link, mismatched-filename 404, and worker-log correlation —
  need a completed archive seeded through a supported test surface

Then extend the section's blockquote with the two defects this task found, so a
manual tester is not misled by a blank page:

```markdown
> Two defects in `render_download` as of 2026-09-09: the create-failure message
> at `Account.pm:743-747` is set but never rendered (`docs/manage/tpl/user/download.html`
> has no error output), and `list_user_tasks` errors are swallowed at
> `Account.pm:722-726` into an empty list. An API failure therefore looks like a
> missing row rather than an error.
```

- [ ] **Step 5: Commit**

```bash
git add e2e/tests/account-download.spec.ts MANUAL_TEST_PLAN.md
git commit -m "test(e2e): cover the personal data download request flow"
```

---

## Task 6: Staff search

**Files:**
- Create: `e2e/tests/staff-search.spec.ts`
- Modify: `e2e/lib/auth.ts` (append `getAccountNumericId`)

**Interfaces:**
- Consumes: `loginAs`, `uniqueTestEmail`, `MANAGE_URL` from `../lib/auth`;
  `expectCleanPage`, `expectNoErrorBleed` from `../lib/helpers`;
  `resolveDefaultAccountToken`, `renameAccount`, `uniqueAccountName` from
  `../lib/accounts` (Task 1).
- Produces, from `e2e/lib/auth.ts`:
  `getAccountNumericId(sessionToken: string, accountToken: string): Promise<string>`
  — the decimal `accounts.id`, as a string.

**Background the implementer needs:**

The form lives in `docs/manage/tpl/staff.html`: `#search_form` with
`hx-post="/manage/admin/search"`, `hx-target="#users"`, `hx-swap="innerHTML"`,
an `input#q[name=q]`, and a submit button. **The form has no `action`
attribute**, so if HTMX fails to load there is no valid native fallback — a
full-page navigation here means the fragment path is broken, which is why the
tests assert the URL does not change.

Account-name matching is real: `api/sql/search.sql:20-31`
(`SearchAccountsByPattern`) matches `a.name LIKE '%q%'` alongside user
email/username/name and the id_tokens. Renaming the account to a unique string
therefore gives a reliable needle.

Three response shapes from `staff_search` (`lib/NTPPool/Control/Manage.pm:482-612`):

| Query | Rendered into `#users` |
| --- | --- |
| match | `<ul>` of accounts, each with `servers`/`account` links carrying `a=<id_token>`, and an `<ol>` of members |
| no match | `<p>No results found for "…"</p>` |
| **empty** | **nothing** — the handler sets `results => {}` and never sets `query`, so `search_results.html`'s `ELSIF query && !results.error` is false |

The empty-query case renders a blank fragment, **not** a "No results" message.
Assert absence.

Non-staff denial: `manage_dispatch` (`Manage.pm:451-471`) only routes into
`staff_search` when `user_is_staff`, so a non-staff request falls through to
`return 404`. The inner handler's 403 is unreachable from the web route. Expect
404 — and note that `/manage/admin` itself also 404s for non-staff, so check the
navigation on a page a non-staff user can actually load.

`id:<numeric>` **is in scope**, because the readiness pass verified a response
contract for it (handoff R5). The numeric ID is not in the DOM — `search.v1.Account`
carries only `id_token`, and `account_id` appears in the manage templates solely
inside conditionals (`navigation_sidebar.html:26,30`, `account/form.html:33,126`),
never as text — so the harness reads it from an existing authenticated RPC:

```http
POST {NTP_INTERNAL_API_URL}/ntppool.account.v1.AccountService/GetAccount
Authorization: Bearer <the user's minted session token>
X-Account: <the account's id_token>
Content-Type: application/json

{}
```

The header shapes match `lib/NP/CAPI.pm:250,256`, which is how the Perl app
calls the same service. Two things to get right:

- Auth is the **user's session token** (what `loginAs` returns as
  `sessionToken`), not `NTP_TEST_SESSION_KEY`. The service key only mints the
  session.
- `account_id` is a proto `int64`, so ConnectRPC JSON encodes it as a **string**.
  Do not assume a number.

Do not decode the `acc_...` token and do not query SQL to obtain the ID.

- [x] **Step 1: Append `getAccountNumericId` to `e2e/lib/auth.ts`**

Add it after `mintSession`, reusing that function's env-var handling style so a
misconfigured runner still fails with one clear message.

```typescript
/**
 * Read an account's numeric `accounts.id` through AccountService.GetAccount.
 *
 * The staff search `id:<n>` query matches `a.id = $1` (api sql/search.sql
 * SearchAccountByID), and that number is not rendered anywhere in the UI — the
 * templates only ever test `account_id` for truthiness. This is the supported
 * read for it (verified 2026-09-09, readiness handoff R5); the harness must not
 * decode the acc_ token or reach for SQL.
 *
 * Auth is the USER's session token from loginAs/mintSession, not
 * NTP_TEST_SESSION_KEY — the service key only mints sessions. Account context
 * travels in X-Account, the same header lib/NP/CAPI.pm:256 sets.
 */
export async function getAccountNumericId(
  sessionToken: string,
  accountToken: string,
): Promise<string> {
  const apiBase = process.env.NTP_INTERNAL_API_URL;
  if (!apiBase) {
    throw new Error("NTP_INTERNAL_API_URL is not set");
  }

  const url =
    `${apiBase.replace(/\/$/, "")}` +
    "/ntppool.account.v1.AccountService/GetAccount";

  let resp: Response;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${sessionToken}`,
        "X-Account": accountToken,
        "Content-Type": "application/json",
      },
      body: "{}",
    });
  } catch (err) {
    throw new Error(
      `GetAccount request to ${url} failed (network/DNS). ` +
        `Is NTP_INTERNAL_API_URL correct and reachable? ` +
        `Cause: ${(err as Error).message}`,
    );
  }

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(
      `GetAccount failed for ${accountToken}: ${resp.status} ${resp.statusText} - ${text}`,
    );
  }

  // account_id is a proto int64, so ConnectRPC JSON encodes it as a string.
  const data = (await resp.json()) as {
    account?: { account_id?: string | number; id_token?: string };
  };
  const numericId = data.account?.account_id;
  if (numericId === undefined || numericId === null || numericId === "") {
    throw new Error(
      `GetAccount response missing account.account_id: ${JSON.stringify(data)}`,
    );
  }

  // Guard against a shape change slipping through as "[object Object]".
  const asString = String(numericId);
  if (!/^\d+$/.test(asString)) {
    throw new Error(
      `GetAccount returned a non-numeric account_id: ${JSON.stringify(numericId)}`,
    );
  }
  return asString;
}
```

- [x] **Step 2: Write `e2e/tests/staff-search.spec.ts`**

```typescript
import { test, expect, Browser, Page } from "@playwright/test";
import {
  loginAs,
  uniqueTestEmail,
  MANAGE_URL,
  getAccountNumericId,
} from "../lib/auth";
import { expectCleanPage, expectNoErrorBleed } from "../lib/helpers";
import {
  bust,
  renameAccount,
  resolveDefaultAccountToken,
  uniqueAccountName,
} from "../lib/accounts";

// Staff search (MANUAL_TEST_PLAN.md §13, issue #43).
//
// Route: lib/NTPPool/Control/Manage.pm manage_dispatch (:451-461) -> staff_search
// (:482-612). Template: docs/manage/tpl/staff.html (the form) and
// tpl/admin/search_results.html (the HTMX fragment swapped into #users).
//
// This slice covers account-NAME pattern matching only. IP lookup, hostname
// highlighting, include-deleted, `monitors:` and `zone:` all need controlled
// server/monitor fixtures and stay deferred. `id:<numeric>` is deferred too:
// the numeric accounts.id is not reachable from the browser (search results
// carry only id_token, and account_id is never rendered as text).

const ADMIN_PATH = "/manage/admin";
const SEARCH_PATH = "/manage/admin/search";

interface SearchTarget {
  email: string;
  accountToken: string;
  accountName: string;
  /** Decimal accounts.id, for the `id:` query. */
  accountNumericId: string;
}

/**
 * Mint a regular user and give their account a unique, searchable name through
 * the real edit form. Returns the details a staff search should surface.
 *
 * The numeric ID comes from AccountService.GetAccount using the target's own
 * session — it is not rendered anywhere in the UI.
 */
async function createSearchTarget(
  browser: Browser,
  prefix: string,
): Promise<SearchTarget> {
  const context = await browser.newContext();
  try {
    const email = uniqueTestEmail(`${prefix}-target`);
    const { sessionToken } = await loginAs(context, email);
    const page = await context.newPage();

    const accountToken = await resolveDefaultAccountToken(page);
    const accountName = uniqueAccountName(`${prefix}-needle`);
    await renameAccount(page, accountToken, accountName);

    const accountNumericId = await getAccountNumericId(
      sessionToken,
      accountToken,
    );

    return { email, accountToken, accountName, accountNumericId };
  } finally {
    await context.close();
  }
}

/**
 * Type a query into the staff search form and submit it through HTMX.
 *
 * Returns the POST response. Asserts the fragment swap happened without a
 * full-page navigation — #search_form has no `action`, so a navigation here
 * would mean HTMX never ran.
 */
async function runSearch(page: Page, query: string) {
  const urlBefore = page.url();

  await page.locator("#search_form input#q").fill(query);
  const [response] = await Promise.all([
    page.waitForResponse(
      (r) => r.request().method() === "POST" && r.url().includes(SEARCH_PATH),
    ),
    page.locator('#search_form button[type="submit"]').click(),
  ]);

  expect(
    page.url(),
    "search should swap a fragment, not reload the page",
  ).toBe(urlBefore);
  return response;
}

test("staff finds an account by a unique name substring", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-hit");

  await loginAs(context, uniqueTestEmail("search-staff"), { grantStaff: true });

  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(err.message));

  await expectCleanPage(page, bust(ADMIN_PATH));

  // Search a PROPER substring, not the whole name: `a.name LIKE '%q%'` must
  // match on a fragment, and an implementation that quietly degraded to
  // equality would still pass if we searched the full value.
  const needle = target.accountName.slice(4, -2);
  expect(needle, "needle must be a proper substring").not.toBe(
    target.accountName,
  );
  expect(needle.length, "needle must stay distinctive").toBeGreaterThan(12);

  const response = await runSearch(page, needle);
  expect(response.status()).toBe(200);
  await expectNoErrorBleed(page, `${SEARCH_PATH} (${needle})`);

  const results = page.locator("#users");
  await expect(results, "the target account should be found").toContainText(
    target.accountName,
  );

  // Scope member assertions to #users: the acting staff user's own email
  // appears in the page chrome, and the nav carries other identities, so a
  // body-wide email check would pass without any result at all.
  await expect(results, "the account's member should be listed").toContainText(
    target.email,
  );

  // The result must link into the TARGET's account context.
  await expect(
    results.locator(`a[href*="a=${target.accountToken}"]`).first(),
    "result links should carry the target account token",
  ).toBeVisible();

  await expect(results.locator(".alert-danger")).toHaveCount(0);
  expect(pageErrors, "no uncaught page errors during search").toEqual([]);
});

test("staff finds an account by exact numeric id: lookup", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-id");

  await loginAs(context, uniqueTestEmail("search-id-staff"), {
    grantStaff: true,
  });

  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(err.message));

  await expectCleanPage(page, bust(ADMIN_PATH));

  // `id:<n>` takes the decimal accounts.id (api search.go: strconv.ParseInt on
  // the id: prefix, then SearchAccountByID `where a.id = $1`). The acc_ token
  // is NOT that value.
  const response = await runSearch(page, `id:${target.accountNumericId}`);
  expect(response.status()).toBe(200);
  await expectNoErrorBleed(
    page,
    `${SEARCH_PATH} (id:${target.accountNumericId})`,
  );

  const results = page.locator("#users");
  await expect(
    results,
    "the exact-ID lookup should return the target account",
  ).toContainText(target.accountName);
  await expect(results, "with its member listed").toContainText(target.email);
  await expect(
    results.locator(`a[href*="a=${target.accountToken}"]`).first(),
    "result links should carry the target account token",
  ).toBeVisible();

  await expect(results.locator(".alert-danger")).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test("a no-match query replaces earlier results with the no-results message", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-miss");

  await loginAs(context, uniqueTestEmail("search-miss-staff"), {
    grantStaff: true,
  });

  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(err.message));

  await expectCleanPage(page, bust(ADMIN_PATH));

  // Populate results first, so the no-match case has something to replace.
  await runSearch(page, target.accountName);
  await expect(page.locator("#users")).toContainText(target.accountName);

  const missQuery = uniqueAccountName("no-such-account");
  const response = await runSearch(page, missQuery);
  expect(response.status(), "a no-match search is a 200, never a 404").toBe(200);
  await expectNoErrorBleed(page, `${SEARCH_PATH} (${missQuery})`);

  const results = page.locator("#users");
  await expect(results).toContainText(`No results found for "${missQuery}"`);
  await expect(
    results,
    "the earlier result must be replaced, not appended to",
  ).not.toContainText(target.accountName);
  await expect(results.locator(".alert-danger")).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test("an empty query clears earlier results without an error", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-empty");

  await loginAs(context, uniqueTestEmail("search-empty-staff"), {
    grantStaff: true,
  });

  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(err.message));

  await expectCleanPage(page, bust(ADMIN_PATH));
  await runSearch(page, target.accountName);
  await expect(page.locator("#users")).toContainText(target.accountName);

  const response = await runSearch(page, "");
  expect(response.status()).toBe(200);
  await expectNoErrorBleed(page, `${SEARCH_PATH} (empty)`);

  // staff_search returns early for an empty query: results => {} and `query` is
  // never set, so search_results.html renders NOTHING — not a no-results
  // message. Assert absence on all three counts.
  const results = page.locator("#users");
  await expect(results).not.toContainText(target.accountName);
  await expect(results.locator("ul")).toHaveCount(0);
  await expect(results).not.toContainText("No results found");
  await expect(results.locator(".alert-danger")).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test("a non-staff user cannot reach staff search", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-denied");

  await loginAs(context, uniqueTestEmail("search-nonstaff"));

  // (a) No staff-search entry point in the navigation. Check it on a page a
  // non-staff user can actually load — /manage/admin itself 404s for them.
  await expectCleanPage(page, bust("/manage/servers"));
  await expect(
    page.getByRole("link", { name: "Admin search" }),
    "non-staff navigation must not offer staff search",
  ).toHaveCount(0);

  // (b) A direct GET is refused by the outer dispatcher. manage_dispatch only
  // routes into staff_search when user_is_staff, so a non-staff request falls
  // through to `return 404`. That is the expected web-route denial; the inner
  // handler's 403 is unreachable here.
  const getResponse = await page.goto(
    `${SEARCH_PATH}?q=${encodeURIComponent(target.accountName)}`,
  );
  expect(getResponse, "no response from the search route").not.toBeNull();
  expect(
    getResponse!.status(),
    "non-staff GET of the search route should be refused",
  ).toBe(404);
  await expect(page.locator("body")).not.toContainText(target.accountName);

  // (c) The HTMX POST is refused the same way, and leaks no results.
  const postResponse = await context.request.post(
    `${MANAGE_URL}${SEARCH_PATH}`,
    {
      form: { q: target.accountName },
      headers: { "HX-Request": "true" },
      maxRedirects: 0,
    },
  );
  expect(
    postResponse.status(),
    "non-staff HTMX POST should be refused",
  ).toBe(404);
  expect(await postResponse.text()).not.toContain(target.accountName);

  // (d) And the admin page itself is not reachable.
  const adminResponse = await page.goto(ADMIN_PATH);
  expect(adminResponse, "no response from the admin page").not.toBeNull();
  expect(adminResponse!.status()).toBe(404);
});
```

- [x] **Step 3: Run the spec**

Run:

```bash
cd e2e && npx playwright test tests/staff-search.spec.ts --project=manage --reporter=list
```

Expected: 5 passed.

If `runSearch` times out waiting for the POST response, check whether HTMX
loaded (`#search_form` has no `action`, so nothing else would fire the request).
Confirm with `page.on("console")` output rather than adding a navigation
fallback — a fallback would hide exactly the regression this asserts against.

If `getAccountNumericId` fails with a 401/403, the likely cause is passing
`NTP_TEST_SESSION_KEY` instead of the user's `sessionToken`. If it returns a
`account_id` of `0`, the `X-Account` header did not reach the service — check
the header name against `lib/NP/CAPI.pm:256`.

- [x] **Step 4: Falsifiability check**

Three assertions carry this spec; prove each:

1. Change the account-token assertion in the name-substring test to
   `results.locator('a[href*="a=acc_definitely_not_a_token"]').first()`.
   Re-run that test. Expected: FAIL on `"result links should carry the
   target account token"`. Revert.
   Then change `needle` to `target.accountName + "-nope"`. Re-run. Expected:
   FAIL — this confirms the search is matching the needle rather than returning
   the account for some unrelated reason.
2. In the empty-query test, change `await runSearch(page, "")` to
   `await runSearch(page, target.accountName)`. Re-run. Expected: FAIL on the
   `not.toContainText(target.accountName)` assertion. Revert.
3. In the `id:` test, change the query to
   `` `id:${Number(target.accountNumericId) + 7919}` `` (a prime offset, so it
   is very unlikely to hit another account). Re-run. Expected: FAIL on `"the
   exact-ID lookup should return the target account"`. This proves the test
   depends on the ID actually resolving, not merely on the query returning 200.
   Revert.

- [x] **Step 5: Update §13**

In `MANUAL_TEST_PLAN.md` §13, check off four items. Narrow the pattern bullet —
the test covers account-name matching, not the whole pattern matrix — and split
hostname matching and highlighting out, since neither is covered:

```markdown
- [x] `id:<account-id>` lookup — returns that account with its users. (`e2e/tests/staff-search.spec.ts` → "staff finds an account by exact numeric id: lookup")
- [x] Free-text **pattern** search on an **account-name** substring — finds the account and lists its members, with result links carrying that account's `a=` token. (`e2e/tests/staff-search.spec.ts` → "staff finds an account by a unique name substring")
- [ ] Free-text pattern search on a **hostname** substring, and highlighting on matched IPs/hostnames — needs owned server fixtures.
- [x] A query with **no matches** renders an empty result set cleanly (no error alert, no 404 page). (`e2e/tests/staff-search.spec.ts` → "a no-match query replaces earlier results with the no-results message")
- [x] An **empty** query clears earlier results and renders nothing — not a "no results" message, which only appears for a non-empty query. (`e2e/tests/staff-search.spec.ts` → "an empty query clears earlier results without an error")
- [x] As a **non-staff** user, the search is denied (no staff results leak through) — the outer dispatcher 404s before reaching the handler, and no staff-search navigation is offered. (`e2e/tests/staff-search.spec.ts` → "a non-staff user cannot reach staff search")
```

The `id:` bullet says "with its users" rather than "with its users/servers/
monitors": a disposable account has neither servers nor monitors, so the test
cannot assert those.

Leave IP lookup, include-deleted, `monitors:` and `zone:` unchecked — all need
controlled server or monitor fixtures.

Add to the section blockquote how the test gets the numeric ID, since it is not
in the UI anywhere:

```markdown
> The `id:` search takes the decimal `accounts.id`, which is never rendered in
> the UI (search results carry only `id_token`; `account_id` appears in the
> manage templates solely inside truthiness checks). The e2e test reads it from
> `AccountService.GetAccount` — `Authorization: Bearer <user session>` plus
> `X-Account: <account token>` — not by decoding the `acc_…` token.
```

- [ ] **Step 6: Commit**

```bash
git add e2e/lib/auth.ts e2e/tests/staff-search.spec.ts MANUAL_TEST_PLAN.md
git commit -m "test(e2e): cover staff search pattern, exact-ID lookup and denial"
```

---

## Task 7: Vendor open-source submit with an empty justification

**Files:**
- Modify: `e2e/tests/vendor.spec.ts` (append one test after the existing
  `"open-source submit retains justification and edits without error"` test,
  around line 234)

**Interfaces:**
- Consumes: the file's existing `freshZoneData(prefix)`, `createNewZone(page, data)`,
  `loginAs`, `uniqueTestEmail`, `expectCleanPage`, `expectNoErrorBleed`; plus
  `bust` from `../lib/accounts` (Task 1) — add that import to the file.
- Produces: nothing new.

**Background the implementer needs:**

`lib/NTPPool/Control/Vendor.pm:388-397`: when `opensource_request` is set but
`opensource_info` is empty, the handler sets
`$errors = {opensource_info => 'Please provide open source information'}` and
re-renders the zone **before** calling `submit_vendor_zone`. So the zone stays
`New` and never reaches `Pending`.

Two facts that change how this is asserted:

1. **The textarea has no `required` attribute** (`docs/manage/tpl/vendor/_opensource.html:32`).
   A plain click submits the empty form and reaches the server-side check. The
   design's raw-POST fallback is unnecessary; do not build it.
2. **The error is not a Bootstrap alert.** `_opensource.html:28-30` renders
   `<div class="error">…</div>` inside `#opensource`. `errorAlerts()` and
   `expectErrorAlert()` select `.alert-danger, .alert-warning` and will not
   match it. Scope to `#opensource .error`.

No Trace ID is expected — the request is rejected before any RPC is made.

**Assert the status from the zone LIST, not the show page.** Two traps on the
show page:

- `show.html:19-24` makes the first `<blockquote>` the *organization name*
  (or, when `need_subscription` is set, the request information). The status
  blockquote is `show.html:73`, far below.
- That status block sits inside `[% UNLESS need_subscription %]`
  (`show.html:18-76`), so it is not rendered at all for an over-limit account.

`vendor.html:15-31` is unambiguous by comparison. For each zone it renders
`Status: <i>[% vz.status %]</i>` and a link whose text is **"Complete setup"**
when the status is `New`, and "View details" otherwise. So:

- Do **not** click "View details" — a New-only account has no such link, which
  is why copying that line from the neighbouring test would fail outright.
- The link text is itself a status assertion: it reverts to "View details" the
  moment the zone leaves `New`.

(An uncovered account renders `vz.status` raw, because the "Processing" relabel
is gated on `have_subscription`.)

Reopen the zone by its own URL rather than by clicking, so the test does not
depend on link text twice.

Not tested here: a whitespace-only justification currently passes the check
(`if (my $osinfo = ...)` — `" "` is truthy in Perl) and submits the zone.
`Vendor.pm:391` already carries `# todo: sanity check the data?`. Report it in
Task 9; do not add a test that can only fail.

Check `git status e2e/tests/vendor.spec.ts` before editing.

- [x] **Step 1: Append the test to `e2e/tests/vendor.spec.ts`**

```typescript
// §5b: submitting the open-source claim with an EMPTY justification must be
// refused server-side, and the zone must not move to Pending.
//
// The textarea carries no `required` attribute (_opensource.html:32), so a
// plain click reaches the server-side check in Vendor.pm:388-397 — the error
// path returns before submit_vendor_zone is ever called.
//
// The message renders as <div class="error"> inside #opensource, NOT as a
// Bootstrap alert, so errorAlerts()/expectErrorAlert() do not apply here. No
// Trace ID is expected: the request is rejected before any RPC.
test("open-source submit with an empty justification is refused and the zone stays New", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("vendor-os-empty");
  await loginAs(context, email);

  const data = freshZoneData("ose");
  // createNewZone returns the show-page URL, which carries id=<zone token>.
  const zoneUrl = await createNewZone(page, data);
  const zoneToken = new URL(zoneUrl).searchParams.get("id");
  expect(zoneToken, `zone URL should carry id=: ${zoneUrl}`).toBeTruthy();

  const osForm = page.locator('form[action*="/manage/vendor/submit"]');
  await expect(osForm, "uncovered vendor should get the open-source form").toBeVisible();

  const justification = osForm.locator('textarea[name="opensource_info"]');
  // Pin the precondition: if a `required` attribute is ever added, the browser
  // blocks the submit and this test would stop exercising the server check.
  expect(
    await justification.getAttribute("required"),
    "the justification textarea must not rely on native validation",
  ).toBeNull();

  await justification.fill("");
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    osForm.locator('input[type="submit"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());

  await expect(
    page.locator("#opensource .error"),
    "the empty justification should be refused with a specific message",
  ).toHaveText("Please provide open source information");

  // The zone context is retained on the re-render, not dropped.
  await expect(page.locator("body")).toContainText(data.zoneName);

  // The zone must still be New. Assert it from the list (vendor.html:15-31),
  // where the status is rendered plainly, rather than from the show page whose
  // first blockquote is the organization name.
  await expectCleanPage(page, bust("/manage/vendor"));

  const zoneLink = page.locator(`a[href*="id=${zoneToken}"]`);
  await expect(zoneLink, "the zone should still be listed").toBeVisible();
  // "Complete setup" renders only while the status is New; any other status
  // renders "View details".
  await expect(
    zoneLink,
    "a still-New zone should offer Complete setup, not View details",
  ).toHaveText("Complete setup");

  const listEntry = page
    .locator("p")
    .filter({ has: page.locator(`a[href*="id=${zoneToken}"]`) });
  await expect(
    listEntry.locator("i"),
    "the zone must not have transitioned to Pending",
  ).toHaveText("New");

  // Reopen the zone by URL (not by clicking a link whose text we just
  // asserted) and confirm it still offers the open-source form.
  await expectCleanPage(page, bust(zoneUrl));
  await expect(
    page.locator('textarea[name="opensource_info"]'),
    "the zone should still offer the open-source form",
  ).toBeVisible();
});
```

- [x] **Step 2: Run the vendor spec**

Run:

```bash
cd e2e && npx playwright test tests/vendor.spec.ts --project=manage --reporter=list
```

Expected: all tests pass, including the new one. `vendor.spec.ts` is the largest
spec in the suite; if unrelated tests in it fail, record them separately in
Task 9 rather than treating them as this task's problem.

- [x] **Step 3: Falsifiability check**

1. Change `justification.fill("")` to
   `justification.fill("Open source; MIT; https://example.com/src")`.
2. Re-run just this test:
   `npx playwright test tests/vendor.spec.ts --project=manage -g "empty justification" --reporter=list`
3. Expected: FAIL — the submit succeeds, so `#opensource .error` is not present,
   the list link becomes "View details", and the status reads `Pending`. This
   proves all three assertions respond to the input.
4. Revert to `fill("")`.

Also confirm the list locator is not matching nothing: change
`toHaveText("Complete setup")` to `toHaveText("Complete setups")` and re-run.
Expected: FAIL reporting the received text as `"Complete setup"`, which shows
the link was actually found.

- [x] **Step 4: Update §5 and §5b**

Two changes in `MANUAL_TEST_PLAN.md`.

First, §5's blockquote overclaims. It currently says §5-5d are covered "end to
end", but §5c and §5d are not: the vendor-admin invalid-transition test asserts
a safe no-op, which proves neither upstream error rendering nor decorative-call
degradation. Replace:

```markdown
> §5–5d are e2e-covered end to end by `e2e/tests/vendor.spec.ts`, including the
> issue #31 ORM-removal surface: ...
```

with:

```markdown
> `e2e/tests/vendor.spec.ts` covers the §5 items marked below plus the §5b
> open-source claim path, including the issue #31 ORM-removal surface:
> `dns_root_origin` display on both the new-zone and edit forms
> (Vendor.pm render_form), and `id_token`-based edit/create routing
> (form.html + `_get_id`). §5a, §5c, §5d and §5e are **not** covered end to end
> — the admin invalid-transition test asserts a safe no-op, which is not
> evidence of error rendering or of decorative-call degradation.
```

Second, check off the §5b item:

```markdown
- [x] Submitting the open-source form with an **empty** justification is rejected with "Please provide open source information", and the zone stays New. (`e2e/tests/vendor.spec.ts` → "open-source submit with an empty justification is refused and the zone stays New")
```

And record the validation gap next to it, in the §5b blockquote:

```markdown
> Known gap: a **whitespace-only** justification passes the check and submits
> the zone — `Vendor.pm:388-397` tests `if (my $osinfo = ...)`, and `" "` is
> truthy in Perl. The code already carries a `# todo: sanity check the data?`
> there. Not covered by a test, because a test for it could only fail today.
```

While in §5, upgrade the five already-checked items to the full link format
(they carry a spec path but no test name). Do not touch any other section.

- [ ] **Step 5: Commit**

```bash
git add e2e/tests/vendor.spec.ts MANUAL_TEST_PLAN.md
git commit -m "test(e2e): refuse an empty open-source justification on vendor submit"
```

---

## Task 8: Documentation corrections not tied to a new test

**Files:**
- Modify: `e2e/tests/invites.spec.ts:78,181`
- Modify: `MANUAL_TEST_PLAN.md` (§4a, §10, and the intro)
- Modify: `e2e/README.md:28-34,86-90`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new.

**Scope.** Tasks 1-7 each updated the checklist section they earned, so this
task is only what no new test covers: two test names that claim more than they
check, the checklist bullets that repeat those claims, and a stale README.

Run `git status` on each file before editing — see the conflict warning in
Global Constraints.

- [x] **Step 1: Rename the two overclaiming invite tests**

In `e2e/tests/invites.spec.ts`:

- Line 78: `"clicking Resend shows the success badge and sends a new invite email"`
  → `"clicking Resend shows the success badge"`.
  The test checks a badge in the returned HTML. It cannot observe delivery.
- Line 181: `"a non-pending invite shows no Resend button"`
  → `"only a pending invite renders a Resend control"`.
  The test creates a pending invite and asserts no Resend control renders
  against a non-pending status row; it never creates an accepted or expired
  invite.

Update each test's leading comment to match the new name — do not leave a
comment claiming email delivery or accepted/expired coverage.

- [x] **Step 2: Split the §4a bullets that repeat those claims**

In `MANUAL_TEST_PLAN.md` §4a, replace:

```markdown
- [ ] Click **Resend** — success badge ("Invitation email resent"); a new invite email arrives.
```

with two independently verifiable bullets:

```markdown
- [x] Click **Resend** — the success badge ("Invitation email resent") renders. (`e2e/tests/invites.spec.ts` → "clicking Resend shows the success badge")
- [ ] A new invite email actually arrives — not observable on the dev site, which runs in `deployment_mode=devel` and logs "development mode - not sending email" instead of sending.
```

And narrow the accepted/expired bullet, which no test covers:

```markdown
- [ ] **Accepted/expired** invites show no Resend button; the accept link still works — needs an invite/accept flow to create a non-pending invite (`e2e/tests/invites.spec.ts` → "only a pending invite renders a Resend control" covers the pending side only).
```

- [x] **Step 3: Narrow §10's Traditional Chinese item**

`e2e/tests/i18n.spec.ts` loads a **public** doc page and asserts
`lang="zh-tw"` plus a language marker. It says nothing about the authenticated
deletion-flow translation or about translation quality. Replace:

```markdown
- [ ] Switch to **Traditional Chinese (zh-tw)** — doc pages render, "scheduled for deletion" string present.
```

with:

```markdown
- [x] Switch to **Traditional Chinese (zh-tw)** — the public doc page renders with `lang="zh-tw"` and the language switcher shows the native name. (`e2e/tests/i18n.spec.ts` → "Traditional Chinese (zh-tw): doc page renders translated")
- [ ] The authenticated "scheduled for deletion" string renders translated in zh-tw — human check; the automated test only covers a public page.
```

- [x] **Step 4: Record what clean-page assertions actually prove**

`expectCleanPage` / `expectNoErrorBleed` inspect the **returned HTML** for ORM
error bleed, `Can't locate`, and unrendered template directives. They say
nothing about backend logs. Add to the intro bullets in `MANUAL_TEST_PLAN.md`,
next to the linking-convention bullet from Task 1, so no item is read as "the
logs were clean":

```markdown
- Automated items assert on the returned HTML. None of them inspect backend
  logs, so a log check (§12's "no 500s in logs" item, for example) stays manual.
```

- [x] **Step 5: Update `e2e/README.md`**

Remove the DB-assertion layer, which no longer exists (`e2e/.env.example` has no
`NTP_TEST_DB_URL`, and the specs say it was intentionally removed):

- Delete the `NTP_TEST_DB_URL` entry (around lines 28-34), including the
  `assertDevelDatabase` reference.
- Delete "DB-backed assertions need `NTP_TEST_DB_URL`" (around line 88).
- Update the coverage description to list the current specs, including
  `account-frozen.spec.ts`, `account-download.spec.ts` and
  `staff-search.spec.ts`.
- State plainly that the suite has no DB verification layer and that state is
  confirmed through the UI or authorized API reads.
- Document `test-logs/` (added in Task 1) and why logs must not go in
  `test-results/`: Playwright clears its `outputDir` at the start of each run.

- [x] **Step 6: Verify no trailing whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add MANUAL_TEST_PLAN.md e2e/README.md e2e/tests/invites.spec.ts
git commit -m "docs(e2e): reconcile the remaining coverage claims with the tests"
```

---

## Task 9: Validation run and coverage report

**Files:**
- Create: `e2e/COVERAGE_REPORT-2026-09-09.md`

**Interfaces:**
- Consumes: every spec from Tasks 1-7.
- Produces: the report the design's acceptance criteria require.

- [x] **Step 1: Recheck the deployment identifiers**

The readiness pass recorded these on 2026-09-09, with a dev build in progress at
the time, so confirm the code under test is still the code that was probed:

```bash
kubectl --context dala -n askntp get pods -l app=ntppool -o jsonpath='{.items[*].spec.containers[*].image}{"\n"}'
kubectl --context dala -n askntp get pods -l app=api-internal -o jsonpath='{.items[*].spec.containers[*].image}{"\n"}'
```

Compare against the handoff's table (web `ntppool-dev:bTkqIaz`, API
`api-dev:sha-3534d54a`). Devspace syncs Perl source into the running pod, so the
image tag alone is not sufficient — if a test fails unexpectedly, also compare
the deployed file hash for the relevant controller against the local file, the
way the handoff did. Record whatever you observe; a changed identifier is
context for the report, not a blocker.

Note that the dev site syncs source without reloading the app (see the project
memory on this): if a Perl change was synced but the pod was not restarted, the
running behavior can lag the file on disk.

- [x] **Step 2: Run the focused new and modified specs**

Save the output and keep Playwright's exit status. Two traps:

- Do not pipe the run into `grep`: a pipeline discards the exit code, and
  `grep … || echo ok` prints a success line precisely when Playwright failed
  before reaching cleanup.
- Do not write into `test-results/`. That is Playwright's `outputDir`, which the
  runner clears at the start of every run — the second run would delete the
  first run's log, and each run can unlink the log it is writing. Use
  `test-logs/` (created and gitignored in Task 1).

```bash
cd e2e
mkdir -p test-logs
npx playwright test \
  tests/account-frozen.spec.ts \
  tests/account-download.spec.ts \
  tests/staff-search.spec.ts \
  tests/vendor.spec.ts \
  tests/account-dissolve.spec.ts \
  tests/staff-deletion.spec.ts \
  --project=manage --reporter=list \
  > test-logs/run-1.log 2>&1
echo "run 1 playwright exit: $?"
```

Record the exact pass/fail/skip counts and any retries from `run-1.log`.
Retries matter: a test that only passes on retry is not isolated, and the design
requires reporting it.

- [x] **Step 3: Repeat the focused run with fresh identities**

Run the same command again, writing to `test-logs/run-2.log`.

Every identity is minted per attempt, so this run uses entirely new users and
accounts. That makes it a check on **isolation**: no test depends on data
another run left behind.

It is *not* evidence about the first run's accounts — a second run creates its
own and cannot observe the first's. Cleanup evidence comes from the runs' own
logs, because `cleanupScheduledDeletion` verifies the account is restored on a
fresh read and fails an otherwise-passing test when it cannot.

Inspect both saved logs rather than launching a third run:

```bash
cd e2e
for log in test-logs/run-1.log test-logs/run-2.log; do
  echo "--- $log"
  grep -i "CLEANUP FAILED\|cleanup-failure" "$log" \
    && echo "^^ leftover frozen accounts — cancel them by hand" \
    || echo "no cleanup failures recorded"
done
```

Expected: both runs exited 0 and neither log records a cleanup failure. If one
does, the message names the account token — cancel that account before moving
on, and report it.

- [x] **Step 4: Run the affected existing specs**

```bash
cd e2e
npx playwright test \
  tests/account-create.spec.ts \
  tests/account-team.spec.ts \
  tests/account-update.spec.ts \
  tests/invites.spec.ts \
  tests/regression-smoke.spec.ts \
  --project=manage --reporter=list \
  > test-logs/run-existing.log 2>&1
echo "existing-spec run exit: $?"
```

(`staff-deletion.spec.ts` and `account-dissolve.spec.ts` are already in the
focused run above, since Task 4 modifies both.)

Unrelated failures or skips get reported separately and do **not** count as
covered items.

- [x] **Step 5: Write `e2e/COVERAGE_REPORT-2026-09-09.md`**

Include, in this order:

1. **Checklist items now closed** — each with the manual-plan section, the spec
   path, and the test name. Tasks 1-7 already wrote these into
   `MANUAL_TEST_PLAN.md`, so this is a summary of that file, not a fresh audit.
   Confirm the checked boxes match the runs above: if a spec regressed in a
   later task, uncheck its items here rather than leaving a stale claim.
2. **Items still partially open** — what is covered, what is not, and why.
3. **Test results** — both focused runs and the existing-spec run, with
   pass/fail/skip counts and any retries, quoting the reporter output.
4. **Product defects found** — for each: the failing test, the assertion, the
   observed response, and the source location. At minimum, unless a run shows
   otherwise, these three from the tasks above:
   - `render_download` sets a create-failure error the template never renders
     (`Account.pm:743-747` vs `docs/manage/tpl/user/download.html`).
   - `render_download` swallows `list_user_tasks` errors into an empty list
     (`Account.pm:722-726`).
   - A whitespace-only `opensource_info` passes vendor validation and submits
     the zone (`Vendor.pm:388-397`).
5. **Fixture blockers** — the deferred matrix from the design, with the specific
   thing each would unlock, so the next scope has a starting point. Cross-
   reference the readiness handoff's later-coverage table rather than restating
   it; all eight entries remain deferred with no owners assigned.
6. **Environment** — the deployment identifiers from Step 1, and the date and
   runner of the validation runs.
7. **Data left behind** — disposable users, accounts, and vendor zones the runs
   created. Per the agreed cleanup policy (handoff R4), accumulation is
   acceptable for now and Ask owns periodic cleanup; a review is due after two
   weeks of regular runs. What must **not** be left behind is a scheduled
   deletion: report any `cleanup-failure` annotation with its account token so
   it can be cancelled by hand.

State plainly that no product code was changed.

- [ ] **Step 6: Commit**

```bash
git add e2e/COVERAGE_REPORT-2026-09-09.md
git commit -m "docs(e2e): record the coverage run and the defects it surfaced"
```

---

## Self-review notes

**Spec coverage.** Every required section maps to a task: §2 frozen accounts →
Tasks 1-4; §4c download → Task 5; §13 staff search → Task 6; §5b vendor
validation → Task 7; coverage accounting → Task 8; acceptance → Task 9. The
design's deferred matrix is documentation only and is recorded in Task 9 step 4,
with no placeholder tests, as the design requires.

**Deviations from the design, each with its reason.**

1. The design's conditional raw-POST fallback for the vendor test is dropped.
   `_opensource.html:32` has no `required` attribute, so the fallback would be
   unreachable code. Task 7 instead pins the absence of `required` as an
   explicit precondition, so the test fails loudly if that ever changes.
2. The design leaves `id:` numeric lookup to the planner to investigate, to be
   deferred if no response contract exists. One does: the readiness handoff
   verified `AccountService.GetAccount` returning `account.account_id` for a
   disposable account token (R5). So Task 6 **includes** the exact-ID test
   rather than deferring it, with the contract and its two traps (user session
   not service key; int64 arrives as a string) written into the task.
3. The design does not mention timeouts. Task 1 sets a 120s describe-level
   timeout: the frozen-account fixture needs two contexts and roughly a dozen
   round-trips against the live dev site, well past the 30s global default.
4. The design requires cleanup only for new scenarios, but Task 4 extends it to
   the two existing tests that schedule a deletion. This plan runs both, and
   deliberately fails one during a falsifiability check, so without cleanup it
   would itself strand frozen accounts. The agreed cleanup policy (handoff R4)
   exempts nothing that a run executes.
5. Setup helpers never schedule a deletion. `setupFrozenAccount` builds the
   accounts and stops; each test schedules inside its own `try`, so the
   `finally` that cancels is registered first. A helper that scheduled before
   returning would strand an account on any failure between the schedule and
   the caller's `try`.
6. A cleanup failure fails an otherwise-passing test rather than being
   annotated and forgotten, and never replaces an original failure. That is
   what the `bodyFailed` flag in each test's `catch` is for.
7. Falsifiability checks are added to every test-writing task. The design
   requires that tests fail on unexpected responses; for e2e work the common way
   that requirement is silently violated is a selector matching nothing, which a
   green run does not reveal.
