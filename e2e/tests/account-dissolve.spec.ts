import { expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { bust, expectCleanPage, createAccount } from "../lib/helpers";
import {
  test,
  accountFormUrl,
  cancelAccountDeletionAsStaff,
  DISSOLVE_PATH,
  dissolveUrl,
  scheduleAccountDeletion,
} from "../lib/accounts";

// Account scheduled deletion / dissolve flow.
//
// Scheduling is staff-only; cancelling is not. The dissolve route
// (lib/NTPPool/Control/Manage/Account.pm manage_dispatch:
// `return 403 unless $self->user_is_staff || $member_cancel`) and the UI link
// (docs/manage/tpl/account/form.html `[% IF combust.user_is_staff %]`) are
// gated on support_staff, so a non-staff user 403s on a bare GET — correct.
// But $member_cancel lets any member POST cancel=1, and form.html:3-23 renders
// a "Cancel scheduled deletion" banner for exactly that.
//
// Reaching that banner needs /manage/account to render for a *frozen* account,
// where permissions.can_edit is false for everyone, staff included
// (AccountWritable = !deletion_on). manage_dispatch excepts the /manage/account
// URI for a frozen account so both the member banner and the staff
// "Account deletion scheduled — manage" link are reachable.
//
// Routes / templates this exercises:
//   - /manage/account              render_account_form -> tpl/account/form.html
//                                  (staff: "Delete account" link, class text-danger)
//   - GET  /manage/account/dissolve  render_account_dissolve (GET) ->
//                                  tpl/account/dissolve_confirmation.html
//                                  (h3 "Delete account: <name>", schedule form)
//   - POST /manage/account/dissolve  schedule (API picks a fixed 7-day date),
//                                  redirects to /manage/account on success
//   - POST .../dissolve cancel=1     cancel_account_deletion, redirects back
//
// Selectors/button text below are real, from form.html and
// dissolve_confirmation.html. Staff users are minted fresh per test with
// loginAs(..., { grantStaff: true }) so we dissolve a throwaway account, never
// a real one.
//
// The schedule/cancel mechanics live in lib/accounts.ts, which verifies each
// state change on a fresh read; the tests below add the UI assertions.

// The destructive link on /manage/account is an <a class="text-danger"> reading
// "Delete account" before anything is scheduled (form.html:163).
function deleteAccountLink(page: Page) {
  return page.locator("a.text-danger", { hasText: "Delete account" });
}

test("staff sees the destructive Delete account link on /manage/account", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("dissolve-staff-link");
  await loginAs(context, email, { grantStaff: true });

  await expectCleanPage(page, "/manage/account");

  // The red, destructive "Delete account" link renders for staff at the bottom
  // of the account form (form.html: `[% IF combust.user_is_staff %]`).
  await expect(deleteAccountLink(page)).toBeVisible();
  await expect(deleteAccountLink(page)).toHaveAttribute(
    "href",
    /\/manage\/account\/dissolve/,
  );
});

test("non-staff user: link hidden and dissolve route returns 403", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("dissolve-nonstaff");
  // No grantStaff: a fresh, non-staff user.
  await loginAs(context, email);

  await expectCleanPage(page, "/manage/account");

  // The staff-gated link must not render for a non-staff user.
  await expect(deleteAccountLink(page)).toHaveCount(0);

  // A bare GET of /manage/account/dissolve is staff-only -> 403
  // (manage_dispatch). This stays correct after the frozen-account fix: what
  // the fix changed is that a non-staff member of an already-frozen account can
  // reach /manage/account and POST cancel=1 from the banner there, not that the
  // GET opens up.
  const response = await page.request.get(DISSOLVE_PATH);
  expect(response.status(), "non-staff dissolve GET should be 403").toBe(403);
});

test("staff: dissolve confirmation page renders", async ({ page, context }) => {
  const email = uniqueTestEmail("dissolve-confirm");
  await loginAs(context, email, { grantStaff: true });

  await expectCleanPage(page, DISSOLVE_PATH);

  // Heading from dissolve_confirmation.html: "Delete account: <name>".
  await expect(
    page.getByRole("heading", { name: /Delete account:/ }),
  ).toBeVisible();

  // The default (un-scheduled) state shows the schedule form/button.
  await expect(
    page.getByRole("button", { name: "Schedule account deletion" }),
  ).toBeVisible();
});

test("staff: schedule, see pending state, then cancel back to normal", async ({
  page,
  context,
  scheduledDeletions,
}) => {
  const email = uniqueTestEmail("dissolve-cycle");
  await loginAs(context, email, { grantStaff: true });

  // Dissolution refuses to orphan a member, so a sole-owner account can't be
  // dissolved (that scenario is user-deletion). Create a SECOND account and
  // dissolve that one — the user keeps their first account, so no one is
  // orphaned and the schedule succeeds.
  const acct = await createAccount(page);

  // Register before scheduling, so teardown is already armed if anything below
  // fails or times out.
  scheduledDeletions.register(acct);

  // Schedule deletion. The API picks a fixed 7-day-out date.
  await scheduleAccountDeletion(page, acct);

  // Revisit the dissolve page: it now shows the pending scheduled state with a
  // cancel option (dissolve_confirmation.html `[% ELSIF pending %]`):
  //   - a "Deletion scheduled" badge,
  //   - the scheduled date (deletion_on, date-only),
  //   - a "Cancel scheduled deletion" button.
  await expectCleanPage(page, bust(dissolveUrl(acct)));
  await expect(page.locator("body")).toContainText("Deletion scheduled");
  await expect(page.locator("body")).toContainText("scheduled for deletion on");
  // A scheduled-date marker: an ISO date (YYYY-MM-DD) is rendered in the notice.
  // The exact +7d value is the API's responsibility; asserting a date appears is
  // enough here.
  await expect(page.locator("body")).toContainText(/\d{4}-\d{2}-\d{2}/);
  await expect(
    page.getByRole("button", { name: "Cancel scheduled deletion" }),
  ).toBeVisible();

  // Cancel — state clears and the account is back to normal. Leaving the staff
  // account scheduled for deletion would be unfriendly, so always cancel.
  await cancelAccountDeletionAsStaff(page, acct);

  // The dissolve page is back to the un-scheduled state: schedule button shown,
  // no "Deletion scheduled" badge.
  await expectCleanPage(page, bust(dissolveUrl(acct)));
  await expect(
    page.getByRole("button", { name: "Schedule account deletion" }),
  ).toBeVisible();
  await expect(page.locator("body")).not.toContainText("Deletion scheduled");
});

test("staff: a frozen account still renders /manage/account with the scheduled-deletion link", async ({
  page,
  context,
  scheduledDeletions,
}) => {
  const email = uniqueTestEmail("dissolve-frozen-form");
  await loginAs(context, email, { grantStaff: true });

  // Same setup as the cycle test: dissolve a throwaway second account so no one
  // is orphaned.
  const acct = await createAccount(page);

  // Register before scheduling, so teardown is already armed if anything below
  // fails or times out.
  scheduledDeletions.register(acct);
  await scheduleAccountDeletion(page, acct);

  // Before the fix this redirected to /manage/ (can_edit is false for staff too
  // on a frozen account), leaving form.html:156-167 dead. It must now render
  // the account form.
  await expectCleanPage(page, bust(accountFormUrl(acct)));
  await expect(page).toHaveURL(/\/manage\/account(\?|$)/);
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
  ).toBe(DISSOLVE_PATH);
  expect(
    pendingUrl.searchParams.get("a"),
    `pending-deletion link should target the frozen account: ${pendingHref}`,
  ).toBe(acct);

  // The un-scheduled "Delete account" link is replaced, not shown alongside.
  await expect(deleteAccountLink(page)).toHaveCount(0);
});

// Not covered here: a *non-staff member* of a frozen account seeing the red
// "Account scheduled for deletion" banner (form.html:3-23) and cancelling from
// it. That needs a second member on the account, and the invite has to be
// accepted before the account is frozen (CreateAccountInvite returns
// FailedPrecondition once deletion_on is set). Blocked on the accept-invite
// helper, so it stays a manual check.
//
// Note: a grey-box check that scheduling writes a deletion-scheduled email row
// was removed — the account_dissolution email has no UI/API surface and was
// verifiable only through the read-only DB layer (intentionally not used). The
// schedule/cancel cycle itself is covered by the test above.
