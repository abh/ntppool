import { test } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { expectCleanPage } from "../lib/helpers";

test("core pages load clean as a logged-in user", async ({ page, context }) => {
  const email = uniqueTestEmail();
  await loginAs(context, email);

  // Server list page. A fresh account renders the empty-but-valid list. This
  // page also hosts the add-server form (tpl/manage.html PROCESSes
  // add_form.html); /manage/server/add itself is a POST-only, CSRF-protected
  // form action and 403s on a bare GET, so it is not a navigable page.
  await expectCleanPage(page, "/manage/servers");

  // Account overview — another core surface reachable by a fresh account.
  await expectCleanPage(page, "/manage/account");
});
