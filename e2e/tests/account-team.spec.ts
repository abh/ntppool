import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { expectCleanPage } from "../lib/helpers";

// Account team / user removal (Gitea #14; MANUAL_TEST_PLAN.md §4).
//
// SCOPE NOTE — the core of #14 (removing a real member, the self-removal block
// with >1 member, and the removal-notification email) all require an account
// with TWO real members. The only way to add a second *accepted* member through
// the app is the invite-accept flow, which needs the invite `code` (available
// only via the DB or the invite email body) plus a second authenticated
// identity — the same dependency already documented as deferred/skipped in
// invites.spec.ts. There is no DB layer and no email-side-effect surface in this
// harness, so those cases are written as test.skip with the assertion shape kept
// ready. Closing them needs a dev-only test RPC (e.g. add-member, or
// accept-invite-by-code), guarded like AuthService.CreateTestSession.
//
// What IS feasible with a single-member account is asserted below.
//
// Routes / template:
//   - GET  /manage/account/team   render_users -> tpl/account/team.html
//   - POST /manage/account/team   user_id=<id>  -> _remove_user_from_account
//
// Real selectors from team.html:
//   - h3 "<account name> - Account team"
//   - member rows: table.table > tr, each <td> shows user.email
//   - remove control: button[name="user_id"] "Remove from team", rendered only
//     when account.permissions.can_edit AND users.size > 1 AND not yourself
//     (unless staff).

const TEAM_PATH = "/manage/account/team";

function removeButtons(page: Page) {
  return page.locator('button[name="user_id"]', { hasText: "Remove from team" });
}

function memberRows(page: Page) {
  return page.locator("table.table tr");
}

test("team page renders and lists the logged-in user as a member", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("team-self");
  await loginAs(context, email);

  await expectCleanPage(page, TEAM_PATH);

  // Heading from team.html: "<account name> - Account team".
  await expect(
    page.getByRole("heading", { name: /- Account team$/ }),
  ).toBeVisible();

  // The fresh user is the sole member and appears in the member table.
  await expect(memberRows(page)).toHaveCount(1);
  await expect(memberRows(page).first()).toContainText(email);
});

test("a sole-member account shows no Remove control", async ({
  page,
  context,
}) => {
  // team.html only renders "Remove from team" when users.size > 1 (and never for
  // yourself unless staff). With one member there is no remove control — the UI
  // expression of the self-removal / last-member guard for a single-owner
  // account.
  await loginAs(context, uniqueTestEmail("team-noremove"));

  await expectCleanPage(page, TEAM_PATH);
  await expect(removeButtons(page)).toHaveCount(0);
});

test("an outsider cannot view another account's team members", async ({
  browser,
}) => {
  // Context A: owner with their own account + a known member (themselves).
  const ownerContext = await browser.newContext();
  const ownerPage = await ownerContext.newPage();
  const owner = uniqueTestEmail("team-owner");
  await loginAs(ownerContext, owner);
  await expectCleanPage(ownerPage, TEAM_PATH);
  await expect(ownerPage.locator("table.table")).toContainText(owner);

  // Find the owner's account token to attempt cross-account access with it.
  const ownerToken = await firstAccountToken(ownerPage);
  expect(ownerToken, "expected the owner's account token").not.toBeNull();

  // Context B: an unrelated user. Their own team page lists themselves, not the
  // owner.
  const otherContext = await browser.newContext();
  const otherPage = await otherContext.newPage();
  const other = uniqueTestEmail("team-outsider");
  await loginAs(otherContext, other);

  await expectCleanPage(otherPage, TEAM_PATH);
  await expect(otherPage.locator("table.table")).toContainText(other);
  await expect(otherPage.locator("body")).not.toContainText(owner);

  // Passing the owner's ?a= token grants no access: the controller bounces a
  // non-member away (to /manage/) rather than rendering the owner's team, so the
  // owner's email never appears for the outsider.
  await otherPage.goto(`${TEAM_PATH}?a=${encodeURIComponent(ownerToken!)}`);
  await expect(otherPage.locator("body")).not.toContainText(owner);

  await ownerContext.close();
  await otherContext.close();
});

test.skip("removing a second member drops them from the team and notifies them", async ({
  page,
  context,
}) => {
  // §4 / #14 cases 1, 3, 4: with a 2-member account, the owner removes the other
  // member; the member table shrinks to 1, the removed user no longer appears,
  // and a removal email is sent (TO removed user, CC remaining members).
  //
  // SKIPPED: setting up a second *accepted* member needs the invite code (DB or
  // email body) and a second identity to accept it — deferred, exactly as in
  // invites.spec.ts. The email assertion additionally needs an email-side-effect
  // surface this harness does not have. Once a dev-only add-member/accept-by-code
  // RPC exists, drive it here and assert:
  //   await removeButtons(page).first().click();
  //   await expect(memberRows(page)).toHaveCount(1);
  //   await expect(page.locator("table.table")).not.toContainText(removedEmail);
  await loginAs(context, uniqueTestEmail("team-remove"));
  await expectCleanPage(page, TEAM_PATH);
});

test.skip("a member cannot remove themselves from a multi-member account", async ({
  page,
  context,
}) => {
  // §4 / #14 case 2: in a 2-member account the API blocks self-removal
  // (CodePermissionDenied, "you cannot remove yourself from an account"). The
  // non-staff UI never offers a self-remove control (team.html excludes yourself
  // from the remove button), and a forced self-removal POST is a no-op.
  //
  // SKIPPED: needs a 2-member account (see the note at the top of this file).
  // Assertion shape, once members can be provisioned:
  //   - no remove button targets your own user_id, and
  //   - a forced POST with your own user_id leaves the member list unchanged.
  await loginAs(context, uniqueTestEmail("team-self-remove"));
  await expectCleanPage(page, TEAM_PATH);
});

// First distinct a=acc_ token referenced on the current page, or null.
async function firstAccountToken(page: Page): Promise<string | null> {
  const hrefs = await page
    .locator("a[href]")
    .evaluateAll((els) =>
      els.map((e) => (e as HTMLAnchorElement).getAttribute("href") || ""),
    );
  for (const h of hrefs) {
    const m = h.match(/[?&]a=(acc_[a-z0-9]+)/i);
    if (m) {
      return m[1];
    }
  }
  return null;
}
