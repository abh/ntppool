import type { Locator, Page } from "@playwright/test";
import { accountFormUrl } from "../lib/accounts";
import { installSession, loginAs, mintSession, uniqueTestEmail } from "../lib/auth";
import { expect, monitorFamily, test, type Fixture } from "../lib/fixtures";
import { bust, expectCleanPage } from "../lib/helpers";
import {
  ADMIN_MONITOR_LIST_PATH,
  listMonitors,
  MONITOR_LIST_PATH,
  monitorListUrl,
  openMonitorConfigEditor,
  saveMonitorConfig,
  updateAccountMonitorConfig,
} from "../lib/monitors";

// Account flag badges in the monitor lists.
//
// tpl/monitors/list.html renders one <h2> per account group inside
// <div class="block">, with tpl/monitors/account_flags_badge.html in it. The
// badge template renders nothing unless the viewer is a monitor admin and the
// API sent mon.account.flags, and no <small> at all when no flag is set. The
// per-account list (/manage/monitors?a=) has one group; the admin list
// (/manage/monitors/admin) has one per account, whose heading links to
// /manage/monitors?a=<token>. The per-account list redirects to
// /manage/monitors/new unless the account has a testing, active or paused
// monitor (Monitor.pm manage_dispatch), so the badge fixtures use a paused
// monitor.
//
// Badges (account_flags_badge.html):
//   .badge-success "Bypass"        monitor_enabled
//   .badge-danger  "Disabled"      registration disabled (monitor_limit -1)
//   .badge-info    "Custom Limit"  other monitor_limit override,
//                                  title "Custom monitor limit: N"
//   .badge-warning "Per-Server"    per-server override,
//                                  title "Custom monitors per server limit: N"
//
// A monitor admin can open another account's pages (IsStaff() includes
// monitor_admin, so ?a= resolves for them). The fixture's own session is an
// ordinary member. The lists can show a metrics warning when devel Prometheus
// is unavailable; these tests don't assert on it.
//
// Dual-stack cards, tpl/monitors/info_card.html and info_details.html: an IPv4
// and an IPv6 row sharing a TLS name make one card whose header shows the TLS
// name minus the monitor domain. Each address gets a list item with an
// <h5 class="card-subtitle"> holding its IP. With equal statuses
// (combined_status) one "Status <status>" pill renders in an extra list item
// and none in the address items; otherwise each address item has its own. The
// "Connection" pill isn't asserted: for a monitor that never connected it
// renders with empty text.

type ListView = "account" | "admin";
const VIEWS: ListView[] = ["account", "admin"];

/** Load one monitor list and return the fixture account's group heading. */
async function openAccountHeading(page: Page, view: ListView, fixture: Fixture): Promise<Locator> {
  const path = view === "account" ? monitorListUrl(fixture.accountToken) : ADMIN_MONITOR_LIST_PATH;
  await expectCleanPage(page, bust(path));
  if (view === "account") {
    expect(
      new URL(page.url()).pathname,
      "the account monitor list redirected (the account needs a testing, active or paused monitor)",
    ).toBe(MONITOR_LIST_PATH);
  }
  const headings = page.locator(".block h2");
  const heading = view === "account"
    ? headings
    : headings.filter({ has: page.locator(`a[href*="a=${fixture.accountToken}"]`) });
  await expect(heading, `the ${view} list should have one heading for the fixture account`).toHaveCount(1);
  return heading;
}

async function expectNoBadges(page: Page, view: ListView, fixture: Fixture) {
  const heading = await openAccountHeading(page, view, fixture);
  await expect(heading.locator(".badge"), `no badges in the ${view} list`).toHaveCount(0);
  // The badge wrapper is a <small class="ml-2">; its absence means no stray gap.
  await expect(heading.locator("small"), `no badge wrapper in the ${view} list`).toHaveCount(0);
}

interface BadgeState {
  bypass: boolean;
  disabled: boolean;
  customLimit?: number;
  perServer?: number;
}

async function expectBadges(page: Page, view: ListView, fixture: Fixture, state: BadgeState) {
  const heading = await openAccountHeading(page, view, fixture);
  const bypass = heading.locator(".badge-success");
  const disabled = heading.locator(".badge-danger");
  const customLimit = heading.locator(".badge-info");
  const perServer = heading.locator(".badge-warning");

  if (state.bypass) {
    await expect(bypass, `Bypass in the ${view} list`).toHaveText(/Bypass/);
  } else {
    await expect(bypass, `no Bypass in the ${view} list`).toHaveCount(0);
  }
  if (state.disabled) {
    await expect(disabled, `Disabled in the ${view} list`).toHaveText(/Disabled/);
  } else {
    await expect(disabled, `no Disabled in the ${view} list`).toHaveCount(0);
  }
  if (state.customLimit !== undefined) {
    await expect(customLimit, `Custom Limit in the ${view} list`).toHaveText(/Custom Limit/);
    await expect(customLimit, `Custom Limit tooltip in the ${view} list`).toHaveAttribute(
      "title",
      `Custom monitor limit: ${state.customLimit}`,
    );
  } else {
    await expect(customLimit, `no Custom Limit in the ${view} list`).toHaveCount(0);
  }
  if (state.perServer !== undefined) {
    await expect(perServer, `Per-Server in the ${view} list`).toHaveText(/Per-Server/);
    await expect(perServer, `Per-Server tooltip in the ${view} list`).toHaveAttribute(
      "title",
      `Custom monitors per server limit: ${state.perServer}`,
    );
  } else {
    await expect(perServer, `no Per-Server in the ${view} list`).toHaveCount(0);
  }
}

test("monitor admin sees account flag badges in both monitor lists", async ({ page, context, fixtures }) => {
  const fixture = await fixtures.create({ monitors: [{ ipv4: { status: "paused" } }] });
  const { sessionToken: adminSession } = await loginAs(context, uniqueTestEmail("monitor-badges-admin"), {
    grantMonitorAdmin: true,
  });

  // Defaults: no badges and no badge wrapper.
  for (const view of VIEWS) await expectNoBadges(page, view, fixture);

  // The form sets the checkbox and the -1 limit, which monitor-config.spec.ts
  // doesn't cover.
  await expectCleanPage(page, bust(accountFormUrl(fixture.accountToken)));
  await expect(page.locator("#monitor-config-section")).toBeVisible();
  await openMonitorConfigEditor(page);
  const form = page.locator("#monitor-config-display");
  await form.locator('input[name="monitor_enabled"]').check();
  await form.locator('select[name="monitor_limit"]').selectOption("-1");
  await form.locator('select[name="monitors_per_server_limit"]').selectOption("3");
  await saveMonitorConfig(page);
  for (const view of VIEWS) {
    await expectBadges(page, view, fixture, { bypass: true, disabled: true, perServer: 3 });
  }

  // A custom limit replaces Disabled with Custom Limit.
  await updateAccountMonitorConfig(adminSession, fixture.accountToken, { monitorLimit: 10 });
  for (const view of VIEWS) {
    await expectBadges(page, view, fixture, { bypass: true, disabled: false, customLimit: 10, perServer: 3 });
  }
});

test("non-monitor-admin sees no badges, gets no flags, and can't open the admin list", async ({
  page,
  context,
  fixtures,
}) => {
  const fixture = await fixtures.create({ monitors: [{ ipv4: { status: "paused" } }] });
  const tlsName = fixture.monitors[0].tlsName;

  // Set flags as a monitor admin, so an admin *would* see badges here.
  const adminSession = await mintSession(uniqueTestEmail("monitor-badges-flagger"), { grantMonitorAdmin: true });
  await updateAccountMonitorConfig(adminSession, fixture.accountToken, {
    monitorEnabled: true,
    monitorsPerServerLimit: 3,
  });

  // Control: the same read as a monitor admin carries the flags.
  const asAdmin = (await listMonitors(adminSession, fixture.accountToken)).filter((m) => m.tlsName === tlsName);
  expect(asAdmin).toHaveLength(1);
  expect(asAdmin[0].flags, "a monitor admin gets the account flags").toBeDefined();
  expect(asAdmin[0].flags?.monitorEnabled).toBe(true);

  await installSession(context, fixture.sessionToken);
  const heading = await openAccountHeading(page, "account", fixture);
  await expect(heading.locator(".badge")).toHaveCount(0);
  await expect(heading.locator("small")).toHaveCount(0);
  await expect(
    page.locator(".card-header", { hasText: `fixture-${fixture.attemptId}` }),
    "the owner still sees the monitor itself",
  ).toBeVisible();

  const asOwner = (await listMonitors(fixture.sessionToken, fixture.accountToken)).filter((m) => m.tlsName === tlsName);
  expect(asOwner).toHaveLength(1);
  expect(asOwner[0].flags, "a non-admin's ListMonitors response has no flags key").toBeUndefined();

  const adminList = await page.request.get(ADMIN_MONITOR_LIST_PATH, { maxRedirects: 0 });
  expect(adminList.status(), "the all-accounts list is monitor-admin only").toBe(403);
});

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Matches an element whose whole text is `value`, ignoring surrounding whitespace. */
function exactText(value: string): RegExp {
  return new RegExp(`^\\s*${escapeRegExp(value)}\\s*$`);
}

/** Load the fixture account's list and return the fixture monitor's card. */
async function openMonitorCard(page: Page, fixture: Fixture): Promise<Locator> {
  await expectCleanPage(page, bust(monitorListUrl(fixture.accountToken)));
  expect(
    new URL(page.url()).pathname,
    "the account monitor list redirected (the account needs a testing, active or paused monitor)",
  ).toBe(MONITOR_LIST_PATH);
  const card = page
    .locator(".card")
    .filter({ has: page.locator(".card-header", { hasText: `fixture-${fixture.attemptId}` }) });
  await expect(card, "one card for the fixture monitor").toHaveCount(1);
  return card;
}

function statusPills(scope: Locator): Locator {
  return scope.locator(".badge").filter({ hasText: /^\s*Status\s/ });
}

/** The card's list item for one address. */
function addressItem(page: Page, card: Locator, ip: string): Locator {
  return card
    .locator(".list-group-item")
    .filter({ has: page.locator(".card-subtitle").filter({ hasText: exactText(ip) }) });
}

test("dual-stack monitor cards show per-family or combined status", async ({ page, context, fixtures }) => {
  // Only pending and paused: an active or testing fixture monitor picks up a
  // candidate score row from any server add on devel, and cleanup then refuses.
  const split = await fixtures.create({ monitors: [{ ipv4: { status: "pending" }, ipv6: { status: "paused" } }] });
  const combined = await fixtures.create({ monitors: [{ ipv4: { status: "paused" }, ipv6: { status: "paused" } }] });

  await installSession(context, split.sessionToken);
  const splitCard = await openMonitorCard(page, split);
  const splitV4 = monitorFamily(split.monitors[0], "ipv4");
  const splitV6 = monitorFamily(split.monitors[0], "ipv6");
  await expect(statusPills(splitCard), "one status pill per address").toHaveCount(2);
  await expect(statusPills(addressItem(page, splitCard, splitV4.ip))).toHaveText(/Status pending/);
  await expect(statusPills(addressItem(page, splitCard, splitV6.ip))).toHaveText(/Status paused/);

  await installSession(context, combined.sessionToken);
  const combinedCard = await openMonitorCard(page, combined);
  const combinedV4 = monitorFamily(combined.monitors[0], "ipv4");
  const combinedV6 = monitorFamily(combined.monitors[0], "ipv6");
  await expect(addressItem(page, combinedCard, combinedV4.ip)).toHaveCount(1);
  await expect(addressItem(page, combinedCard, combinedV6.ip)).toHaveCount(1);
  await expect(statusPills(combinedCard), "one combined status pill").toHaveCount(1);
  await expect(statusPills(combinedCard)).toHaveText(/Status paused/);
  await expect(statusPills(addressItem(page, combinedCard, combinedV4.ip))).toHaveCount(0);
  await expect(statusPills(addressItem(page, combinedCard, combinedV6.ip))).toHaveCount(0);
});
