import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  expectCleanPage,
  expectErrorAlert,
  expectNoErrorBleed,
} from "../lib/helpers";

// Vendor zone flow, regular-user (non-staff) portions only.
//
// Routes / templates this exercises (see lib/NTPPool/Control/Vendor.pm):
//   - /manage/vendor          render_zones / redirect to /new when no zones
//   - /manage/vendor/new      render_form  -> tpl/vendor/form.html
//   - POST /manage/vendor/zone render_edit -> request_vendor_zone (status New)
//                              then redirect to the show page
//   - /manage/vendor/zone?id=&mode=edit  render_form(zone) (prefilled)
//   - POST /manage/vendor/submit render_submit -> Pending (open-source path here)
//
// Field names below come from docs/manage/tpl/vendor/form.html and
// docs/manage/tpl/vendor/products.html (the open-source form). The new-zone
// form POSTs to /manage/vendor/zone with a hidden id="new".
//
// Admin approve/reject and the Approved/Rejected transitions are staff-gated
// and intentionally out of scope here.

// A fresh account has no Stripe subscription, so a brand-new zone is created in
// the "New" state and the show page renders the product/open-source picker
// (show.html: `IF vz.status == 'New' && need_subscription`).

interface NewZoneData {
  zoneName: string;
  organizationName: string;
  requestInformation: string;
  deviceCount: string; // value attribute of a <select> option, e.g. "5000"
  deviceInformation: string;
}

function freshZoneData(prefix: string): NewZoneData {
  // Zone names are lowercased and stripped to [a-z0-9-] server-side
  // (_edit_zone), so keep the value within that charset for a stable round-trip.
  const rand = Math.random().toString(36).slice(2, 8);
  return {
    zoneName: `${prefix}${rand}`,
    organizationName: "Example Vendor",
    requestInformation: "Embedded appliances polling a few times per hour.",
    deviceCount: "5000",
    deviceInformation: "Example NTP client devices, hourly polling.",
  };
}

// Fill the new-zone request form (/manage/vendor/new) and submit it. Returns
// the show-page URL the create redirects to (carries id= and a= params).
async function createNewZone(page: Page, data: NewZoneData): Promise<string> {
  await expectCleanPage(page, "/manage/vendor/new");

  // Real selectors from form.html.
  await page.fill('input[name="zone_name"]', data.zoneName);
  await page.fill('input[name="organization_name"]', data.organizationName);
  await page.fill('textarea[name="request_information"]', data.requestInformation);
  await page.selectOption('select[name="device_count"]', data.deviceCount);
  await page.fill('textarea[name="device_information"]', data.deviceInformation);

  // Submit button value is "Continue →".
  await Promise.all([
    page.waitForURL(/\/manage\/vendor\/zone\?/),
    page.click('form[action="/manage/vendor/zone"] input[type="submit"]'),
  ]);

  await expectNoErrorBleed(page, page.url());
  return page.url();
}

test("vendor list and new-zone form load clean for a fresh user", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("vendor-load");
  await loginAs(context, email);

  // A brand-new account has no zones, so /manage/vendor redirects to
  // /manage/vendor/new (Vendor.pm: redirect when no zones). Assert we land on
  // the new-zone form and it is NOT an error page.
  const response = await page.goto("/manage/vendor");
  expect(response, "no response from /manage/vendor").not.toBeNull();
  expect(response!.status()).toBe(200);
  expect(page.url()).toContain("/manage/vendor/new");
  await expectNoErrorBleed(page, page.url());

  // The new-zone form renders with its real fields.
  await expect(page.locator('input[name="zone_name"]')).toBeVisible();
  await expect(page.locator('select[name="device_count"]')).toBeVisible();

  // Directly visiting /manage/vendor/new also loads clean.
  await expectCleanPage(page, "/manage/vendor/new");
  await expect(page.locator('input[name="zone_name"]')).toBeVisible();
});

test("create a New vendor zone request", async ({ page, context }) => {
  const email = uniqueTestEmail("vendor-create");
  await loginAs(context, email);

  const data = freshZoneData("ex");
  await createNewZone(page, data);

  // The show page renders the just-created zone. New zones display the
  // products/open-source picker rather than a status line, so assert on the
  // zone identity and the absence of errors instead.
  await expectNoErrorBleed(page, page.url());
  await expect(page.locator("h3")).toContainText(data.zoneName);
  await expect(page.locator(".alert-danger")).toHaveCount(0);

  // The list page now shows the zone (no longer redirects to /new).
  await expectCleanPage(page, "/manage/vendor");
  await expect(page.locator("body")).toContainText(data.zoneName);
  // Fresh, unsubmitted zone is in the "New" state and the list offers to
  // "Complete setup" (shown only for status == 'New' in vendor.html).
  await expect(
    page.locator('a:has-text("Complete setup")').first(),
  ).toBeVisible();
});

test("edit a New/Pending zone and persist a changed field", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("vendor-edit");
  await loginAs(context, email);

  const data = freshZoneData("ex");
  await createNewZone(page, data);

  // Open the edit form via the show page's Edit link
  // (/manage/vendor/zone?id=...&mode=edit -> render_form(zone)).
  await page.click('a[href*="mode=edit"]');
  await expectNoErrorBleed(page, page.url());

  // The edit form is prefilled with the existing organization name.
  const orgField = page.locator('input[name="organization_name"]');
  await expect(orgField).toHaveValue(data.organizationName);

  // Change a field and save.
  const newOrg = "Example Vendor (edited)";
  await orgField.fill(newOrg);
  await Promise.all([
    page.waitForURL(/\/manage\/vendor\/zone\?/),
    page.click('form[action="/manage/vendor/zone"] input[type="submit"]'),
  ]);

  // Must not dead-end with a blank form: the show page renders the new value.
  await expectNoErrorBleed(page, page.url());
  await expect(page.locator("body")).toContainText(newOrg);
  await expect(page.locator(".alert-danger")).toHaveCount(0);

  // Reopen the edit form and confirm the change persisted.
  await page.click('a[href*="mode=edit"]');
  await expect(page.locator('input[name="organization_name"]')).toHaveValue(
    newOrg,
  );
});

test("open-source submit retains justification and edits without error", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("vendor-opensource");
  await loginAs(context, email);

  const data = freshZoneData("os");
  await createNewZone(page, data);

  // The show page for a New zone (no subscription) renders the open-source form
  // from products.html: hidden opensource_request=1 + an opensource_info
  // textarea, posting to /manage/vendor/submit.
  const justification =
    "Open source NTP client; AGPL-3.0; https://example.com/src ; no revenue.";
  const osForm = page.locator(
    'form[action*="/manage/vendor/submit"]',
  );
  await expect(osForm).toBeVisible();
  await osForm.locator('textarea[name="opensource_info"]').fill(justification);

  await osForm.locator('input[type="submit"]').click();

  // Submit succeeds: zone moves to Pending and the submitted confirmation
  // renders (submitted.html), no error alert.
  await expectNoErrorBleed(page, page.url());
  await expect(page.locator(".alert-danger")).toHaveCount(0);
  await expect(page.locator("body")).toContainText(data.zoneName);

  // Reopen the zone's show page and assert the open-source justification was
  // retained (show.html renders `IF vz.opensource_info`), i.e. not dropped.
  await expectCleanPage(page, "/manage/vendor");
  await page.locator('a:has-text("View details")').first().click();
  await expectNoErrorBleed(page, page.url());
  await expect(page.locator("body")).toContainText(justification);

  // Editing an unrelated field on the now-Pending open-source zone must not
  // dead-end or error with "opensource_info is required" (the edit form omits
  // the opensource fields by design; see _edit_zone comment in Vendor.pm).
  await page.click('a[href*="mode=edit"]');
  await expectNoErrorBleed(page, page.url());
  const newOrg = "Example Vendor (os edited)";
  await page.fill('input[name="organization_name"]', newOrg);
  await Promise.all([
    page.waitForURL(/\/manage\/vendor\/zone\?/),
    page.click('form[action="/manage/vendor/zone"] input[type="submit"]'),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(page.locator(".alert-danger")).toHaveCount(0);
  await expect(page.locator("body")).not.toContainText("opensource_info");
  await expect(page.locator("body")).toContainText(newOrg);

  // The open-source justification still displays after the unrelated edit.
  await expect(page.locator("body")).toContainText(justification);
});

test("duplicate zone name surfaces a red error alert with a Trace ID", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("vendor-dup");
  await loginAs(context, email);

  // Create a first zone, then attempt a second with the SAME zone name to
  // induce an API error on /manage/vendor/zone (render_edit -> _edit_zone).
  const first = freshZoneData("dup");
  await createNewZone(page, first);

  const dupData: NewZoneData = { ...freshZoneData("dup"), zoneName: first.zoneName };

  await expectCleanPage(page, "/manage/vendor/new");
  await page.fill('input[name="zone_name"]', dupData.zoneName);
  await page.fill('input[name="organization_name"]', dupData.organizationName);
  await page.fill(
    'textarea[name="request_information"]',
    dupData.requestInformation,
  );
  await page.selectOption('select[name="device_count"]', dupData.deviceCount);
  await page.fill(
    'textarea[name="device_information"]',
    dupData.deviceInformation,
  );

  await page.click('form[action="/manage/vendor/zone"] input[type="submit"]');

  // _edit_zone returns {general, trace_id} on API error; render_edit re-renders
  // via render_form with _errors.html -> .alert-danger + "Trace ID: ...". Assert
  // the red alert with a Trace ID and that the page is NOT blank (the request
  // form still renders rather than dead-ending).
  await expectErrorAlert(page, { requireTraceId: true });
  await expectNoErrorBleed(page, page.url());

  // The form is still present (not a blank dead-end), so the user can correct
  // and resubmit. NOTE: on the *create* path _edit_zone returns an undef zone
  // (see Vendor.pm), so render_form has no `vz` to echo the entered zone_name
  // back into the field. We therefore assert the form is still usable rather
  // than that the field retains the typed value. HUMAN-VERIFY against the live
  // site whether the entered zone_name should be repopulated on this path.
  await expect(page.locator('input[name="zone_name"]')).toBeVisible();
  await expect(
    page.locator('form[action="/manage/vendor/zone"] input[type="submit"]'),
  ).toBeVisible();
});
