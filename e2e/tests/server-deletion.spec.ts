import { installSession, mintSession, uniqueTestEmail } from "../lib/auth";
import { resolveDefaultAccountToken } from "../lib/accounts";
import { bust } from "../lib/helpers";
import { expect, getAccountAuditLogs, getServer, serverDeleteUrl, test, type ServerFixture } from "../lib/servers";

test.use({ trace: "off" });

const FORM = 'form[action="/manage/server/delete"]';

async function staffSession(): Promise<string> {
  return mintSession(uniqueTestEmail("deletion-audit-staff"), { grantStaff: true });
}

function humanDate(isoDate: string): string {
  return new Intl.DateTimeFormat("en-US", { month: "long", day: "2-digit", year: "numeric", timeZone: "UTC" })
    .format(new Date(`${isoDate}T00:00:00Z`));
}

async function assertDeletionOn(fixture: ServerFixture, index: number, value: string) {
  const server = fixture.servers[index];
  expect((await getServer(fixture.sessionToken, fixture.accountToken, server.ip)).deletionOn).toBe(value);
}

test("scheduling deletion persists the selected date", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  const server = fixture.servers[0];
  await installSession(context, fixture.sessionToken);
  const url = serverDeleteUrl(server, fixture.accountToken);
  await page.goto(bust(url));
  const form = page.locator(FORM);
  const picker = form.locator('select[name="deletion_date"]');
  const selectedDate = await picker.locator("option").nth(1).getAttribute("value");
  expect(selectedDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  await picker.selectOption(selectedDate!);
  const postResponse = page.waitForResponse((response) => new URL(response.url()).pathname === "/manage/server/delete" && response.request().method() === "POST");
  await form.locator('input[name="submitbtn"]').click();
  const response = await postResponse;
  expect(response.status()).toBe(302);
  const location = new URL(response.headers()["location"], response.url());
  expect(location.pathname).toBe("/manage/servers");
  expect(location.searchParams.get("a")).toBe(fixture.accountToken);
  expect(location.hash).toBe(`#s-${server.ip}`);

  await page.goto(bust(url));
  await expect(page.locator(".block", { has: page.locator(FORM) })).toContainText(humanDate(selectedDate!));
  await expect(page.locator(`${FORM} input[name="cancel_deletion"]`)).toBeVisible();
  await expect(page.locator(`${FORM} select[name="deletion_date"]`)).toHaveCount(0);
  await assertDeletionOn(fixture, 0, selectedDate!);
  const logs = await getAccountAuditLogs(await staffSession(), fixture.accountToken);
  expect(logs).toContainEqual(expect.objectContaining({
    type: "server",
    message: `Deletion scheduled for ${selectedDate}`,
    user: { userId: fixture.userId, email: fixture.email },
    server: { serverId: server.serverId, ip: server.ip },
    account: { accountToken: fixture.accountToken },
  }));
});

test("cancelling deletion clears the scheduled date", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true, scheduledDeletion: true }]);
  const server = fixture.servers[0];
  await installSession(context, fixture.sessionToken);
  const url = serverDeleteUrl(server, fixture.accountToken);
  await page.goto(bust(url));
  const form = page.locator(FORM);
  const postResponse = page.waitForResponse((response) => new URL(response.url()).pathname === "/manage/server/delete" && response.request().method() === "POST");
  await form.locator('input[name="cancel_deletion"]').click();
  const response = await postResponse;
  expect(response.status()).toBe(302);
  const location = new URL(response.headers()["location"], response.url());
  expect(location.pathname).toBe("/manage/servers");
  expect(location.searchParams.get("a")).toBe(fixture.accountToken);
  expect(location.hash).toBe(`#s-${server.ip}`);
  await page.goto(bust(url));
  await expect(page.locator(`${FORM} select[name="deletion_date"]`)).toBeVisible();
  await expect(page.locator(`${FORM} input[name="cancel_deletion"]`)).toHaveCount(0);
  await assertDeletionOn(fixture, 0, "");
  const logs = await getAccountAuditLogs(await staffSession(), fixture.accountToken);
  expect(logs.some((log) => log.type === "server" && log.message.startsWith("Deletion cancelled by ") &&
    log.user?.userId === fixture.userId && log.user.email === fixture.email &&
    log.server?.serverId === server.serverId && log.server.ip === server.ip &&
    log.account?.accountToken === fixture.accountToken)).toBe(true);
});

test("API date validation is shown on the deletion picker", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  const server = fixture.servers[0];
  await installSession(context, fixture.sessionToken);
  await page.goto(bust(serverDeleteUrl(server, fixture.accountToken)));
  const csrf = await page.locator(`${FORM} input[name="auth_token"]`).inputValue();
  const response = await page.request.post("/manage/server/delete", {
    form: { server: server.serverId, a: fixture.accountToken, auth_token: csrf, deletion_date: "2099-1-01", submitbtn: "Schedule Deletion" },
    maxRedirects: 0,
  });
  expect(response.status()).toBe(200);
  const disposable = await context.newPage();
  try {
    await disposable.setContent(await response.text());
    await expect(disposable.locator('.alert.alert-danger[role="alert"]')).toContainText("invalid deletion_date format, expected YYYY-MM-DD");
    await expect(disposable.locator(`${FORM} select[name="deletion_date"]`)).toBeVisible();
  } finally {
    await disposable.close();
  }
  await assertDeletionOn(fixture, 0, "");
});

test("cancellation is denied with two active unverified servers", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([
    { ipVersion: 4, verified: true, scheduledDeletion: true },
    { ipVersion: 4 },
    { ipVersion: 6 },
  ]);
  const target = fixture.servers[0];
  await installSession(context, fixture.sessionToken);
  await page.goto(bust(serverDeleteUrl(target, fixture.accountToken)));
  await page.locator(`${FORM} input[name="cancel_deletion"]`).click();
  await expect(page.locator('.alert.alert-danger[role="alert"]')).toHaveText("Please verify active servers in the account first.");
  await assertDeletionOn(fixture, 0, "2099-01-01");
});

test("deletion without CSRF is refused without mutation", async ({ page, context, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  const server = fixture.servers[0];
  await installSession(context, fixture.sessionToken);
  const response = await page.request.post("/manage/server/delete", {
    form: { server: server.serverId, a: fixture.accountToken, deletion_date: "2099-01-01", submitbtn: "Schedule Deletion" },
    maxRedirects: 0,
  });
  expect(response.status()).toBe(403);
  await assertDeletionOn(fixture, 0, "");
});

test("another account cannot schedule the owner's server", async ({ browser, serverFixtures }) => {
  const fixture = await serverFixtures.create([{ ipVersion: 4, verified: true }]);
  const server = fixture.servers[0];
  const outsiderSession = await mintSession(uniqueTestEmail("deletion-outsider"));
  const outsiderContext = await browser.newContext();
  await installSession(outsiderContext, outsiderSession);
  const outsiderPage = await outsiderContext.newPage();
  try {
    const outsiderAccount = await resolveDefaultAccountToken(outsiderPage);
    const csrf = await outsiderPage.locator('form[action="/manage/server/add#add"] input[name="auth_token"]').inputValue();
    const response = await outsiderPage.request.post("/manage/server/delete", {
      form: { server: server.ip, a: outsiderAccount, auth_token: csrf, deletion_date: "2099-01-01", submitbtn: "Schedule Deletion" },
      maxRedirects: 0,
    });
    expect(response.status()).toBe(404);
  } finally {
    await outsiderContext.close();
  }
  await assertDeletionOn(fixture, 0, "");
});
