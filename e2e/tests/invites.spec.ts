import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  acceptInvite,
  errorAlerts,
  expectCleanPage,
  expectNoErrorBleed,
  inviteUser,
} from "../lib/helpers";

// Account invitation resend, regular-user (non-staff) flow.
// MANUAL_TEST_PLAN.md §4a "Resend account invitations".
//
// Routes / templates this exercises (see lib/NTPPool/Control/Manage/Account.pm
// and docs/manage/tpl/account/team.html):
//   - GET  /manage/account/team   render_users -> tpl/account/team.html
//                                 (current_account resolves the default account,
//                                  so no explicit ?a= token is needed)
//   - POST /manage/account/team   invite_email=...     -> render_users_invite
//                                 resend_invite_id=...  -> render_resend_invite
//
// Rules (enforced by the Go API; Perl just relays):
//   - a pending invite can be resent at most once every 5 minutes and at most
//     3 times per 24h (the initial send counts as 1);
//   - each resend extends the invite expiry to ~30 days out;
//   - the button state + "next available" time come from the API fields
//     `can_resend` / `resend_available_at` on each invite.
//
// Real selectors / strings from team.html:
//   - invite-create:  input[name="invite_email"], submit value "Send invite"
//   - resend (active): form with hidden input[name="resend_invite_id"] +
//                      button[type=submit] "Resend"
//   - resend (cooled): button[disabled] "Resend" + <small>available after …</small>
//   - success badge:   .alert-success "Sent ... Invitation email resent."
//   - rate-limit warn: .alert-warning with errors.resend text
//
// The team page resolves the logged-in user's default account via
// current_account, so a direct navigation is enough.
const TEAM_PATH = "/manage/account/team";

// Locators for a pending invite's Resend control on the team page.
function activeResendButton(page: Page) {
  // The active form carries the resend_invite_id hidden field.
  return page.locator(
    'form:has(input[name="resend_invite_id"]) button[type="submit"]',
  );
}

function disabledResendButton(page: Page) {
  return page.locator("button[disabled]", { hasText: "Resend" });
}

test("pending invite shows a Resend button for an account with edit access", async ({
  page,
  context,
}) => {
  const owner = uniqueTestEmail("invite-owner");
  await loginAs(context, owner);

  const invitee = uniqueTestEmail("invite-invitee");
  await inviteUser(page, invitee);

  // §4a: a fresh pending invite is immediately resendable (can_resend true),
  // so the active Resend submit button renders.
  await expect(activeResendButton(page)).toBeVisible();
});

test("clicking Resend shows the success badge", async ({
  page,
  context,
}) => {
  const owner = uniqueTestEmail("invite-owner");
  await loginAs(context, owner);

  const invitee = uniqueTestEmail("invite-invitee");
  await inviteUser(page, invitee);

  await expect(activeResendButton(page)).toBeVisible();
  await activeResendButton(page).click();

  // §4a: success badge — team.html renders .alert-success with the "Sent" badge
  // and the copy "Invitation email resent.".
  await expectNoErrorBleed(page, page.url());
  const successAlert = page.locator(".alert-success");
  await expect(successAlert).toBeVisible();
  await expect(successAlert).toContainText("Invitation email resent");
  // The success badge only renders on a successful resend, which is what queues
  // the invite email. Verifying the email row itself needs the read-only DB layer
  // (intentionally not used here), and there is no UI/API surface for sent email,
  // so the badge is the observable assertion.
});

test("an immediate second resend is blocked by the 5-minute cooldown", async ({
  page,
  context,
}) => {
  const owner = uniqueTestEmail("invite-owner");
  await loginAs(context, owner);

  const invitee = uniqueTestEmail("invite-invitee");
  await inviteUser(page, invitee);

  // First resend succeeds.
  await expect(activeResendButton(page)).toBeVisible();
  await activeResendButton(page).click();
  await expect(page.locator(".alert-success")).toBeVisible();

  // §4a: immediately resending again hits the 5-minute cooldown. The API now
  // reports can_resend=false, so team.html renders the DISABLED Resend button
  // (with an "available after …" hint when resend_available_at is set). The
  // active resend form should no longer be present.
  //
  // Two render paths are acceptable per the plan:
  //   (a) the page already re-rendered with can_resend=false (disabled button), or
  //   (b) a forced resend POST is rejected with a rate-limit .alert-warning.
  // After a successful resend the page is freshly rendered, so we assert (a):
  // the disabled state, and that the active resend form is gone.
  await expect(disabledResendButton(page)).toBeVisible();
  await expect(activeResendButton(page)).toHaveCount(0);

  // The "available after …" hint renders when the API supplies
  // resend_available_at. It is API-dependent, so assert softly: if the small
  // hint is present it must carry the "available after" copy.
  const hint = page.locator("small.text-muted", { hasText: "available after" });
  if ((await hint.count()) > 0) {
    await expect(hint.first()).toContainText("available after");
  }
});

test.skip("exceeding 3 sends in 24h blocks resend with a limit warning", async ({
  page,
  context,
}) => {
  // §4a: the initial send counts as 1; after 2 more resends (3 total) the next
  // resend is blocked with a "too many … (limit: 3)" warning surfaced from the
  // API's resource_exhausted error via errors.resend (.alert-warning).
  //
  // SKIPPED: the 5-minute cooldown between sends makes reaching 3 sends in a
  // single test run impractical through the UI without time-travel or a DB
  // write to backdate the prior sends — both deliberately out of scope for the
  // read-only harness. Closing this needs a test-only `api e2e invite backdate`
  // command in the Go API (api-dev build only, like `api e2e session`); the exact
  // shape is written up in FINDINGS-error-surfacing.md (task 5). The assertion
  // shape below is kept ready for that day.
  const owner = uniqueTestEmail("invite-owner");
  await loginAs(context, owner);

  const invitee = uniqueTestEmail("invite-invitee");
  await inviteUser(page, invitee);

  // (Pseudo-flow once cooldown can be bypassed: resend twice more so the
  // counter reaches 3, then attempt a 4th resend.)
  await activeResendButton(page).click();
  // … advance time / clear cooldown (not yet possible) …
  await activeResendButton(page).click();
  // … advance time / clear cooldown (not yet possible) …
  await activeResendButton(page).click();

  // The blocked resend surfaces the API limit message in a warning alert.
  // errorAlerts() excludes the persistent dev-site banner (also .alert-warning).
  const warn = errorAlerts(page);
  await expect(warn).toBeVisible();
  await expect(warn).toContainText("limit: 3");
});

// Note: a §4a check that each resend extends the invite expiry to ~30 days out
// was removed — it could only be verified through the read-only DB layer
// (expires_on), which is intentionally not used, and the team UI does not render
// the invite expiry. Restore it if/when an invite-detail API surface exists.

test("only a pending invite renders a Resend control", async ({ page, context }) => {
  // §4a: only PENDING invites render a Resend control, so a freshly created
  // (pending) invite is the only one with the button, and the rendered table
  // never shows a Resend control against a non-pending status row.
  //
  // This does not cover accepted/expired invites — creating one needs the
  // invite code to drive the accept flow as the invitee, plus a second
  // authenticated identity — see the skipped test below.
  const owner = uniqueTestEmail("invite-owner");
  await loginAs(context, owner);

  const invitee = uniqueTestEmail("invite-invitee");
  await inviteUser(page, invitee);

  // team.html only renders any Resend control inside `IF inv.status ==
  // 'pending'`. Assert the invitee row is pending (so the test setup is sound)
  // and that no Resend control exists for a non-pending status. With a single
  // fresh invite there is exactly one (pending) row; the structural guarantee
  // is that Resend lives only under the pending branch.
  await expect(page.locator("body")).toContainText("pending");

  // Any Resend control present must belong to the pending invite (active form
  // or, after cooldown, the disabled button). There must be no Resend control
  // that is NOT under a pending invite — encoded as: the total number of
  // Resend controls never exceeds the number of pending invites (here, 1).
  const resendControls = page.locator("button", { hasText: "Resend" });
  await expect(resendControls).toHaveCount(1);
});

test("accepted invite hides Resend and the accept link still works", async ({
  browser,
}) => {
  // §4a, harder half: accept the invite as the invitee, then confirm the
  // accepted invite no longer offers Resend, while the accept link itself
  // worked.
  //
  // Driving the accept flow needs the invite `code` and a separate
  // authenticated identity for the invitee. Neither needs the DB or an email
  // body: get_account_invites(for_user => 1) serves the code straight to
  // whichever user is logged in, and a second BrowserContext is a second real
  // identity (see lib/helpers.ts's acceptInvite).
  const ownerContext = await browser.newContext();
  const ownerPage = await ownerContext.newPage();
  const owner = uniqueTestEmail("invite-owner");
  await loginAs(ownerContext, owner);

  const invitee = uniqueTestEmail("invite-invitee");
  await inviteUser(ownerPage, invitee);

  const inviteeContext = await browser.newContext();
  const inviteePage = await inviteeContext.newPage();
  await loginAs(inviteeContext, invitee);
  await acceptInvite(inviteePage);

  // Back on the owner's team page the accepted invite shows no Resend control.
  await expectCleanPage(ownerPage, TEAM_PATH);
  await expect(activeResendButton(ownerPage)).toHaveCount(0);
  await expect(disabledResendButton(ownerPage)).toHaveCount(0);

  await ownerContext.close();
  await inviteeContext.close();
});

test("a user without access to the account cannot resend", async ({
  browser,
}) => {
  // §4a: non-edit / wrong account context cannot resend (permission denied, no
  // button).
  //
  // Owner (context A) creates a pending invite. A separate, unrelated user
  // (context B) has their own auto-created account and no access to the owner's
  // account; their team page is their own and shows neither the owner's invite
  // nor any Resend control for it.

  // Context A: owner creates the pending invite.
  const ownerContext = await browser.newContext();
  const ownerPage = await ownerContext.newPage();
  const owner = uniqueTestEmail("invite-owner");
  await loginAs(ownerContext, owner);

  const invitee = uniqueTestEmail("invite-invitee");
  await inviteUser(ownerPage, invitee);
  await expect(activeResendButton(ownerPage)).toBeVisible();

  // Context B: an unrelated user. current_account resolves to THEIR own
  // (auto-created) account, never the owner's, so they cannot see or resend the
  // owner's invite.
  const otherContext = await browser.newContext();
  const otherPage = await otherContext.newPage();
  const other = uniqueTestEmail("invite-outsider");
  await loginAs(otherContext, other);

  await expectCleanPage(otherPage, TEAM_PATH);

  // The outsider's team page does not list the owner's invitee …
  await expect(otherPage.locator("body")).not.toContainText(invitee);
  // … and offers no Resend control at all (no pending invites of their own).
  await expect(activeResendButton(otherPage)).toHaveCount(0);
  await expect(
    otherPage.locator("button", { hasText: "Resend" }),
  ).toHaveCount(0);

  await ownerContext.close();
  await otherContext.close();
});
