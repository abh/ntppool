import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";

// Visit a page and assert it loaded cleanly: HTTP 200, no Perl error bleed,
// no server error. A fresh account has no servers, so we tolerate an
// empty-but-valid server list rather than requiring server data.
async function expectCleanPage(page: Page, path: string) {
  const response = await page.goto(path);
  expect(response, `no response from ${path}`).not.toBeNull();
  expect(response!.status(), `unexpected status for ${path}`).toBe(200);

  const body = await page.content();
  expect(body, `Rose::DB / ORM error leaked on ${path}`).not.toContain(
    "NP::Model::",
  );
  expect(body, `Perl 'Can't locate' error on ${path}`).not.toContain(
    "Can't locate",
  );
}

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
