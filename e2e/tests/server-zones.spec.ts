import type { Locator, Page } from "@playwright/test";
import { installSession } from "../lib/auth";
import { bust } from "../lib/helpers";
import { expect, test, type Fixture, type FixtureServer } from "../lib/fixtures";
import { humanDate, serverListUrl, swapNetspeed } from "../lib/servers";

const SEED = [
  { ipVersion: 4 as const, verified: true, zone: "de" },
  { ipVersion: 4 as const, verified: true, zone: "de", scheduledDeletion: true },
];

// The manage page lists every zone the server is in except the root ".".
function expectedZones(server: FixtureServer): string[] {
  return server.zones.filter((zone) => zone !== ".").sort();
}

async function openServers(page: Page, fixture: Fixture) {
  await page.goto(bust(serverListUrl(fixture.accountToken)));
}

// The template puts no separator between the links, so assert on the a
// elements rather than the span's text.
async function assertZoneLinks(page: Page, block: Locator, server: FixtureServer) {
  const links = await block.locator(`#zones_${server.serverId} a`).evaluateAll((elements) =>
    elements.map((a) => ({ name: a.textContent!.trim(), href: a.getAttribute("href")! })));
  expect(links.map((link) => link.name).sort()).toEqual(expectedZones(server));
  for (const { name, href } of links) {
    expect(decodeURIComponent(new URL(href, page.url()).pathname)).toBe(`/zone/${name}`);
    expect((await page.request.get(href)).status(), href).toBe(200);
  }
}

test("zones are listed with links on the server list", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ servers: SEED });
  const server = fixture.servers[0];
  await installSession(context, fixture.sessionToken);
  await openServers(page, fixture);
  await assertZoneLinks(page, page.locator(`#server_${server.serverId}`), server);
});

// Before API 5f63a0c, UpdateServer returned the root "." zone and zones
// without URLs, so the swapped-in list showed "." and broken links. Devel
// already runs the fix, so this can't be shown red live;
// update_server_zones_integration_test.go guards the API side.
test("zones survive an HTMX netspeed swap", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ servers: SEED });
  const server = fixture.servers[0];
  await installSession(context, fixture.sessionToken);
  await openServers(page, fixture);
  const block = await swapNetspeed(page, server, "1500");
  await assertZoneLinks(page, block, server);
});

test("a scheduled server shows its zones and the long deletion date", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ servers: SEED });
  const server = fixture.servers[1];
  await installSession(context, fixture.sessionToken);
  await openServers(page, fixture);
  const block = page.locator(`#server_${server.serverId}`);
  await expect(block).toContainText(`scheduled for deletion on ${humanDate(server.deletionOn)}.`);
  await assertZoneLinks(page, block, server);
});
