import { expect, type Page } from "@playwright/test";
import { connectRpc } from "./auth";
import { swapFragment } from "./helpers";
import { boolField, record, stringField } from "./json";

// Monitor list and account monitor-config helpers.
//
// Routes: lib/NTPPool/Control/Manage/Monitor.pm render_monitors
// (/manage/monitors?a=<token>), rendering tpl/monitors/list.html, and
// render_admin_list (/manage/monitors/admin), rendering
// tpl/monitors/admin_list.html, which PROCESSes list.html with
// admin_list = 1; lib/NTPPool/Control/Manage/Account.pm
// render_monitor_config_form / render_monitor_config_update
// (/manage/account/monitor-config?a=<token>), HTMX fragments swapped into
// #monitor-config-display. The monitor-config routes answer 403 unless the
// viewer is a monitor admin.

export const MONITOR_LIST_PATH = "/manage/monitors";
export const ADMIN_MONITOR_LIST_PATH = "/manage/monitors/admin";
export const MONITOR_CONFIG_PATH = "/manage/account/monitor-config";

/** The per-account monitor list for an explicit account context. */
export function monitorListUrl(accountToken: string): string {
  return `${MONITOR_LIST_PATH}?a=${encodeURIComponent(accountToken)}`;
}

export function monitorUrl(accountToken: string, tlsName: string): string {
  return `/manage/monitors/monitor?a=${encodeURIComponent(accountToken)}&name=${encodeURIComponent(tlsName)}`;
}

export function monitorConfigUrl(accountToken: string): string {
  return `${MONITOR_CONFIG_PATH}?a=${encodeURIComponent(accountToken)}`;
}

export interface MonitorAccountFlags {
  monitorEnabled: boolean;
  monitorLimitOverride: boolean;
  monitorsPerServerLimitOverride: boolean;
  registrationDisabled: boolean;
}

export interface ListedMonitor {
  tlsName: string;
  accountToken: string;
  /** Undefined when the response has no `flags` key (non-monitor-admin callers). */
  flags?: MonitorAccountFlags;
}

/**
 * MonitorService.ListMonitors for one account (X-Account). Proto JSON omits
 * false booleans and empty lists, so those read as false / empty; a present
 * `account.flags` object, even `{}`, means the API disclosed the flags.
 */
export async function listMonitors(sessionToken: string, accountToken: string): Promise<ListedMonitor[]> {
  const raw = record(await connectRpc<unknown>(
    "ListMonitors",
    "ntppool.monitor.v1.MonitorService/ListMonitors",
    { Authorization: `Bearer ${sessionToken}`, "X-Account": accountToken },
    {},
    accountToken,
  ), "ListMonitors response");
  const monitors = raw.monitors ?? [];
  if (!Array.isArray(monitors)) throw new Error("ListMonitors monitors is malformed");
  return monitors.map((value, index) => {
    const label = `ListMonitors monitor ${index}`;
    const monitor = record(value, label);
    const account = record(monitor.account, `${label} account`);
    const listed: ListedMonitor = {
      tlsName: stringField(monitor.tls_name, `${label} tls_name`),
      accountToken: stringField(account.id_token, `${label} account.id_token`),
    };
    if (account.flags !== undefined) {
      const flags = record(account.flags, `${label} account.flags`);
      listed.flags = {
        monitorEnabled: boolField(flags.monitor_enabled, `${label} flags.monitor_enabled`),
        monitorLimitOverride: boolField(flags.monitor_limit_override, `${label} flags.monitor_limit_override`),
        monitorsPerServerLimitOverride: boolField(flags.monitors_per_server_limit_override, `${label} flags.monitors_per_server_limit_override`),
        registrationDisabled: boolField(flags.registration_disabled, `${label} flags.registration_disabled`),
      };
    }
    return listed;
  });
}

export interface MonitorConfigUpdate {
  monitorEnabled?: boolean;
  /** 0 clears the override; -1 disables registration. */
  monitorLimit?: number;
  /** 0 clears the override. */
  monitorsPerServerLimit?: number;
}

/** AccountService.UpdateAccountMonitorConfig as a monitor admin; sends only the given fields. */
export async function updateAccountMonitorConfig(
  sessionToken: string,
  accountToken: string,
  update: MonitorConfigUpdate,
): Promise<void> {
  const body: Record<string, unknown> = {};
  if (update.monitorEnabled !== undefined) body.monitor_enabled = update.monitorEnabled;
  if (update.monitorLimit !== undefined) body.monitor_limit = update.monitorLimit;
  if (update.monitorsPerServerLimit !== undefined) body.monitors_per_server_limit = update.monitorsPerServerLimit;
  if (Object.keys(body).length === 0) throw new Error("updateAccountMonitorConfig needs at least one field");
  record(await connectRpc<unknown>(
    "UpdateAccountMonitorConfig",
    "ntppool.account.v1.AccountService/UpdateAccountMonitorConfig",
    { Authorization: `Bearer ${sessionToken}`, "X-Account": accountToken },
    body,
    accountToken,
  ), "UpdateAccountMonitorConfig response");
}

/**
 * Click a button that swaps #monitor-config-display and wait until htmx has
 * wired up the new fragment; see swapFragment.
 */
export async function swapMonitorConfig(
  page: Page,
  buttonName: string,
  method: "GET" | "POST",
) {
  await swapFragment(page, "#monitor-config-display", MONITOR_CONFIG_PATH, method, () =>
    page.getByRole("button", { name: buttonName }).click(),
  );
}

/** Replace the display card with the edit form. */
export async function openMonitorConfigEditor(page: Page) {
  await swapMonitorConfig(page, "Edit Configuration", "GET");
}

/** Save the open edit form and wait for the "Updated" display card. */
export async function saveMonitorConfig(page: Page) {
  await swapMonitorConfig(page, "Save Changes", "POST");
  await expect(page.locator("#monitor-config-display .badge-success")).toHaveText(/Updated/);
}
