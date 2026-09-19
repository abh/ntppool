import { expect, type Browser, type BrowserContext, type Locator, type Page } from "@playwright/test";
import { connectRpc, loginAs, RpcError } from "./auth";
import { bust, errorAlerts, expectCleanPage, expectNoErrorBleed } from "./helpers";
import { idField, record, stringField } from "./json";

// Vendor zone helpers for tests/vendor.spec.ts and tests/vendor-coverage.spec.ts.
// Routes: lib/NTPPool/Control/Vendor.pm. Templates: docs/manage/tpl/vendor/.
// API: the Go repo's server/api/vendorzone/.
//
// Field names come from form.html and _opensource.html. The new-zone form
// posts to /manage/vendor/zone with a hidden id="new".

/** The Go SubmitVendorZone coverage gate's refusal (submit.go). */
export const SUBSCRIPTION_REQUIRED = "a subscription is required, or apply as open source";

/** show.html's need_upgrade text: a live subscription the zone would exceed. */
export const UPGRADE_MESSAGE = "The current subscription plan doesn't support adding the new DNS zone.";

/**
 * show.html's upgrade offer: a device overage on the account's one tiered
 * subscription. format_number renders thousands separators.
 */
export function upgradeOfferText(maxDevices: number, requiredDevices: number): string {
  return (
    `Your plan covers ${maxDevices.toLocaleString("en-US")} devices; ` +
    `this zone brings the account to ${requiredDevices.toLocaleString("en-US")}.`
  );
}

/** The upgrade offer's button, which posts to /manage/vendor/plan/upgrade. */
export function upgradeButtonName(quantity: number): string {
  return `Update plan to ${quantity.toLocaleString("en-US")} devices`;
}

/** Any upgrade offer button, for asserting there is none. */
export const UPGRADE_BUTTON = /Update plan to/;

/** The justification createAndSubmitPendingZone submits. */
export const OPEN_SOURCE_JUSTIFICATION = "Open source NTP client; AGPL-3.0; https://example.com/src ; no revenue.";

export interface NewZoneData {
  zoneName: string;
  organizationName: string;
  requestInformation: string;
  deviceCount: string; // value attribute of a <select> option, e.g. "5000"
  deviceInformation: string;
}

export function freshZoneData(prefix: string): NewZoneData {
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

/** The zone's show page; mode "edit" opens the edit form when the viewer may edit. */
export function zonePath(idToken: string, mode?: "edit"): string {
  const path = `/manage/vendor/zone?id=${encodeURIComponent(idToken)}`;
  return mode ? `${path}&mode=${mode}` : path;
}

/**
 * The zone and account tokens from the show-page URL createNewZone returns.
 * render_edit redirects with id= and a= (Vendor.pm:475-481).
 */
export function zoneUrlParams(url: string): { idToken: string; accountToken: string } {
  const params = new URL(url).searchParams;
  const idToken = params.get("id");
  const accountToken = params.get("a");
  if (!idToken || !accountToken) {
    throw new Error(`zone URL is missing id= or a=: ${url}`);
  }
  return { idToken, accountToken };
}

// Fill the new-zone request form (/manage/vendor/new) and submit it. Returns
// the show-page URL the create redirects to (carries id= and a= params).
export async function createNewZone(page: Page, data: NewZoneData): Promise<string> {
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

// Mint a vendor-admin session in its own context. Returns the context, a page
// on it and the session token for API calls. The caller closes the context.
export async function loginAsVendorAdmin(
  browser: Browser,
  email: string,
): Promise<{ context: BrowserContext; page: Page; sessionToken: string }> {
  const context = await browser.newContext();
  // grantVendorAdmin sets user_privileges.vendor_admin; grantStaff is included
  // so the session is also support_staff where an admin view expects it.
  const { sessionToken } = await loginAs(context, email, { grantStaff: true, grantVendorAdmin: true });
  const page = await context.newPage();
  return { context, page, sessionToken };
}

// Probe whether the session behind `page` is a working vendor admin: load the
// admin route and check we landed on it rather than being bounced to
// /manage/vendor (render_admin redirects non-admins). Returns true only when the
// admin list page actually rendered.
export async function isVendorAdmin(page: Page): Promise<boolean> {
  const response = await page.goto("/manage/vendor/admin");
  if (!response || response.status() !== 200) {
    return false;
  }
  if (!page.url().includes("/manage/vendor/admin")) {
    return false;
  }
  const heading = page.locator('h3:has-text("Pending zones")');
  return (await heading.count()) > 0;
}

/**
 * The confirmation render_submit renders (submitted.html) once
 * SubmitVendorZone has moved the zone to Pending. A refused submit re-renders
 * the zone page instead, which has neither the heading nor the <tt> name.
 */
export async function expectSubmitted(page: Page, zoneName: string): Promise<void> {
  await expect(page.getByRole("heading", { name: "Vendor Zone Application Submitted" })).toBeVisible();
  await expect(page.locator(".block tt")).toHaveText(zoneName);
}

/**
 * The "Current plan" card on /manage/vendor, once the heading is up. billing.html
 * renders one <div class="col"> per live subscription, the plan name in <b> and
 * the limits in <ul class="product-details">; vendor.html includes it only when
 * the account has a subscription, so a match proves the section rendered.
 */
export async function currentPlanCard(page: Page): Promise<Locator> {
  await expect(page.getByRole("heading", { name: "Current plan" })).toBeVisible();
  return page.locator("div.col").filter({ has: page.locator(".product-details") });
}

// Create + submit a zone as the owner so it lands in the Pending state, ready for
// admin action. Returns the zone's id_token (parsed from the show-page URL).
export async function createAndSubmitPendingZone(page: Page, data: NewZoneData): Promise<string> {
  const showUrl = await createNewZone(page, data);
  const idToken = new URL(showUrl).searchParams.get("id");
  expect(idToken, "create redirect should carry an id= token").toBeTruthy();

  // Submit via the open-source path (no subscription on a fresh account):
  // _opensource.html posts to /manage/vendor/submit with hidden
  // opensource_request=1 + opensource_info.
  const osForm = page.locator('form[action*="/manage/vendor/submit"]');
  await expect(osForm).toBeVisible();
  await osForm.locator('textarea[name="opensource_info"]').fill(OPEN_SOURCE_JUSTIFICATION);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    osForm.locator('input[type="submit"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(page.locator(".alert-danger")).toHaveCount(0);
  await expectSubmitted(page, data.zoneName);

  return idToken!;
}

// The admin acts on a zone through its show page reached via the admin route:
// /manage/vendor/admin?show=1&id=<token> -> render_zone($id,'show'), which
// renders show.html with the approve/reject form (gated on vendor_admin).
export async function adminOpenZone(page: Page, idToken: string): Promise<void> {
  await page.goto(`/manage/vendor/admin?show=1&id=${encodeURIComponent(idToken)}`);
  await expectNoErrorBleed(page, page.url());
}

export interface VendorZoneRead {
  status: string;
  zoneName: string;
  /** An int64, so the API's JSON sends it as a string. */
  deviceCount: string;
  opensourceRequested: boolean;
  /** Absent when unset. */
  opensourceInfo?: string;
  /** Staff's grant. Absent means undecided. */
  opensourceApproved?: boolean;
}

/**
 * Read a zone through VendorZoneService.GetVendorZone. The UI never shows
 * opensource_approved. Any logged-in user who can see the zone may call it;
 * X-Account is optional here. The API emits default values but omits unset
 * optional fields, so a null fails the checks below.
 */
export async function getVendorZone(sessionToken: string, idToken: string): Promise<VendorZoneRead> {
  const data = record(
    await connectRpc<unknown>(
      "GetVendorZone",
      "ntppool.vendorzone.v1.VendorZoneService/GetVendorZone",
      { Authorization: `Bearer ${sessionToken}` },
      { id_token: idToken },
      idToken,
    ),
    "GetVendorZone response",
  );
  const label = `GetVendorZone ${idToken}`;
  const zone = record(data.zone, `${label} zone`);
  const requested = zone.opensource_requested;
  if (typeof requested !== "boolean") {
    throw new Error(`${label} opensource_requested is missing or malformed`);
  }
  const info = zone.opensource_info;
  if (info !== undefined && typeof info !== "string") {
    throw new Error(`${label} opensource_info is malformed`);
  }
  const approved = zone.opensource_approved;
  if (approved !== undefined && typeof approved !== "boolean") {
    throw new Error(`${label} opensource_approved is malformed`);
  }
  return {
    status: stringField(zone.status, `${label} status`),
    zoneName: stringField(zone.zone_name, `${label} zone_name`),
    deviceCount: idField(zone.device_count, `${label} device_count`),
    opensourceRequested: requested,
    opensourceInfo: info,
    opensourceApproved: approved,
  };
}

/**
 * Call VendorZoneService.SubmitVendorZone directly, as the Perl submit page
 * would. The body is only id_token, so the gate reads the claim already
 * stored on the zone. accountToken goes in X-Account.
 */
export async function submitVendorZoneApi(sessionToken: string, accountToken: string, idToken: string): Promise<void> {
  await connectRpc<unknown>(
    "SubmitVendorZone",
    "ntppool.vendorzone.v1.VendorZoneService/SubmitVendorZone",
    { Authorization: `Bearer ${sessionToken}`, "X-Account": accountToken },
    { id_token: idToken },
    idToken,
  );
}

/** SubmitVendorZone must fail with the coverage gate's failed_precondition. */
export async function expectSubmitRefused(
  sessionToken: string,
  accountToken: string,
  idToken: string,
  who: string,
): Promise<void> {
  let error: unknown;
  try {
    await submitVendorZoneApi(sessionToken, accountToken, idToken);
  } catch (err) {
    error = err;
  }
  expect(error, `SubmitVendorZone as ${who} should fail with an RPC error`).toBeInstanceOf(RpcError);
  const rpc = error as RpcError;
  expect(rpc.code, `SubmitVendorZone as ${who}: Connect code`).toBe("failed_precondition");
  expect(rpc.connectMessage, `SubmitVendorZone as ${who}: Connect message`).toBe(SUBSCRIPTION_REQUIRED);
}

const ADMIN_FORM = 'form[action="/manage/vendor/admin"]';

/**
 * Approve a Pending or Rejected zone on its admin page. `grant` sets the
 * "Grant open-source (non-revenue) plan" checkbox (#opensource_grant), which
 * show.html pre-checks when the zone carries a claim.
 */
export async function approveZone(page: Page, idToken: string, zoneName: string, opts: { grant: boolean }): Promise<void> {
  await adminOpenZone(page, idToken);
  const form = page.locator(ADMIN_FORM);
  await form.locator("#opensource_grant").setChecked(opts.grant);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    form.locator('input[name="status_change"][value="Approve"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(errorAlerts(page), `approving ${zoneName} should not show an error`).toHaveCount(0);
  // render_admin sets msg "<zone> approved" on success.
  await expect(page.locator("body")).toContainText(`${zoneName} approved`);
}

/** Reject a Pending zone on its admin page. Perl always sends opensource_approved=false. */
export async function rejectZone(page: Page, idToken: string, zoneName: string): Promise<void> {
  await adminOpenZone(page, idToken);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    page.locator(ADMIN_FORM).locator('input[name="status_change"][value="Reject"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(errorAlerts(page), `rejecting ${zoneName} should not show an error`).toHaveCount(0);
  await expect(page.locator("body")).toContainText(`${zoneName} rejected`);
}

export type ZoneFields = Partial<NewZoneData>;

/**
 * Open the edit form, change the given fields, save, and wait for the show
 * page. A successful save redirects with mode=show (render_edit); an API error
 * re-renders the form instead, which this helper treats as a failure.
 */
export async function editZone(page: Page, idToken: string, fields: ZoneFields): Promise<void> {
  await expectCleanPage(page, bust(zonePath(idToken, "edit")));
  const form = page.locator('form[action="/manage/vendor/zone"]');
  await expect(form, "the edit form should open").toBeVisible();
  if (fields.zoneName !== undefined) await form.locator('input[name="zone_name"]').fill(fields.zoneName);
  if (fields.organizationName !== undefined) await form.locator('input[name="organization_name"]').fill(fields.organizationName);
  if (fields.requestInformation !== undefined) await form.locator('textarea[name="request_information"]').fill(fields.requestInformation);
  if (fields.deviceCount !== undefined) await form.locator('select[name="device_count"]').selectOption(fields.deviceCount);
  if (fields.deviceInformation !== undefined) await form.locator('textarea[name="device_information"]').fill(fields.deviceInformation);
  await Promise.all([
    page.waitForURL(/[?&]mode=show/),
    form.locator('input[type="submit"]').click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(errorAlerts(page), "the edit should save without an error alert").toHaveCount(0);
}
