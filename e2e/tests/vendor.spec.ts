import { test, expect, type Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  bust,
  errorAlerts,
  expectCleanPage,
  expectErrorAlert,
  expectNoErrorBleed,
} from "../lib/helpers";
import {
  adminOpenZone,
  approveZone,
  createAndSubmitPendingZone,
  createNewZone,
  editZone,
  expectSubmitRefused,
  freshZoneData,
  getVendorZone,
  isVendorAdmin,
  loginAsVendorAdmin,
  type NewZoneData,
  OPEN_SOURCE_JUSTIFICATION,
  rejectZone,
  zonePath,
  zoneUrlParams,
} from "../lib/vendor";

// Vendor zone flows for fresh, uncovered vendors, plus the vendor admin block
// at the end of the file. Vendors with a live subscription are in
// vendor-coverage.spec.ts.
//
// Routes / templates this exercises (see lib/NTPPool/Control/Vendor.pm):
//   - /manage/vendor          render_zones / redirect to /new when no zones
//   - /manage/vendor/new      render_form  -> tpl/vendor/form.html
//   - POST /manage/vendor/zone render_edit -> request_vendor_zone (status New)
//                              then redirect to the show page
//   - /manage/vendor/zone?id=&mode=edit  render_form(zone) (prefilled)
//   - POST /manage/vendor/submit render_submit -> Pending (open-source path here)
//
// A fresh account has no subscription, so a New or Rejected zone's show page
// renders the open-source form (show.html:91-103). Helpers live in
// lib/vendor.ts.

const MISSING_PLAN = "Please choose a subscription plan or choose open source below";

// The list page (vendor.html) renders each zone's status plainly, and
// "Complete setup" shows only while a zone is New.
async function expectZoneListedAsNew(page: Page, idToken: string) {
  await expectCleanPage(page, bust("/manage/vendor"));
  const zoneLink = page.locator(`a[href*="id=${idToken}"]`);
  await expect(zoneLink, "the zone should still be listed").toBeVisible();
  await expect(zoneLink, "a still-New zone should offer Complete setup, not View details").toHaveText("Complete setup");
  await expect(
    page.locator("p").filter({ has: zoneLink }).locator("i"),
    "the zone must not have moved to Pending",
  ).toHaveText("New");
}

// Change every field a regular user can write, then check the show page and
// the reopened form. organization_name has its own test, and form.html only
// renders contact_information when the zone already has one, which a regular
// user can't set. The show page formats device_count, so the form's select
// value is checked instead.
async function expectEveryFieldSaves(page: Page, idToken: string, prefix: string) {
  const changed = {
    zoneName: freshZoneData(prefix).zoneName,
    requestInformation: "Edited: set-top boxes polling once a day.",
    deviceCount: "25000",
    deviceInformation: "Edited: vendor firmware 2.x with an SNTP client.",
  };
  await editZone(page, idToken, changed);

  await expect(page.locator("h3").first()).toContainText(changed.zoneName);
  await expect(page.locator("body")).toContainText(changed.requestInformation);
  await expect(page.locator("body")).toContainText(changed.deviceInformation);

  await expectCleanPage(page, bust(zonePath(idToken, "edit")));
  const form = page.locator('form[action="/manage/vendor/zone"]');
  await expect(form.locator('input[name="zone_name"]')).toHaveValue(changed.zoneName);
  await expect(form.locator('textarea[name="request_information"]')).toHaveValue(changed.requestInformation);
  await expect(form.locator('select[name="device_count"]')).toHaveValue(changed.deviceCount);
  await expect(form.locator('textarea[name="device_information"]')).toHaveValue(changed.deviceInformation);
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
  // The zone-title h3 is first; the always-ask open-source form adds its own
  // "Open Source" h3 below, so scope to the first heading.
  await expect(page.locator("h3").first()).toContainText(data.zoneName);
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

  // Edit path: form.html reads vz.dns_root_origin straight off the API zone
  // hashref (Vendor.pm render_form's edit branch, which no longer makes the
  // NP::Model->dns_root->fetch ORM read here). Confirm it still renders.
  await expect(
    page.getByText(/\[name\]\.[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\)/i),
  ).toBeVisible();

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

// Regular user, New.
test("every writable field saves on a New zone", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("vendor-fields-new"));
  const { idToken } = zoneUrlParams(await createNewZone(page, freshZoneData("fn")));
  await expectEveryFieldSaves(page, idToken, "fn");
});

// Regular user, Pending (after an open-source submit).
test("every writable field saves on a Pending zone", async ({ page, context }) => {
  const { sessionToken } = await loginAs(context, uniqueTestEmail("vendor-fields-pending"));
  const idToken = await createAndSubmitPendingZone(page, freshZoneData("fp"));
  expect((await getVendorZone(sessionToken, idToken)).status, "the zone is Pending before the edits").toBe("Pending");
  await expectEveryFieldSaves(page, idToken, "fp");
});

// Perl's check is a truthiness test, so "   " reaches the API, whose
// validateOpensourceInfo refuses it before any write. render_submit shows the
// Connect message in the _errors.html alert with a Trace ID.
test("a whitespace-only justification is refused by the API and the zone stays New", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("vendor-os-blank"));
  const { idToken } = zoneUrlParams(await createNewZone(page, freshZoneData("osb")));

  const osForm = page.locator('form[action*="/manage/vendor/submit"]');
  await osForm.locator('textarea[name="opensource_info"]').fill("   ");
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    osForm.locator('input[type="submit"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expectErrorAlert(page, { requireTraceId: true });
  await expect(errorAlerts(page).first()).toContainText(
    "opensource_info must contain non-whitespace characters",
  );

  await expectZoneListedAsNew(page, idToken);
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
  const justification = OPEN_SOURCE_JUSTIFICATION;
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

// Submitting the open-source claim with an EMPTY justification must be refused
// server-side, and the zone must not move to Pending.
//
// The textarea carries no `required` attribute (_opensource.html:32), so a
// plain click reaches the server-side check in Vendor.pm:388-397 — the error
// path returns before submit_vendor_zone is ever called.
//
// The message renders as <div class="error"> inside #opensource, NOT as a
// Bootstrap alert, so errorAlerts()/expectErrorAlert() do not apply here. No
// Trace ID is expected: the request is rejected before any RPC.
test("open-source submit with an empty justification is refused and the zone stays New", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("vendor-os-empty");
  await loginAs(context, email);

  const data = freshZoneData("ose");
  // createNewZone returns the show-page URL, which carries id=<zone token>.
  const zoneUrl = await createNewZone(page, data);
  const zoneToken = new URL(zoneUrl).searchParams.get("id");
  expect(zoneToken, `zone URL should carry id=: ${zoneUrl}`).toBeTruthy();

  const osForm = page.locator('form[action*="/manage/vendor/submit"]');
  await expect(osForm, "uncovered vendor should get the open-source form").toBeVisible();

  const justification = osForm.locator('textarea[name="opensource_info"]');
  // Pin the precondition: if a `required` attribute is ever added, the browser
  // blocks the submit and this test would stop exercising the server check.
  expect(
    await justification.getAttribute("required"),
    "the justification textarea must not rely on native validation",
  ).toBeNull();

  await justification.fill("");
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    osForm.locator('input[type="submit"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());

  // The error div renders inside the submit <form> itself
  // (_opensource.html:19-34), not inside the `#opensource` id, which is only
  // the section header (_opensource.html:1-5) and closes long before the
  // form opens. Scope to the form, which we already have a handle on.
  await expect(
    osForm.locator(".error"),
    "the empty justification should be refused with a specific message",
  ).toHaveText("Please provide open source information");

  // The zone context is retained on the re-render, not dropped.
  await expect(page.locator("body")).toContainText(data.zoneName);

  // The zone must still be New.
  await expectZoneListedAsNew(page, zoneToken!);

  // Reopen the zone by URL (not by clicking a link whose text we just
  // asserted) and confirm it still offers the open-source form.
  await expectCleanPage(page, bust(zoneUrl));
  await expect(
    page.locator('textarea[name="opensource_info"]'),
    "the zone should still offer the open-source form",
  ).toBeVisible();
});

// Regression guard for the vendor submit-control routing.
//
// The bug: show.html used to route the New/Rejected submit control on a single
// `!need_subscription` guard, so ANY vendor whose zone did not need a
// subscription was handed the open-source justification form
// (tpl/vendor/_opensource.html -> textarea[name="opensource_info"] + hidden
// opensource_request=1). Submitting it set the vendor's open-source CLAIM, so a
// subscription-covered vendor was silently marked open source.
//
// The fix routes on coverage (have_subscription, now derived from
// has_live_subscription in Vendor.pm render_zone): a covered vendor gets a plain
// "Submit for production →" and is NOT marked open source; an uncovered vendor
// gets the open-source justification form, which is how they apply for the
// non-revenue plan.
//
// WHAT THIS TEST GUARDS (and the fixture gap it lives with)
// ---------------------------------------------------------------------------
// The covered direction is in vendor-coverage.spec.ts, which seeds a live
// subscription through `api e2e fixture create`, and in the Go integration test
// TestSubmitVendorZone_DoesNotForceOpensource.
//
// What e2e CAN reach is a fresh, uncovered vendor — and the subtle failure that
// nearly shipped was the routing fix removing the open-source path for exactly
// that vendor. This test pins that path open: an uncovered New zone must still
// offer the justification form and must NOT be handed a plain production submit
// (which would let an uncovered vendor reach production with neither a plan nor
// an open-source claim).
test("uncovered vendor submit page shows the open-source form, not a plain submit", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("vendor-uncovered");
  await loginAs(context, email);

  const data = freshZoneData("uc");
  await createNewZone(page, data);
  await expectNoErrorBleed(page, page.url());

  // A fresh account has no live subscription, so the zone renders uncovered:
  // the open-source justification form (its textarea carries the claim) is
  // offered so the vendor can apply for the non-revenue plan.
  await expect(
    page.locator('textarea[name="opensource_info"]'),
    "uncovered vendor must still be offered the open-source justification form",
  ).toBeVisible();

  // The plain production submit must NOT be offered here — that control is for a
  // subscription-covered vendor only. Its absence is what stops an uncovered
  // vendor from reaching production without a plan or an open-source claim.
  await expect(
    page.getByRole("button", {
      name: /Submit for production|Resubmit for production/,
    }),
    "uncovered vendor must not get a plain production submit button",
  ).toHaveCount(0);
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

// ---------------------------------------------------------------------------
// Staff / admin vendor-zone flows — the editability matrix (staff rows) and
// admin approve/reject error surfacing.
//
// MULTI-SESSION APPROACH
// ----------------------
// These flows need TWO concurrent identities acting on the SAME zone:
//   - the OWNER (a fresh regular user) creates and submits the zone, then later
//     resubmits a rejected zone.  The owner uses each test's default
//     {page, context} fixture.
//   - the ADMIN (a separate user) approves/rejects via /manage/vendor/admin.
//     The admin gets its OWN BrowserContext (browser.newContext()) with its own
//     session cookie, opened as a second page. The two contexts never share
//     cookies, so the owner session stays intact while the admin acts.
//
// Privilege note
// ----------------------------------------------------------------------------
// The vendor admin route and approve/reject buttons are gated on the
// `vendor_admin` privilege (distinct from `support_staff`):
//   - Vendor.pm render_admin: `redirect("/manage/vendor") unless user_is_vendor_admin`
//   - show.html approve/reject form: `IF combust.user.privileges.vendor_admin`
//   - Go vendorzone/status.go UpdateVendorZoneStatus: requires Privilege.VendorAdmin
// The mint command grants it via the `grant_vendor_admin` flag (Go
// e2efixture.CreateSession -> GrantUserVendorAdmin), wired through
// loginAs(..., { grantVendorAdmin: true }). Each admin-dependent test still
// probes isVendorAdmin() first so it skips with a clear message (rather than
// failing obscurely) if the deployed dev API predates the grant_vendor_admin
// flag.
// ---------------------------------------------------------------------------

test.describe.serial("vendor admin & editability", () => {
  // Loud preflight: prove the dev API can actually mint a vendor_admin session
  // BEFORE the admin tests run. Every test below otherwise self-skips via
  // `test.skip(!isVendorAdmin(...))`, so if the deployed dev API lost (or never
  // had) the grant_vendor_admin flag, ALL admin coverage would vanish silently —
  // six green-looking skips hiding a real regression. This beforeAll turns that
  // into ONE obvious failure: if a freshly minted vendor_admin session can't
  // reach /manage/vendor/admin, the whole describe block fails here with a clear
  // message. The per-test skips remain as defensive backstops (they will not
  // trigger once this preflight passes, since the capability is dev-API-wide).
  test.beforeAll(async ({ browser }) => {
    const { context, page } = await loginAsVendorAdmin(
      browser,
      uniqueTestEmail("vendor-admin-preflight"),
    );
    try {
      const ok = await isVendorAdmin(page);
      if (!ok) {
        throw new Error(
          "vendor_admin preflight FAILED: a freshly minted session could not " +
            "reach /manage/vendor/admin. The api-dev binary must honor " +
            "`api e2e session`'s grant_vendor_admin flag (Go " +
            "e2efixture.CreateSession -> GrantUserVendorAdmin). Without it " +
            "all admin tests would silently skip — failing loudly here " +
            "instead so the missing grant is one obvious check, not six dropped " +
            "tests.",
        );
      }
    } finally {
      await context.close();
    }
  });

  // 1. Admin list loads for a staff session.
  test("admin list page loads clean for a vendor admin", async ({
    browser,
  }) => {
    const adminEmail = uniqueTestEmail("vendor-admin");
    const { context, page } = await loginAsVendorAdmin(browser, adminEmail);
    try {
      test.skip(
        !(await isVendorAdmin(page)),
        "minted session lacks vendor_admin; deployed dev API may predate the " +
          "grant_vendor_admin flag",
      );

      // isVendorAdmin already navigated to /manage/vendor/admin and saw the
      // "Pending zones" heading; re-assert a clean render here.
      await expectNoErrorBleed(page, page.url());
      await expect(page.locator('h3:has-text("Pending zones")')).toBeVisible();
    } finally {
      await context.close();
    }
  });

  // Uncovered without a claim. The normal form hides a plain submit from an
  // uncovered vendor, so the site gate is reached by removing the hidden
  // opensource_request input, and the Go gate by calling SubmitVendorZone.
  test("an uncovered plain submit is refused by the site and by the API", async ({
    page,
    context,
    browser,
  }) => {
    const { sessionToken: ownerSession } = await loginAs(context, uniqueTestEmail("vendor-uncovered-submit"));
    const { idToken, accountToken } = zoneUrlParams(await createNewZone(page, freshZoneData("ups")));

    const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-admin"));
    try {
      test.skip(
        !(await isVendorAdmin(admin.page)),
        "minted session lacks vendor_admin; cannot submit as a vendor admin",
      );

      // Site gate. locator.evaluate runs through CDP, so the page CSP doesn't apply.
      const osForm = page.locator('form[action*="/manage/vendor/submit"]');
      await osForm.locator('input[name="opensource_request"]').evaluate((el) => el.remove());
      await osForm.locator('textarea[name="opensource_info"]').fill("Plain submit without the open-source flag.");
      await Promise.all([
        page.waitForNavigation({ waitUntil: "load" }),
        osForm.locator('input[type="submit"]').click(),
      ]);
      await expectNoErrorBleed(page, page.url());
      await expect(page.locator("div.text-danger").filter({ hasText: MISSING_PLAN })).toBeVisible();
      await expectZoneListedAsNew(page, idToken);

      // Go gate, as the owner and as a vendor admin with their own account.
      await expectSubmitRefused(ownerSession, accountToken, idToken, "the owner");
      await adminOpenZone(admin.page, idToken);
      const adminAccount = await admin.page.locator('form[action="/manage/vendor/admin"] input[name="a"]').inputValue();
      expect(adminAccount, "the vendor admin's own account").not.toBe(accountToken);
      await expectSubmitRefused(admin.sessionToken, adminAccount, idToken, "a vendor admin");

      expect((await getVendorZone(ownerSession, idToken)).status).toBe("New");
    } finally {
      await admin.context.close();
    }
  });

  // One zone walks New -> Pending -> Rejected -> Pending -> Approved. It covers
  // the Rejected editability row; grant undecided, claim kept after resubmit,
  // Rejected edit, and the checked half of the Grant row.
  test("approve/reject status changes and owner resubmit", async ({
    page,
    context,
    browser,
  }) => {
    test.setTimeout(90_000);
    const { sessionToken: ownerSession } = await loginAs(context, uniqueTestEmail("vendor-owner"));
    const data = freshZoneData("ex");
    const idToken = await createAndSubmitPendingZone(page, data);

    const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-admin"));
    try {
      test.skip(
        !(await isVendorAdmin(admin.page)),
        "minted session lacks vendor_admin; cannot drive approve/reject UI",
      );

      await test.step("the open-source submit records the claim and leaves the grant undecided", async () => {
        const zone = await getVendorZone(ownerSession, idToken);
        expect(zone.status).toBe("Pending");
        expect(zone.opensourceRequested).toBe(true);
        expect(zone.opensourceApproved, "the grant is undecided").toBeUndefined();
      });

      await test.step("Reject records the grant as false", async () => {
        await rejectZone(admin.page, idToken, data.zoneName);
        const zone = await getVendorZone(ownerSession, idToken);
        expect(zone.status).toBe("Rejected");
        expect(zone.opensourceApproved).toBe(false);
      });

      await test.step("the owner edits the Rejected zone", async () => {
        const edited = {
          organizationName: "Example Vendor (rejected edit)",
          requestInformation: "Edited while Rejected: appliances polling hourly.",
        };
        await editZone(page, idToken, edited);
        const body = page.locator("body");
        await expect(body).not.toContainText("opensource_info");
        await expect(body).toContainText(edited.organizationName);
        await expect(body).toContainText(edited.requestInformation);
        await expect(body, "the stored justification still shows").toContainText(OPEN_SOURCE_JUSTIFICATION);
      });

      const resubmitted = "Resubmitted: open source NTP client; BSD-2-Clause; https://example.com/src ; no revenue.";
      await test.step("the owner resubmits with a new justification", async () => {
        await expectCleanPage(page, bust(zonePath(idToken)));
        const form = page.locator('form[action*="/manage/vendor/submit"]');
        await form.locator('textarea[name="opensource_info"]').fill(resubmitted);
        await Promise.all([
          page.waitForNavigation({ waitUntil: "load" }),
          form.locator('input[type="submit"]').click(),
        ]);
        await expectNoErrorBleed(page, page.url());
        await expect(errorAlerts(page)).toHaveCount(0);
        const zone = await getVendorZone(ownerSession, idToken);
        expect(zone.status).toBe("Pending");
        expect(zone.opensourceRequested).toBe(true);
        expect(zone.opensourceInfo).toBe(resubmitted);
        expect(zone.opensourceApproved, "a resubmit resets the grant to undecided").toBeUndefined();
      });

      await test.step("Approve with Grant left checked records the grant", async () => {
        await adminOpenZone(admin.page, idToken);
        await expect(admin.page.locator("#opensource_grant"), "Grant is pre-checked for a zone with a claim").toBeChecked();
        await approveZone(admin.page, idToken, data.zoneName, { grant: true });
        const zone = await getVendorZone(ownerSession, idToken);
        expect(zone.status).toBe("Approved");
        expect(zone.opensourceApproved).toBe(true);
      });
    } finally {
      await admin.context.close();
    }
  });

  // The unchecked half of the Grant row.
  test("approving with Grant unchecked leaves the zone on the paid path", async ({
    page,
    context,
    browser,
  }) => {
    const { sessionToken: ownerSession } = await loginAs(context, uniqueTestEmail("vendor-nogrant-owner"));
    const data = freshZoneData("ng");
    const idToken = await createAndSubmitPendingZone(page, data);

    const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-admin"));
    try {
      test.skip(
        !(await isVendorAdmin(admin.page)),
        "minted session lacks vendor_admin; cannot approve",
      );
      await approveZone(admin.page, idToken, data.zoneName, { grant: false });
      const zone = await getVendorZone(ownerSession, idToken);
      expect(zone.status).toBe("Approved");
      expect(zone.opensourceApproved).toBe(false);
      expect(zone.opensourceRequested, "the vendor's claim is kept").toBe(true);
    } finally {
      await admin.context.close();
    }
  });

  // 4. Regular user, Approved: no Edit button; the edit URL falls through to the
  // read-only show page (can_edit_zone is false for a non-admin on an Approved
  // zone, so render_zone skips render_form and renders show.html).
  test("owner sees no edit on an Approved zone; edit URL is read-only", async ({
    page,
    context,
    browser,
  }) => {
    const ownerEmail = uniqueTestEmail("vendor-approved-owner");
    await loginAs(context, ownerEmail);
    const data = freshZoneData("ap");
    const idToken = await createAndSubmitPendingZone(page, data);

    const adminEmail = uniqueTestEmail("vendor-admin");
    const { context: adminCtx, page: adminPage } = await loginAsVendorAdmin(
      browser,
      adminEmail,
    );
    try {
      test.skip(
        !(await isVendorAdmin(adminPage)),
        "minted session lacks vendor_admin; cannot approve to set up this case",
      );

      // Admin approves so the zone is Approved.
      await approveZone(adminPage, idToken, data.zoneName, { grant: true });

      // Owner views the Approved zone: show.html only renders the Edit button
      // when can_edit_zone is true, which is false for a non-admin on Approved.
      await page.goto(zonePath(idToken));
      await expectNoErrorBleed(page, page.url());
      await expect(page.locator("body")).toContainText("Approved");
      await expect(
        page.locator('a[href*="mode=edit"]'),
        "Approved zone shows no Edit button to the owner",
      ).toHaveCount(0);

      // Opening the edit URL directly falls through to the read-only show page:
      // render_zone ignores mode=edit when !can_edit_zone, so no editable form.
      await page.goto(zonePath(idToken, "edit"));
      await expectNoErrorBleed(page, page.url());
      await expect(
        page.locator('form[action="/manage/vendor/zone"]'),
        "edit URL must not render the editable zone form for a non-admin owner",
      ).toHaveCount(0);
      // The read-only show page renders the status instead.
      await expect(page.locator("body")).toContainText("Approved");
    } finally {
      await adminCtx.close();
    }
  });

  // 5. Staff (vendor admin), Approved: the edit form OPENS (can_edit_zone is true
  // for an admin regardless of status); zone_name is read-only; other fields save.
  test("vendor admin can edit an Approved zone; zone_name is read-only; other fields save", async ({
    page,
    context,
    browser,
  }) => {
    // Owner creates + submits the zone.
    const ownerEmail = uniqueTestEmail("vendor-staffedit-owner");
    await loginAs(context, ownerEmail);
    const data = freshZoneData("se");
    const idToken = await createAndSubmitPendingZone(page, data);

    // Admin approves, then edits via the admin session (which IS the editing
    // identity here — the admin acts on the zone through the normal edit form).
    const adminEmail = uniqueTestEmail("vendor-admin");
    const { context: adminCtx, page: adminPage } = await loginAsVendorAdmin(
      browser,
      adminEmail,
    );
    try {
      test.skip(
        !(await isVendorAdmin(adminPage)),
        "minted session lacks vendor_admin; cannot edit an Approved zone as admin",
      );

      await approveZone(adminPage, idToken, data.zoneName, { grant: true });

      // Admin opens the edit form on the Approved zone. can_edit_zone is true for
      // an admin, so render_zone renders render_form (the editable form).
      await adminPage.goto(zonePath(idToken, "edit"));
      await expectNoErrorBleed(adminPage, adminPage.url());
      const form = adminPage.locator('form[action="/manage/vendor/zone"]');
      await expect(form).toBeVisible();

      // zone_name is rendered with the `readonly` attribute on Approved
      // (form.html: `IF vz.status == 'Approved' readonly`). Assert the attribute
      // and the prefilled value.
      const zoneNameInput = adminPage.locator('input[name="zone_name"]');
      await expect(zoneNameInput).toHaveAttribute("readonly", "");
      await expect(zoneNameInput).toHaveValue(data.zoneName);

      // Change a non-locked field (organization_name) and save.
      const newOrg = "Example Vendor (admin edited)";
      await adminPage.fill('input[name="organization_name"]', newOrg);
      await Promise.all([
        adminPage.waitForURL(/\/manage\/vendor\/zone\?/),
        adminPage.click(
          'form[action="/manage/vendor/zone"] input[type="submit"]',
        ),
      ]);
      await expectNoErrorBleed(adminPage, adminPage.url());
      await expect(adminPage.locator(".alert-danger")).toHaveCount(0);
      await expect(adminPage.locator("body")).toContainText(newOrg);

      // Reopen the edit form and confirm the org change persisted and zone_name
      // is unchanged (still the original, still read-only).
      await adminPage.goto(zonePath(idToken, "edit"));
      await expect(
        adminPage.locator('input[name="organization_name"]'),
      ).toHaveValue(newOrg);
      await expect(adminPage.locator('input[name="zone_name"]')).toHaveValue(
        data.zoneName,
      );
    } finally {
      await adminCtx.close();
    }
  });

  // Staff, Approved. zone_name is readonly in the form, which is only a browser
  // hint, so the test removes the attribute and submits the real form.
  // UpdateVendorZone refuses the rename (update.go:224-234), and render_edit
  // re-renders the form with the alert instead of redirecting.
  test("renaming an Approved zone shows the API's refusal", async ({
    page,
    context,
    browser,
  }) => {
    await loginAs(context, uniqueTestEmail("vendor-rename-owner"));
    const data = freshZoneData("rn");
    const idToken = await createAndSubmitPendingZone(page, data);

    const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-admin"));
    try {
      test.skip(
        !(await isVendorAdmin(admin.page)),
        "minted session lacks vendor_admin; cannot reach the Approved-rename case",
      );
      await approveZone(admin.page, idToken, data.zoneName, { grant: true });

      await expectCleanPage(admin.page, bust(zonePath(idToken, "edit")));
      const form = admin.page.locator('form[action="/manage/vendor/zone"]');
      const zoneName = form.locator('input[name="zone_name"]');
      await expect(zoneName).toHaveAttribute("readonly", "");
      // locator.evaluate runs through CDP, so the page CSP doesn't apply.
      await zoneName.evaluate((el) => el.removeAttribute("readonly"));
      await zoneName.fill(`${data.zoneName}x`);
      await Promise.all([
        admin.page.waitForNavigation({ waitUntil: "load" }),
        form.locator('input[type="submit"]').click(),
      ]);
      await expectNoErrorBleed(admin.page, admin.page.url());

      expect(new URL(admin.page.url()).search, "a refused edit re-renders the form, not the show page").toBe("");
      await expectErrorAlert(admin.page, { requireTraceId: true });
      await expect(errorAlerts(admin.page).first()).toContainText("zone name cannot be changed after approval");
      const reRendered = admin.page.locator('form[action="/manage/vendor/zone"] input[name="zone_name"]');
      await expect(reRendered, "the form shows the stored name").toHaveValue(data.zoneName);
      await expect(reRendered).toHaveAttribute("readonly", "");

      expect((await getVendorZone(admin.sessionToken, idToken)).zoneName).toBe(data.zoneName);
    } finally {
      await admin.context.close();
    }
  });

  // 7. An invalid admin transition must be a SAFE no-op — it must not dead-end,
  // corrupt the zone, or leak a Perl/ORM error — and IF it ever does surface an
  // alert, that alert must carry a Trace ID (the project convention).
  //
  // We deliberately do NOT claim to force the admin status-RPC error here,
  // because no UI/HTTP path can: render_admin re-fetches the zone's LIVE status
  // and only forwards the RPC for `status eq 'Pending'` (Reject) or
  // `status =~ /(Pending|Rejected)/` (Approve). Those guards exactly mirror the
  // Go API's SQL precondition (`UPDATE ... WHERE status IN ('Pending','Rejected')`
  // in sql/vendor_zones.sql), so every call the controller forwards is one the
  // API accepts. Re-posting Approve against an already-Approved zone is therefore
  // a controller no-op, never an RPC error. Proving the admin-path Trace-ID
  // convention end-to-end would need an app change (test-only fault injection);
  // that gap is written up in FINDINGS-error-surfacing.md (task 2). The
  // duplicate-name edit case (~line 220) already proves the Trace-ID convention
  // end-to-end on the regular-user edit path.
  //
  // So this test asserts what IS reachable: the no-op is safe, and the
  // conditional Trace-ID check below is a free regression net for the day a
  // forced-failure path exists.
  test("invalid admin transition is a safe no-op (and any alert carries a Trace ID)", async ({
    page,
    context,
    browser,
  }) => {
    const ownerEmail = uniqueTestEmail("vendor-adminerr-owner");
    await loginAs(context, ownerEmail);
    const data = freshZoneData("ae");
    const idToken = await createAndSubmitPendingZone(page, data);

    const adminEmail = uniqueTestEmail("vendor-admin");
    const { context: adminCtx, page: adminPage } = await loginAsVendorAdmin(
      browser,
      adminEmail,
    );
    try {
      test.skip(
        !(await isVendorAdmin(adminPage)),
        "minted session lacks vendor_admin; cannot exercise admin error path",
      );

      // Approve the zone first so it is Approved.
      await approveZone(adminPage, idToken, data.zoneName, { grant: true });

      // Read the admin form's auth_token from the show page to craft a POST.
      await adminOpenZone(adminPage, idToken);
      const authToken = await adminPage
        .locator('form[action="/manage/vendor/admin"] input[name="auth_token"]')
        .inputValue()
        .catch(() => "");

      // Re-post status_change=Approve against the now-Approved zone. render_admin
      // re-fetches the live status and its guard `status =~ /(Pending|Rejected)/`
      // does NOT match 'Approved', so the controller no-ops without forwarding
      // the RPC — exercising the controller's transition guard, not the API error
      // path (which is unreachable from here; see the test's header comment and
      // FINDINGS-error-surfacing.md). We assert the no-op is safe.
      const resp = await adminPage.request.post("/manage/vendor/admin", {
        form: {
          id: idToken,
          auth_token: authToken,
          status_change: "Approve",
        },
      });
      expect(resp.status(), "admin POST should not 5xx").toBeLessThan(500);

      // Re-render the admin show page and check error surfacing convention: if a
      // danger/warning alert is present it MUST include a Trace ID (the project
      // convention), and the page must not be a blank error bleed.
      await adminOpenZone(adminPage, idToken);
      const alert = errorAlerts(adminPage);
      if ((await alert.count()) > 0) {
        await expectErrorAlert(adminPage, { requireTraceId: true });
      } else {
        // Expected path: controller no-op due to its transition guards.
        // adminOpenZone lands on the single-zone admin show page, which must
        // still render cleanly rather than dead-end. Assert the zone heading is
        // present and the status is unchanged (still Approved) — i.e. the no-op
        // POST left the zone intact. Forcing the alert + Trace ID would require
        // test-only fault injection in the Go API (see FINDINGS-error-surfacing.md).
        await expect(
          adminPage.locator(`h3:has-text("${data.zoneName}")`),
        ).toBeVisible();
        await expect(adminPage.locator("body")).toContainText("Approved");
      }
    } finally {
      await adminCtx.close();
    }
  });
});
