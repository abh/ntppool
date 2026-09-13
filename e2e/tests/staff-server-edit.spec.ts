import type { BrowserContext, Page } from "@playwright/test";
import { installSession, mintSession, uniqueTestEmail } from "../lib/auth";
import { bust } from "../lib/helpers";
import { expect, test, type Fixture } from "../lib/fixtures";
import { getAccountAuditLogs, getServer } from "../lib/servers";

// Staff hostname and zone edits on the scores page.
//
// Routes: lib/NTPPool/Control/Manage.pm manage_dispatch -> staff_hostname_edit
// (/manage/admin/hostname/{edit,save}) and staff_zone_edit
// (/manage/admin/zones/{edit,save}). tpl/admin/hostname_{view,edit}.html swap
// #server_header_section and tpl/admin/zone_{view,edit}.html swap #zone_list,
// both outerHTML.
//
// Fixture servers use documentation addresses, so no real hostname can pass
// the API's DNS check; saving an empty hostname is the one save that succeeds.
// Fixtures are never put in a real zone: an unknown zone name reaches the API
// and fails there without touching zone membership.

test.use({ trace: "off" });

const HOSTNAME_EDIT_PATH = "/manage/admin/hostname/edit";
const HOSTNAME_SAVE_PATH = "/manage/admin/hostname/save";
const ZONES_SAVE_PATH = "/manage/admin/zones/save";

function adminPath(path: string, fixture: Fixture): string {
  const ip = fixture.servers[0].ip;
  return `${path}?server=${encodeURIComponent(ip)}&a=${encodeURIComponent(fixture.accountToken)}`;
}

/**
 * Log in as a fresh staff user and open the fixture server's scores page in
 * the staff user's own account context, as server-scores-context.spec.ts
 * does. Returns the staff session for API reads.
 */
async function openScoresAsStaff(
  page: Page,
  context: BrowserContext,
  fixture: Fixture,
): Promise<string> {
  const staffSession = await mintSession(uniqueTestEmail("staff-server-edit"), { grantStaff: true });
  await installSession(context, staffSession);
  await page.goto(bust("/manage"));
  const staffAccount = new URL(page.url()).searchParams.get("a");
  expect(staffAccount).toBeTruthy();
  const ip = fixture.servers[0].ip;
  const response = await page.goto(bust(`/scores/${encodeURIComponent(ip)}?a=${encodeURIComponent(staffAccount!)}`));
  expect(response?.status()).toBe(200);
  return staffSession;
}

/**
 * Run an action that swaps `selector` (outerHTML), assert the fragment request
 * returned 200, and wait for htmx to settle the replacement. A click inside
 * the settle window lands on an element whose hx-* handlers aren't attached
 * yet; see swapMonitorConfig in monitor-config.spec.ts.
 */
async function swapFragment(
  page: Page,
  selector: string,
  path: string,
  method: "GET" | "POST",
  action: () => Promise<void>,
) {
  const fragment = page.locator(selector);
  const oldFragment = await fragment.elementHandle();
  expect(oldFragment).not.toBeNull();
  const responsePromise = page.waitForResponse(
    (response) => new URL(response.url()).pathname === path && response.request().method() === method,
  );
  await action();
  expect((await responsePromise).status()).toBe(200);
  await expect.poll(() => oldFragment!.evaluate((node) => node.isConnected)).toBe(false);
  await expect(fragment).not.toHaveClass(/\bhtmx-added\b/);
}

async function serverAuditLogCount(staffSession: string, fixture: Fixture): Promise<number> {
  const logs = await getAccountAuditLogs(staffSession, fixture.accountToken);
  return logs.filter((log) => log.server?.serverId === fixture.servers[0].serverId).length;
}

test("staff hostname save through the form reaches the API", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ servers: [{ ipVersion: 4, verified: true }] });
  const staffSession = await openScoresAsStaff(page, context, fixture);
  const auditBefore = await serverAuditLogCount(staffSession, fixture);

  const header = "#server_header_section";
  await swapFragment(page, header, HOSTNAME_EDIT_PATH, "GET", () => page.locator(`${header} button[hx-get]`).click());
  const form = page.locator(`${header} form.hostname-edit-form`);
  await form.locator('input[name="hostname"]').fill("");
  await swapFragment(page, header, HOSTNAME_SAVE_PATH, "POST", () => form.getByRole("button", { name: "Save" }).click());

  await expect(page.locator(`${header} button[hx-get]`)).toHaveText("Set hostname");
  await expect(page.locator(`${header} .error`)).toHaveCount(0);
  // The audit row is what the no-token test below relies on to detect a save.
  expect(await serverAuditLogCount(staffSession, fixture)).toBeGreaterThan(auditBefore);
});

test("staff hostname and zone saves without a CSRF token are refused without mutation", async ({
  page,
  context,
  fixtures,
}) => {
  const fixture = await fixtures.create({ servers: [{ ipVersion: 4, verified: true }] });
  const staffSession = await openScoresAsStaff(page, context, fixture);
  const auditBefore = await serverAuditLogCount(staffSession, fixture);

  // Without the CSRF check both bodies reach UpdateServer: the empty hostname
  // is saved and audited, and the unknown zone comes back as an API error.
  const posts: Array<[string, Record<string, string>]> = [
    [HOSTNAME_SAVE_PATH, { hostname: "" }],
    [ZONES_SAVE_PATH, { zones: `e2e-csrf-zone-${Date.now()}` }],
  ];
  for (const [path, form] of posts) {
    const response = await page.request.post(adminPath(path, fixture), {
      form,
      headers: { "HX-Request": "true" },
      maxRedirects: 0,
    });
    expect(response.status(), `${path} without auth_token`).toBe(403);
  }

  expect(await serverAuditLogCount(staffSession, fixture)).toBe(auditBefore);
  const server = await getServer(fixture.sessionToken, fixture.accountToken, fixture.servers[0].ip);
  expect(server.hostname).toBe("");
  expect(server.zones).toEqual([]);
});

test("staff zone save shows the API error for an unknown zone and keeps the form usable", async ({
  page,
  context,
  fixtures,
}) => {
  const fixture = await fixtures.create({ servers: [{ ipVersion: 4, verified: true }] });
  await openScoresAsStaff(page, context, fixture);

  const zoneList = page.locator("#zone_list");
  await swapFragment(page, "#zone_list", "/manage/admin/zones/edit", "GET", () => page.locator("#server_edit_zones").click());
  const unknownZone = `e2e-no-such-zone-${Date.now()}`;
  await zoneList.locator('input[name="zones"]').fill(unknownZone);
  await swapFragment(page, "#zone_list", ZONES_SAVE_PATH, "POST", () => zoneList.getByRole("button", { name: "Save" }).click());

  const alert = zoneList.locator('.alert-danger[role="alert"]');
  await expect(alert).toContainText(`zone not found: ${unknownZone}`);
  await expect(alert).toContainText(/Trace ID: [0-9a-f]{32}/);
  await expect(zoneList.locator('input[name="zones"]')).toHaveValue(unknownZone);
  expect((await getServer(fixture.sessionToken, fixture.accountToken, fixture.servers[0].ip)).zones).toEqual([]);

  // The re-rendered form must still point at this server: Cancel returns the
  // read-only zone view, with exactly one Edit button. zone_view.html used to
  // render the button outside the swapped #zone_list, so each view swap added
  // another one.
  await swapFragment(page, "#zone_list", "/manage/admin/zones/edit", "GET", () => zoneList.getByRole("button", { name: "Cancel" }).click());
  await expect(page.locator("span#zone_list")).toBeVisible();
  await expect(page.locator("#zone_list .alert-danger")).toHaveCount(0);
  await expect(page.locator("#server_edit_zones")).toHaveCount(1);
});
