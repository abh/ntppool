import "dotenv/config";
import { defineConfig, devices } from "@playwright/test";

// Public pages live on the web host; the authenticated /manage app is a
// separate Combust site on the manage host. Each project pins its own baseURL
// so specs keep using relative goto() paths.
const webURL = process.env.NTP_BASE_URL || "https://web.askdev.grundclock.com";
const manageURL =
  process.env.NTP_MANAGE_URL || "https://manage.askdev.grundclock.com";

// Specs that exercise public, unauthenticated pages on the web host. Everything
// else is an authenticated /manage flow and runs against the manage host.
const WEB_SPECS = [
  "**/scores.spec.ts",
  "**/i18n.spec.ts",
  "**/dns-zone.spec.ts",
];

export default defineConfig({
  testDir: "./tests",
  // Validate config + prove a session can be minted before running anything,
  // so a misconfigured run fails fast with one clear message.
  globalSetup: "./global-setup.ts",
  // Finish the run: the API schedules the run's users for deletion and
  // deletes their sessions.
  globalTeardown: "./global-teardown.ts",
  timeout: 30_000,
  expect: {
    timeout: 10_000,
  },
  retries: 1,
  // `list` prints a readable per-test line in the terminal; the HTML report
  // (npm run report) is far easier to read for failures (traces, diffs).
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "web",
      testMatch: WEB_SPECS,
      use: { ...devices["Desktop Chrome"], baseURL: webURL },
    },
    {
      name: "manage",
      testIgnore: WEB_SPECS,
      use: { ...devices["Desktop Chrome"], baseURL: manageURL },
    },
  ],
});
