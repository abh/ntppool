import { expect, Browser, BrowserContext, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  bust,
  expectCleanPage,
  expectNoErrorBleed,
  createAccount,
} from "../lib/helpers";
import {
  test,
  DISSOLVE_PATH,
  dissolveUrl,
  resolveDefaultAccountToken,
  scheduleAccountDeletion,
} from "../lib/accounts";

// Staff-targeted user & account deletion, plus the scoping checks. This
// complements account-dissolve.spec.ts, which covers a staff user dissolving
// its OWN account; here staff act on ANOTHER account / user, and a non-staff
// user is confirmed to have no such reach.
//
// Controller: lib/NTPPool/Control/Manage/Account.pm manage_dispatch:
//   - /manage/account/team   render_users -> tpl/account/team.html. Staff see a
//     per-user "Delete user" link to /manage/account/delete?u=<user.id_token>
//     (team.html `[% IF combust.user_is_staff %]`); non-staff never see it.
//   - /manage/account/delete?u=<token>  (manage_dispatch lines ~220-240):
//       * u == self           -> act on self
//       * u != self & staff   -> get_user(id_token=u), act on target user
//       * u != self & !staff  -> `return 403 unless $self->user_is_staff`
//     GET  renders tpl/user/delete_confirmation.html (form "Delete user account")
//     POST schedules; targeting another user renders tpl/user/delete_scheduled.html
//     showing the TARGET's email ("Deletion scheduled for user <email>").
//   - /manage/account/dissolve  render_account_dissolve. Staff-gated GET +
//     schedule; scopes to current_account (the `a=` token). On success it
//     REDIRECTS to /manage/account; the pending state (date + cancel) shows on a
//     GET revisit. Account context is the `a=` param; staff may switch into any
//     account (api sessions.go: SupportStaff override in ValidateSession), a
//     non-staff user requesting a foreign account gets PermissionDenied.
//
// Audit log type strings (api/server/api/{user,account}/schedule_deletion.go):
//   - user deletion:    logs.type = "user",    message "scheduled deletion of
//                       user <email> (<id>)", user_id = acting STAFF user,
//                       account_id = target user's account(s).
//   - account deletion: logs.type = "account", message "scheduled deletion of
//                       account "<name>" (<id>) for <date>", account_id = target
//                       account, user_id = acting STAFF user.
//   NOTE: logs.user_id is the ACTING staff user, not the subject. We have only
//   id_tokens (mintSession returns a token, not numeric ids), so the DB asserts
//   filter by action and match the target's email/name in `message` rather than
//   by numeric subject id.
//
// Obtaining the target's tokens (mintSession returns only a session token):
//   1. Account token: log the freshly minted target into its OWN context, GET
//      /manage, and read `?a=<token>` from the redirect URL (Manage.pm sends a
//      logged-in user to /manage/servers?a=<account>).
//   2. User id_token: as STAFF, GET /manage/account/team?a=<accountToken>; the
//      "Delete user" link href carries u=<user.id_token>. This is the realistic
//      path (and exactly what a staff operator would click), so we extract it
//      from the rendered DOM rather than guessing a token format.

const TEAM_PATH = "/manage/account/team";
const DELETE_PATH = "/manage/account/delete";

interface Target {
  email: string;
  /** Account id_token, used as the `a=` account-context param. */
  accountToken: string;
}

/**
 * Mint a fresh throwaway user+account and resolve its account id_token from the
 * target's own /manage redirect. Returns the target info and the logged-in
 * target context (caller is responsible for closing it).
 *
 * mintSession returns only a session token (no numeric ids), so we discover the
 * account id_token from the URL the target's own /manage redirects to.
 */
async function mintTarget(
  browser: Browser,
): Promise<{ target: Target; targetContext: BrowserContext }> {
  const email = uniqueTestEmail("staff-del-target");
  const targetContext = await browser.newContext();
  // Install the target's own session cookie so its /manage resolves its account.
  await loginAs(targetContext, email);

  const page = await targetContext.newPage();
  // Manage.pm routes a logged-in user to /manage/servers?a=<accountToken>.
  const accountToken = await resolveDefaultAccountToken(page);

  await page.close();
  return { target: { email, accountToken }, targetContext };
}

/**
 * As staff, load the target account's team page and extract the target user's
 * id_token from the "Delete user" link href (u=<token>).
 */
async function targetUserTokenFromTeam(
  staffPage: Page,
  accountToken: string,
): Promise<string> {
  await expectCleanPage(
    staffPage,
    `${TEAM_PATH}?a=${encodeURIComponent(accountToken)}`,
  );

  // The staff-only "Delete user" link (team.html `[% IF combust.user_is_staff %]`)
  // points at /manage/account/delete?...&u=<user.id_token>.
  const deleteLink = staffPage
    .locator(`a[href*="${DELETE_PATH}"]`, { hasText: "Delete user" })
    .first();
  await expect(
    deleteLink,
    "staff team page should show a Delete user link",
  ).toBeVisible();

  const href = await deleteLink.getAttribute("href");
  expect(href, "Delete user link should have an href").toBeTruthy();
  const u = new URL(href!, staffPage.url()).searchParams.get("u");
  expect(u, `Delete user link should carry u=<token>: ${href}`).toBeTruthy();
  return u!;
}

test("staff can open another account's team page and see the target user", async ({
  page,
  context,
  browser,
}) => {
  // As staff, open another account's team page (with that account's context)
  // and confirm it renders and lists the target user.
  const { target, targetContext } = await mintTarget(browser);

  try {
    await loginAs(context, uniqueTestEmail("staff-team-viewer"), {
      grantStaff: true,
    });

    await expectCleanPage(
      page,
      `${TEAM_PATH}?a=${encodeURIComponent(target.accountToken)}`,
    );

    // The team table lists account members by email (team.html row: user.email).
    await expect(page.locator("body")).toContainText(target.email);

    // The team heading reads "<account name> - Account team" (team.html h3); a
    // staff override into a foreign account renders it normally, not an error.
    await expect(
      page.getByRole("heading", { name: /Account team$/ }),
    ).toBeVisible();
  } finally {
    await targetContext.close();
  }
});

test("staff schedules deletion of another USER, targeting that user (not self)", async ({
  page,
  context,
  browser,
}) => {
  // Schedule deletion for another user via u=<target id_token>; the
  // deletion-scheduled page must name the TARGET, not the acting staff user.
  const staffEmail = uniqueTestEmail("staff-user-deleter");
  const { target, targetContext } = await mintTarget(browser);

  try {
    await loginAs(context, staffEmail, { grantStaff: true });

    // Extract the target user's id_token from the staff team-page DOM (the
    // delete link must carry the correct user's token).
    const targetUserToken = await targetUserTokenFromTeam(
      page,
      target.accountToken,
    );

    // GET the delete confirmation for the target user. delete_confirmation.html
    // shows the target email as the <h3> and (a fresh user with no servers is
    // deletable) a "Delete user account" submit button.
    const deleteUrl = `${DELETE_PATH}?a=${encodeURIComponent(
      target.accountToken,
    )}&u=${encodeURIComponent(targetUserToken)}`;
    await expectCleanPage(page, deleteUrl);
    await expect(
      page.getByRole("heading", { name: target.email }),
    ).toBeVisible();
    // Crucially NOT the staff user's own email (we are not deleting ourselves).
    // Scope to the delete-confirmation content: the acting staff user's email
    // legitimately appears in the page chrome (the "Logout (…)" link and the
    // staff Admin-search recent-accounts list), so a body-wide check is too broad.
    const confirmContent = page
      .locator(".col-md-10")
      .filter({ has: page.getByRole("heading", { name: target.email }) });
    await expect(confirmContent).not.toContainText(staffEmail);

    // Submit the schedule. POST renders tpl/user/delete_scheduled.html (because
    // is_self is false; the self path would redirect to /manage/logout).
    await page
      .getByRole("button", { name: "Delete user account" })
      .click();
    await page.waitForLoadState("networkidle");
    await expectNoErrorBleed(page, page.url());

    // delete_scheduled.html: "Deletion scheduled for user <target email>".
    await expect(
      page.getByRole("heading", { name: "Deletion scheduled" }),
    ).toBeVisible();
    // Scope to the scheduled-confirmation content for the same chrome reason as
    // above (staff email appears in nav/admin-search, never in the delete content).
    const scheduledContent = page
      .locator(".col-md-10")
      .filter({
        has: page.getByRole("heading", { name: "Deletion scheduled" }),
      });
    await expect(scheduledContent).toContainText(target.email);
    // The acting staff user must not be the one shown as scheduled.
    await expect(scheduledContent).not.toContainText(staffEmail);
  } finally {
    await targetContext.close();
  }
});

test("staff schedules another ACCOUNT's deletion, scoped to that account", async ({
  page,
  context,
  browser,
  scheduledDeletions,
}) => {
  // Schedule another account's deletion as staff — works, scoped to the target
  // account (the `a=` context), not the staff user's own account.
  const staffEmail = uniqueTestEmail("staff-account-deleter");
  const { target, targetContext } = await mintTarget(browser);

  try {
    // Dissolution refuses to orphan a member, so the target's sole-owner primary
    // account can't be dissolved. Give the target a SECOND account (in its own
    // context); staff then dissolves that one — the target keeps its primary, so
    // no member is orphaned.
    const targetPage = await targetContext.newPage();
    const dissolveAcct = await createAccount(targetPage);
    await targetPage.close();

    await loginAs(context, staffEmail, { grantStaff: true });

    // This test asserts the pending state, then must not leave it pending.
    // Register before scheduling, so teardown is already armed.
    scheduledDeletions.register(dissolveAcct);

    // Schedule in the TARGET account context. scheduleAccountDeletion loads the
    // dissolve confirmation (heading "Delete account: <name>"), clicks through,
    // and waits for the redirect back to the dissolve page for THIS account —
    // render_account_dissolve keeps the a=<dissolveAcct> context rather than
    // going to /manage/account, which would bounce a pending-deletion account.
    await scheduleAccountDeletion(page, dissolveAcct);

    // Revisit the dissolve page for the TARGET account — pending state with a
    // scheduled date and a cancel option, scoped to that account.
    await expectCleanPage(page, bust(dissolveUrl(dissolveAcct)));
    await expect(page.locator("body")).toContainText("Deletion scheduled");
    await expect(page.locator("body")).toContainText(
      "scheduled for deletion on",
    );
    // A rendered ISO date (the API picks +7d; asserting a date appears suffices).
    await expect(page.locator("body")).toContainText(/\d{4}-\d{2}-\d{2}/);
    await expect(
      page.getByRole("button", { name: "Cancel scheduled deletion" }),
    ).toBeVisible();
  } finally {
    await targetContext.close();
  }
});

test("non-staff user cannot target another user or account", async ({
  browser,
}) => {
  // A non-staff fresh user must only reach its own user/account. We verify the
  // negative on three surfaces:
  //   (a) the staff-only "Delete user" link is absent on the team page,
  //   (b) /manage/account/delete?u=<foreign token> returns 403 (manage_dispatch
  //       `return 403 unless $self->user_is_staff`),
  //   (c) /manage/account/dissolve?a=<foreign token> is denied — current_account
  //       can't resolve a foreign account for a non-staff user (api
  //       ValidateSession PermissionDenied), so the route does not show the
  //       schedule form for someone else's account.
  const { target, targetContext } = await mintTarget(browser);
  const nonStaffContext = await browser.newContext();

  try {
    await loginAs(nonStaffContext, uniqueTestEmail("non-staff-actor"));
    const page = await nonStaffContext.newPage();

    // (a) Non-staff loads its OWN team page: no "Delete user" link at all
    // (team.html gates it on combust.user_is_staff).
    await expectCleanPage(page, TEAM_PATH);
    await expect(
      page.locator(`a[href*="${DELETE_PATH}"]`, { hasText: "Delete user" }),
    ).toHaveCount(0);

    // (b) Directly hit the user-delete route for the FOREIGN target's account,
    // with a `u=` that is not self. The non-staff branch returns 403. Because
    // the `u=` token belongs to another user we cannot read it without staff;
    // it's enough to show that any non-self `u=` is rejected. Use the foreign
    // account token as a stand-in non-self `u=` value: the controller checks
    // `$u_token ne $self_token` first, then `return 403 unless user_is_staff`,
    // so any value that isn't the caller's own id_token trips the 403 for a
    // non-staff user. (Marked uncertain: if the token coincidentally equals the
    // caller's own id_token the branch is skipped — astronomically unlikely for
    // distinct minted accounts.)
    const foreignDelete = await page.goto(
      `${DELETE_PATH}?a=${encodeURIComponent(
        target.accountToken,
      )}&u=${encodeURIComponent(target.accountToken)}`,
    );
    expect(foreignDelete, "no response from foreign delete route").not.toBeNull();
    // A non-staff user requesting a foreign account is denied: validate_session
    // rejects the foreign `a=`, current_account is undef, and the app renders the
    // sign-in page (HTTP 200) — NOT any delete UI. The security property is that
    // no actionable delete control is served, so assert that rather than a status
    // code (page.goto follows redirects; a safe denial is a 200 login page).
    await expect(
      page.getByRole("button", { name: "Delete user account" }),
    ).toHaveCount(0);
    await expect(
      page.locator('form[action*="/manage/account/delete"]'),
    ).toHaveCount(0);

    // (c) Foreign account dissolve: denied for non-staff. The foreign `a=` fails
    // account resolution before the dissolve branch's staff guard, so the app
    // renders the sign-in page (HTTP 200) and never the schedule form. As above,
    // assert the schedule control is absent rather than checking the status code.
    const foreignDissolve = await page.goto(
      `${DISSOLVE_PATH}?a=${encodeURIComponent(target.accountToken)}`,
    );
    expect(
      foreignDissolve,
      "no response from foreign dissolve route",
    ).not.toBeNull();
    await expect(
      page.getByRole("button", { name: "Schedule account deletion" }),
    ).toHaveCount(0);
  } finally {
    await nonStaffContext.close();
    await targetContext.close();
  }
});

// Note: two grey-box checks that scheduling a user/account deletion writes an
// audit-log ("logs") row were removed — the audit log has no UI/API surface and
// was verifiable only through the read-only DB layer (intentionally not used).
// The scheduling behavior itself is covered by the staff user/account deletion
// tests above. Restore these if/when an audit-log API surface exists.
