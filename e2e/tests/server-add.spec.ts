import type { Page } from "@playwright/test";
import { resolveDefaultAccountToken } from "../lib/accounts";
import { installSession, mintSession, uniqueTestEmail } from "../lib/auth";
import { bust } from "../lib/helpers";
import { expect, test } from "../lib/fixtures";
import { getServer, serverListUrl } from "../lib/servers";

const ADD_FORM = 'form[action="/manage/server/add#add"]';

// Precheck answers for an existing server before it queries NTP, so these
// run with fixture IPs that never answer.
async function submitAdd(page: Page, ip: string) {
  const form = page.locator(ADD_FORM);
  await form.locator('input[name="host"]').fill(ip);
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/manage/server/add"),
    form.locator('[type="submit"]').click(),
  ]);
}

test("re-adding an active server to its own account says it is already registered", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ servers: [{ ipVersion: 4, verified: true }] });
  const server = fixture.servers[0];
  await installSession(context, fixture.sessionToken);
  await page.goto(bust(serverListUrl(fixture.accountToken)));
  await submitAdd(page, server.ip);
  await expect(page.locator(".alert.alert-info")).toContainText(`${server.ip} is already registered in the system.`);
});

test("adding another account's active server is refused", async ({ browser, fixtures }) => {
  const fixture = await fixtures.create({ servers: [{ ipVersion: 4, verified: true }] });
  const server = fixture.servers[0];
  const outsiderSession = await mintSession(uniqueTestEmail("add-outsider"));
  const outsiderContext = await browser.newContext();
  await installSession(outsiderContext, outsiderSession);
  const outsiderPage = await outsiderContext.newPage();
  try {
    await resolveDefaultAccountToken(outsiderPage);
    await submitAdd(outsiderPage, server.ip);
    await expect(outsiderPage.locator('.alert.alert-danger[role="alert"]')).toContainText("Server already registered");
  } finally {
    await outsiderContext.close();
  }
  const read = await getServer(fixture.sessionToken, fixture.accountToken, server.ip);
  expect(read.account?.idToken).toBe(fixture.accountToken);
});
