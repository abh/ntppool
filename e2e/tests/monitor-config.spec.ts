import { test, expect, type Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { accountFormUrl, resolveDefaultAccountToken } from "../lib/accounts";
import { bust, expectCleanPage, expectNoErrorBleed } from "../lib/helpers";
import {
  MONITOR_CONFIG_PATH,
  monitorConfigUrl,
  openMonitorConfigEditor,
  saveMonitorConfig,
} from "../lib/monitors";

// Account monitor configuration — the monitor-admin-only card on the account
// page. MANUAL_TEST_PLAN.md §14.
//
// Routes (lib/NTPPool/Control/Manage/Account.pm:197-204), both HTMX fragments:
//   - GET  /manage/account/monitor-config?a=<token>  render_monitor_config_form
//                              -> tpl/account/monitor_config_edit_form.html
//   - POST /manage/account/monitor-config?a=<token>  render_monitor_config_update
//                              -> tpl/account/monitor_config_display_clean.html
// Both answer 403 unless user_is_monitor_admin. monitor_admin is its own
// privilege bit — support_staff does not imply it.
//
// Real selectors from monitor_config_section.html, monitor_config_fields.html
// and monitor_config_edit_form.html:
//   - #monitor-config-section   the whole card; rendered only for monitor admins
//   - #monitor-config-display   the HTMX swap target (hx-swap="outerHTML"), so
//                               the same id holds either the display card or
//                               the edit form
//   - buttons "Edit Configuration" (GET) and "Save Changes" (POST)
//   - select[name="monitors_per_server_limit"], whose value-0 option is
//     "Default (1)"
//   - .badge-success "Updated" on the display card after a successful save
//
// The API returns the *effective* config, so an account with no override
// reports monitors_per_server_limit = 1 and the form selects the value-0
// "Default (1)" option (posting 0 is what clears the override).

/** The "Monitors per Server" column of the read-only display card. */
function perServerDisplay(page: Page) {
  return page
    .locator("#monitor-config-display .col-md-4")
    .filter({ hasText: "Monitors per Server:" });
}

/** The "Monitors per Server" select of the edit form. */
function perServerSelect(page: Page) {
  return page.locator(
    '#monitor-config-display select[name="monitors_per_server_limit"]',
  );
}

/** Pick a per-server limit in the open edit form and save it. */
async function savePerServerLimit(page: Page, value: string) {
  await perServerSelect(page).selectOption(value);
  await saveMonitorConfig(page);
}

test("monitor admin changes the per-server limit and restores Default (1)", async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("monitor-config-admin"), {
    grantMonitorAdmin: true,
  });
  const accountToken = await resolveDefaultAccountToken(page);
  const accountURL = accountFormUrl(accountToken);
  await expectCleanPage(page, bust(accountURL));

  await expect(page.locator("#monitor-config-section")).toBeVisible();
  // One locator for every visit to the editor: the swap reuses the same id, so
  // re-resolving it after each swap would describe the same element again.
  const select = perServerSelect(page);
  await openMonitorConfigEditor(page);
  await expect(select).toHaveValue("0");
  await expect(select.locator('option[value="0"]')).toHaveText(/Default \(1\)/);

  await savePerServerLimit(page, "3");
  await expect(perServerDisplay(page)).toContainText(/\b3\b/);
  await openMonitorConfigEditor(page);
  await expect(select).toHaveValue("3");

  await savePerServerLimit(page, "0");
  await expect(perServerDisplay(page)).toContainText(/\b1\b/);

  await expectCleanPage(page, bust(accountURL));
  await expect(perServerDisplay(page)).toContainText(/\b1\b/);
  await openMonitorConfigEditor(page);
  await expect(select).toHaveValue("0");
  await expectNoErrorBleed(page, page.url());
});

test("failed save shows the HTTP status and trace ID and saves nothing", async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("monitor-config-error"), {
    grantMonitorAdmin: true,
  });
  const accountToken = await resolveDefaultAccountToken(page);
  const accountURL = accountFormUrl(accountToken);
  await expectCleanPage(page, bust(accountURL));

  const select = perServerSelect(page);
  await openMonitorConfigEditor(page);
  await expect(select).toHaveValue("0");
  await select.selectOption("3");

  // A bogus CSRF token is the cheapest reliable failure: the account
  // dispatcher answers 403 from check_auth_token before the save handler runs.
  // openMonitorConfigEditor has already waited for the form to settle, so this
  // edits the live form htmx will post.
  await page
    .locator('#monitor-config-display input[name="auth_token"]')
    .evaluate((input: HTMLInputElement) => {
      input.value = "bogus-auth-token";
    });

  // swapMonitorConfig asserts a 200, so wait for the failing POST directly.
  const responsePromise = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === MONITOR_CONFIG_PATH &&
      response.request().method() === "POST",
  );
  await page.getByRole("button", { name: "Save Changes" }).click();
  expect((await responsePromise).status()).toBe(403);

  await expect(page.locator("#monitor-config-error")).toBeVisible();
  await expect(page.locator("#monitor-config-error-message")).toHaveText(
    "Permission denied (HTTP 403)",
  );
  await expect(page.locator("#monitor-config-error-traceid")).toHaveText(
    /^[0-9a-f]{32}$/,
  );

  // htmx does not swap a 403, so the edit form keeps the unsaved choice.
  await expect(select).toHaveValue("3");

  await expectCleanPage(page, bust(accountURL));
  await expect(perServerDisplay(page)).toContainText(/\b1\b/);
  await openMonitorConfigEditor(page);
  await expect(select).toHaveValue("0");
});

test("non-monitor-admin cannot reach or update monitor configuration", async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("monitor-config-user"));
  const accountToken = await resolveDefaultAccountToken(page);
  await expectCleanPage(page, bust(accountFormUrl(accountToken)));

  await expect(page.locator("#monitor-config-section")).toHaveCount(0);

  const getResponse = await page.request.get(monitorConfigUrl(accountToken), {
    maxRedirects: 0,
  });
  expect(getResponse.status()).toBe(403);

  // The POST needs a real CSRF token for its 403 to mean anything: the account
  // dispatcher checks check_auth_token *before* the monitor_admin gate and
  // answers 403 too, so a missing or empty token would make this pass for the
  // wrong reason. combust.auth_token is the session's csrf_token, so the
  // account form's copy is valid for any manage POST.
  const authToken = await page
    .locator('#account-form input[name="auth_token"]')
    .inputValue();
  expect(authToken, "account form should carry a CSRF token").toBeTruthy();

  // Same body the real form posts (monitor_config_edit_form.html): `a` travels
  // in the query string only.
  const postResponse = await page.request.post(monitorConfigUrl(accountToken), {
    form: {
      auth_token: authToken,
      monitor_enabled: "1",
      monitor_limit: "3",
      monitors_per_server_limit: "3",
    },
    maxRedirects: 0,
  });
  expect(postResponse.status()).toBe(403);
});
