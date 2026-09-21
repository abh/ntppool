import { test, expect } from "@playwright/test";
import { resolveDefaultAccountToken } from "../lib/accounts";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { bust, errorAlerts, expectCleanPage } from "../lib/helpers";

test("core pages load clean as a logged-in user", async ({ page, context }) => {
  const email = uniqueTestEmail();
  await loginAs(context, email);

  // Server list page. A fresh account renders the empty-but-valid list. This
  // page also hosts the add-server form (tpl/manage.html PROCESSes
  // add_form.html); /manage/server/add itself is a POST-only, CSRF-protected
  // form action and 403s on a bare GET, so it is not a navigable page.
  await expectCleanPage(page, "/manage/servers");

  // Account overview — another core surface reachable by a fresh account.
  await expectCleanPage(page, "/manage/account");
});

// Regression guard for the dev-banner blind spot.
//
// docs/shared/tpl/common/development_notice.html renders a "Development Site" /
// "Beta Site" banner on EVERY non-prod page (it lives in the shared style
// layout, docs/shared/tpl/style/default.html). That banner is a
// `<div class="alert alert-warning">`. A naive `.alert-danger, .alert-warning`
// selector therefore matches it on every page and mistakes it for a surfaced
// API error — which previously caused a false PASS in server.spec.ts (the
// banner satisfied an error-alert assertion the app never actually rendered) and
// a false FAIL in vendor.spec.ts (the banner was demanded to carry a Trace ID).
//
// The fix was errorAlerts() in lib/helpers.ts, which filters the banner out via
// its unique "Live site:" text. This test locks that in: on a clean page the
// banner MUST be present (so the page genuinely carries an .alert-warning) yet
// errorAlerts() MUST see zero errors. If anyone reverts errorAlerts() to a bare
// `.alert-warning` selector, the second assertion flips to >= 1 and fails here.
test("dev banner is present but is not seen as an error alert", async ({
  page,
  context,
}) => {
  // Any authenticated manage page renders the shared layout (and thus the
  // banner). /manage/account is clean for a brand-new user.
  await loginAs(context, uniqueTestEmail("regression-smoke"));
  await expectCleanPage(page, "/manage/account");

  // 1. The development banner is present: at least one raw .alert-warning. This
  //    guards against the errorAlerts()==0 check below passing vacuously on a
  //    page that simply has no alerts at all.
  const bannerCount = await page.locator(".alert-warning").count();
  expect(
    bannerCount,
    "expected the non-prod development banner (.alert-warning) to be present",
  ).toBeGreaterThanOrEqual(1);

  // 2. ...but errorAlerts() must NOT treat that banner as a surfaced error.
  const errorCount = await errorAlerts(page).count();
  expect(
    errorCount,
    "errorAlerts() must filter out the dev-site banner — a clean page has zero error alerts",
  ).toBe(0);
});

// docs/shared/error/403.html once looked up the `" support"` address (leading
// space) for the mailto: and `"support"` for the link text, so the two
// differed. A non-monitor-admin GET of the monitor-config fragment is a known
// 403 (Manage/Account.pm) rendered through that template.
test("403 page support link mails the address it shows", async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("regression-403"));
  const accountToken = await resolveDefaultAccountToken(page);
  const response = await page.goto(
    bust(`/manage/account/monitor-config?a=${encodeURIComponent(accountToken)}`),
  );
  expect(response?.status()).toBe(403);

  const link = page
    .locator("p", { hasText: "Permission denied" })
    .locator('a[href^="mailto:"]');
  await expect(link).toHaveCount(1);
  const address = (await link.textContent())?.trim() ?? "";
  expect(address).toMatch(/^[^\s@]+@[^\s@]+$/);
  await expect(link).toHaveAttribute("href", `mailto:${address}`);
});

// combust's _process_status picks the error page heading by status. 400 and
// 403 had none, so the heading read "403 - ".
test("403 page heading names the status", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("regression-403-heading"));
  const accountToken = await resolveDefaultAccountToken(page);
  const response = await page.goto(
    bust(`/manage/account/monitor-config?a=${encodeURIComponent(accountToken)}`),
  );
  expect(response?.status()).toBe(403);
  await expect(page.locator("h3", { hasText: /^\s*403 -/ })).toHaveText(
    "403 - Permission Denied",
  );
});
