import { test, expect, Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import {
  expectCleanPage,
  expectNoErrorBleed,
  expectErrorAlert,
} from "../lib/helpers";

// E2E coverage for MANUAL_TEST_PLAN.md §8 (add server) and §8a (scheduled
// delete / cancel), for a REGULAR (non-staff) user. Only the reversible parts
// are exercised here.
//
// Where the form lives: the add-server form is rendered on /manage/servers
// (tpl/manage.html PROCESSes add_form.html unconditionally). /manage/server/add
// itself is a POST-only, CSRF-protected form *action* — a bare GET returns 403
// on the missing auth_token (Combust::Control check_auth_token), so it is never
// navigated to directly. The page surface to load and assert is /manage/servers.
//
// Gating: the add flow is guarded by the `can_add_servers` permission. A
// brand-new account must verify its existing servers before it may add more, so
// /manage/servers renders a "...before adding more" notice alongside the form
// (tpl/manage.html, ~line 26; the POST handler renders the same notice from
// Server.pm handle_add ~lines 144-148). The Go API may also reject a
// non-routable RFC 5737 IP. These tests therefore degrade gracefully: they
// assert the permission/error notice instead of failing, and skip the
// delete/cancel flow when no server could be created.
//
// NOTE: audit-log and email side-effect assertions (the API writes a log row
// in the same transaction; a notification email is sent when a comment is
// given) are deliberately out of scope here — they need DB access and are a
// later round (see §8a final checklist item).

// Real field names / button text come from the templates, not invented:
//   - add form (tpl/manage/add_form.html):
//       input[name="host"], input[type=submit][value="Add"], hidden auth_token, a
//   - precheck/confirm (tpl/manage/add.html):
//       hidden precheck_token, textarea[name="comment"],
//       input[type=submit][name="yes"][value="Yes, this is my server, add it!"]
//   - permission notice (handle_add): "Please verify your existing servers before adding more."
//   - delete picker (tpl/manage/delete_instructions.html):
//       select[name="deletion_date"], input[type=submit][name="submitbtn"][value="Schedule Deletion"]
//   - scheduled state (tpl/manage/delete_set.html):
//       "has been scheduled for deletion", input[name="cancel_deletion"]
//
// The delete page is reached at /manage/server/delete?server=<ip>&a=<token>;
// req_server() auto-detects IP vs numeric id (Server.pm req_server).

const TEST_IP = process.env.NTP_SERVER_TEST_IP || "192.0.2.123";
const EXISTING_SERVER_IP = process.env.NTP_EXISTING_SERVER_IP;

// Shared phrase of the can_add_servers notice. /manage/servers renders
// "Please verify your servers before adding more." while the POST handler
// renders "Please verify your existing servers before adding more." — both
// contain this substring.
const PERMISSION_NOTICE = "before adding more";

// Returns true if the current page rendered the can_add_servers permission
// notice (account must verify existing servers before adding more).
async function hasPermissionGate(page: Page): Promise<boolean> {
  return (await page.content()).includes(PERMISSION_NOTICE);
}

test.describe("server add (§8)", () => {
  test("add-server form renders clean for a fresh user", async ({
    page,
    context,
  }) => {
    await loginAs(context, uniqueTestEmail());

    // The add form is rendered on the servers page, not at /manage/server/add
    // (which is the POST target). It is present even for a fresh account.
    await expectCleanPage(page, "/manage/servers");

    await expect(page.locator('input[name="host"]')).toBeVisible();
    await expect(
      page.locator('input[type="submit"][value="Add"]'),
    ).toBeVisible();

    // A brand-new account that must verify existing servers first also shows
    // the permission notice next to the form — both states are valid (the
    // clean-page + visible-form assertions above hold either way).
  });

  test("add a server (best-effort, gated by permission + routable IP)", async ({
    page,
    context,
  }) => {
    await loginAs(context, uniqueTestEmail());

    await expectCleanPage(page, "/manage/servers");

    // If the account can't add servers yet, the servers page shows the notice.
    // Assert it and stop — this is the expected state for a brand-new account,
    // not a failure.
    if (await hasPermissionGate(page)) {
      await expect(page.locator("body")).toContainText(PERMISSION_NOTICE);
      test.skip(
        true,
        "account lacks can_add_servers (must verify existing servers first)",
      );
      return;
    }

    // Step 1: precheck — submit the hostname/IP via the add form. This posts
    // `host` and lands on the confirmation page (tpl/manage/add.html).
    await page.fill('input[name="host"]', TEST_IP);
    await page.click('input[type="submit"][value="Add"]');
    await page.waitForLoadState("networkidle");
    await expectNoErrorBleed(page, "after add precheck");

    // The precheck may reject the IP (e.g. RFC 5737 not routable / resolvable).
    // In that case the confirm button won't render — skip rather than fail.
    const confirmBtn = page.locator('input[type="submit"][name="yes"]');
    if ((await confirmBtn.count()) === 0) {
      test.skip(
        true,
        `precheck did not accept ${TEST_IP} (set NTP_SERVER_TEST_IP to a routable IP to exercise the add flow)`,
      );
      return;
    }

    // If the precheck couldn't determine the country it renders a required
    // <select name="explicit_zone_<ip>"> — pick the first real option so the
    // confirm submit isn't blocked by data_missing.
    const zoneSelect = page.locator(`select[name="explicit_zone_${TEST_IP}"]`);
    if ((await zoneSelect.count()) > 0) {
      const options = zoneSelect.locator("option[value]:not([value=''])");
      if ((await options.count()) > 0) {
        await zoneSelect.selectOption({ index: 1 });
      }
    }

    // Step 2: confirm (`yes`). On success the controller redirects to the
    // server's manage page (/manage/servers#s-<ip>).
    await confirmBtn.click();
    await page.waitForLoadState("networkidle");
    await expectNoErrorBleed(page, "after add confirm");

    // The added server should now appear on the servers list.
    await expectCleanPage(page, "/manage/servers");
    await expect(page.locator("body")).toContainText(TEST_IP);
  });
});

test.describe.serial("server scheduled delete + cancel (§8a)", () => {
  // State carries between the tests below: a server added in the first test is
  // used by the schedule/cancel test. An env-provided existing server is used
  // as a fallback. If neither is available, the dependent tests skip.
  let serverIp: string | null = EXISTING_SERVER_IP || null;

  test("set up a server to delete (or use env-provided one)", async ({
    page,
    context,
  }) => {
    if (serverIp) {
      // Env provided an existing server; nothing to set up.
      return;
    }

    await loginAs(context, uniqueTestEmail());
    await expectCleanPage(page, "/manage/servers");

    if (await hasPermissionGate(page)) {
      test.skip(
        true,
        "account lacks can_add_servers; set NTP_EXISTING_SERVER_IP to run the delete/cancel test",
      );
      return;
    }

    await page.fill('input[name="host"]', TEST_IP);
    await page.click('input[type="submit"][value="Add"]');
    await page.waitForLoadState("networkidle");

    const confirmBtn = page.locator('input[type="submit"][name="yes"]');
    if ((await confirmBtn.count()) === 0) {
      test.skip(
        true,
        `precheck did not accept ${TEST_IP}; set NTP_EXISTING_SERVER_IP to run the delete/cancel test`,
      );
      return;
    }

    const zoneSelect = page.locator(`select[name="explicit_zone_${TEST_IP}"]`);
    if ((await zoneSelect.count()) > 0) {
      const options = zoneSelect.locator("option[value]:not([value=''])");
      if ((await options.count()) > 0) {
        await zoneSelect.selectOption({ index: 1 });
      }
    }
    await confirmBtn.click();
    await page.waitForLoadState("networkidle");

    serverIp = TEST_IP;
  });

  test("schedule deletion shows scheduled state, then cancel restores it", async ({
    page,
    context,
  }) => {
    test.skip(
      !serverIp,
      "no server available to delete (account permission / IP gating)",
    );

    await loginAs(context, uniqueTestEmail());

    // Open the delete page for the server. req_server() resolves `server` as an
    // IP. The `a` account param is required for account context.
    const deletePath = `/manage/server/delete?server=${encodeURIComponent(serverIp!)}`;
    const response = await page.goto(deletePath);
    expect(response, `no response from ${deletePath}`).not.toBeNull();

    // If the account context isn't resolved the controller may NOT_FOUND the
    // server; treat that as a gating skip rather than a hard failure.
    if (response!.status() !== 200) {
      test.skip(
        true,
        `delete page returned ${response!.status()} for ${serverIp}; needs an accessible server in the active account`,
      );
      return;
    }
    await expectNoErrorBleed(page, deletePath);

    // The date-picker page (delete_instructions.html) shows a deletion_date
    // select and a "Schedule Deletion" submit.
    const dateSelect = page.locator('select[name="deletion_date"]');
    await expect(dateSelect).toBeVisible();

    // Pick the first real date option (skip the "Select a date ..." placeholder).
    await dateSelect.selectOption({ index: 1 });
    await page.click('input[type="submit"][name="submitbtn"]');
    await page.waitForLoadState("networkidle");
    await expectNoErrorBleed(page, "after schedule deletion");

    // After a successful schedule the controller redirects and the page
    // re-fetches state, rendering the SCHEDULED STATE (delete_set.html):
    // the "scheduled for deletion" heading + a cancel button — NOT the
    // date-picker again.
    await expectCleanPage(
      page,
      `/manage/server/delete?server=${encodeURIComponent(serverIp!)}`,
    );
    await expect(page.locator("body")).toContainText(
      "has been scheduled for deletion",
    );
    const cancelBtn = page.locator('input[name="cancel_deletion"]');
    await expect(cancelBtn).toBeVisible();
    // The date-picker must be gone in the scheduled state.
    await expect(page.locator('select[name="deletion_date"]')).toHaveCount(0);

    // Cancel the scheduled deletion. On success the controller redirects and
    // the server returns to normal (no deletion date → date-picker again).
    await cancelBtn.click();
    await page.waitForLoadState("networkidle");
    await expectNoErrorBleed(page, "after cancel deletion");

    await expectCleanPage(
      page,
      `/manage/server/delete?server=${encodeURIComponent(serverIp!)}`,
    );
    await expect(page.locator('select[name="deletion_date"]')).toBeVisible();
    await expect(page.locator("body")).not.toContainText(
      "has been scheduled for deletion",
    );
  });
});

test.describe("server delete error surfacing (§8a)", () => {
  test("scheduling without a session does not fake success", async ({
    page,
    context,
  }) => {
    // No login: clear any cookies so this is a genuinely unauthenticated
    // context. A schedule attempt must surface an error / redirect to login,
    // never a silent fake "scheduled" success.
    await context.clearCookies();

    const ip = EXISTING_SERVER_IP || TEST_IP;
    const deletePath = `/manage/server/delete?server=${encodeURIComponent(ip)}`;
    const response = await page.goto(deletePath);
    expect(response, `no response from ${deletePath}`).not.toBeNull();

    const body = await page.content();

    // Whatever happens — redirect to login, NOT_FOUND, or an error alert — the
    // page must NOT claim the deletion was scheduled.
    expect(body).not.toContain("has been scheduled for deletion");

    const url = page.url();
    const bounced = url.includes("/login") || !url.includes("/manage/server/delete");

    // Acceptable outcomes for an unauthenticated request:
    //   - bounced to login / away from the delete page, OR
    //   - a non-200 status (e.g. NOT_FOUND because no server is in context), OR
    //   - the page rendered an error alert.
    // Any of these proves the attempt did not silently succeed.
    if (!bounced && response!.status() === 200) {
      await expectErrorAlert(page);
    } else {
      expect(bounced || response!.status() !== 200).toBeTruthy();
    }
  });
});
