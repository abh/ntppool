import {
  test as base,
  expect,
  Browser,
  BrowserContext,
  Page,
} from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  bust,
  expectCleanPage,
  expectNoErrorBleed,
  createAccount,
  errorAlerts,
} from "../lib/helpers";
import {
  accountFormUrl,
  cleanupScheduledDeletion,
  dissolveUrl,
  renameAccount,
  resolveDefaultAccountToken,
  scheduleAccountDeletion,
  submitAccountNameEdit,
  uniqueAccountName,
} from "../lib/accounts";

// Frozen-account behavior from the NON-STAFF OWNER's side.
//
// account-dissolve.spec.ts covers the staff half. The tests here need a
// non-staff *member* of a frozen account, which does not need an accept-invite
// helper: the second account from createAccount() has its creator as sole
// member, so the creator is already a non-staff member of it. A separate staff
// identity freezes that account; the owner never accepts an invitation.
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
 * The member-facing frozen-account banner (form.html:3-23).
 *
 * Locating on `.alert-danger` is itself the destructive-styling assertion: if
 * the banner were downgraded to a neutral notice this would not match.
 */
function deletionBanner(page: Page) {
  return page
    .locator(".alert-danger")
    .filter({ hasText: "Account scheduled for deletion" });
}

/** The account edit form's name field, for reading the persisted value back. */
function accountNameField(page: Page) {
  return page.locator('#account-form input[name="name"]');
}

/**
 * Attempt a rename through the real form and assert it was refused with the
 * specific message, and that nothing was written.
 *
 * Filter on the exact message: the deletion banner is also .alert-danger and
 * must not be able to satisfy this assertion. The banner's text is
 * "...scheduled for permanent deletion on", which does not contain this.
 */
async function expectFrozenEditRefused(
  page: Page,
  accountToken: string,
  unchangedName: string,
  attemptPrefix: string,
  why: string,
): Promise<void> {
  await submitAccountNameEdit(
    page,
    accountToken,
    uniqueAccountName(attemptPrefix),
  );

  await expect(errorAlerts(page).filter({ hasText: FROZEN_EDIT_ERROR }), why)
    .toBeVisible();

  // A fresh read proves nothing was written.
  await expectCleanPage(page, bust(accountFormUrl(accountToken)));
  await expect(
    accountNameField(page),
    "the account name must be unchanged after a refused edit",
  ).toHaveValue(unchangedName);
}

/**
 * Build the frozen-account scenario UP TO but NOT INCLUDING the freeze: a
 * non-staff owner with two accounts, plus a separate staff identity.
 *
 * Scheduling deliberately does NOT happen here — see the `frozen` fixture.
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

/** A short, readable stem from the test title, for the minted identities. */
function titleSlug(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 24);
}

/**
 * `frozen` gives each test the scenario above and always unfreezes the account
 * afterwards.
 *
 * A fixture rather than a per-test try/finally: Playwright registers the
 * teardown as the fixture is set up, so cleanup is guaranteed before the test
 * body — and therefore before any scheduleAccountDeletion call — can run. It
 * also runs on teardown's own time budget, so a test that times out mid-cycle
 * still gets its account restored.
 *
 * A cleanup failure fails the test only when the test would otherwise have
 * passed, so it can never replace a real failure.
 */
const test = base.extend<{ frozen: FrozenFixture }>({
  frozen: async ({ browser }, use, testInfo) => {
    const f = await setupFrozenAccount(browser, titleSlug(testInfo.title));
    let cleanupError: Error | null = null;
    try {
      await use(f);
    } finally {
      cleanupError = await cleanupScheduledDeletion(f.staffPage, f.accountToken);
      await f.ownerContext.close();
      await f.staffContext.close();
    }
    if (cleanupError && testInfo.status === testInfo.expectedStatus) {
      throw cleanupError;
    }
  },
});

// Two browser contexts, several round-trips against the live dev site, and a
// cancel cycle do not fit the 30s global timeout in playwright.config.ts. The
// fixture's setup and teardown are billed to the same budget.
test.describe.configure({ timeout: 120_000 });

test("a non-staff owner sees the deletion banner on a frozen account", async ({
  frozen: f,
}) => {
  const scheduledDate = await scheduleAccountDeletion(
    f.staffPage,
    f.accountToken,
  );

  // Before the fix this redirected to /manage/ (can_edit is false on a frozen
  // account), so the member could never reach the cancel control.
  await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));

  const banner = deletionBanner(f.ownerPage);
  await expect(
    banner,
    "non-staff member should see the frozen-account banner",
  ).toBeVisible();

  // The banner names the scheduled date the API picked.
  await expect(banner).toContainText(scheduledDate);

  // ...and carries a cancel form scoped to THIS account.
  const cancelForm = banner.locator('form[action*="/manage/account/dissolve"]');
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
});

test("freezing one account leaves the owner's other account untouched", async ({
  frozen: f,
}) => {
  await scheduleAccountDeletion(f.staffPage, f.accountToken);

  // The original account is unaffected: it loads, has no banner, and is
  // still editable.
  await expectCleanPage(
    f.ownerPage,
    bust(accountFormUrl(f.originalAccountToken)),
  );
  await expect(
    deletionBanner(f.ownerPage),
    "the owner's other account must not be marked for deletion",
  ).toHaveCount(0);

  const renamed = uniqueAccountName("frozen-isolation-ok");
  await renameAccount(f.ownerPage, f.originalAccountToken, renamed);

  // And the frozen account still carries its own, unchanged name.
  await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));
  await expect(accountNameField(f.ownerPage)).toHaveValue(f.accountName);
});

test("a frozen account refuses a name edit from its non-staff owner", async ({
  frozen: f,
}) => {
  await scheduleAccountDeletion(f.staffPage, f.accountToken);

  // The form still renders while frozen (form.html has no can_edit gate),
  // which is exactly why the POST needs its own refusal.
  await expectFrozenEditRefused(
    f.ownerPage,
    f.accountToken,
    f.accountName,
    "frozen-edit-attempt",
    "frozen edit should render the specific refusal message",
  );
});

test("a frozen account refuses a name edit from staff too", async ({
  frozen: f,
}) => {
  await scheduleAccountDeletion(f.staffPage, f.accountToken);

  // Freezing removes can_edit for everyone: AccountWritable is
  // !deletion_on, with no staff exemption.
  await expectCleanPage(f.staffPage, bust(accountFormUrl(f.accountToken)));

  // Staff get the manage link, never the member banner (form.html:3 vs :156).
  await expect(
    deletionBanner(f.staffPage),
    "staff should not see the member cancel banner",
  ).toHaveCount(0);
  await expect(
    f.staffPage.locator("a.text-danger", {
      hasText: "Account deletion scheduled",
    }),
  ).toBeVisible();

  await expectFrozenEditRefused(
    f.staffPage,
    f.accountToken,
    f.accountName,
    "frozen-staff-attempt",
    "frozen edit should be refused for staff with the same message",
  );
});

test("the owner cancels from the banner and the account is editable again", async ({
  frozen: f,
}) => {
  await scheduleAccountDeletion(f.staffPage, f.accountToken);

  await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));

  const banner = deletionBanner(f.ownerPage);
  await expect(banner).toBeVisible();

  // Any member may cancel (Account.pm: $member_cancel), and the controller
  // redirects back to the account page on success. This must stay inline: the
  // owner is NOT staff, so cancelAccountDeletionAsStaff's dissolve GET would
  // 403 for them — the banner form is their only route.
  //
  // waitForNavigation, not waitForURL: the owner is already on
  // /manage/account before the click, and waitForURL would resolve
  // immediately against that pre-click URL instead of waiting for the click's
  // navigation.
  await Promise.all([
    f.ownerPage.waitForNavigation({
      url: /\/manage\/account(\?|$)/,
      waitUntil: "load",
    }),
    banner.getByRole("button", { name: "Cancel scheduled deletion" }).click(),
  ]);
  await expectNoErrorBleed(f.ownerPage, f.ownerPage.url());

  // A fresh navigation, not just the redirect response, shows the banner gone.
  await expectCleanPage(f.ownerPage, bust(accountFormUrl(f.accountToken)));
  await expect(
    deletionBanner(f.ownerPage),
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
});
