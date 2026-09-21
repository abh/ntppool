import { Page, expect } from "@playwright/test";

/**
 * Append a cache buster, per CLAUDE.local.md's dev-site guidance. A fresh
 * browser context starts with an empty browser cache but says nothing about
 * the CDN in front of the dev site, so explicit navigations carry `x=`.
 *
 * Keep this at the navigation site: the URL builders in lib/accounts.ts stay
 * pure so they can also be used for waitForURL patterns and URL comparisons.
 */
export function bust(path: string): string {
  const sep = path.includes("?") ? "&" : "?";
  return `${path}${sep}x=${Math.random().toString(36).slice(2, 10)}`;
}

/**
 * Visit a page and assert it loaded cleanly: HTTP 200, no Perl/ORM error bleed,
 * no obvious server error. Returns the navigation response for further checks.
 *
 * A fresh account has no servers/zones, so callers should tolerate
 * empty-but-valid pages rather than requiring data.
 */
export async function expectCleanPage(page: Page, path: string) {
  const response = await page.goto(path);
  expect(response, `no response from ${path}`).not.toBeNull();
  expect(response!.status(), `unexpected status for ${path}`).toBe(200);
  await expectNoErrorBleed(page, path);
  return response!;
}

/**
 * Assert the current page body shows no Perl/ORM error leakage. Use after a
 * navigation when you've already checked (or deliberately don't care about) the
 * HTTP status.
 */
export async function expectNoErrorBleed(page: Page, label = page.url()) {
  const body = await page.content();
  expect(body, `Rose::DB / ORM error leaked on ${label}`).not.toContain(
    "NP::Model::",
  );
  expect(body, `Perl 'Can't locate' error on ${label}`).not.toContain(
    "Can't locate",
  );
  // Unrendered Template Toolkit directives indicate a broken template render.
  expect(body, `unrendered template directive on ${label}`).not.toContain(
    "[% ",
  );
}

/**
 * Create an additional account for the page's logged-in user via the sidebar
 * "New account" form (POST /manage/account with a=new) and return the new
 * account's id_token (acc_…).
 *
 * The user keeps their existing account(s), so the returned account is safely
 * *dissolvable*: account dissolution refuses to orphan a member, so a sole-owner
 * account can't be dissolved (that path is user-deletion). Tests that exercise
 * dissolution use this to set up an account whose owner has somewhere else to go.
 */
export async function createAccount(page: Page): Promise<string> {
  await page.goto("/manage/account");
  const before = await accountTokensOnPage(page);

  // The New-account form lives in a collapsed Bootstrap dropdown; submit it
  // directly rather than toggling the menu open. (This runs via CDP, not an
  // inline page script, so it doesn't touch the page CSP.) The form carries its
  // own auth_token, a=new and new_form=1 hidden inputs.
  // The sidebar (and this form) is rendered twice — desktop + mobile nav — and
  // lives in a collapsed dropdown, so target the first match and check it's
  // attached rather than visible.
  const form = page
    .locator('form[action="/manage/account"]')
    .filter({ has: page.locator('input[name="a"][value="new"]') })
    .first();
  await expect(form, "sidebar New-account form not found").toBeAttached();
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    form.evaluate((f) => (f as HTMLFormElement).submit()),
  ]);
  await expectNoErrorBleed(page, "/manage/account (after New account)");

  const after = await accountTokensOnPage(page);
  const fresh = after.filter((t) => !before.includes(t));
  expect(
    fresh.length,
    `expected exactly one new account token (before=${JSON.stringify(
      before,
    )}, after=${JSON.stringify(after)})`,
  ).toBe(1);
  return fresh[0];
}

/**
 * Invite `invitee` to the account team the page's logged-in user manages.
 * The inviter must already be logged in on `page`'s context.
 *
 * Returns once the pending invite is visible in the "Account invitations"
 * table (docs/manage/tpl/account/team.html).
 */
export async function inviteUser(page: Page, invitee: string): Promise<void> {
  await expectCleanPage(page, "/manage/account/team");

  // The invite-create form (team.html) — submitting the rendered form carries
  // the hidden auth_token (CSRF) and a= account token along with it.
  await page.fill('input[name="invite_email"]', invitee);
  await page.click('input[type="submit"][value="Send invite"]');

  await expectNoErrorBleed(page, page.url());

  // The new pending invite shows up in the "Account invitations" table.
  await expect(page.locator("body")).toContainText(invitee);
}

/**
 * Accept the current user's first pending invite, entirely through the
 * browser: no DB access, no email body. `/manage/account/invites/` (see
 * render_user_invitations, lib/NTPPool/Control/Manage/Account.pm) lists the
 * logged-in user's pending invites with the invite `code` already rendered
 * into each row's Accept form (docs/manage/tpl/user/invites.html), so a
 * second `loginAs` in a second BrowserContext is all a test needs to drive
 * this as a real second identity.
 *
 * Gotcha: the route match is `m!^/manage/account/invites/!` — the trailing
 * slash is required. `/manage/account/invites` (no slash) falls through to
 * the account-lookup dispatch and 404s.
 *
 * On success the controller redirects — to the joined account's team page
 * normally, but to /manage (which itself redirects on to /manage/servers)
 * when the invitee had no current_account yet, i.e. a brand-new user whose
 * first-ever action is accepting this invite (handle_invitation's POST
 * branch, the "didn't have an account yet" case). Callers that need to land
 * on the team page should navigate there explicitly afterward rather than
 * assume the redirect target.
 */
export async function acceptInvite(page: Page): Promise<void> {
  await expectCleanPage(page, "/manage/account/invites/");

  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    page.getByRole("button", { name: "Accept" }).click(),
  ]);
  await expectNoErrorBleed(page, page.url());
}

/** Distinct account id_tokens (acc_…) referenced by `a=` links on the page. */
async function accountTokensOnPage(page: Page): Promise<string[]> {
  const hrefs = await page
    .locator("a[href]")
    .evaluateAll((els) =>
      els.map((e) => (e as HTMLAnchorElement).getAttribute("href") || ""),
    );
  const tokens = new Set<string>();
  for (const h of hrefs) {
    const m = h.match(/[?&]a=(acc_[a-z0-9]+)/i);
    if (m) {
      tokens.add(m[1]);
    }
  }
  return [...tokens];
}

/**
 * Extract a rendered "Trace ID: <hex>" value from an error alert, if present.
 * Error pages surface the OpenTelemetry trace id alongside the message
 * (see CLAUDE.md error-surfacing patterns). Returns null when none is shown.
 */
export async function getTraceId(page: Page): Promise<string | null> {
  const body = await page.content();
  const match = body.match(/Trace ID:\s*([0-9a-f]+)/i);
  return match ? match[1] : null;
}

/**
 * Locate genuine error/warning alerts, excluding the persistent "Development
 * Site" / "Beta Site" banner that `development_notice.html` renders on every
 * non-prod page. That banner is an `.alert-warning` and never carries a Trace
 * ID, so a naive `.alert-danger, .alert-warning` selector would always match it
 * and mistake it for a surfaced API error. The banner is the only alert that
 * contains "Live site:", so filtering on that text reliably excludes it.
 */
export function errorAlerts(page: Page) {
  return page
    .locator(".alert-danger, .alert-warning")
    .filter({ hasNotText: "Live site:" });
}

/**
 * Assert an error alert is visible. When `requireTraceId` is true, also assert a
 * Trace ID is rendered with it (the project convention for surfaced API errors).
 */
export async function expectErrorAlert(
  page: Page,
  opts: { requireTraceId?: boolean } = {},
) {
  const alert = errorAlerts(page).first();
  await expect(alert, "expected a visible error alert").toBeVisible();
  if (opts.requireTraceId) {
    const traceId = await getTraceId(page);
    expect(traceId, "error alert should include a Trace ID").not.toBeNull();
  }
}
