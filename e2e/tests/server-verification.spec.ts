import { randomUUID } from "node:crypto";
import { installSession, mintSession, uniqueTestEmail } from "../lib/auth";
import { expect, getAccountAuditLogs, getServer, test } from "../lib/servers";

function verificationPath(token: string, accountToken?: string): string {
  const query = accountToken ? `?a=${encodeURIComponent(accountToken)}` : "";
  return `/manage/server/verify/${encodeURIComponent(token)}${query}`;
}

async function staffSession(): Promise<string> {
  return mintSession(uniqueTestEmail("server-audit-staff"), { grantStaff: true });
}

test("pending verification redirects into the owner's account and completes", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, pendingVerification: true }]);
  const server = fixture.servers[0];
  await installSession(context, fixture.sessionToken);

  const firstResponse = page.waitForResponse((response) => {
    const url = new URL(response.url());
    return url.pathname === verificationPath(server.verificationToken) &&
      response.request().method() === "GET" && response.status() === 302;
  });
  await page.goto(verificationPath(server.verificationToken));
  const redirect = await firstResponse;
  const target = new URL(redirect.headers()["location"], redirect.url());
  expect(target.pathname).toBe(verificationPath(server.verificationToken));
  expect(target.searchParams.get("a")).toBe(fixture.accountToken);

  const form = page.locator(`form[action="${verificationPath(server.verificationToken)}"]`);
  await expect(page.getByRole("heading", { name: `Verify ${server.ip}` })).toBeVisible();
  await expect(form).toBeVisible();
  await expect(form.locator('input[name="a"]')).toHaveValue(fixture.accountToken);
  await expect(form.locator('input[name="server"]')).toHaveValue(server.serverId);

  const postResponse = page.waitForResponse((response) =>
    new URL(response.url()).pathname === verificationPath(server.verificationToken) &&
    response.request().method() === "POST",
  );
  await form.locator('input[name="verify"]').click();
  const completed = await postResponse;
  expect(completed.status()).toBe(302);
  const completedLocation = new URL(completed.headers()["location"], completed.url());
  expect(completedLocation.pathname).toBe("/manage/servers");
  expect(completedLocation.searchParams.get("a")).toBe(fixture.accountToken);

  expect((await getServer(fixture.sessionToken, fixture.accountToken, server.ip)).verification.verified).toBe(true);
  await page.goto(verificationPath(server.verificationToken, fixture.accountToken));
  await expect(page.locator(`form[action="${verificationPath(server.verificationToken)}"]`)).toHaveCount(0);

  const logs = await getAccountAuditLogs(await staffSession(), fixture.accountToken);
  expect(logs).toContainEqual(expect.objectContaining({
    type: "server",
    message: "Server verified",
    user: { userId: fixture.userId, email: fixture.email },
    server: { serverId: server.serverId, ip: server.ip },
    account: { accountToken: fixture.accountToken },
  }));
});

test("invalid verification token is not found", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  await installSession(context, fixture.sessionToken);
  const response = await page.goto(verificationPath(randomUUID(), fixture.accountToken));
  expect(response?.status()).toBe(404);
});

test("verification without CSRF is refused and stays pending", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, pendingVerification: true }]);
  const server = fixture.servers[0];
  await installSession(context, fixture.sessionToken);
  const response = await page.request.post(verificationPath(server.verificationToken, fixture.accountToken), {
    form: { a: fixture.accountToken, server: server.serverId, verify: `I am authorized to add ${server.ip} to the NTP Pool` },
    maxRedirects: 0,
  });
  expect(response.status()).toBe(403);
  expect((await getServer(fixture.sessionToken, fixture.accountToken, server.ip)).verification.verified).toBe(false);
});

test("another account cannot complete the owner's verification", async ({ browser, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, pendingVerification: true }]);
  const server = fixture.servers[0];
  const outsiderSession = await mintSession(uniqueTestEmail("verify-outsider"));
  const outsiderContext = await browser.newContext();
  await installSession(outsiderContext, outsiderSession);
  const outsiderPage = await outsiderContext.newPage();
  try {
    await outsiderPage.goto("/manage/servers");
    const outsiderAccount = new URL(outsiderPage.url()).searchParams.get("a");
    expect(outsiderAccount).toBeTruthy();
    expect(outsiderAccount).not.toBe(fixture.accountToken);
    const csrf = await outsiderPage.locator('form[action="/manage/server/add"] input[name="auth_token"]').inputValue();
    const response = await outsiderPage.request.post(verificationPath(server.verificationToken, outsiderAccount!), {
      form: { a: outsiderAccount!, server: server.serverId, auth_token: csrf, verify: `I am authorized to add ${server.ip} to the NTP Pool` },
      maxRedirects: 0,
    });
    expect(response.status()).toBe(200);
    expect(response.headers()["location"]).toBeUndefined();
  } finally {
    await outsiderContext.close();
  }
  expect((await getServer(fixture.sessionToken, fixture.accountToken, server.ip)).verification.verified).toBe(false);
  const logs = await getAccountAuditLogs(await staffSession(), fixture.accountToken);
  expect(logs.some((log) => log.type === "server" && log.message === "Server verified" && log.server?.serverId === server.serverId)).toBe(false);
});
