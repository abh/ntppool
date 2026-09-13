import type { Browser, BrowserContext, Page } from "@playwright/test";
import { test, expect } from "../lib/servers";
import {
  loginAs,
  uniqueTestEmail,
  MANAGE_URL,
  getAccountNumericId,
} from "../lib/auth";
import { bust, expectCleanPage, expectNoErrorBleed } from "../lib/helpers";
import {
  renameAccount,
  resolveDefaultAccountToken,
  uniqueAccountName,
} from "../lib/accounts";

// Staff search (MANUAL_TEST_PLAN.md §13, issue #43).
//
// Route: lib/NTPPool/Control/Manage.pm manage_dispatch (:451-461) -> staff_search
// (:482-612). Template: docs/manage/tpl/staff.html (the form) and
// tpl/admin/search_results.html (the HTMX fragment swapped into #users).
//
// This slice covers account-NAME pattern matching, the `id:<numeric>` lookup,
// and exact-IP lookup against the bounded server fixture. The numeric
// accounts.id is not reachable from the browser (search results carry only
// id_token, and account_id is never rendered as text), so the id: test reads
// it through AccountService.GetAccount as the target itself.
//
// Hostname highlighting, include-deleted, `monitors:` and `zone:` searches
// still need controlled fixtures and stay deferred.

const ADMIN_PATH = "/manage/admin";
const SEARCH_PATH = "/manage/admin/search";

interface SearchTarget {
  email: string;
  accountToken: string;
  accountName: string;
  /** The target's own session, for reads the UI does not expose (see the id: test). */
  sessionToken: string;
}

/**
 * Mint a regular user and give their account a unique, searchable name through
 * the real edit form. Returns the details a staff search should surface.
 */
async function createSearchTarget(
  browser: Browser,
  prefix: string,
): Promise<SearchTarget> {
  const context = await browser.newContext();
  try {
    const email = uniqueTestEmail(`${prefix}-target`);
    const { sessionToken } = await loginAs(context, email);
    const page = await context.newPage();

    const accountToken = await resolveDefaultAccountToken(page);
    const accountName = uniqueAccountName(`${prefix}-needle`);
    await renameAccount(page, accountToken, accountName);

    return { email, accountToken, accountName, sessionToken };
  } finally {
    // The session outlives the context — it is server-side state — so the id:
    // test can still read through it after this returns.
    await context.close();
  }
}

/** Collect uncaught page errors for the life of the page. */
function capturePageErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on("pageerror", (err) => errors.push(err.message));
  return errors;
}

/**
 * Log in as a fresh staff user, start collecting page errors, and open the
 * admin page that carries the search form.
 */
async function openStaffSearch(
  page: Page,
  context: BrowserContext,
  prefix: string,
): Promise<string[]> {
  await loginAs(context, uniqueTestEmail(`${prefix}-staff`), {
    grantStaff: true,
  });
  const pageErrors = capturePageErrors(page);
  await expectCleanPage(page, bust(ADMIN_PATH));
  return pageErrors;
}

/**
 * Type a query into the staff search form and submit it through HTMX.
 *
 * Returns the POST response. Asserts the fragment swap happened without a
 * full-page navigation — #search_form has no `action`, so a navigation here
 * would mean HTMX never ran.
 */
async function runSearch(page: Page, query: string) {
  const urlBefore = page.url();

  await page.locator("#search_form input#q").fill(query);
  const [response] = await Promise.all([
    page.waitForResponse(
      (r) => r.request().method() === "POST" && r.url().includes(SEARCH_PATH),
    ),
    page.locator('#search_form button[type="submit"]').click(),
  ]);

  expect(
    page.url(),
    "search should swap a fragment, not reload the page",
  ).toBe(urlBefore);
  return response;
}

/**
 * Assert the swapped-in result set surfaces the target account.
 *
 * Scoped to #users: the acting staff user's own email appears in the page
 * chrome, and the nav carries other identities, so a body-wide email check
 * would pass without any result at all.
 */
async function expectAccountResult(
  page: Page,
  target: SearchTarget,
  why: string,
) {
  const results = page.locator("#users");
  await expect(results, why).toContainText(target.accountName);
  await expect(results, "the account's member should be listed").toContainText(
    target.email,
  );

  // The result must link into the TARGET's account context.
  await expect(
    results.locator(`a[href*="a=${target.accountToken}"]`).first(),
    "result links should carry the target account token",
  ).toBeVisible();

  await expect(results.locator(".alert-danger")).toHaveCount(0);
}

test("staff finds an account by a unique name substring", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-hit");
  const pageErrors = await openStaffSearch(page, context, "search");

  // Search a PROPER substring, not the whole name: `a.name LIKE '%q%'` must
  // match on a fragment, and an implementation that quietly degraded to
  // equality would still pass if we searched the full value.
  const needle = target.accountName.slice(4, -2);
  expect(needle, "needle must be a proper substring").not.toBe(
    target.accountName,
  );
  expect(needle.length, "needle must stay distinctive").toBeGreaterThan(12);

  const response = await runSearch(page, needle);
  expect(response.status()).toBe(200);
  await expectNoErrorBleed(page, `${SEARCH_PATH} (${needle})`);

  await expectAccountResult(
    page,
    target,
    "the target account should be found",
  );
  expect(pageErrors, "no uncaught page errors during search").toEqual([]);
});

test("staff finds an account by exact numeric id: lookup", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-id");
  const pageErrors = await openStaffSearch(page, context, "search-id");

  // `id:<n>` takes the decimal accounts.id (api search.go: strconv.ParseInt on
  // the id: prefix, then SearchAccountByID `where a.id = $1`). The acc_ token
  // is NOT that value, and it is not rendered anywhere in the UI — so read it
  // through the API, as the target itself. Only this test needs it.
  const numericId = await getAccountNumericId(
    target.sessionToken,
    target.accountToken,
  );

  const response = await runSearch(page, `id:${numericId}`);
  expect(response.status()).toBe(200);
  await expectNoErrorBleed(page, `${SEARCH_PATH} (id:${numericId})`);

  await expectAccountResult(
    page,
    target,
    "the exact-ID lookup should return the target account",
  );
  expect(pageErrors).toEqual([]);
});

test("staff finds a fixture server by exact IP", async ({
  page,
  context,
  serverFixtures,
}) => {
  const fixture = await serverFixtures.create([
    { ipVersion: 4, verified: true },
  ]);
  const server = fixture.servers[0];
  const pageErrors = await openStaffSearch(page, context, "search-ip");

  const response = await runSearch(page, server.ip);
  expect(response.status()).toBe(200);

  const results = page.locator("#users");
  // staff_search wraps the matched field in <b>, so this covers both "the
  // server came back" and "the match is highlighted" in one assertion.
  await expect(
    results.locator("b", { hasText: server.ip }),
    "the matched IP should be rendered and highlighted",
  ).toBeVisible();

  // Checked after the first awaited assertion: the fragment is in the DOM by
  // now, so this reads the swapped-in results and not the pre-swap page.
  await expectNoErrorBleed(page, `${SEARCH_PATH} (${server.ip})`);

  // One href carries both halves of the grouping claim — this is the fixture
  // server's own row, and it is rendered under the fixture's account. Two
  // separately scoped checks would also pass with the row under some OTHER
  // account, which is exactly what this test is meant to rule out.
  await expect(
    results.locator(
      `a[href*="/scores/${server.ip}"][href*="a=${fixture.accountToken}"]`,
    ),
    "the server result should link to its score page in the fixture account",
  ).toBeVisible();
  await expect(results.locator(".alert-danger")).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test("a no-match query replaces earlier results with the no-results message", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-miss");
  const pageErrors = await openStaffSearch(page, context, "search-miss");

  // Populate results first, so the no-match case has something to replace.
  // Checked with expectAccountResult, not a bare toContainText: the no-results
  // fragment echoes the query verbatim ("No results found for \"...\""), so a
  // bare containText(target.accountName) would pass even if this search found
  // nothing at all.
  await runSearch(page, target.accountName);
  await expectAccountResult(page, target, "the populate step should find the target account");

  const missQuery = uniqueAccountName("no-such-account");
  const response = await runSearch(page, missQuery);
  expect(response.status(), "a no-match search is a 200, never a 404").toBe(200);
  await expectNoErrorBleed(page, `${SEARCH_PATH} (${missQuery})`);

  const results = page.locator("#users");
  await expect(results).toContainText(`No results found for "${missQuery}"`);
  await expect(
    results,
    "the earlier result must be replaced, not appended to",
  ).not.toContainText(target.accountName);
  await expect(results.locator(".alert-danger")).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test("an empty query clears earlier results without an error", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-empty");
  const pageErrors = await openStaffSearch(page, context, "search-empty");

  // Checked with expectAccountResult, not a bare toContainText: see the
  // no-match test for why a substring check alone would be vacuous here.
  await runSearch(page, target.accountName);
  await expectAccountResult(page, target, "the populate step should find the target account");

  const response = await runSearch(page, "");
  expect(response.status()).toBe(200);
  await expectNoErrorBleed(page, `${SEARCH_PATH} (empty)`);

  // staff_search returns early for an empty query: results => {} and `query` is
  // never set, so search_results.html renders NOTHING — not a no-results
  // message. Assert absence on all three counts.
  const results = page.locator("#users");
  await expect(results).not.toContainText(target.accountName);
  await expect(results.locator("ul")).toHaveCount(0);
  await expect(results).not.toContainText("No results found");
  await expect(results.locator(".alert-danger")).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test("a staff search POST without a CSRF token is refused", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-csrf");
  await openStaffSearch(page, context, "search-csrf");

  // The same request the form sends, minus auth_token. manage_dispatch
  // checks the token for every POST under /manage/admin.
  const response = await page.request.post(SEARCH_PATH, {
    form: { q: target.accountName },
    headers: { "HX-Request": "true" },
    maxRedirects: 0,
  });
  expect(response.status()).toBe(403);
  expect(await response.text()).not.toContain(target.email);
});

test("a non-staff user cannot reach staff search", async ({
  page,
  context,
  browser,
}) => {
  const target = await createSearchTarget(browser, "search-denied");

  await loginAs(context, uniqueTestEmail("search-nonstaff"));

  // (a) No staff-search entry point in the navigation. Check it on a page a
  // non-staff user can actually load — /manage/admin itself 404s for them.
  await expectCleanPage(page, bust("/manage/servers"));
  await expect(
    page.getByRole("link", { name: "Admin search" }),
    "non-staff navigation must not offer staff search",
  ).toHaveCount(0);

  // (b) A direct GET is refused by the outer dispatcher. manage_dispatch only
  // routes into staff_search when user_is_staff, so a non-staff request falls
  // through to `return 404`. That is the expected web-route denial; the inner
  // handler's 403 is unreachable here.
  const getResponse = await page.goto(
    `${SEARCH_PATH}?q=${encodeURIComponent(target.accountName)}`,
  );
  expect(getResponse, "no response from the search route").not.toBeNull();
  expect(
    getResponse!.status(),
    "non-staff GET of the search route should be refused",
  ).toBe(404);
  await expect(page.locator("body")).not.toContainText(target.accountName);

  // (c) The HTMX POST is refused the same way, and leaks no results.
  const postResponse = await context.request.post(
    `${MANAGE_URL}${SEARCH_PATH}`,
    {
      form: { q: target.accountName },
      headers: { "HX-Request": "true" },
      maxRedirects: 0,
    },
  );
  expect(
    postResponse.status(),
    "non-staff HTMX POST should be refused",
  ).toBe(404);
  expect(await postResponse.text()).not.toContain(target.accountName);

  // (d) And the admin page itself is not reachable.
  const adminResponse = await page.goto(ADMIN_PATH);
  expect(adminResponse, "no response from the admin page").not.toBeNull();
  expect(adminResponse!.status()).toBe(404);
});
