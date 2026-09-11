import type { Page } from "@playwright/test";
import { installSession } from "../lib/auth";
import { bust } from "../lib/helpers";
import { expect, getServer, test, type ServerFixture } from "../lib/servers";

test.use({ trace: "off" });

const UPDATE_PATH = "/manage/server/update/netspeed";

async function openServer(page: Page, fixture: ServerFixture) {
  await page.goto(bust(`/manage/servers?a=${encodeURIComponent(fixture.accountToken)}`));
  return page.locator(`#server_${fixture.servers[0].serverId}`);
}

async function currentSpeed(fixture: ServerFixture): Promise<number> {
  return (await getServer(fixture.sessionToken, fixture.accountToken, fixture.servers[0].ip)).netspeed;
}

test("verified netspeed updates replace the HTMX fragment without navigation", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  await installSession(context, fixture.sessionToken);
  const fragment = await openServer(page, fixture);
  const oldElement = await fragment.elementHandle();
  let navigations = 0;
  page.on("framenavigated", (frame) => { if (frame === page.mainFrame()) navigations += 1; });
  const responsePromise = page.waitForResponse((response) => new URL(response.url()).pathname === UPDATE_PATH && response.request().method() === "POST");
  await fragment.locator('select[name="netspeed"]').selectOption("1500");
  const response = await responsePromise;
  expect(response.request().headers()["hx-request"]).toBe("true");
  expect(response.status()).toBe(200);
  expect(oldElement).not.toBeNull();
  await expect.poll(() => oldElement!.evaluate((node) => node.isConnected)).toBe(false);
  await expect(page.locator(`#netspeed_${fixture.servers[0].serverId}`)).toHaveText("1.5 Mbit");
  expect(navigations).toBe(0);
  expect(await currentSpeed(fixture)).toBe(1500);
  await openServer(page, fixture);
  await expect(page.locator(`#netspeed_${fixture.servers[0].serverId}`)).toHaveText("1.5 Mbit");
});

test("unverified netspeed increase shows the verification error and preserves speed", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4 }]);
  await installSession(context, fixture.sessionToken);
  const fragment = await openServer(page, fixture);
  const csrf = await fragment.locator('input[name="auth_token"]').inputValue();
  const response = await page.request.post(UPDATE_PATH, {
    form: { auth_token: csrf, server: fixture.servers[0].serverId, a: fixture.accountToken, netspeed: "1500" },
    headers: { "HX-Request": "true" }, maxRedirects: 0,
  });
  expect(response.status()).toBe(200);
  const body = await response.text();
  const disposable = await context.newPage();
  try {
    await disposable.setContent(body);
    const responseFragment = disposable.locator(
      `#server_${fixture.servers[0].serverId}`,
    );
    await expect(responseFragment.locator(`#netspeed_${fixture.servers[0].serverId}`)).toHaveText("512 Kbit");
    await expect(responseFragment.locator('.alert.alert-danger[role="alert"]')).toHaveText(/^please verify your server before increasing the netspeed$/i);
  } finally {
    await disposable.close();
  }
  expect(await currentSpeed(fixture)).toBe(512);
});

test("nonnumeric netspeed is rejected without mutation", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  await installSession(context, fixture.sessionToken);
  const fragment = await openServer(page, fixture);
  const csrf = await fragment.locator('input[name="auth_token"]').inputValue();
  const response = await page.request.post(UPDATE_PATH, {
    form: { auth_token: csrf, server: fixture.servers[0].serverId, a: fixture.accountToken, netspeed: "fast" },
    headers: { "HX-Request": "true" }, maxRedirects: 0,
  });
  expect(response.status()).toBe(400);
  expect(await currentSpeed(fixture)).toBe(512);
});

test("netspeed without CSRF is rejected without mutation", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  await installSession(context, fixture.sessionToken);
  await openServer(page, fixture);
  const response = await page.request.post(UPDATE_PATH, {
    form: { server: fixture.servers[0].serverId, a: fixture.accountToken, netspeed: "1500" },
    headers: { "HX-Request": "true" }, maxRedirects: 0,
  });
  expect(response.status()).toBe(403);
  expect(await currentSpeed(fixture)).toBe(512);
});

test("non-HTMX netspeed update redirects and persists", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  await installSession(context, fixture.sessionToken);
  const fragment = await openServer(page, fixture);
  const csrf = await fragment.locator('input[name="auth_token"]').inputValue();
  const response = await page.request.post(UPDATE_PATH, {
    form: { auth_token: csrf, server: fixture.servers[0].serverId, a: fixture.accountToken, netspeed: "1500" }, maxRedirects: 0,
  });
  expect(response.status()).toBe(302);
  expect(new URL(response.headers()["location"], response.url()).pathname).toBe("/manage/servers");
  expect(await currentSpeed(fixture)).toBe(1500);
  await openServer(page, fixture);
  await expect(page.locator(`#netspeed_${fixture.servers[0].serverId}`)).toHaveText("1.5 Mbit");
});
