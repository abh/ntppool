import "dotenv/config";
import { chromium } from "@playwright/test";
import { connectRpc, loginAs, MANAGE_URL, uniqueTestEmail } from "./lib/auth";
import {
  requireDevelEnvironmentHeader,
  requireDevelSettings,
} from "./lib/deployment";

// Run once before the whole suite. Validates configuration and proves we can
// actually mint a session, so a misconfigured run fails immediately with ONE
// actionable error instead of every login-dependent test throwing an opaque
// "fetch failed".
export default async function globalSetup() {
  const required = [
    "NTP_BASE_URL",
    "NTP_MANAGE_URL",
    "NTP_INTERNAL_API_URL",
    "NTP_API_CLI",
  ];
  const missing = required.filter((k) => !process.env[k]);
  if (missing.length) {
    throw new Error(
      `e2e config incomplete: ${missing.join(", ")} not set.\n` +
        `Copy e2e/.env.example to e2e/.env and fill it in (see e2e/README.md).`,
    );
  }

  // Catch leftover placeholder values copied from .env.example.
  const internal = process.env.NTP_INTERNAL_API_URL!;
  let internalHost: string;
  try {
    internalHost = new URL(internal).host;
  } catch {
    throw new Error(
      `NTP_INTERNAL_API_URL is not a valid URL: ${internal}`,
    );
  }
  if (/(^|\.)example\./.test(internalHost) || internalHost.includes(".example")) {
    throw new Error(
      `NTP_INTERNAL_API_URL is still the placeholder (${internal}).\n` +
        `Point it at the real internal Go API (Tailscale-reachable). See e2e/README.md.`,
    );
  }

  // Refuse to create sessions or fixtures until the API and both web surfaces
  // independently identify themselves as the devel deployment.
  try {
    const settings = await connectRpc<unknown>(
      "GetSettings",
      "ntppool.system.v1.SystemService/GetSettings",
      {},
      {},
    );
    requireDevelSettings(settings);

    const targets = [
      { label: "public web", url: new URL("/", process.env.NTP_BASE_URL!).toString() },
      { label: "manage web", url: new URL("/manage", MANAGE_URL).toString() },
    ];
    await Promise.all(
      targets.map(async ({ label, url }) => {
        const response = await fetch(url, {
          signal: AbortSignal.timeout(15_000),
        });
        requireDevelEnvironmentHeader(
          label,
          response.url,
          response.headers.get("x-ntppool-environment"),
        );
      }),
    );
  } catch (err) {
    throw new Error(
      `e2e environment preflight failed; refusing to run outside a verified devel deployment.\n` +
        `Underlying error: ${(err as Error).message}`,
    );
  }

  // Preflight: mint a throwaway session AND prove it actually authenticates a
  // browser against the manage app. This catches the whole login path in one
  // place — a reachable API but a broken cookie (bad encoding), wrong host, or
  // unhonored session fails ONCE here with a clear message instead of as 30
  // opaque per-test failures.
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext();
    const { email } = await loginAs(context, uniqueTestEmail("e2e-preflight"));

    const page = await context.newPage();
    const resp = await page.goto(new URL("/manage", MANAGE_URL).toString(), {
      waitUntil: "domcontentloaded",
    });
    const status = resp?.status();
    // The manage layout renders the sidebar twice (a desktop copy and a hidden
    // #mobile-nav copy), so match the *visible* logout link specifically.
    const loggedIn = await page
      .locator('a[href*="/manage/logout"]:visible')
      .first()
      .waitFor({ state: "visible", timeout: 10_000 })
      .then(() => true)
      .catch(() => false);

    if (status !== 200 || !loggedIn) {
      throw new Error(
        `loaded ${MANAGE_URL}/manage with a minted session but it is not ` +
          `logged in (status=${status}, Logout link visible=${loggedIn}). ` +
          `The session cookie was installed for host ` +
          `${new URL(MANAGE_URL).hostname}; if the manage app is served ` +
          `elsewhere, fix NTP_MANAGE_URL.`,
      );
    }
  } catch (err) {
    throw new Error(
      `e2e preflight failed: could not establish a logged-in session.\n` +
        `Checked:\n` +
        `  - mint via NTP_API_CLI: exec access to the API? ` +
        `api-dev image with \`api e2e\` deployed? same database as ${MANAGE_URL}?\n` +
        `  - logged-in load of ${MANAGE_URL}/manage (correct NTP_MANAGE_URL?)\n` +
        `Underlying error: ${(err as Error).message}`,
    );
  } finally {
    await browser.close();
  }
}
