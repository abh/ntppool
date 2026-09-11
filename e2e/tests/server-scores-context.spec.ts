import { installSession, mintSession, uniqueTestEmail } from "../lib/auth";
import { expect, getServer, test, type FixtureServer, type RpcError } from "../lib/servers";

function expandIPv6(ip: string): string {
  const [left, right = ""] = ip.split("::");
  const leftParts = left ? left.split(":") : [];
  const rightParts = right ? right.split(":") : [];
  const missing = 8 - leftParts.length - rightParts.length;
  return [...leftParts, ...Array(missing).fill("0"), ...rightParts]
    .map((part) => part.padStart(4, "0")).join(":");
}

function scoresPath(server: FixtureServer, accountToken?: string): string {
  return `/scores/${encodeURIComponent(server.ip)}${accountToken ? `?a=${encodeURIComponent(accountToken)}` : ""}`;
}

test("IPv6 scores normalize to the canonical fixture address", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 6, verified: true }]);
  const server = fixture.servers[0];
  const expanded = expandIPv6(server.ip);
  const compressedRead = await getServer(fixture.sessionToken, fixture.accountToken, server.ip);
  const expandedRead = await getServer(fixture.sessionToken, fixture.accountToken, expanded);
  expect(expandedRead.id).toBe(compressedRead.id);
  await installSession(context, fixture.sessionToken);
  const response = await page.request.get(`/scores/${expanded}`, { maxRedirects: 0 });
  expect(response.status()).toBe(301);
  expect(new URL(response.headers()["location"], response.url()).pathname).toBe(`/scores/${server.ip}`);
  const canonical = await page.goto(scoresPath(server, fixture.accountToken));
  expect(canonical?.status()).toBe(200);
  await expect(page.locator("h3").first()).toContainText(server.ip);
});

test("staff scores edit targets the server's account from another active account", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  const server = fixture.servers[0];
  const staffSession = await mintSession(uniqueTestEmail("scores-staff"), { grantStaff: true });
  await installSession(context, staffSession);
  await page.goto("/manage");
  const staffAccount = new URL(page.url()).searchParams.get("a");
  expect(staffAccount).toBeTruthy();
  expect(staffAccount).not.toBe(fixture.accountToken);
  await page.goto(scoresPath(server, staffAccount!));
  const button = page.locator("#server_header_section button[hx-get]");
  await expect(button).toBeVisible();
  const requestPromise = page.waitForRequest((request) => new URL(request.url()).pathname === "/manage/admin/hostname/edit");
  await button.click();
  const target = new URL((await requestPromise).url());
  expect(target.searchParams.get("server")).toBe(server.ip);
  expect(target.searchParams.get("a")).toBe(fixture.accountToken);
  const editForm = page.locator("#server_header_section form.hostname-edit-form");
  await expect(editForm).toBeVisible();
  const saveTarget = new URL((await editForm.getAttribute("hx-post"))!, page.url());
  expect(saveTarget.searchParams.get("server")).toBe(server.ip);
  expect(saveTarget.searchParams.get("a")).toBe(fixture.accountToken);
});

test("owner scores omit staff controls", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  await installSession(context, fixture.sessionToken);
  await page.goto(scoresPath(fixture.servers[0], fixture.accountToken));
  await expect(page.locator("#server_header_section button[hx-get]")).toHaveCount(0);
});

test("unrelated scores omit private account details and staff controls", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  const outsider = await mintSession(uniqueTestEmail("scores-outsider"));
  await installSession(context, outsider);
  await page.goto("/manage");
  const outsiderAccount = new URL(page.url()).searchParams.get("a");
  expect(outsiderAccount).toBeTruthy();
  const privateAccount = (await getServer(fixture.sessionToken, fixture.accountToken, fixture.servers[0].ip)).account;
  expect(privateAccount).toBeDefined();
  await page.goto(scoresPath(fixture.servers[0], outsiderAccount!));
  await expect(page.locator("body")).toContainText(fixture.servers[0].ip);
  await expect(page.locator("body")).not.toContainText(fixture.email);
  await expect(page.locator("body")).not.toContainText(fixture.accountToken);
  await expect(page.locator("body")).not.toContainText(privateAccount!.displayName);
  if (privateAccount!.publicUrl) {
    await expect(page.locator("body")).not.toContainText(privateAccount!.publicUrl);
  }
  await expect(page.locator("#server_header_section button[hx-get]")).toHaveCount(0);
});

test("public scores omit private account details and staff controls", async ({ browser, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  const privateAccount = (await getServer(fixture.sessionToken, fixture.accountToken, fixture.servers[0].ip)).account;
  expect(privateAccount).toBeDefined();
  const context = await browser.newContext();
  const page = await context.newPage();
  try {
    const base = process.env.NTP_BASE_URL;
    expect(base).toBeTruthy();
    const response = await page.goto(new URL(`/scores/${fixture.servers[0].ip}`, base).toString());
    expect(response?.status()).toBe(200);
    await expect(page.locator("body")).toContainText(fixture.servers[0].ip);
    await expect(page.locator("body")).not.toContainText(fixture.email);
    await expect(page.locator("body")).not.toContainText(fixture.accountToken);
    await expect(page.locator("body")).not.toContainText(privateAccount!.displayName);
    if (privateAccount!.publicUrl) {
      await expect(page.locator("body")).not.toContainText(privateAccount!.publicUrl);
    }
    await expect(page.locator("#server_header_section button[hx-get]")).toHaveCount(0);
  } finally {
    await context.close();
  }
});

test("GetServer enforces private account visibility and edit permission", async ({ browser, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  const server = fixture.servers[0];
  const owner = await getServer(fixture.sessionToken, fixture.accountToken, server.ip);
  expect(owner.account).toEqual({
    idToken: fixture.accountToken,
    displayName: expect.any(String),
    publicUrl: expect.any(String),
    publicProfile: false,
  });

  const outsiderSession = await mintSession(uniqueTestEmail("server-rpc-outsider"));
  const outsiderContext = await browser.newContext();
  await installSession(outsiderContext, outsiderSession);
  const outsiderPage = await outsiderContext.newPage();
  await outsiderPage.goto("/manage");
  const outsiderAccount = new URL(outsiderPage.url()).searchParams.get("a");
  await outsiderContext.close();
  expect(outsiderAccount).toBeTruthy();

  const staffSession = await mintSession(uniqueTestEmail("server-rpc-staff"), { grantStaff: true });
  expect((await getServer(staffSession, fixture.accountToken, server.ip)).account).toEqual(owner.account);
  expect((await getServer(outsiderSession, outsiderAccount!, server.ip)).account).toBeUndefined();
  expect((await getServer(undefined, undefined, server.ip)).account).toBeUndefined();
  await expect(getServer(fixture.sessionToken, fixture.accountToken, server.ip, true)).resolves.toMatchObject({ id: server.serverId });
  await expect(getServer(staffSession, fixture.accountToken, server.ip, true)).resolves.toMatchObject({ id: server.serverId });
  await expect(getServer(outsiderSession, outsiderAccount!, server.ip, true)).rejects.toMatchObject({ status: 404, code: "not_found" } satisfies Partial<RpcError>);
  await expect(getServer(undefined, undefined, server.ip, true)).rejects.toMatchObject({ status: 401, code: "unauthenticated" } satisfies Partial<RpcError>);
});
