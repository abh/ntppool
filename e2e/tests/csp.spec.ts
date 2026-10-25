import { accountFormUrl } from "../lib/accounts";
import { installSession, loginAs, MANAGE_URL, uniqueTestEmail } from "../lib/auth";
import { expectNoCspViolations, watchCspViolations } from "../lib/csp";
import { expect, test } from "../lib/fixtures";
import { bust, expectCleanPage } from "../lib/helpers";
import { monitorListUrl, monitorUrl } from "../lib/monitors";
import { serverListUrl } from "../lib/servers";

// The behaviors that used inline JavaScript (an onclick, an hx-on attribute
// and a <script> in an htmx fragment), plus a sweep of the main pages. Every
// test fails on any CSP violation.

function wwwUrl(path: string): string {
  const base = process.env.NTP_BASE_URL;
  if (!base) throw new Error("NTP_BASE_URL is not set");
  return new URL(bust(path), base).toString();
}

function manageUrl(path: string): string {
  return new URL(bust(path), MANAGE_URL).toString();
}

let violations: () => string[];

test.beforeEach(async ({ page }) => {
  violations = await watchCspViolations(page);
});

test.afterEach(async ({ page }) => {
  await expectNoCspViolations(page, violations);
});

test("development notice Details toggles devDetails", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("csp-dev"));
  await expectCleanPage(page, bust("/manage/"));

  const details = page.locator("#devDetails");
  const toggle = page.locator(".alert-warning button");
  await expect(details).toHaveClass(/\bd-none\b/);
  await toggle.click();
  await expect(details).not.toHaveClass(/\bd-none\b/);
  await toggle.click();
  await expect(details).toHaveClass(/\bd-none\b/);
});

test("delete confirmation modal opens, cancels and reopens without CSP violations", async ({ page, context, fixtures }) => {
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
});

test("monitor admin toggles combined and per-address status forms", async ({ page, context, fixtures }) => {
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
});

test("main pages load without CSP violations", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({
    servers: [{ ipVersion: 4, verified: true }],
    monitors: [{ ipv4: { status: "paused" } }],
  });
  await installSession(context, fixture.sessionToken);

  // The footer status widget (status-page.ts) fetches same-origin
  // /api/status/v2/summary.json, which connect-src 'self' must cover. With
  // status data it sets an indicator class on .color-dot; without it, it hides
  // the link. Either one means the fetch ran and its result was handled.
  const home = wwwUrl("/en/");
  const statusResponse = page.waitForResponse((response) =>
    new URL(response.url()).pathname === "/api/status/v2/summary.json");
  await expectCleanPage(page, home);
  expect(new URL((await statusResponse).url()).origin, "status fetch origin").toBe(new URL(home).origin);
  const statusLink = page.locator('a[href="https://status.ntppool.org/"]');
  await expect(
    statusLink.and(page.locator(".status-link-hidden"))
      .or(statusLink.locator(".color-dot.none, .color-dot.minor, .color-dot.major, .color-dot.critical")),
    "the status widget handled its fetch",
  ).toHaveCount(1);

  const pages = [
    home,
    wwwUrl(`/scores/${fixture.servers[0].ip}`),
    manageUrl("/manage/login"),
    manageUrl(serverListUrl(fixture.accountToken)),
    manageUrl(accountFormUrl(fixture.accountToken)),
    manageUrl(monitorListUrl(fixture.accountToken)),
  ];
  for (const url of pages) {
    await expectCleanPage(page, url);
    await page.waitForLoadState("networkidle");
  }
});

/** The value of one directive in a Content-Security-Policy header. */
function cspDirective(header: string, name: string): string {
  const directive = header
    .split(";")
    .map((part) => part.trim())
    .find((part) => part === name || part.startsWith(`${name} `));
  if (directive === undefined) throw new Error(`no ${name} directive in: ${header}`);
  return directive;
}

test("script-src and base-uri are locked down on www and manage", async ({ page }) => {
  for (const url of [wwwUrl("/"), manageUrl("/")]) {
    const response = await page.request.get(url);
    expect(response.status(), `status for ${url}`).toBe(200);
    const header = response.headers()["content-security-policy"];
    expect(header, `content-security-policy on ${url}`).toBeTruthy();
    const scriptSrc = cspDirective(header!, "script-src");
    expect(scriptSrc, `script-src on ${url}`).toBe(
      "script-src 'self' https://www.mapper.ntppool.org/mapper.js https://send.webform.dev",
    );
    expect(cspDirective(header!, "base-uri"), `base-uri on ${url}`).toBe("base-uri 'none'");
    expect(scriptSrc, `script-src on ${url}`).not.toContain("'unsafe-inline'");
    expect(scriptSrc, `script-src on ${url}`).not.toContain("'unsafe-eval'");
    expect(scriptSrc, `script-src on ${url}`).not.toContain("statuspage.io");
    expect(scriptSrc, `script-src on ${url}`).not.toContain("stripe.com");
    const connectSrc = cspDirective(header!, "connect-src");
    expect(connectSrc, `connect-src on ${url}`).not.toContain("statuspage.io");
    expect(connectSrc, `connect-src on ${url}`).not.toContain("status.ntppool.org");
  }
});
