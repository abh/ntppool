import { test } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { expectCleanPage } from "../lib/helpers";

test("core pages load clean as a logged-in user", async ({ page, context }) => {
  const email = uniqueTestEmail();
  await loginAs(context, email);

  // Server list page. A fresh account renders the empty-but-valid list.
  await expectCleanPage(page, "/manage/servers");

  // Per-server view. A fresh account has no servers to deep-link into,
  // so exercise the add-server page (route: /manage/server/add), which is
  // the reachable per-server surface for a new account. Still must render
  // clean and authenticated.
  await expectCleanPage(page, "/manage/server/add");
});
