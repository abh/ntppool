import { randomUUID } from "node:crypto";
import type { Locator, Page, Response } from "@playwright/test";
import { resolveDefaultAccountToken } from "../lib/accounts";
import {
  installSession,
  MANAGE_URL,
  mintSession,
  uniqueTestEmail,
} from "../lib/auth";
import { bust } from "../lib/helpers";
import { expect, test } from "../lib/fixtures";
import { getAccountAuditLogs, getServer } from "../lib/servers";

test.use({ trace: "off" });

const REDACTED_VERIFICATION_PATH = "/manage/server/verify/redacted";

function verificationPath(token: string, accountToken?: string): string {
  const query = accountToken ? `?a=${encodeURIComponent(accountToken)}` : "";
  return `/manage/server/verify/${encodeURIComponent(token)}${query}`;
}

async function redactVerificationDiagnostics(page: Page): Promise<void> {
  await page.evaluate((redactedPath) => {
    const currentUrl = new URL(window.location.href);
    if (currentUrl.pathname.startsWith("/manage/server/verify/")) {
      const safeUrl = new URL(redactedPath, window.location.origin);
      const account = currentUrl.searchParams.get("a");
      if (account) safeUrl.searchParams.set("a", account);
      window.history.replaceState(null, "", safeUrl);
    }
    document
      .querySelector<HTMLFormElement>(
        'form[action^="/manage/server/verify/"]',
      )
      ?.setAttribute("action", redactedPath);
  }, REDACTED_VERIFICATION_PATH);
}

async function failWithoutVerificationSecret(
  page: Page,
  message: string,
): Promise<never> {
  await redactVerificationDiagnostics(page).catch(() => undefined);
  throw new Error(message);
}

async function navigateToVerification(
  page: Page,
  token: string,
  accountToken?: string,
): Promise<Response | null> {
  const navigation = page.waitForNavigation({ waitUntil: "load" });
  try {
    await page.evaluate(
      (url) => window.location.assign(url),
      new URL(
        bust(verificationPath(token, accountToken)),
        MANAGE_URL,
      ).toString(),
    );
    return await navigation;
  } catch {
    void navigation.catch(() => undefined);
    return failWithoutVerificationSecret(
      page,
      "verification page navigation failed",
    );
  }
}

interface VerificationFormState {
  present: boolean;
  actionMatches: boolean;
  accountToken: string;
  serverId: string;
  headingMatches: boolean;
}

async function readVerificationFormState(
  page: Page,
  expectedPath: string,
  expectedIp: string,
): Promise<VerificationFormState> {
  try {
    return await page.evaluate(
      ({ path, ip }) => {
        const form = document.querySelector<HTMLFormElement>(
          'form[action^="/manage/server/verify/"]',
        );
        return {
          present: Boolean(form),
          actionMatches: form?.getAttribute("action") === path,
          accountToken:
            form?.querySelector<HTMLInputElement>('input[name="a"]')?.value ??
            "",
          serverId:
            form?.querySelector<HTMLInputElement>('input[name="server"]')
              ?.value ?? "",
          headingMatches: Array.from(document.querySelectorAll("h3")).some(
            (heading) => heading.textContent?.trim() === `Verify ${ip}`,
          ),
        };
      },
      { path: expectedPath, ip: expectedIp },
    );
  } catch {
    return failWithoutVerificationSecret(
      page,
      "verification confirmation form could not be inspected",
    );
  }
}

async function submitVerificationForm(
  page: Page,
  form: Locator,
  token: string,
): Promise<Response> {
  const navigationPromise = page.waitForNavigation({ waitUntil: "load" });
  const responsePromise = page.waitForResponse(
    (response) =>
      response.request().method() === "POST" &&
      new URL(response.url()).pathname.endsWith(`/${token}`),
  );
  try {
    await form.locator('input[name="verify"]').click({ noWaitAfter: true });
    const [response] = await Promise.all([
      responsePromise,
      navigationPromise,
    ]);
    await response.finished();
    return response;
  } catch {
    void responsePromise.catch(() => undefined);
    void navigationPromise.catch(() => undefined);
    return failWithoutVerificationSecret(
      page,
      "verification form submission failed",
    );
  }
}

async function staffSession(): Promise<string> {
  return mintSession(uniqueTestEmail("server-audit-staff"), {
    grantStaff: true,
  });
}

test("pending verification redirects into the owner's account and completes", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ servers: [{ ipVersion: 4, pendingVerification: true }] });
  const server = fixture.servers[0];
  const path = verificationPath(server.verificationToken);
  await installSession(context, fixture.sessionToken);

  const firstResponse = page.waitForResponse((response) => {
    const url = new URL(response.url());
    return url.pathname.endsWith(`/${server.verificationToken}`) &&
      response.request().method() === "GET" && response.status() === 302;
  });
  let redirect: Response;
  try {
    [redirect] = await Promise.all([
      firstResponse,
      navigateToVerification(page, server.verificationToken),
    ]);
  } catch {
    void firstResponse.catch(() => undefined);
    return failWithoutVerificationSecret(
      page,
      "verification redirect response was not observed",
    );
  }
  const target = new URL(redirect.headers()["location"], redirect.url());
  if (target.pathname !== path) {
    await failWithoutVerificationSecret(
      page,
      "verification redirect targeted a different pending request",
    );
  }
  if (target.searchParams.get("a") !== fixture.accountToken) {
    await failWithoutVerificationSecret(
      page,
      "verification redirect targeted the wrong account",
    );
  }

  const formState = await readVerificationFormState(page, path, server.ip);
  if (!formState.present || !formState.actionMatches || !formState.headingMatches) {
    await failWithoutVerificationSecret(
      page,
      "verification confirmation form did not match the pending server",
    );
  }
  if (
    formState.accountToken !== fixture.accountToken ||
    formState.serverId !== server.serverId
  ) {
    await failWithoutVerificationSecret(
      page,
      "verification confirmation form targeted the wrong account or server",
    );
  }

  const form = page.locator('form[action^="/manage/server/verify/"]');
  const completed = await submitVerificationForm(
    page,
    form,
    server.verificationToken,
  );
  if (completed.status() !== 302) {
    await failWithoutVerificationSecret(
      page,
      "verification form did not return the success redirect",
    );
  }
  let completedTargetMatches = false;
  try {
    const location = completed.headers()["location"];
    if (location) {
      const target = new URL(location, MANAGE_URL);
      completedTargetMatches =
        target.pathname === "/manage/servers" &&
        target.searchParams.get("a") === fixture.accountToken &&
        target.hash === `#s-${server.ip}`;
    }
  } catch {
    // Report the malformed or secret-bearing target only through the static failure below.
  }
  if (!completedTargetMatches) {
    await failWithoutVerificationSecret(
      page,
      "verification form redirected to the wrong target",
    );
  }

  expect((await getServer(fixture.sessionToken, fixture.accountToken, server.ip)).verification.verified).toBe(true);
  await navigateToVerification(page, server.verificationToken, fixture.accountToken);
  if (await page.locator('form[action^="/manage/server/verify/"]').count()) {
    await failWithoutVerificationSecret(
      page,
      "completed verification still offered the confirmation form",
    );
  }

  const logs = await getAccountAuditLogs(await staffSession(), fixture.accountToken);
  expect(logs).toContainEqual(expect.objectContaining({
    type: "server",
    message: "Server verified",
    user: { userId: fixture.userId, email: fixture.email },
    server: { serverId: server.serverId, ip: server.ip },
    account: { accountToken: fixture.accountToken },
  }));
});

test("invalid verification token is not found", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ servers: [{ ipVersion: 4, verified: true }] });
  await installSession(context, fixture.sessionToken);
  const response = await navigateToVerification(page, randomUUID(), fixture.accountToken);
  await redactVerificationDiagnostics(page);
  expect(response?.status()).toBe(404);
});

test("verification without CSRF is refused and stays pending", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ servers: [{ ipVersion: 4, pendingVerification: true }] });
  const server = fixture.servers[0];
  const path = verificationPath(server.verificationToken);
  await installSession(context, fixture.sessionToken);
  await navigateToVerification(page, server.verificationToken, fixture.accountToken);
  const state = await readVerificationFormState(page, path, server.ip);
  if (!state.present || !state.actionMatches) {
    await failWithoutVerificationSecret(page, "pending verification form was missing");
  }
  const form = page.locator('form[action^="/manage/server/verify/"]');
  await form.locator('input[name="auth_token"]').evaluate((input) => input.remove());
  const response = await submitVerificationForm(
    page,
    form,
    server.verificationToken,
  );
  await redactVerificationDiagnostics(page);
  expect(response.status()).toBe(403);
  expect((await getServer(fixture.sessionToken, fixture.accountToken, server.ip)).verification.verified).toBe(false);
});

test("another account cannot complete the owner's verification", async ({ browser, fixtures }) => {
  const fixture = await fixtures.create({ servers: [{ ipVersion: 4, pendingVerification: true }] });
  const server = fixture.servers[0];
  const path = verificationPath(server.verificationToken);
  const outsiderSession = await mintSession(uniqueTestEmail("verify-outsider"));
  const outsiderContext = await browser.newContext();
  await installSession(outsiderContext, outsiderSession);
  const outsiderPage = await outsiderContext.newPage();
  try {
    const outsiderAccount = await resolveDefaultAccountToken(outsiderPage);
    expect(outsiderAccount).not.toBe(fixture.accountToken);
    const csrf = await outsiderPage.locator('form[action="/manage/server/add#add"] input[name="auth_token"]').inputValue();
    await navigateToVerification(
      outsiderPage,
      server.verificationToken,
      outsiderAccount,
    );
    const state = await readVerificationFormState(
      outsiderPage,
      path,
      server.ip,
    );
    if (
      !state.present ||
      !state.actionMatches ||
      state.accountToken !== outsiderAccount
    ) {
      await failWithoutVerificationSecret(
        outsiderPage,
        "cross-account verification form targeted the wrong account",
      );
    }
    const form = outsiderPage.locator(
      'form[action^="/manage/server/verify/"]',
    );
    try {
      await form
        .locator('input[name="auth_token"]')
        .evaluate((input, value) => {
          (input as HTMLInputElement).value = value;
        }, csrf);
    } catch {
      await failWithoutVerificationSecret(
        outsiderPage,
        "cross-account verification CSRF could not be installed",
      );
    }
    const response = await submitVerificationForm(
      outsiderPage,
      form,
      server.verificationToken,
    );
    await redactVerificationDiagnostics(outsiderPage);
    expect(response.status()).toBe(200);
    expect(response.headers()["location"]).toBeUndefined();
  } finally {
    await outsiderContext.close();
  }
  expect((await getServer(fixture.sessionToken, fixture.accountToken, server.ip)).verification.verified).toBe(false);
  const logs = await getAccountAuditLogs(await staffSession(), fixture.accountToken);
  expect(logs.some((log) => log.type === "server" && log.message === "Server verified" && log.server?.serverId === server.serverId)).toBe(false);
});
