import { Page, expect, test as base } from "@playwright/test";
import { bust, expectCleanPage, expectNoErrorBleed } from "./helpers";

export const ACCOUNT_PATH = "/manage/account";
export const DISSOLVE_PATH = "/manage/account/dissolve";

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
  await expectCleanPage(page, bust("/manage"));

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
  await submitAccountNameEdit(page, accountToken, newName);

  await expectCleanPage(page, bust(accountFormUrl(accountToken)));
  await expect(
    page.locator('#account-form input[name="name"]'),
    "account rename did not persist",
  ).toHaveValue(newName);
}

/**
 * Load the account edit form and POST a new name, with no expectation about
 * whether the write is accepted — that is the caller's assertion.
 *
 * Split out of renameAccount so the frozen-account tests, which submit exactly
 * this form and then assert a refusal, don't restate the form mechanics.
 */
export async function submitAccountNameEdit(
  page: Page,
  accountToken: string,
  newName: string,
): Promise<void> {
  await expectCleanPage(page, bust(accountFormUrl(accountToken)));
  const form = page.locator("#account-form");
  await expect(form, "account edit form not found").toBeVisible();

  await form.locator('input[name="name"]').fill(newName);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    form.locator('input[type="submit"][value="Update"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
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
  await expectCleanPage(staffPage, bust(dissolveUrl(accountToken)));
  await expect(
    staffPage.getByRole("heading", { name: /^Delete account:/ }),
    "dissolve confirmation page did not render",
  ).toBeVisible();

  // A predicate rather than a regex over the href: this pins the path exactly
  // and compares the account token by equality, so a longer token that merely
  // starts with this one could not satisfy it.
  //
  // waitForNavigation, not waitForURL: staffPage is already on this dissolve
  // URL before the click, and waitForURL resolves immediately when the
  // CURRENT url already matches its predicate — it would not wait for the
  // click's navigation at all. waitForNavigation always waits for the next
  // navigation to occur.
  await Promise.all([
    staffPage.waitForNavigation({
      url: (u) =>
        u.pathname === DISSOLVE_PATH &&
        u.searchParams.get("a") === accountToken,
      waitUntil: "load",
    }),
    staffPage
      .getByRole("button", { name: "Schedule account deletion" })
      .click(),
  ]);
  await expectNoErrorBleed(staffPage, staffPage.url());

  await expect(
    staffPage.getByRole("button", { name: "Cancel scheduled deletion" }),
    "scheduling did not produce a pending state",
  ).toBeVisible();

  // dissolve_confirmation.html renders the date as
  // "...scheduled for deletion on <b>YYYY-MM-DD</b>." Read that element rather
  // than regexing the whole serialized document.
  const dateEl = staffPage
    .locator("p", { hasText: "scheduled for deletion on" })
    .locator("b");
  await expect(
    dateEl,
    "pending dissolve page should render the scheduled date",
  ).toHaveText(/^\d{4}-\d{2}-\d{2}$/);
  return (await dateEl.textContent())!.trim();
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
  await expectCleanPage(staffPage, bust(dissolveUrl(accountToken)));

  // "Delete account: <name>" is the confirmation page's own heading. A login
  // page or an error page does not have it.
  await expect(
    staffPage.getByRole("heading", { name: /^Delete account:/ }),
    `not the dissolve confirmation page for ${accountToken}`,
  ).toBeVisible();

  const [cancelButtons, scheduleButtons] = await Promise.all([
    staffPage.getByRole("button", { name: "Cancel scheduled deletion" }).count(),
    staffPage.getByRole("button", { name: "Schedule account deletion" }).count(),
  ]);

  if (cancelButtons === 1 && scheduleButtons === 0) return "pending";
  if (cancelButtons === 0 && scheduleButtons === 1) return "not-scheduled";

  throw new Error(
    `dissolve page for ${accountToken} is in an unrecognised state ` +
      `(cancel buttons: ${cancelButtons}, schedule buttons: ${scheduleButtons})`,
  );
}

/**
 * Click cancel on an ALREADY-LOADED pending dissolve page, then confirm on a
 * FRESH read that the deletion actually cleared. The redirect landing on
 * /manage/account is not evidence the write happened.
 */
async function cancelFromPendingDissolvePage(
  staffPage: Page,
  accountToken: string,
): Promise<void> {
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
 * Cancel a scheduled deletion from the staff dissolve page, refusing if there
 * is nothing scheduled, and verifying the clear on a fresh read.
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
  await cancelFromPendingDissolvePage(staffPage, accountToken);
}

/**
 * Teardown: cancel a still-pending deletion so no test leaves an account for
 * the purge worker to delete.
 *
 * Returns the error instead of throwing, so the caller can apply the right
 * policy: a cleanup failure must fail an otherwise-passing test, but it must
 * never replace an original failure. Returns null when there was nothing to
 * clean up, or when cleanup succeeded and was verified.
 *
 * The state read here doubles as the "is it pending" check, so cancelling costs
 * one page load fewer than going through cancelAccountDeletionAsStaff.
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
    if ((await readDissolveState(staffPage, accountToken)) === "pending") {
      await cancelFromPendingDissolvePage(staffPage, accountToken);
    }
    return null;
  } catch (err) {
    const error = new Error(
      `CLEANUP FAILED: account ${accountToken} may still be scheduled for ` +
        `deletion and needs manual cancellation — ${(err as Error).message}`,
    );
    console.error(error.message);
    base.info().annotations.push({
      type: "cleanup-failure",
      description: error.message,
    });
    return error;
  }
}

/** Records accounts a test may have frozen, so teardown can unfreeze them. */
export interface ScheduledDeletions {
  /**
   * Register an account BEFORE scheduling its deletion. A synchronous push, so
   * there is no window between registering and scheduling in which a failure
   * could strand a frozen account.
   */
  register(accountToken: string): void;
}

/**
 * `test` with a `scheduledDeletions` fixture that unfreezes every registered
 * account after the test.
 *
 * A fixture rather than a per-test try/finally: Playwright registers the
 * teardown when the fixture is set up — before the test body starts, therefore
 * before any scheduling — and runs teardown on its own time budget, so cleanup
 * still happens when the test times out rather than merely when it throws.
 *
 * The fixture depends on `page` so it tears down while that page is still open.
 * A cleanup failure fails the test only when the test would otherwise have
 * passed, so it can never replace a real failure.
 */
export const test = base.extend<{ scheduledDeletions: ScheduledDeletions }>({
  scheduledDeletions: async ({ page }, use, testInfo) => {
    const tokens: string[] = [];
    await use({ register: (t: string) => tokens.push(t) });

    let firstError: Error | null = null;
    for (const token of tokens) {
      const cleanupError = await cleanupScheduledDeletion(page, token);
      firstError ??= cleanupError;
    }
    if (firstError && testInfo.status === testInfo.expectedStatus) {
      throw firstError;
    }
  },
});
