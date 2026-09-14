import { test, expect, Browser, BrowserContext, Page } from "@playwright/test";
import { resolveDefaultAccountToken } from "../lib/accounts";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  acceptInvite,
  errorAlerts,
  expectCleanPage,
  expectNoErrorBleed,
  inviteUser,
} from "../lib/helpers";

// Account team / user removal (Gitea #14; MANUAL_TEST_PLAN.md §4).
//
// A 2-member account is built with the real invite + accept flow: inviteUser
// (send, as the owner) then acceptInvite (accept, as a second identity in a
// second BrowserContext) — see lib/helpers.ts. Neither needs DB access or an
// email body: get_account_invites(for_user => 1) serves the invite `code`
// straight to whichever user is logged in and it's rendered right into the
// Accept form (Gitea #46).
//
// The removal-notification email itself is not independently verified —
// there is no email-side-effect surface in this harness (same limitation
// noted in invites.spec.ts's Resend test), so the member list is the
// observable assertion.
//
// Routes / template:
//   - GET  /manage/account/team   render_users -> tpl/account/team.html
//   - POST /manage/account/team   user_id=<id>  -> _remove_user_from_account
//
// Real selectors from team.html:
//   - h3 "<account name> - Account team"
//   - member rows: table.table > tr, each <td> shows user.email. The member
//     table lives inside the first #account-form; once an invite has ever
//     existed on the account, a SEPARATE "Account invitations" table (its own
//     table.table, with a header row) renders further down the page, so scope
//     past the member form rather than matching "table.table" bare.
//   - remove control: button[name="user_id"] "Remove from team", rendered only
//     when account.permissions.can_edit AND users.size > 1 AND not yourself
//     (unless staff).

const TEAM_PATH = "/manage/account/team";

function memberForm(page: Page) {
  // Duplicate id="account-form" on the page (member table + invite-create
  // form below it) — the member table is the first one in document order.
  return page.locator("#account-form").first();
}

function removeButtons(page: Page) {
  return memberForm(page).locator('button[name="user_id"]', {
    hasText: "Remove from team",
  });
}

function memberRows(page: Page) {
  return memberForm(page).locator("table.table tr");
}

// The Remove control on one member's row. A member's numeric user_id is only
// ever exposed as this button's value (team.html), so this doubles as the way
// to read it.
function removeButtonFor(page: Page, email: string) {
  return memberRows(page)
    .filter({ hasText: email })
    .locator('button[name="user_id"]');
}

/**
 * Force a removal POST the UI does not offer: inject a hidden user_id into the
 * member form — which still carries the account token and the CSRF auth_token —
 * and submit. This proves the Go API's server-side guard rather than just the
 * absence of a button.
 */
async function forceRemovalPost(page: Page, userId: string): Promise<void> {
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    memberForm(page).evaluate((form, id) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "user_id";
      input.value = id;
      (form as HTMLFormElement).appendChild(input);
      (form as HTMLFormElement).submit();
    }, userId),
  ]);
  await expectNoErrorBleed(page, page.url());
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

/**
 * Build a 2-member account: `owner` invites `invitee` and `invitee` accepts,
 * for real, through the browser-only invite/accept flow. Returns the two
 * contexts (caller must close them) plus their pages, already logged in.
 * `ownerLoginOptions` is passed to the owner's loginAs; the invitee is always
 * an ordinary user. Only `grantStaff` is honoured: the other MintOptions
 * either contradict this helper (`existingUser` — it always mints a fresh
 * owner) or have no bearing on team.html.
 * `inviteePage` is wherever the post-accept redirect landed — NOT necessarily
 * the team page, since a brand-new invitee with no prior account redirects
 * through /manage instead (see acceptInvite) — so callers that need the team
 * page must navigate there explicitly.
 */
async function buildTwoMemberAccount(
  browser: Browser,
  prefix: string,
  ownerLoginOptions: { grantStaff?: boolean } = {},
): Promise<{
  ownerContext: BrowserContext;
  ownerPage: Page;
  inviteeContext: BrowserContext;
  inviteePage: Page;
  owner: string;
  invitee: string;
}> {
  const ownerContext = await browser.newContext();
  const ownerPage = await ownerContext.newPage();
  const owner = uniqueTestEmail(`${prefix}-owner`);
  await loginAs(ownerContext, owner, ownerLoginOptions);

  const invitee = uniqueTestEmail(`${prefix}-invitee`);
  await inviteUser(ownerPage, invitee);

  const inviteeContext = await browser.newContext();
  const inviteePage = await inviteeContext.newPage();
  await loginAs(inviteeContext, invitee);
  await acceptInvite(inviteePage);

  return { ownerContext, ownerPage, inviteeContext, inviteePage, owner, invitee };
}

test("removing a second member drops them from the team and notifies them", async ({
  browser,
}) => {
  // §4 / #14 cases 1, 3, 4: with a 2-member account, the owner removes the other
  // member; the member table shrinks to 1 and the removed user no longer
  // appears. (Removal-email delivery itself is not asserted — see the note at
  // the top of this file.)
  const { ownerContext, ownerPage, inviteeContext, invitee } =
    await buildTwoMemberAccount(browser, "team-remove");

  await expectCleanPage(ownerPage, TEAM_PATH);
  await expect(memberRows(ownerPage)).toHaveCount(2);

  const inviteeRow = memberRows(ownerPage).filter({ hasText: invitee });
  await Promise.all([
    // A successful removal re-renders team.html at the same URL rather than
    // redirecting, so waitForURL (which would resolve immediately against the
    // already-matching current URL) is wrong here — wait for the navigation
    // itself.
    ownerPage.waitForNavigation({ waitUntil: "load" }),
    inviteeRow.locator('button[name="user_id"]').click(),
  ]);
  await expectNoErrorBleed(ownerPage, ownerPage.url());

  await expect(memberRows(ownerPage)).toHaveCount(1);
  await expect(memberForm(ownerPage)).not.toContainText(invitee);

  await ownerContext.close();
  await inviteeContext.close();
});

test("a member cannot remove themselves from a multi-member account", async ({
  browser,
}) => {
  // §4 / #14 case 2: in a 2-member account the API blocks self-removal
  // (RemoveUserFromAccount: "you cannot remove yourself from an account"). The
  // non-staff UI never offers a self-remove control (team.html excludes
  // yourself from the remove button), and a forced self-removal POST is a
  // no-op. Acting user is the invited (non-owner) member, matching the
  // self-removal error path this unblocks.
  const { ownerContext, ownerPage, inviteeContext, inviteePage, invitee } =
    await buildTwoMemberAccount(browser, "team-self-remove");

  await expectCleanPage(inviteePage, TEAM_PATH);

  // The invitee's own row never gets a remove control: 2 members, 1 remove
  // button (targeting the owner's row only).
  await expect(memberRows(inviteePage)).toHaveCount(2);
  await expect(removeButtons(inviteePage)).toHaveCount(1);

  // The invitee's numeric user_id is never exposed on their own page (their
  // row has no button), but it IS the value of the button the OWNER sees on
  // the invitee's row. ownerPage is still showing its pre-accept render (built
  // by inviteUser, before the invitee accepted), so reload it first.
  await expectCleanPage(ownerPage, TEAM_PATH);
  const inviteeUserId = await removeButtonFor(ownerPage, invitee).getAttribute(
    "value",
  );
  expect(
    inviteeUserId,
    "expected the invitee's user_id on the owner's page",
  ).toMatch(/^\d+$/);

  // Target yourself with the removal the UI never offers.
  await forceRemovalPost(inviteePage, inviteeUserId!);

  await expect(errorAlerts(inviteePage)).toContainText(/yourself/i);
  await expect(memberRows(inviteePage)).toHaveCount(2);

  await ownerContext.close();
  await inviteeContext.close();
});

test("staff clicking Remove on their own row is refused with the self-removal message", async ({
  browser,
}) => {
  // §4b: team.html renders "Remove from team" on a staff user's OWN row too
  // (`combust.user_is_staff OR combust.user.user_id != user.user_id`), unlike
  // the non-staff case above. The Go API refuses self-removal with no staff
  // exemption (RemoveUserFromAccount: "you cannot remove yourself from an
  // account"), and _remove_user_from_account shows that message rather than
  // the old generic "Failed to remove user. Please try again.".
  const { ownerContext, ownerPage, inviteeContext, owner, invitee } =
    await buildTwoMemberAccount(browser, "staff-self-remove", {
      grantStaff: true,
    });

  // ownerPage still shows inviteUser's pre-accept render; load a fresh one so
  // both members are listed.
  await expectCleanPage(ownerPage, TEAM_PATH);
  await expect(memberRows(ownerPage)).toHaveCount(2);

  // Staff gets a Remove button on every row, their own included (a non-staff
  // member sees only 1 here).
  await expect(removeButtons(ownerPage)).toHaveCount(2);
  const ownRemove = removeButtonFor(ownerPage, owner);
  await expect(ownRemove).toHaveCount(1);

  await Promise.all([
    // The refusal re-renders team.html at the same URL, so wait for the
    // navigation itself rather than a URL change.
    ownerPage.waitForNavigation({ waitUntil: "load" }),
    ownRemove.click(),
  ]);
  await expectNoErrorBleed(ownerPage, ownerPage.url());

  // Exactly one alert, carrying the API's message rather than the generic
  // "Failed to remove user. Please try again." this replaced. (For staff,
  // log_table.html adds an .alert-warning only when the audit-log fetch
  // failed.)
  const alerts = errorAlerts(ownerPage);
  await expect(alerts).toHaveCount(1);
  await expect(alerts).toContainText(
    /you cannot remove yourself from an account/i,
  );

  // Nobody was removed.
  await expect(memberRows(ownerPage)).toHaveCount(2);
  await expect(memberForm(ownerPage)).toContainText(owner);
  await expect(memberForm(ownerPage)).toContainText(invitee);

  await ownerContext.close();
  await inviteeContext.close();
});

test("staff cannot remove the last member of an account", async ({
  browser,
}) => {
  // §4b: RemoveUserFromAccount checks self-removal BEFORE counting members
  // (mutations.go), so "cannot remove the last user from an account" is only
  // reachable by an editor who isn't the remaining member: a non-member staff
  // user on someone else's account via the ?a= override. The UI never renders
  // Remove on a one-member account (team.html: users.size > 1), and a member's
  // numeric user_id only appears as a Remove button's value. So: build a
  // 2-member account, read the owner's user_id while both buttons exist,
  // remove the invitee for real, then force the POST for the owner.
  const { ownerContext, ownerPage, inviteeContext, owner, invitee } =
    await buildTwoMemberAccount(browser, "staff-lastmember");

  const ownerToken = await resolveDefaultAccountToken(ownerPage);

  const staffContext = await browser.newContext();
  const staffPage = await staffContext.newPage();
  await loginAs(staffContext, uniqueTestEmail("staff-lastmember-actor"), {
    grantStaff: true,
  });

  await expectCleanPage(
    staffPage,
    `${TEAM_PATH}?a=${encodeURIComponent(ownerToken)}`,
  );
  await expect(memberRows(staffPage)).toHaveCount(2);
  await expect(removeButtons(staffPage)).toHaveCount(2);

  const ownerUserId = await removeButtonFor(staffPage, owner).getAttribute(
    "value",
  );
  expect(ownerUserId, "expected the owner's user_id on the staff page").toMatch(
    /^\d+$/,
  );

  // Get down to one member through the ordinary removal path.
  await Promise.all([
    staffPage.waitForNavigation({ waitUntil: "load" }),
    removeButtonFor(staffPage, invitee).click(),
  ]);
  await expectNoErrorBleed(staffPage, staffPage.url());
  await expect(errorAlerts(staffPage)).toHaveCount(0);
  await expect(memberRows(staffPage)).toHaveCount(1);
  await expect(memberForm(staffPage)).not.toContainText(invitee);

  // One member left: no Remove control for anyone, staff included.
  await expect(removeButtons(staffPage)).toHaveCount(0);

  // Target the sole remaining member, which the UI no longer offers.
  await forceRemovalPost(staffPage, ownerUserId!);

  const alerts = errorAlerts(staffPage);
  await expect(alerts).toHaveCount(1);
  await expect(alerts).toContainText(
    /cannot remove the last user from an account/i,
  );

  // The owner is still the account's member.
  await expect(memberRows(staffPage)).toHaveCount(1);
  await expect(memberForm(staffPage)).toContainText(owner);

  await ownerContext.close();
  await inviteeContext.close();
  await staffContext.close();
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
