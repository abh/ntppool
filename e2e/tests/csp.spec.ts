import { accountFormUrl } from "../lib/accounts";
import { installSession, loginAs, MANAGE_URL, uniqueTestEmail } from "../lib/auth";
import { expectNoCspViolations, watchCspViolations } from "../lib/csp";
import { expect, test } from "../lib/fixtures";
import { bust, expectCleanPage } from "../lib/helpers";
import { monitorListUrl } from "../lib/monitors";

// The behaviors that used inline JavaScript (an onclick, an hx-on attribute
// and a <script> in an htmx fragment), plus a sweep of the main pages. Every
// test fails on any CSP violation, so a page that still needs inline script
// shows up here once the header drops 'unsafe-inline' and 'unsafe-eval'.

function monitorUrl(accountToken: string, tlsName: string): string {
  return `/manage/monitors/monitor?a=${encodeURIComponent(accountToken)}&name=${encodeURIComponent(tlsName)}`;
}

function wwwUrl(path: string): string {
  const base = process.env.NTP_BASE_URL;
  if (!base) throw new Error("NTP_BASE_URL is not set");
  return new URL(bust(path), base).toString();
}

test("development notice Details toggles devDetails", async ({ page, context }) => {
  const violations = await watchCspViolations(page);
  await loginAs(context, uniqueTestEmail("csp-dev"));
  await expectCleanPage(page, bust("/manage/"));

  const details = page.locator("#devDetails");
  const toggle = page.locator(".alert-warning button");
  await expect(details).toHaveClass(/\bd-none\b/);
  await toggle.click();
  await expect(details).not.toHaveClass(/\bd-none\b/);
  await toggle.click();
  await expect(details).toHaveClass(/\bd-none\b/);

  expectNoCspViolations(violations);
});

test("delete confirmation modal opens, cancels and reopens without CSP violations", async ({ page, context, fixtures }) => {
  const violations = await watchCspViolations(page);
  const fixture = await fixtures.create({ monitors: [{ ipv4: { status: "paused" } }] });
  await installSession(context, fixture.sessionToken);
  await expectCleanPage(page, bust(monitorUrl(fixture.accountToken, fixture.monitors[0].tlsName)));

  const openButton = page.locator('button[hx-get*="confirm-delete"]');
  const modal = page.locator("#delete-modal");

  await openButton.click();
  await expect(modal).toBeVisible();
  await modal.getByText("Cancel").click();
  await expect(modal).toHaveCount(0);

  await openButton.click();
  await expect(modal).toBeVisible();
  await expect(page.locator(".modal-backdrop")).toHaveCount(1);

  expectNoCspViolations(violations);
});

test("monitor admin toggles combined and per-address status forms", async ({ page, context, fixtures }) => {
  const violations = await watchCspViolations(page);
  const fixture = await fixtures.create({
    monitors: [{ ipv4: { status: "testing" }, ipv6: { status: "testing" } }],
  });
  await loginAs(context, uniqueTestEmail("csp-admin"), { grantMonitorAdmin: true });
  await expectCleanPage(page, bust(monitorUrl(fixture.accountToken, fixture.monitors[0].tlsName)));

  const forms = page.locator(".monitor-status");
  await expect(forms).toHaveCount(3);
  await expect(forms.nth(0)).toBeVisible();
  await expect(forms.nth(1)).toBeHidden();
  await expect(forms.nth(2)).toBeHidden();

  await page.getByRole("button", { name: "Change status for both or individually" }).click();
  await expect(forms.nth(0)).toBeHidden();
  await expect(forms.nth(1)).toBeVisible();
  await expect(forms.nth(2)).toBeVisible();

  expectNoCspViolations(violations);
});

test("main pages load without CSP violations", async ({ page, context, fixtures }) => {
  const violations = await watchCspViolations(page);
  const fixture = await fixtures.create({
    servers: [{ ipVersion: 4, verified: true }],
    monitors: [{ ipv4: { status: "paused" } }],
  });
  await installSession(context, fixture.sessionToken);

  const acc = encodeURIComponent(fixture.accountToken);
  const pages = [
    wwwUrl("/en/"),
    wwwUrl(`/scores/${fixture.servers[0].ip}`),
    new URL(bust("/manage/login"), MANAGE_URL).toString(),
    new URL(bust(`/manage/servers?a=${acc}`), MANAGE_URL).toString(),
    new URL(bust(accountFormUrl(fixture.accountToken)), MANAGE_URL).toString(),
    new URL(bust(monitorListUrl(fixture.accountToken)), MANAGE_URL).toString(),
  ];
  for (const url of pages) {
    await expectCleanPage(page, url);
    await page.waitForLoadState("networkidle");
  }

  expectNoCspViolations(violations);
});
