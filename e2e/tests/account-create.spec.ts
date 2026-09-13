import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { expectCleanPage, createAccount } from "../lib/helpers";

// Account creation flow (Gitea #12; MANUAL_TEST_PLAN.md §1 automatic account
// creation + §4 account management).
//
// The DB-level checks in the issue (accounts / account_users rows) are asserted
// here through their UI equivalents, since the harness has no DB layer:
//   - "default account created"  -> /manage/account loads an editable account
//   - "user added to account"    -> the user appears on that account's team page
//
// Routes exercised:
//   - GET  /manage/account            render_account_form -> tpl/account/form.html
//   - POST /manage/account (a=new)    _create_account via NP::CAPI::Account
//                                     (the sidebar "New account" form; see
//                                     createAccount in lib/helpers.ts)
//   - GET  /manage/account/team       render_users -> tpl/account/team.html

const ACCOUNT_PATH = "/manage/account";

function nameInput(page: Page) {
  return page.locator('#account-form input[name="name"]');
}
function updateButton(page: Page) {
  return page.locator('#account-form input[type="submit"][value="Update"]');
}

test("a new user lands on an editable default account", async ({
  page,
  context,
}) => {
  // The Go API auto-creates a default account at login when the user has none
  // (and no pending invites), so a fresh user reaches a working account form.
  await loginAs(context, uniqueTestEmail("acct-create-default"));

  await expectCleanPage(page, ACCOUNT_PATH);

  // An editable account is present: the name field and the "Update" submit
  // (account_id != 0) both render, which means the user has edit access.
  await expect(nameInput(page)).toBeVisible();
  await expect(updateButton(page)).toBeVisible();

  // The page references the account by token (acc_…/a= link), confirming a real
  // account was created rather than the new-account placeholder.
  const hasAccountToken = await page
    .locator("a[href]")
    .evaluateAll((els) =>
      els.some((e) =>
        /[?&]a=acc_/i.test((e as HTMLAnchorElement).getAttribute("href") || ""),
      ),
    );
  expect(hasAccountToken, "expected an a=acc_ account link on the page").toBe(
    true,
  );
});

test("the default account is named after the user identity", async ({
  page,
  context,
}) => {
  // Minted test users have no profile name (loginAs sends `api e2e session` an
  // empty name), so the name-from-Auth0-profile branch can't be exercised
  // here. With no name, the auto-created default account is named after the
  // user's email — a deterministic, non-empty default. (A real Auth0 login would
  // instead carry the profile name.)
  const email = uniqueTestEmail("acct-create-named");
  await loginAs(context, email);

  await expectCleanPage(page, ACCOUNT_PATH);
  await expect(nameInput(page)).toHaveValue(email);
});

test('the "New account" button creates an additional account', async ({
  page,
  context,
}) => {
  await loginAs(context, uniqueTestEmail("acct-create-second"));

  // Capture the original (default) account token.
  await expectCleanPage(page, ACCOUNT_PATH);
  const original = await firstAccountToken(page);
  expect(original, "expected a default account token").not.toBeNull();

  // createAccount() submits the sidebar New-account form (a=new) and returns the
  // brand-new account's token, asserting exactly one new token appeared.
  const second = await createAccount(page);
  expect(second).not.toBe(original);

  // The new account is editable. The sidebar form sends no name, and the minted
  // user has no profile name, so _create_account falls back to "My Account"
  // (name ||= $self->user->{name} || 'My Account').
  await expectCleanPage(page, `${ACCOUNT_PATH}?a=${encodeURIComponent(second)}`);
  await expect(nameInput(page)).toHaveValue("My Account");

  // The user keeps access to the original account too.
  await expectCleanPage(
    page,
    `${ACCOUNT_PATH}?a=${encodeURIComponent(original!)}`,
  );
  await expect(updateButton(page)).toBeVisible();
});

test("the creating user is a member of a newly created account", async ({
  page,
  context,
}) => {
  const email = uniqueTestEmail("acct-create-member");
  await loginAs(context, email);

  await expectCleanPage(page, ACCOUNT_PATH);
  const second = await createAccount(page);

  // The team page for the new account lists the creating user as a member,
  // the UI equivalent of an account_users row (team.html renders user.email).
  await expectCleanPage(
    page,
    `/manage/account/team?a=${encodeURIComponent(second)}`,
  );
  await expect(page.locator("table.table")).toContainText(email);
});

// First distinct a=acc_ token referenced on the current page, or null.
async function firstAccountToken(page: Page): Promise<string | null> {
  const hrefs = await page
    .locator("a[href]")
    .evaluateAll((els) =>
      els.map((e) => (e as HTMLAnchorElement).getAttribute("href") || ""),
    );
  for (const h of hrefs) {
    const m = h.match(/[?&]a=(acc_[a-z0-9]+)/i);
    if (m) {
      return m[1];
    }
  }
  return null;
}
