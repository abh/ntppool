import type { Page } from "@playwright/test";
import { installSession, uniqueTestEmail } from "../lib/auth";
import { expect, test, type Fixture } from "../lib/fixtures";
import { bust, errorAlerts, expectCleanPage, expectNoErrorBleed } from "../lib/helpers";
import {
  approveZone,
  createNewZone,
  expectSubmitRefused,
  expectSubmitted,
  freshZoneData,
  getVendorZone,
  isVendorAdmin,
  loginAsVendorAdmin,
  rejectZone,
  SUBSCRIPTION_REQUIRED,
  UPGRADE_MESSAGE,
  zonePath,
  zoneUrlParams,
} from "../lib/vendor";

// Vendor zones for an account with a live subscription. MANUAL_TEST_PLAN.md
// §5 (plan checks), §5b (covered rows) and §5e (coverage gate).
//
// Each test seeds a subscription-only fixture through `api e2e fixture
// create` (status active, plan name "E2E fixture") and logs in as its owner.
// The fixture user has one account, so pages without a= use it.
//
// Both gates read the zone's account (Go subscription.AccountCoverage): a live
// subscription covers a zone while the account's Approved zone count is below
// max_zones and its Approved devices plus the zone's device_count stay within
// max_devices. Only Approved zones count.
//
// show.html gives a covered New or Rejected zone one plain "Submit for
// production" / "Resubmit for production" button (:91-99), and an over-limit
// New zone the upgrade message with no submit control (:132-148). Perl
// refuses before calling the API, so the Go gate is checked with a direct
// SubmitVendorZone call.
//
// vendor.spec.ts's vendor_admin preflight doesn't run for this file, so the
// admin steps fail, rather than skip, when a minted vendor admin can't reach
// /manage/vendor/admin.

// A fixture create, an admin mint and many page loads don't fit in 30 s.
test.describe.configure({ timeout: 90_000 });

const VENDOR_ADMIN_REQUIRED =
  "a freshly minted vendor_admin session could not reach /manage/vendor/admin; " +
  "the api-dev binary must honor the grant_vendor_admin flag of `api e2e session`";

const SUBMIT_CONTROL = /Submit for production|Resubmit for production/;

/**
 * Submit with the covered vendor's plain button on the zone's show page,
 * which `page` must already show, and check the confirmation. `button` is
 * anchored because "Resubmit for production" contains "submit for production".
 */
async function plainSubmit(page: Page, zoneName: string, button: RegExp) {
  await expect(page.getByRole("button", { name: SUBMIT_CONTROL }), "one plain submit control").toHaveCount(1);
  await expect(page.locator('textarea[name="opensource_info"]'), "no open-source justification form").toHaveCount(0);
  await expect(page.locator('input[name="opensource_request"]'), "no opensource_request field").toHaveCount(0);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    page.getByRole("button", { name: button }).click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(errorAlerts(page)).toHaveCount(0);
  // The ticket paragraph in submitted.html renders only for an uncovered vendor.
  await expectSubmitted(page, zoneName);
  await expect(page.locator("body")).not.toContainText("You'll get an email shortly with a ticket number");
}

/**
 * A covered New zone over its plan limits: the show page has the upgrade
 * message and no submit control, a crafted POST to /manage/vendor/submit gets
 * the upgrade message again, and the Go gate refuses SubmitVendorZone.
 */
async function expectOverLimitRefusal(page: Page, fixture: Fixture, idToken: string) {
  await expectCleanPage(page, bust(zonePath(idToken)));
  await expect(page.getByText(UPGRADE_MESSAGE)).toBeVisible();
  await expect(page.getByRole("button", { name: SUBMIT_CONTROL })).toHaveCount(0);
  await expect(page.locator('form[action*="/manage/vendor/submit"]')).toHaveCount(0);
  await expect(page.locator('textarea[name="opensource_info"]')).toHaveCount(0);

  // The show page has no submit form, and the only other form with an
  // auth_token is the sidebar's "New account" form (a=new), so take id, a and
  // auth_token from the edit form (form.html:15-17).
  await expectCleanPage(page, bust(zonePath(idToken, "edit")));
  const form = page.locator('form[action="/manage/vendor/zone"]');
  const post = await page.request.post("/manage/vendor/submit", {
    form: {
      id: await form.locator('input[name="id"]').inputValue(),
      a: await form.locator('input[name="a"]').inputValue(),
      auth_token: await form.locator('input[name="auth_token"]').inputValue(),
    },
  });
  expect(post.status(), "the crafted submit POST").toBe(200);
  const body = await post.text();
  expect(body, "the crafted submit gets the upgrade message again").toContain(UPGRADE_MESSAGE);
  // The upgrade message alone doesn't prove the Perl gate refused: had
  // render_submit called SubmitVendorZone, Go's refusal would render in the
  // _errors.html alert with a Trace ID (Vendor.pm:429-440), and render_zone
  // would still add the upgrade message for this New zone.
  expect(body, "Perl refuses before calling SubmitVendorZone").not.toContain(SUBSCRIPTION_REQUIRED);
  expect(body, "no API error alert").not.toContain("alert-danger");
  expect(body, "no API error Trace ID").not.toContain("Trace ID");

  await expectSubmitRefused(fixture.sessionToken, fixture.accountToken, idToken, "the owner");
  expect((await getVendorZone(fixture.sessionToken, idToken)).status).toBe("New");
}

// §5 subscription row, §5b covered rows, §5e covered.
test("a covered vendor gets a plain submit and stays off the open-source path", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ subscription: { maxZones: 1, maxDevices: 10000 } });
  await installSession(context, fixture.sessionToken);
  const data = freshZoneData("cv"); // 5,000 devices
  const { idToken } = zoneUrlParams(await createNewZone(page, data));

  await plainSubmit(page, data.zoneName, /^Submit for production/);

  await expectCleanPage(page, bust("/manage/vendor"));
  const zoneLink = page.locator(`a[href*="id=${idToken}"]`);
  await expect(page.locator("p").filter({ has: zoneLink }).locator("i"), "a covered Pending zone").toHaveText("Processing");
  await expect(page.getByRole("heading", { name: "Current plan" })).toBeVisible();
  // billing.html: one <div class="col"> per live subscription, with the plan
  // name in <b> and the limits in <ul class="product-details">.
  const plan = page.locator("div.col").filter({ has: page.locator(".product-details") });
  await expect(plan.locator("b")).toHaveText("E2E fixture");
  await expect(plan.locator(".product-details li")).toHaveText(["Up to 1 DNS zones", "Up to 10,000 client devices"]);

  // Blank until a product is chosen, but it must load.
  await expectCleanPage(page, bust("/manage/vendor/plan"));

  await expectCleanPage(page, bust(zonePath(idToken)));
  await expect(page.locator("body")).not.toContainText("Open Source information");

  const zone = await getVendorZone(fixture.sessionToken, idToken);
  expect(zone.status).toBe("Pending");
  expect(zone.opensourceRequested).toBe(false);
  expect(zone.opensourceApproved, "the grant is undecided").toBeUndefined();
});

// §5e over-limit, device limit.
test("a covered vendor over the device limit is refused by the site and by the API", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ subscription: { maxZones: 1, maxDevices: 5000 } });
  await installSession(context, fixture.sessionToken);
  const { idToken } = zoneUrlParams(await createNewZone(page, { ...freshZoneData("od"), deviceCount: "10000" }));

  await expectOverLimitRefusal(page, fixture, idToken);
});

// §5e over-limit, zone limit. max_devices is large, so only the zone count can
// refuse. Pending zones don't count toward max_zones, so zone A is approved
// first.
test("a covered vendor at the zone limit is refused by the site and by the API", async ({
  page,
  context,
  browser,
  fixtures,
}) => {
  const fixture = await fixtures.create({ subscription: { maxZones: 1, maxDevices: 100000 } });
  await installSession(context, fixture.sessionToken);

  const first = freshZoneData("zla");
  const { idToken: firstToken } = zoneUrlParams(await createNewZone(page, first));
  await plainSubmit(page, first.zoneName, /^Submit for production/);

  const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-coverage-admin"));
  try {
    expect(await isVendorAdmin(admin.page), VENDOR_ADMIN_REQUIRED).toBe(true);
    await approveZone(admin.page, firstToken, first.zoneName, { grant: false });
  } finally {
    await admin.context.close();
  }
  expect((await getVendorZone(fixture.sessionToken, firstToken)).status).toBe("Approved");

  const second = freshZoneData("zlb");
  const { idToken: secondToken } = zoneUrlParams(await createNewZone(page, second));
  await expectOverLimitRefusal(page, fixture, secondToken);
});

// §5e vendor admin, §5b covered resubmit of a Rejected zone.
test("a vendor admin submits for a covered account, and the owner resubmits after a rejection", async ({
  page,
  context,
  browser,
  fixtures,
}) => {
  const fixture = await fixtures.create({ subscription: { maxZones: 1, maxDevices: 10000 } });
  await installSession(context, fixture.sessionToken);
  const data = freshZoneData("as");
  const { idToken } = zoneUrlParams(await createNewZone(page, data));

  const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-coverage-admin"));
  try {
    expect(await isVendorAdmin(admin.page), VENDOR_ADMIN_REQUIRED).toBe(true);

    // The admin's own account has no subscription, and this form posts it as
    // a (show.html:96). The submit only works if both layers read coverage
    // from the zone's account.
    await expectCleanPage(admin.page, bust(zonePath(idToken)));
    const adminAccount = await admin.page.locator('form[action="/manage/vendor/submit"] input[name="a"]').inputValue();
    expect(adminAccount, "the admin submits with their own account").not.toBe(fixture.accountToken);
    await plainSubmit(admin.page, data.zoneName, /^Submit for production/);

    const zone = await getVendorZone(fixture.sessionToken, idToken);
    expect(zone.status).toBe("Pending");
    expect(zone.opensourceRequested).toBe(false);
    expect(zone.opensourceApproved).toBeUndefined();

    await rejectZone(admin.page, idToken, data.zoneName);
  } finally {
    await admin.context.close();
  }

  // need_subscription is only set for New zones, so a covered Rejected zone
  // gets a plain resubmit and no open-source form.
  await expectCleanPage(page, bust(zonePath(idToken)));
  await plainSubmit(page, data.zoneName, /^Resubmit for production/);
  expect((await getVendorZone(fixture.sessionToken, idToken)).status).toBe("Pending");
});
