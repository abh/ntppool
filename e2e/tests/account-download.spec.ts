import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  bust,
  expectCleanPage,
  expectNoErrorBleed,
  errorAlerts,
} from "../lib/helpers";

// Personal data download requests (MANUAL_TEST_PLAN.md §4c, issue #15).
//
// Controller: lib/NTPPool/Control/Manage/Account.pm render_download (:693-754).
//   GET  /manage/account/download   lists the user's `download` tasks.
//   POST /manage/account/download   creates a task when none is pending, then
//                                   redirects back (POST/redirect/GET).
//
// Template: docs/manage/tpl/user/download.html
//   - <h3>[% user.email %]</h3>
//   - the request list is a bare <table> of <tr><td>created_on</td><td>state</td>
//   - the request form (#download-form) is hidden once a request is pending
//   - a failed task renders "Error: <traceid>" in the state cell
//
// NOT covered here (deferred by the design; each needs a task held pending or
// completed on the backend): duplicate-POST suppression, archive contents,
// download delivery, filename validation, worker-log correlation.

const DOWNLOAD_PATH = "/manage/account/download";

/**
 * Rows of the request list. Scoped away from the audit-log table (#logs) that
 * other manage pages include, so a layout change there cannot inflate the count.
 */
function requestRows(page: Page) {
  return page.locator("table:not(#logs) tr:has(td)");
}

test("a fresh user submits one personal data download request", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("download-req");
  await loginAs(context, email);

  // --- First load: identity, an enabled form, and nothing left over ---------
  await expectCleanPage(page, bust(DOWNLOAD_PATH));
  await expect(
    page.getByRole("heading", { name: email }),
    "the download page should name the requesting user",
  ).toBeVisible();

  await expect(requestRows(page), "a fresh user has no prior requests").toHaveCount(
    0,
  );
  await expect(errorAlerts(page), "no error bleed on first load").toHaveCount(0);

  const submit = page.locator('#download-form button[type="submit"]');
  await expect(submit, "the request form should be offered").toBeVisible();
  await expect(submit).toBeEnabled();

  // --- Submit: a real POST, a real redirect, then a GET --------------------
  // Landing on a 200 page proves nothing on its own, so observe the POST
  // response and its Location header directly.
  //
  // waitForNavigation, not waitForURL: the page is already on this download
  // URL before the click, and waitForURL would resolve immediately against
  // that pre-click URL instead of waiting for the click's navigation.
  const [postResponse] = await Promise.all([
    page.waitForResponse(
      (r) =>
        r.request().method() === "POST" && r.url().includes(DOWNLOAD_PATH),
    ),
    page.waitForNavigation({
      url: /\/manage\/account\/download(\?|$)/,
      waitUntil: "load",
    }),
    submit.click(),
  ]);

  expect(
    postResponse.status(),
    "the request POST should redirect, not render in place",
  ).toBe(302);
  expect(
    postResponse.headers()["location"],
    "the redirect should return to the download page",
  ).toContain(DOWNLOAD_PATH);

  await expectNoErrorBleed(page, page.url());
  expect(
    page.url(),
    "the browser should land on the download page via GET",
  ).toContain(DOWNLOAD_PATH);

  // --- Result: exactly one request for this fresh identity -----------------
  await expect(
    requestRows(page),
    "exactly one download request should exist after one submission",
  ).toHaveCount(1);
  await expect(errorAlerts(page)).toHaveCount(0);

  // Worker timing is external, so pending and already-completed are both
  // acceptable — but a task error is a failure to report, not completion.
  const stateCell = requestRows(page).first().locator("td").nth(1);
  await expect(
    stateCell,
    "the request should be pending or downloadable, never errored",
  ).toHaveText(/Processing archive, check back later\.|Download archive/);
  await expect(page.locator("body")).not.toContainText("Error:");

  // --- Reload is a GET and creates nothing --------------------------------
  await expectCleanPage(page, bust(DOWNLOAD_PATH));
  await expect(
    requestRows(page),
    "reloading the download page must not create a second request",
  ).toHaveCount(1);

  // Re-check the task's state, not just the row count: the worker can process
  // the task in the gap between the first check above and this reload, and a
  // row-count-only check would still pass at 1 even if that processing failed
  // (row count doesn't change either way). Repeating the same state assertion
  // here is what actually proves the reload didn't silently pick up an error.
  await expect(
    requestRows(page).first().locator("td").nth(1),
    "the request should still be pending or downloadable, never errored, after reload",
  ).toHaveText(/Processing archive, check back later\.|Download archive/);
  await expect(page.locator("body")).not.toContainText("Error:");
});
