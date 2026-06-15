import "dotenv/config";
import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.NTP_BASE_URL || "https://web.askdev.grundclock.com";

export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  expect: {
    timeout: 10_000,
  },
  retries: 1,
  // `list` prints a readable per-test line in the terminal; the HTML report
  // (npm run report) is far easier to read for failures (traces, diffs).
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL,
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
