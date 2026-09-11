import { test, expect } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { bust, expectCleanPage } from "../lib/helpers";

test("add-server form renders clean for a fresh user", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("server-add-form"));
  await expectCleanPage(page, bust("/manage/servers"));

  const form = page.locator('form[action="/manage/server/add"]');
  await expect(form).toBeVisible();
  await expect(form.locator('input[name="host"]')).toBeVisible();
  await expect(form.locator('input[type="submit"][value="Add"]')).toBeVisible();
});
