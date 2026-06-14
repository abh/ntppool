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
  reporter: "list",
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
