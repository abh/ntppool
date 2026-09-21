import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  expectCleanPage,
  expectNoErrorBleed,
  errorAlerts,
  createAccount,
} from "../lib/helpers";

// Account field updates — account management.
//
// All UI-driven on the account edit form, no DB/email side effects:
//   - GET  /manage/account[?a=<token>]   render_account_form -> tpl/account/form.html
//   - POST /manage/account?a=<token>      render_account_edit (name, organization_*,
//                                          url_slug, public_profile), re-renders the
//                                          same form on success or error.
//
// Real selectors from docs/manage/tpl/account/form.html:
//   - input[name="name"]                (account name, maxlength 60, required)
//   - input[name="organization_name"]   (maxlength 65, nullable)
//   - input[name="organization_url"]    (type=url, maxlength 65, nullable)
//   - input[name="url_slug"]            (3-32 chars, ^[a-z0-9][a-z0-9-]*[a-z0-9]$)
//   - input[name="public_profile"]      (checkbox, value 1)
//   - input[type=submit][value="Update"]
//
// The form posts back to itself and the controller re-renders form.html with the
// updated account, so persistence is asserted by reading the field values back
// after a fresh navigation (not just the immediate post-response).

const ACCOUNT_PATH = "/manage/account";

// Build the edit-form URL for a specific account token. The default account is
// reachable without ?a= (current_account resolves it).
function accountUrl(token?: string): string {
  return token
    ? `${ACCOUNT_PATH}?a=${encodeURIComponent(token)}`
    : ACCOUNT_PATH;
}

function nameInput(page: Page) {
  return page.locator('#account-form input[name="name"]');
}
function orgNameInput(page: Page) {
  return page.locator('#account-form input[name="organization_name"]');
}
function orgUrlInput(page: Page) {
  return page.locator('#account-form input[name="organization_url"]');
}
function slugInput(page: Page) {
  return page.locator('#account-form input[name="url_slug"]');
}
function publicProfileCheckbox(page: Page) {
  return page.locator('#account-form input[name="public_profile"]');
}
function updateButton(page: Page) {
  return page.locator('#account-form input[type="submit"][value="Update"]');
}

// Submit the account edit form and wait for the re-render. The form posts to
// /manage/account and the controller renders form.html in the response (no
// redirect), so we wait for navigation to settle and check for error bleed.
async function submitForm(page: Page) {
  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    updateButton(page).click(),
  ]);
  await expectNoErrorBleed(page, page.url());
}

// A fresh, valid slug per run (lowercase, 3-32 chars, starts/ends alphanumeric).
function uniqueSlug(prefix = "e2e"): string {
  const rand = Math.random().toString(36).replace(/[^a-z0-9]/g, "").slice(0, 6);
  return `${prefix}-${rand}`.slice(0, 32);
}

test("update account name saves and persists", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("acct-update-name"));

  await expectCleanPage(page, accountUrl());
  const newName = `Renamed ${Date.now()}`;
  await nameInput(page).fill(newName);
  await submitForm(page);

  // Re-fetch the form fresh: the new name must be what the API stored.
  await expectCleanPage(page, accountUrl());
  await expect(nameInput(page)).toHaveValue(newName);
});

test("update organization name and website saves and persists", async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("acct-update-org"));

  await expectCleanPage(page, accountUrl());
  const orgName = `Example Org ${Date.now()}`;
  const orgUrl = "https://example.com/";
  await orgNameInput(page).fill(orgName);
  await orgUrlInput(page).fill(orgUrl);
  await submitForm(page);

  await expectCleanPage(page, accountUrl());
  await expect(orgNameInput(page)).toHaveValue(orgName);
  await expect(orgUrlInput(page)).toHaveValue(orgUrl);
});

test("set a valid URL slug saves and persists", async ({ page, context }) => {
  await loginAs(context, uniqueTestEmail("acct-update-slug"));

  await expectCleanPage(page, accountUrl());
  const slug = uniqueSlug();
  await slugInput(page).fill(slug);
  await submitForm(page);

  await expectCleanPage(page, accountUrl());
  await expect(slugInput(page)).toHaveValue(slug);
});

test("uppercase URL slug is normalized to lowercase", async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("acct-update-slug-case"));

  await expectCleanPage(page, accountUrl());
  const slug = uniqueSlug();
  await slugInput(page).fill(slug.toUpperCase());
  await submitForm(page);

  // The API normalizes to lowercase (mutations.go validateURLSlug).
  await expectCleanPage(page, accountUrl());
  await expect(slugInput(page)).toHaveValue(slug);
});

test("invalid URL slug shows an error and is not saved", async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("acct-update-slug-bad"));

  await expectCleanPage(page, accountUrl());
  // Underscore is not allowed by ^[a-z0-9][a-z0-9-]*[a-z0-9]$.
  await slugInput(page).fill("bad_slug");
  await submitForm(page);

  // The API rejects it; the form must surface the error (form.html includes the
  // common error_alert) rather than silently discarding the input.
  await expect(errorAlerts(page).first()).toBeVisible();

  // Nothing was persisted: a fresh load shows no slug stored.
  await expectCleanPage(page, accountUrl());
  await expect(slugInput(page)).toHaveValue("");
});

test("reserved URL slug shows an error and is not saved", async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("acct-update-slug-reserved"));

  await expectCleanPage(page, accountUrl());
  // "admin" is reserved (mutations.go validateURLSlug reserved list).
  await slugInput(page).fill("admin");
  await submitForm(page);

  await expect(errorAlerts(page).first()).toBeVisible();

  await expectCleanPage(page, accountUrl());
  await expect(slugInput(page)).toHaveValue("");
});

test("duplicate URL slug across two accounts shows an error", async ({
  page,
  context,
}) => {
  // One user owning two accounts: set a slug on the first, then try the same
  // slug on the second — the API enforces uniqueness (CodeAlreadyExists).
  await loginAs(context, uniqueTestEmail("acct-update-slug-dup"));

  // Default account: claim a unique slug.
  await expectCleanPage(page, accountUrl());
  const slug = uniqueSlug("dup");
  await slugInput(page).fill(slug);
  await submitForm(page);
  await expectCleanPage(page, accountUrl());
  await expect(slugInput(page)).toHaveValue(slug);

  // Second account: the same slug must be rejected.
  const second = await createAccount(page);
  await expectCleanPage(page, accountUrl(second));
  await slugInput(page).fill(slug);
  await submitForm(page);

  await expect(errorAlerts(page).first()).toBeVisible();

  // The duplicate was not stored on the second account.
  await expectCleanPage(page, accountUrl(second));
  await expect(slugInput(page)).toHaveValue("");
});

test("enable then disable the public profile flag persists", async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("acct-update-public"));

  // A fresh account starts with the public profile off.
  await expectCleanPage(page, accountUrl());
  await expect(publicProfileCheckbox(page)).not.toBeChecked();

  // Enable it.
  await publicProfileCheckbox(page).check();
  await submitForm(page);
  await expectCleanPage(page, accountUrl());
  await expect(publicProfileCheckbox(page)).toBeChecked();

  // Disable it again (the checkbox sends no value when unchecked; the
  // controller maps that to JSON::XS::false).
  await publicProfileCheckbox(page).uncheck();
  await submitForm(page);
  await expectCleanPage(page, accountUrl());
  await expect(publicProfileCheckbox(page)).not.toBeChecked();
});
