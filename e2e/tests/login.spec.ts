import { test, expect } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";

test("minted user lands on the manage dashboard", async ({ page, context }) => {
  const email = uniqueTestEmail();
  await loginAs(context, email);

  const response = await page.goto("/manage");
  expect(response, "no response from /manage").not.toBeNull();
  expect(response!.status()).toBe(200);

  // Must be on the manage dashboard, not bounced to a login/dead-end page.
  expect(page.url()).toContain("/manage");
  expect(page.url()).not.toContain("/login");

  // Stable logged-in marker: the sidebar logout link renders the
  // authenticated user's email (manage/tpl/navigation_sidebar.html).
  // This selector may need adjusting against the live site, but it must
  // stay a genuine "authenticated" marker. Do NOT weaken this to something
  // that also renders on the logged-out / empty dead-end page.
  // The manage layout renders the sidebar twice (a desktop copy and a hidden
  // #mobile-nav copy), so scope to the visible Logout link.
  const logout = page.locator("a.nav-link:visible", { hasText: "Logout" });
  await expect(logout).toBeVisible();
  await expect(logout).toContainText(email);
});

test("new user lands on a next step, not the invitations dead-end", async ({
  page,
  context,
}) => {
  // A brand-new identity auto-creates a user + account and must not dead-end on
  // the empty "No pending account invitations." page.
  const email = uniqueTestEmail();
  await loginAs(context, email);

  const response = await page.goto("/manage");
  expect(response, "no response from /manage").not.toBeNull();
  expect(response!.status()).toBe(200);

  // /manage redirects to /manage/servers?a=<token> (Manage.pm manage_dispatch),
  // which renders tpl/manage.html. With no servers the page shows the
  // "Add my server" form (tpl/manage/add_form.html) as the sensible next step.
  expect(page.url()).toContain("/manage/servers");
  await expect(
    page.getByRole("heading", { name: "Add my server" }),
  ).toBeVisible();

  // The dead-end this test guards against: the empty invitations page
  // (docs/manage/tpl/user/invites.html). A new user should never see it.
  await expect(page.locator("body")).not.toContainText(
    "No pending account invitations.",
  );
});

test("login page copy reflects the broader scope", async ({ browser }) => {
  // Fresh context with NO session cookie: /manage falls through to
  // $self->login and renders tpl/login.html (Manage.pm render / Login.pm login).
  const context = await browser.newContext();
  const page = await context.newPage();

  const response = await page.goto("/manage");
  expect(response, "no response from /manage").not.toBeNull();
  expect(response!.status()).toBe(200);

  // Login page heading and call to action (docs/manage/tpl/login.html).
  await expect(
    page.getByRole("heading", { name: "Sign in to the NTP Pool" }),
  ).toBeVisible();

  // Broader-scope copy: not just "add a server" — servers, account, and vendor
  // zones. Real string from tpl/login.html line 16.
  await expect(page.locator("body")).toContainText(
    "Manage your servers, account, and vendor zones",
  );

  // Sanity: while logged out, no authenticated marker is present.
  await expect(page.locator("a.nav-link", { hasText: "Logout" })).toHaveCount(
    0,
  );

  await context.close();
});

test("logout then log back in restores the same account", async ({
  page,
  context,
}) => {
  // Log out and back in — session restored, no duplicate account created.
  // "No duplicate account" is best verified at the DB layer (Round 2); here we
  // assert the same email lands on a working dashboard both times.
  const email = uniqueTestEmail();

  // First login.
  await loginAs(context, email);
  await page.goto("/manage");
  const logout = page.locator("a.nav-link:visible", { hasText: "Logout" });
  await expect(logout).toContainText(email);

  // Visit the logout route (/manage/logout per Manage.pm render). It clears the
  // session and redirects back to /manage, which now shows the login page.
  await page.goto("/manage/logout");
  await expect(
    page.getByRole("heading", { name: "Sign in to the NTP Pool" }),
  ).toBeVisible();
  await expect(
    page.locator("a.nav-link", { hasText: "Logout" }),
  ).toHaveCount(0);

  // Log back in as the SAME user and confirm the dashboard renders for that
  // same account (session restored, not a dead-end). Logout deleted the first
  // session, so this mints a new one for the existing user.
  await loginAs(context, email, { existingUser: true });
  const response = await page.goto("/manage");
  expect(response!.status()).toBe(200);
  expect(page.url()).toContain("/manage/servers");
  await expect(logout).toContainText(email);
});
