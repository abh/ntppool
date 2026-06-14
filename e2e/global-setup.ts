import "dotenv/config";
import { mintSession, uniqueTestEmail } from "./lib/auth";

// Run once before the whole suite. Validates configuration and proves we can
// actually mint a session, so a misconfigured run fails immediately with ONE
// actionable error instead of every login-dependent test throwing an opaque
// "fetch failed".
export default async function globalSetup() {
  const required = [
    "NTP_BASE_URL",
    "NTP_INTERNAL_API_URL",
    "NTP_TEST_SESSION_KEY",
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

  // Preflight: actually mint a throwaway session. This proves the API URL is
  // reachable, the key is valid, and the dev API includes CreateTestSession.
  try {
    await mintSession(uniqueTestEmail("e2e-preflight"));
  } catch (err) {
    throw new Error(
      `e2e preflight failed: could not mint a test session via ${internal}\n` +
        `Check that:\n` +
        `  - NTP_INTERNAL_API_URL is reachable (Tailscale up? correct host/port/path?)\n` +
        `  - the deployed dev API includes the CreateTestSession RPC\n` +
        `  - NTP_TEST_SESSION_KEY is a valid test-session-api key\n` +
        `Underlying error: ${(err as Error).message}`,
    );
  }
}
