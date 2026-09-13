import { test, expect, Page, BrowserContext } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  bust,
  errorAlerts,
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

  // form.html renders the DNS root origin next to the zone-name field as
  // "([name].<origin>)". On this new-zone path it comes straight from
  // get_vendor_zone_form_metadata's dns_roots (Vendor.pm render_form, issue
  // #31 commit 1 removed the NP::Model->dns_root ORM fallback here), so a
  // real domain must render, not a blank/undef.
  await expect(
    page.getByText(/\[name\]\.[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\)/i),
  ).toBeVisible();

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
  // hashref (Vendor.pm render_form's edit branch, issue #31 commit 1 removed
  // the NP::Model->dns_root->fetch ORM read here). Confirm it still renders.
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

// §5b: submitting the open-source claim with an EMPTY justification must be
// refused server-side, and the zone must not move to Pending.
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

  // The zone must still be New. Assert it from the list (vendor.html:15-31),
  // where the status is rendered plainly, rather than from the show page whose
  // first blockquote is the organization name.
  await expectCleanPage(page, bust("/manage/vendor"));

  const zoneLink = page.locator(`a[href*="id=${zoneToken}"]`);
  await expect(zoneLink, "the zone should still be listed").toBeVisible();
  // "Complete setup" renders only while the status is New; any other status
  // renders "View details".
  await expect(
    zoneLink,
    "a still-New zone should offer Complete setup, not View details",
  ).toHaveText("Complete setup");

  const listEntry = page.locator("p").filter({ has: zoneLink });
  await expect(
    listEntry.locator("i"),
    "the zone must not have transitioned to Pending",
  ).toHaveText("New");

  // Reopen the zone by URL (not by clicking a link whose text we just
  // asserted) and confirm it still offers the open-source form.
  await expectCleanPage(page, bust(zoneUrl));
  await expect(
    page.locator('textarea[name="opensource_info"]'),
    "the zone should still offer the open-source form",
  ).toBeVisible();
});

// Issue #39 regression guard.
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
// The harness cannot mint a live subscription: `api e2e session` grants
// privileges only (grant_staff / grant_vendor_admin — see lib/auth.ts), there is
// no Stripe fixture, and the suite deliberately has no DB write layer
// (e2e/.env.example). So the COVERED direction of #39 is guarded by the Go
// integration test TestSubmitVendorZone_DoesNotForceOpensource instead.
//
// What e2e CAN reach is a fresh, uncovered vendor — and the subtle failure this
// plan nearly shipped was the routing fix removing the open-source path for
// exactly that vendor. This test pins that path open: an uncovered New zone must
// still offer the justification form and must NOT be handed a plain production
// submit (which would let an uncovered vendor reach production with neither a
// plan nor an open-source claim).
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
    "uncovered vendor must still be offered the open-source justification form (#39)",
  ).toBeVisible();

  // The plain production submit must NOT be offered here — that control is for a
  // subscription-covered vendor only. Its absence is what stops an uncovered
  // vendor from reaching production without a plan or an open-source claim.
  await expect(
    page.getByRole("button", {
      name: /Submit for production|Resubmit for production/,
    }),
    "uncovered vendor must not get a plain production submit button (#39)",
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
// Staff / admin vendor-zone flows — MANUAL_TEST_PLAN.md §5a (editability matrix,
// staff rows) and §5c (admin approve/reject error surfacing).
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

// Mint a vendor-admin session in its own context. Returns the context + a page
// on it. The caller is responsible for context.close().
async function loginAsVendorAdmin(
  browser: import("@playwright/test").Browser,
  email: string,
): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext();
  // grantVendorAdmin sets user_privileges.vendor_admin; grantStaff is included
  // so the session is also support_staff where an admin view expects it.
  await loginAs(context, email, { grantStaff: true, grantVendorAdmin: true });
  const page = await context.newPage();
  return { context, page };
}

// Probe whether the session behind `page` is a working vendor admin: load the
// admin route and check we landed on it rather than being bounced to
// /manage/vendor (render_admin redirects non-admins). Returns true only when the
// admin list page actually rendered.
async function isVendorAdmin(page: Page): Promise<boolean> {
  const response = await page.goto("/manage/vendor/admin");
  if (!response || response.status() !== 200) {
    return false;
  }
  // render_admin redirects non-vendor-admins to /manage/vendor; the admin page
  // itself stays on /manage/vendor/admin and renders the "Pending zones" heading.
  if (!page.url().includes("/manage/vendor/admin")) {
    return false;
  }
  const heading = page.locator('h3:has-text("Pending zones")');
  return (await heading.count()) > 0;
}

// Create + submit a zone as the owner so it lands in the Pending state, ready for
// admin action. Returns the zone's id_token (parsed from the show-page URL).
async function createAndSubmitPendingZone(
  page: Page,
  data: NewZoneData,
): Promise<string> {
  const showUrl = await createNewZone(page, data);
  const idToken = new URL(showUrl).searchParams.get("id");
  expect(idToken, "create redirect should carry an id= token").toBeTruthy();

  // Submit via the open-source path (no Stripe subscription on a fresh account),
  // mirroring the existing open-source test: products.html renders a form posting
  // to /manage/vendor/submit with hidden opensource_request=1 + opensource_info.
  const osForm = page.locator('form[action*="/manage/vendor/submit"]');
  await expect(osForm).toBeVisible();
  await osForm
    .locator('textarea[name="opensource_info"]')
    .fill("Open source NTP client; AGPL-3.0; https://example.com/src ; no revenue.");
  await osForm.locator('input[type="submit"]').click();
  await expectNoErrorBleed(page, page.url());
  await expect(page.locator(".alert-danger")).toHaveCount(0);

  return idToken!;
}

// The admin acts on a zone through its show page reached via the admin route:
// /manage/vendor/admin?show=1;id=<token> -> render_zone($id,'show') which renders
// show.html with the approve/reject form (gated on vendor_admin). Submitting a
// status_change button posts to /manage/vendor/admin. Returns the page so the
// caller can assert on the post-action render.
async function adminOpenZone(page: Page, idToken: string): Promise<void> {
  // admin.html links to "admin?show=1;id=<token>"; ';' is a query separator here.
  await page.goto(`/manage/vendor/admin?show=1&id=${encodeURIComponent(idToken)}`);
  await expectNoErrorBleed(page, page.url());
}

test.describe.serial("vendor admin & editability (§5a staff, §5c)", () => {
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
            "all §5a/§5c admin tests would silently skip — failing loudly here " +
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

  // 2 + 3. Owner submits to Pending; admin Rejects then Approves; owner resubmits
  // a Rejected zone back to Pending. Combined so a single zone walks the whole
  // status path (New -> Pending -> Rejected -> Pending -> Approved) while showing
  // both sessions interacting.
  test("approve/reject status changes and owner resubmit", async ({
    page,
    context,
    browser,
  }) => {
    // OWNER session = default {page, context}.
    const ownerEmail = uniqueTestEmail("vendor-owner");
    await loginAs(context, ownerEmail);
    const data = freshZoneData("ex");
    const idToken = await createAndSubmitPendingZone(page, data);

    // ADMIN session = separate context.
    const adminEmail = uniqueTestEmail("vendor-admin");
    const { context: adminCtx, page: adminPage } = await loginAsVendorAdmin(
      browser,
      adminEmail,
    );
    try {
      test.skip(
        !(await isVendorAdmin(adminPage)),
        "minted session lacks vendor_admin; cannot drive approve/reject UI",
      );

      // --- Reject (Pending -> Rejected) ---
      await adminOpenZone(adminPage, idToken);
      // show.html: Reject button only renders for status == 'Pending'.
      const rejectBtn = adminPage.locator(
        'form[action="/manage/vendor/admin"] input[name="status_change"][value="Reject"]',
      );
      await expect(rejectBtn).toBeVisible();
      await rejectBtn.click();
      await expectNoErrorBleed(adminPage, adminPage.url());
      // render_admin sets msg "<zone> rejected"; the zone now reads Rejected.
      await expect(adminPage.locator("body")).toContainText(
        `${data.zoneName} rejected`,
      );

      // --- Owner resubmits (Rejected -> Pending) ---
      // §5a staff row: a Rejected zone returns to the open-source justification
      // form (the always-ask-open-source submission workflow). Re-supplying the
      // justification and submitting returns the zone to Pending. The owner
      // reloads the show page first.
      await page.goto(
        `/manage/vendor/zone?id=${encodeURIComponent(idToken)}`,
      );
      await expectNoErrorBleed(page, page.url());
      // _opensource.html posts to /manage/vendor/submit?id=...#opensource, so
      // match on a substring rather than the exact action.
      const resubmitForm = page.locator(
        'form[action*="/manage/vendor/submit"]',
      );
      await expect(resubmitForm).toBeVisible();
      await resubmitForm
        .locator('textarea[name="opensource_info"]')
        .fill("Open source NTP client; AGPL-3.0; https://example.com/src ; no revenue.");
      await resubmitForm.locator('input[type="submit"]').click();
      await expectNoErrorBleed(page, page.url());
      await expect(page.locator(".alert-danger")).toHaveCount(0);

      // Back in admin view the zone is Pending again (Approve + Reject offered).
      await adminOpenZone(adminPage, idToken);
      await expect(
        adminPage.locator(
          'form[action="/manage/vendor/admin"] input[name="status_change"][value="Reject"]',
        ),
        "Reject button means status returned to Pending",
      ).toBeVisible();

      // --- Approve (Pending -> Approved) ---
      const approveBtn = adminPage.locator(
        'form[action="/manage/vendor/admin"] input[name="status_change"][value="Approve"]',
      );
      await expect(approveBtn).toBeVisible();
      await approveBtn.click();
      await expectNoErrorBleed(adminPage, adminPage.url());
      // render_admin sets msg "<zone> approved" on success.
      await expect(adminPage.locator("body")).toContainText(
        `${data.zoneName} approved`,
      );
    } finally {
      await adminCtx.close();
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
      await adminOpenZone(adminPage, idToken);
      await adminPage
        .locator(
          'form[action="/manage/vendor/admin"] input[name="status_change"][value="Approve"]',
        )
        .click();
      await expect(adminPage.locator("body")).toContainText(
        `${data.zoneName} approved`,
      );

      // Owner views the Approved zone: show.html only renders the Edit button
      // when can_edit_zone is true, which is false for a non-admin on Approved.
      await page.goto(
        `/manage/vendor/zone?id=${encodeURIComponent(idToken)}`,
      );
      await expectNoErrorBleed(page, page.url());
      await expect(page.locator("body")).toContainText("Approved");
      await expect(
        page.locator('a[href*="mode=edit"]'),
        "Approved zone shows no Edit button to the owner",
      ).toHaveCount(0);

      // Opening the edit URL directly falls through to the read-only show page:
      // render_zone ignores mode=edit when !can_edit_zone, so no editable form.
      await page.goto(
        `/manage/vendor/zone?id=${encodeURIComponent(idToken)}&mode=edit`,
      );
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

      await adminOpenZone(adminPage, idToken);
      await adminPage
        .locator(
          'form[action="/manage/vendor/admin"] input[name="status_change"][value="Approve"]',
        )
        .click();
      await expect(adminPage.locator("body")).toContainText(
        `${data.zoneName} approved`,
      );

      // Admin opens the edit form on the Approved zone. can_edit_zone is true for
      // an admin, so render_zone renders render_form (the editable form).
      await adminPage.goto(
        `/manage/vendor/zone?id=${encodeURIComponent(idToken)}&mode=edit`,
      );
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
      await adminPage.goto(
        `/manage/vendor/zone?id=${encodeURIComponent(idToken)}&mode=edit`,
      );
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

  // 6. Staff, Approved: changing zone_name is rejected by the API (name locked
  // once live). The form field is `readonly` (not `disabled`), so Playwright
  // .fill() would throw rather than exercise the API. We therefore bypass the UI
  // and POST a crafted request via page.request (which carries the admin session
  // cookies) with a CHANGED zone_name, then assert the API/controller does NOT
  // accept the rename: the zone_name stays the original on the show page.
  //
  // HUMAN-VERIFY: confirm the API rejects the rename of an Approved zone with an
  // error (vs. silently ignoring it). Both outcomes leave zone_name unchanged,
  // which is what this test asserts; tighten to expectErrorAlert if the API
  // surfaces an error through render_edit on this path.
  test("vendor admin cannot rename an Approved zone via the API", async ({
    page,
    context,
    browser,
  }) => {
    const ownerEmail = uniqueTestEmail("vendor-rename-owner");
    await loginAs(context, ownerEmail);
    const data = freshZoneData("rn");
    const idToken = await createAndSubmitPendingZone(page, data);

    const adminEmail = uniqueTestEmail("vendor-admin");
    const { context: adminCtx, page: adminPage } = await loginAsVendorAdmin(
      browser,
      adminEmail,
    );
    try {
      test.skip(
        !(await isVendorAdmin(adminPage)),
        "minted session lacks vendor_admin; cannot reach the Approved-rename case",
      );

      await adminOpenZone(adminPage, idToken);
      await adminPage
        .locator(
          'form[action="/manage/vendor/admin"] input[name="status_change"][value="Approve"]',
        )
        .click();
      await expect(adminPage.locator("body")).toContainText(
        `${data.zoneName} approved`,
      );

      // Read the auth_token from the edit form (POSTs require it; manage_dispatch
      // returns 403 without a valid auth_token).
      await adminPage.goto(
        `/manage/vendor/zone?id=${encodeURIComponent(idToken)}&mode=edit`,
      );
      const authToken = await adminPage
        .locator('form[action="/manage/vendor/zone"] input[name="auth_token"]')
        .inputValue();
      const accountToken = await adminPage
        .locator('form[action="/manage/vendor/zone"] input[name="a"]')
        .inputValue();

      // Craft a POST that tries to rename the Approved zone. The field is
      // readonly in the UI, so we submit directly to exercise the API guard.
      const renamed = `${data.zoneName}x`;
      const resp = await adminPage.request.post("/manage/vendor/zone", {
        form: {
          id: idToken,
          a: accountToken,
          auth_token: authToken,
          zone_name: renamed,
          organization_name: data.organizationName,
          request_information: data.requestInformation,
          device_information: data.deviceInformation,
          device_count: data.deviceCount,
        },
      });
      // Whether the API errors (re-renders the form) or ignores the locked field,
      // the rename must NOT take effect.
      expect(resp.status(), "rename POST should not 5xx").toBeLessThan(500);

      // Reload the zone and assert the name is still the original (not renamed).
      await adminPage.goto(
        `/manage/vendor/zone?id=${encodeURIComponent(idToken)}`,
      );
      await expectNoErrorBleed(adminPage, adminPage.url());
      await expect(
        adminPage.locator("body"),
        "Approved zone_name must remain locked to its original value",
      ).toContainText(data.zoneName);
      await expect(
        adminPage.locator("body"),
        "the attempted new zone_name must not appear",
      ).not.toContainText(renamed);
    } finally {
      await adminCtx.close();
    }
  });

  // 7. §5c: an invalid admin transition must be a SAFE no-op — it must not
  // dead-end, corrupt the zone, or leak a Perl/ORM error — and IF it ever does
  // surface an alert, that alert must carry a Trace ID (the project convention).
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
  test("§5c invalid admin transition is a safe no-op (and any alert carries a Trace ID)", async ({
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
      await adminOpenZone(adminPage, idToken);
      await adminPage
        .locator(
          'form[action="/manage/vendor/admin"] input[name="status_change"][value="Approve"]',
        )
        .click();
      await expect(adminPage.locator("body")).toContainText(
        `${data.zoneName} approved`,
      );

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
      // danger/warning alert is present it MUST include a Trace ID (the §5c rule),
      // and the page must not be a blank error bleed.
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
