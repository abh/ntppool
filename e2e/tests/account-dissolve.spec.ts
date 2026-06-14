import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { expectCleanPage, expectNoErrorBleed } from "../lib/helpers";
import { latestEmailTo } from "../lib/db";

// Account scheduled deletion / dissolve flow (MANUAL_TEST_PLAN.md §2).
//
// Staff-only feature. Both the route and the UI link are gated on the
// support_staff privilege (lib/NTPPool/Control/Manage/Account.pm
// manage_dispatch: `return 403 unless $self->user_is_staff || $member_cancel`
// for /manage/account/dissolve; docs/manage/tpl/account/form.html:154
// `[% IF combust.user_is_staff %]`). A non-staff user gets a 403 and never
// sees the link — correct, not a bug.
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

const DISSOLVE_PATH = "/manage/account/dissolve";

// The destructive link on /manage/account is an <a class="text-danger"> reading
// "Delete account" before anything is scheduled (form.html:163).
function deleteAccountLink(page: Page) {
  return page.locator("a.text-danger", { hasText: "Delete account" });
}

// Schedule the deletion from the confirmation page and wait for the post-success
// redirect to /manage/account (render_account_dissolve redirects on scheduled).
async function scheduleDeletion(page: Page) {
  // Submit button value/text is "Schedule account deletion" (btn-warning).
  await Promise.all([
    page.waitForURL(/\/manage\/account(\?|$)/),
    page
      .getByRole("button", { name: "Schedule account deletion" })
      .click(),
  ]);
  await expectNoErrorBleed(page, page.url());
}

// Cancel a scheduled deletion from the confirmation page; on success the
// controller redirects back to /manage/account.
async function cancelDeletion(page: Page) {
  await Promise.all([
    page.waitForURL(/\/manage\/account(\?|$)/),
    page
      .getByRole("button", { name: "Cancel scheduled deletion" })
      .click(),
  ]);
  await expectNoErrorBleed(page, page.url());
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

  // GET /manage/account/dissolve is staff-only -> 403 (manage_dispatch).
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
}) => {
  const email = uniqueTestEmail("dissolve-cycle");
  await loginAs(context, email, { grantStaff: true });

  // §2: schedule deletion. The API picks a fixed 7-day-out date.
  await expectCleanPage(page, DISSOLVE_PATH);
  await scheduleDeletion(page);

  // Revisit the dissolve page: it now shows the pending scheduled state with a
  // cancel option (dissolve_confirmation.html `[% ELSIF pending %]`):
  //   - a "Deletion scheduled" badge,
  //   - the scheduled date (deletion_on, date-only),
  //   - a "Cancel scheduled deletion" button.
  await expectCleanPage(page, DISSOLVE_PATH);
  await expect(page.locator("body")).toContainText("Deletion scheduled");
  await expect(page.locator("body")).toContainText("scheduled for deletion on");
  // A scheduled-date marker: an ISO date (YYYY-MM-DD) is rendered in the notice.
  // The exact +7d value is the API's responsibility; asserting a date appears is
  // enough here.
  await expect(page.locator("body")).toContainText(
    /\d{4}-\d{2}-\d{2}/,
  );
  await expect(
    page.getByRole("button", { name: "Cancel scheduled deletion" }),
  ).toBeVisible();

  // §2: cancel — state clears and the account is back to normal. Leaving the
  // staff account scheduled for deletion would be unfriendly, so always cancel.
  await cancelDeletion(page);

  // The dissolve page is back to the un-scheduled state: schedule button shown,
  // no "Deletion scheduled" badge.
  await expectCleanPage(page, DISSOLVE_PATH);
  await expect(
    page.getByRole("button", { name: "Schedule account deletion" }),
  ).toBeVisible();
  await expect(page.locator("body")).not.toContainText("Deletion scheduled");
});

test("DB: scheduling writes a deletion-scheduled email row", async ({
  page,
  context,
}) => {
  // Grey-box side-effect check (§2: "Confirm the deletion-scheduled email is
  // sent"). The Go API sends an account_dissolution email to all account
  // members after scheduling (api/server/api/account/schedule_deletion.go ->
  // email.SendAccountDissolutionEmail). The fresh staff user is the sole member
  // of its own account, so the row is addressed to its email.
  //
  // Skip cleanly when the read-only DB layer is not configured.
  test.skip(
    !process.env.NTP_TEST_DB_URL,
    "DB layer not configured (NTP_TEST_DB_URL unset)",
  );

  const email = uniqueTestEmail("dissolve-email");
  await loginAs(context, email, { grantStaff: true });

  await expectCleanPage(page, DISSOLVE_PATH);
  await scheduleDeletion(page);

  // Email delivery is fired in a goroutine after the RPC commits, so allow a
  // short window for the emails row to appear.
  await expect
    .poll(
      async () => {
        const row = await latestEmailTo(email);
        return row?.email_type ?? null;
      },
      {
        message: "expected an account_dissolution email row for the staff user",
        timeout: 10_000,
      },
    )
    .toBe("account_dissolution");

  // Subject is "NTP Pool account scheduled for deletion: <account name>"
  // (api/email/templates.go SendAccountDissolutionEmail).
  const row = await latestEmailTo(email);
  expect(row).not.toBeNull();
  expect(row!.subject).toContain(
    "NTP Pool account scheduled for deletion",
  );

  // Clean up: cancel the scheduled deletion so the staff account is left normal.
  await expectCleanPage(page, DISSOLVE_PATH);
  await cancelDeletion(page);
});
