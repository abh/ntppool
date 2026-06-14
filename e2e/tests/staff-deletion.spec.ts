import { test, expect, Browser, BrowserContext, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { expectCleanPage, expectNoErrorBleed } from "../lib/helpers";
import { auditLogFor } from "../lib/db";

// Staff-targeted user & account deletion (MANUAL_TEST_PLAN.md §3) plus the §4
// scoping checks. This complements account-dissolve.spec.ts (§2), which covers
// a staff user dissolving its OWN account; here staff act on ANOTHER account /
// user, and a non-staff user is confirmed to have no such reach.
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
const DISSOLVE_PATH = "/manage/account/dissolve";

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
  const response = await page.goto("/manage");
  expect(response, "no response from /manage for target").not.toBeNull();
  expect(response!.status()).toBe(200);

  // Manage.pm routes a logged-in user to /manage/servers?a=<accountToken>.
  const url = new URL(page.url());
  const accountToken = url.searchParams.get("a");
  expect(
    accountToken,
    `target /manage URL should carry an account token: ${page.url()}`,
  ).toBeTruthy();

  await page.close();
  return { target: { email, accountToken: accountToken! }, targetContext };
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
  // §3: As staff, open another account's team page (with that account's
  // context) and confirm it renders and lists the target user.
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
  // §3 + §4: schedule deletion for another user via u=<target id_token>; the
  // deletion-scheduled page must name the TARGET, not the acting staff user.
  const staffEmail = uniqueTestEmail("staff-user-deleter");
  const { target, targetContext } = await mintTarget(browser);

  try {
    await loginAs(context, staffEmail, { grantStaff: true });

    // Extract the target user's id_token from the staff team-page DOM (§4: the
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
    await expect(page.locator("body")).not.toContainText(staffEmail);

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
    await expect(page.locator("body")).toContainText(target.email);
    // The acting staff user must not be the one shown as scheduled.
    await expect(page.locator("body")).not.toContainText(staffEmail);
  } finally {
    await targetContext.close();
  }
});

test("staff schedules another ACCOUNT's deletion, scoped to that account", async ({
  page,
  context,
  browser,
}) => {
  // §3: schedule another account's deletion as staff — works, scoped to the
  // target account (the `a=` context), not the staff user's own account.
  const staffEmail = uniqueTestEmail("staff-account-deleter");
  const { target, targetContext } = await mintTarget(browser);

  try {
    await loginAs(context, staffEmail, { grantStaff: true });

    // GET the dissolve confirmation in the TARGET account context. The page
    // heading names the target account ("Delete account: <name>"); a fresh
    // account has no blockers, so the schedule form is shown.
    await expectCleanPage(
      page,
      `${DISSOLVE_PATH}?a=${encodeURIComponent(target.accountToken)}`,
    );
    await expect(
      page.getByRole("heading", { name: /^Delete account:/ }),
    ).toBeVisible();

    // Schedule. render_account_dissolve redirects to /manage/account on success
    // (still in the target's account context, a=<target token>).
    await Promise.all([
      page.waitForURL(
        new RegExp(
          `/manage/account\\?a=${escapeRegExp(target.accountToken)}`,
        ),
      ),
      page
        .getByRole("button", { name: "Schedule account deletion" })
        .click(),
    ]);
    await expectNoErrorBleed(page, page.url());

    // §3 + §4: Revisit the dissolve page for the TARGET account — pending state
    // with a scheduled date and a cancel option, scoped to that account.
    await expectCleanPage(
      page,
      `${DISSOLVE_PATH}?a=${encodeURIComponent(target.accountToken)}`,
    );
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
  context,
  browser,
}) => {
  // §3 + §4: a non-staff fresh user must only reach its own user/account. We
  // verify the negative on three surfaces:
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
    // current_account resolves the `a=` first; a non-staff user requesting a
    // foreign account is denied before reaching the delete branch, so accept
    // either the account-context denial or the user_is_staff 403 — both are
    // "access denied", neither is a 200 schedule page.
    expect(
      foreignDelete!.status(),
      `non-staff must not get a 200 schedule page for a foreign user (got ${foreignDelete!.status()})`,
    ).not.toBe(200);

    // (c) Foreign account dissolve: denied for non-staff. A non-staff GET to
    // /manage/account/dissolve is 403 regardless (manage_dispatch
    // `return 403 unless $self->user_is_staff || $member_cancel`), and the
    // foreign `a=` would also fail account resolution.
    const foreignDissolve = await page.goto(
      `${DISSOLVE_PATH}?a=${encodeURIComponent(target.accountToken)}`,
    );
    expect(
      foreignDissolve,
      "no response from foreign dissolve route",
    ).not.toBeNull();
    expect(
      foreignDissolve!.status(),
      `non-staff must not get a 200 dissolve page for a foreign account (got ${foreignDissolve!.status()})`,
    ).not.toBe(200);
  } finally {
    await nonStaffContext.close();
    await targetContext.close();
  }
});

test("DB: scheduling a user deletion writes an audit-log row for the target", async ({
  page,
  context,
  browser,
}) => {
  // §3 grey-box side-effect: assert a logs row exists for the user deletion.
  // type = "user"; message contains the target email; user_id is the acting
  // staff user (so we match by action + message, not by numeric subject id).
  test.skip(
    !process.env.NTP_TEST_DB_URL,
    "DB layer not configured (NTP_TEST_DB_URL unset)",
  );

  const staffEmail = uniqueTestEmail("staff-user-del-db");
  const { target, targetContext } = await mintTarget(browser);

  try {
    await loginAs(context, staffEmail, { grantStaff: true });
    const targetUserToken = await targetUserTokenFromTeam(
      page,
      target.accountToken,
    );

    await expectCleanPage(
      page,
      `${DELETE_PATH}?a=${encodeURIComponent(
        target.accountToken,
      )}&u=${encodeURIComponent(targetUserToken)}`,
    );
    await page.getByRole("button", { name: "Delete user account" }).click();
    await page.waitForLoadState("networkidle");
    await expect(
      page.getByRole("heading", { name: "Deletion scheduled" }),
    ).toBeVisible();

    // The audit row is written in the same transaction as the schedule. Match a
    // recent type="user" row whose message names the target email.
    await expect
      .poll(
        async () => {
          const rows = await auditLogFor({ action: "user", limit: 25 });
          return rows.some((r) => (r.message || "").includes(target.email));
        },
        {
          message: `expected a type="user" audit row mentioning ${target.email}`,
          timeout: 10_000,
        },
      )
      .toBe(true);
  } finally {
    await targetContext.close();
  }
});

test("DB: scheduling an account deletion writes an audit-log row", async ({
  page,
  context,
  browser,
}) => {
  // §3 grey-box side-effect: assert a logs row exists for the account deletion.
  // type = "account"; message reads `scheduled deletion of account "<name>" ...`.
  // We don't know the auto-assigned account name, so match a recent type=
  // "account" row written right after our schedule (assert at least one such
  // row exists). Uncertain: without the numeric account_id we can't pin the row
  // to THIS account; the test schedules a fresh throwaway account and asserts an
  // "account" deletion row appears, which is the available precise-enough check.
  test.skip(
    !process.env.NTP_TEST_DB_URL,
    "DB layer not configured (NTP_TEST_DB_URL unset)",
  );

  const staffEmail = uniqueTestEmail("staff-acct-del-db");
  const { target, targetContext } = await mintTarget(browser);

  try {
    await loginAs(context, staffEmail, { grantStaff: true });

    await expectCleanPage(
      page,
      `${DISSOLVE_PATH}?a=${encodeURIComponent(target.accountToken)}`,
    );
    await Promise.all([
      page.waitForURL(
        new RegExp(`/manage/account\\?a=${escapeRegExp(target.accountToken)}`),
      ),
      page.getByRole("button", { name: "Schedule account deletion" }).click(),
    ]);
    await expectNoErrorBleed(page, page.url());

    await expect
      .poll(
        async () => {
          const rows = await auditLogFor({ action: "account", limit: 25 });
          return rows.some((r) =>
            (r.message || "").includes("scheduled deletion of account"),
          );
        },
        {
          message:
            'expected a type="account" audit row for the scheduled deletion',
          timeout: 10_000,
        },
      )
      .toBe(true);
  } finally {
    await targetContext.close();
  }
});

/** Escape a string for safe inclusion in a RegExp (account tokens are alnum). */
function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
