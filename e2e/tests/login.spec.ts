import { test, expect } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";

test("minted user lands on the manage dashboard", async ({ page, context }) => {
  const email = uniqueTestEmail();
  await loginAs(context, email);

  const response = await page.goto("/manage");
  expect(response, "no response from /manage").not.toBeNull();
  expect(response!.status()).toBe(200);

  // Must be on the manage dashboard, not bounced to a login/dead-end page.
  expect(page.url()).toContain("/manage");
  expect(page.url()).not.toContain("/login");

  // Stable logged-in marker: the sidebar logout link renders the
  // authenticated user's email (manage/tpl/navigation_sidebar.html).
  // This selector may need adjusting against the live site, but it must
  // stay a genuine "authenticated" marker. Do NOT weaken this to something
  // that also renders on the logged-out / empty dead-end page.
  const logout = page.locator("a.nav-link", { hasText: "Logout" });
  await expect(logout).toBeVisible();
  await expect(logout).toContainText(email);
});
