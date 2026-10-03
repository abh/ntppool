import type { Page, Response } from "@playwright/test";
import { installSession, mintSession, uniqueTestEmail } from "../lib/auth";
import { bust, errorAlerts } from "../lib/helpers";
import { expect, test, type Fixture, type FixtureSeed, type Fixtures } from "../lib/fixtures";
import { ADD_FORM, confirmAdd, getAccountAuditLogs, getServer, serverListUrl, submitAdd } from "../lib/servers";

// Both add paths for a server that is scheduled for deletion or already
// deleted: the owner adding it again, and another account taking it over. The
// fixture IPs never answer NTP; the api-dev precheck answers for them when the
// adder is a fixture account of the same run, and asks for the country, which
// exercises the explicit zone on confirm.

const ZONE = "de";
const SCHEDULED_ON = "2099-01-01";
const DELETED_ON = "2020-01-01";

async function staffSession(): Promise<string> {
  return mintSession(uniqueTestEmail("readd-audit-staff"), { grantStaff: true });
}

async function auditMessages(staff: string, accountToken: string): Promise<string[]> {
  return (await getAccountAuditLogs(staff, accountToken)).map((log) => log.message);
}

// Account B has a subscription for the zone and no servers, so it can add one.
async function createAdder(fixtures: Fixtures): Promise<Fixture> {
  return fixtures.create({ subscription: { maxZones: 1, maxDevices: 5000 } });
}

const SCHEDULED: FixtureSeed = { servers: [{ ipVersion: 4, verified: true, scheduledDeletion: true }] };

async function openServerList(page: Page, fixture: Fixture): Promise<void> {
  await installSession(page.context(), fixture.sessionToken);
  await page.goto(bust(serverListUrl(fixture.accountToken)));
}

// Logs in as the fixture, submits the IP on its server list page and gets to
// the confirm page.
async function startAdd(page: Page, adder: Fixture, ip: string): Promise<void> {
  await openServerList(page, adder);
  await submitAdd(page, ip);
  await expect(page.locator(`select[name="explicit_zone_${ip}"]`)).toBeVisible();
}

// A successful add redirects to the server on the adder's server list.
function expectRedirectToManage(response: Response, ip: string, accountToken: string): void {
  expect(response.status()).toBe(302);
  const location = new URL(response.headers()["location"], response.url());
  expect(location.pathname).toBe("/manage/servers");
  expect(location.searchParams.get("a")).toBe(accountToken);
  expect(location.hash).toBe(`#s-${ip}`);
}

test("re-adding your own server scheduled for deletion cancels the deletion", async ({ page, fixtures }) => {
  const owner = await fixtures.create(SCHEDULED);
  const ip = owner.servers[0].ip;
  await startAdd(page, owner, ip);
  expectRedirectToManage(await confirmAdd(page, ip, ZONE), ip, owner.accountToken);

  const read = await getServer(owner.sessionToken, owner.accountToken, ip);
  expect(read.account?.idToken).toBe(owner.accountToken);
  expect(read.deletionOn).toBe("");
  expect(read.verification.verified).toBe(true);
  expect(await auditMessages(await staffSession(), owner.accountToken)).toContain(
    `Deletion cancelled by adding ${ip} again (was scheduled for ${SCHEDULED_ON})`,
  );
});

// The old owner's server is in another zone, which the takeover must drop.
const OLD_ZONE = "us";
const TAKEOVERS: Array<[string, FixtureSeed, string]> = [
  ["a server scheduled for deletion", { servers: [{ ipVersion: 4, verified: true, scheduledDeletion: true, zone: OLD_ZONE }] }, SCHEDULED_ON],
  ["a deleted server", { servers: [{ ipVersion: 4, verified: true, deleted: true, zone: OLD_ZONE }] }, DELETED_ON],
];

for (const [name, seed, was] of TAKEOVERS) {
  test(`another account takes over ${name}`, async ({ page, fixtures }) => {
    const [owner, adder] = await Promise.all([fixtures.create(seed), createAdder(fixtures)]);
    const ip = owner.servers[0].ip;
    await startAdd(page, adder, ip);
    expectRedirectToManage(await confirmAdd(page, ip, ZONE), ip, adder.accountToken);

    const read = await getServer(adder.sessionToken, adder.accountToken, ip);
    expect(read.account?.idToken).toBe(adder.accountToken);
    expect(read.deletionOn).toBe("");
    expect(read.verification.verified).toBe(false);
    expect(read.zones).toEqual(expect.arrayContaining([ZONE, "europe"]));
    expect(read.zones).not.toContain(OLD_ZONE);

    const staff = await staffSession();
    const [adderMessages, ownerMessages] = await Promise.all([
      auditMessages(staff, adder.accountToken),
      auditMessages(staff, owner.accountToken),
    ]);
    expect(adderMessages).toContain(`Server re-added: ${ip} (was scheduled for deletion on ${was})`);
    expect(ownerMessages).toContain(`Server ${ip} was registered again by another account`);

    await openServerList(page, owner);
    await expect(page.locator(ADD_FORM)).toBeVisible();
    await expect(page.locator("body")).not.toContainText(ip);
  });
}

test("a rejected zone is shown on the add page", async ({ page, fixtures }) => {
  const [owner, adder] = await Promise.all([fixtures.create(SCHEDULED), createAdder(fixtures)]);
  const ip = owner.servers[0].ip;
  await startAdd(page, adder, ip);

  // The page only offers real zones, so rewrite the chosen option. The
  // comment runs the staff email branch on a failed add; the email itself
  // can't be observed here, so this only shows the page still renders.
  const select = page.locator(`select[name="explicit_zone_${ip}"]`);
  await select.selectOption(ZONE);
  await select.evaluate((element) => {
    const option = (element as HTMLSelectElement).selectedOptions[0];
    option.value = "no-such-zone";
  });
  const response = await confirmAdd(page, ip, "no-such-zone", "e2e rejected zone");

  expect(response.status()).toBe(200);
  await expect(errorAlerts(page).filter({ hasText: "Invalid fallback zone: no-such-zone" })).toBeVisible();

  const read = await getServer(owner.sessionToken, owner.accountToken, ip);
  expect(read.account?.idToken).toBe(owner.accountToken);
  expect(read.deletionOn).toBe(SCHEDULED_ON);
});
