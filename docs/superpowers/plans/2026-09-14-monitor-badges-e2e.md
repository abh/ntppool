# Monitor badges E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Playwright harness to `api e2e fixture create|cleanup`, then cover `MANUAL_TEST_PLAN.md` §15 (account flag badges) and a new §16 (dual-stack monitor cards) live against devel.

**Architecture:** `e2e/lib/fixtures.ts` replaces the fixture half of `e2e/lib/servers.ts` and adds monitor seeds; shared JSON validators move to `e2e/lib/json.ts`. `e2e/lib/monitors.ts` holds ListMonitors / UpdateAccountMonitorConfig ConnectRPC helpers and the monitor-config form helpers. `e2e/tests/monitor-badges.spec.ts` holds three tests. No Perl or template changes.

**Tech Stack:** TypeScript, Playwright (`@playwright/test`), Node child processes via `runApiCli`, ConnectRPC JSON via `connectRpc`.

**Spec:** `docs/superpowers/specs/2026-09-13-monitor-badge-fixture-design.md`

**Depends on:** `docs/superpowers/plans/2026-09-14-e2e-fixture-monitors-api.md` fully executed, including its Task 5 deploy (devel `api e2e --help` lists `fixture`).

## Global Constraints

- Repo `~/src/ntppool`, branch `postgres`. Commit, never push. Stage explicit paths only (never `git add -A`, `git add .`, `git commit -a`). Before each commit run `git status` and `git diff --staged`; stop if the staged set isn't this task's files. Many untracked files exist in this repo; leave them alone.
- Remove trailing whitespace from edited lines (`git diff --check` clean); files end with a newline.
- Commands run from `~/src/ntppool/e2e`: `npm run typecheck`, `npm run test:unit`, `npx playwright test --list`, `npx playwright test <specs> --project=manage --retries=0`. `e2e/.env` already sets `NTP_API_CLI=kubectl --context dala -n askntp exec -i deploy/api-internal -c main -- /ko-app/api`. Never set env vars inline on test commands.
- Test emails come from `uniqueTestEmail(...)` (example.com).
- Monitor list pages may render a metrics `.alert-warning` when devel Prometheus is unavailable; tests don't assert its absence.
- Don't weaken an assertion to make a test pass. If an assertion about existing markup fails, inspect the page and the template first; report a real product bug rather than hiding it.
- Commit messages: Conventional Commits (`test(e2e): ...`, `docs(e2e): ...`), no "comprehensive"/"business".
- Monitor fixture TLS name: `fixture-<attemptId>.devel.mon.ntppool.dev`; the card header shows `fixture-<attemptId>`.
- Monitor statuses: `"pending" | "testing" | "active" | "paused"`; default `pending`.

### Dev site freshness check (used before every live run)

Perl isn't changed by this plan, but the dev site only runs what it was started with. Run:

```bash
kubectl --context dala -n askntp get pods -o name | grep ntppool
kubectl --context dala -n askntp get <that pod> -o jsonpath='{.status.containerStatuses[?(@.name=="httpd")].state.running.startedAt}'; echo
cd ~/src/ntppool && git log -1 --format=%cI -- lib docs/manage
```

If the last commit touching `lib` or `docs/manage` is newer than the httpd container's `startedAt`, stop and ask the user to restart the dev site (stop and rerun `devspace dev`). If no `ntppool` pod is found in `askntp`, stop and ask where the dev site runs.

---

### Task 1: Generalized fixtures in the harness

**Files:**
- Create: `e2e/lib/json.ts`
- Create: `e2e/lib/fixtures.ts`
- Modify: `e2e/lib/servers.ts`
- Modify: `e2e/tests/server-verification.spec.ts`, `e2e/tests/server-deletion.spec.ts`, `e2e/tests/server-netspeed.spec.ts`, `e2e/tests/server-scores-context.spec.ts`, `e2e/tests/staff-search.spec.ts`, `e2e/tests/staff-server-edit.spec.ts`

**Interfaces:**
- Consumes: `runApiCli(label, args, request, subject)` from `e2e/lib/apicli.ts`; CLI JSON from the API plan (`api e2e fixture create|cleanup`).
- Produces:
  - `e2e/lib/json.ts`: `type JsonRecord`, `record(value, label)`, `stringField(value, label, allowEmpty?)`, `idField(value, label)`, `intField(value, label)`, `boolField(value, label, omittedDefault?)`.
  - `e2e/lib/fixtures.ts`: `test` (Playwright test with a `fixtures` fixture), `expect`, `type ServerSeed`, `type FixtureServer`, `type MonitorStatus`, `MONITOR_FAMILIES`, `type MonitorFamilyName`, `type MonitorFamilySeed`, `type MonitorSeed`, `type FixtureSeed`, `type FixtureMonitorFamily`, `type FixtureMonitor`, `type Fixture`, `type Fixtures { create(seed: FixtureSeed): Promise<Fixture> }`, `monitorFamily(monitor, name): FixtureMonitorFamily`.
  - `e2e/lib/servers.ts` keeps: `type ServerRead`, `type AuditLog`, `serverDeleteUrl(server: FixtureServer, accountToken)`, `getServer(...)`, `getAccountAuditLogs(...)`.

- [ ] **Step 1: Create `e2e/lib/json.ts`**

```ts
// Validators for JSON the harness reads from the API and the `api e2e`
// commands. Each throws with `label` when a field is missing or has the wrong
// type, so a response shape change fails where it is read.

export type JsonRecord = Record<string, unknown>;

export function record(value: unknown, label: string): JsonRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value as JsonRecord;
}

export function stringField(value: unknown, label: string, allowEmpty = false): string {
  if (typeof value !== "string" || (!allowEmpty && value.length === 0)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value;
}

export function idField(value: unknown, label: string): string {
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value;
}

export function intField(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value;
}

export function boolField(value: unknown, label: string, omittedDefault = false): boolean {
  if (value === undefined) return omittedDefault;
  if (typeof value !== "boolean") throw new Error(`${label} is malformed`);
  return value;
}
```

- [ ] **Step 2: Create `e2e/lib/fixtures.ts`**

```ts
import { randomUUID } from "node:crypto";
import { test as base, expect } from "@playwright/test";
import { runApiCli } from "./apicli";
import { boolField, idField, intField, record, stringField } from "./json";

export { expect };

// Isolated fixtures from `api e2e fixture create|cleanup` (api-dev build only).
// One attempt owns a fresh user and private account, 0 to 4 servers and at
// most one monitor, and needs at least one server or monitor. Cleanup removes
// the servers and monitors and leaves the identity behind.

export interface ServerSeed {
  ipVersion: 4 | 6;
  verified?: boolean;
  pendingVerification?: boolean;
  scheduledDeletion?: boolean;
  netspeed?: number;
}

export interface FixtureServer {
  serverId: string;
  ip: string;
  ipVersion: 4 | 6;
  verificationToken: string;
  verified: boolean;
  deletionOn: string;
  netspeed: number;
}

export type MonitorStatus = "pending" | "testing" | "active" | "paused";
const MONITOR_STATUSES: readonly string[] = ["pending", "testing", "active", "paused"];

export const MONITOR_FAMILIES = ["ipv4", "ipv6"] as const;
export type MonitorFamilyName = (typeof MONITOR_FAMILIES)[number];

export interface MonitorFamilySeed {
  /** Defaults to "pending". */
  status?: MonitorStatus;
}

/** One logical monitor: an IPv4 row, an IPv6 row, or both sharing a TLS name. */
export type MonitorSeed = Partial<Record<MonitorFamilyName, MonitorFamilySeed>>;

export interface FixtureSeed {
  servers?: ServerSeed[];
  monitors?: MonitorSeed[];
}

export interface FixtureMonitorFamily {
  monitorId: string;
  idToken: string;
  ip: string;
  status: MonitorStatus;
}

export interface FixtureMonitor {
  tlsName: string;
  ipv4?: FixtureMonitorFamily;
  ipv6?: FixtureMonitorFamily;
}

export interface Fixture {
  attemptId: string;
  accountToken: string;
  accountId: string;
  userId: string;
  email: string;
  sessionToken: string;
  servers: FixtureServer[];
  monitors: FixtureMonitor[];
}

export interface Fixtures {
  create(seed: FixtureSeed): Promise<Fixture>;
}

/** A created family of a fixture monitor; throws when it wasn't requested. */
export function monitorFamily(monitor: FixtureMonitor, name: MonitorFamilyName): FixtureMonitorFamily {
  const family = monitor[name];
  if (!family) throw new Error(`fixture monitor ${monitor.tlsName} has no ${name} row`);
  return family;
}

type NormalizedServer = ServerSeed & { netspeed: number };
type NormalizedMonitor = Partial<Record<MonitorFamilyName, MonitorStatus>>;

function normalizeServers(seeds: ServerSeed[]): NormalizedServer[] {
  if (seeds.length > 4) throw new Error("fixture allows at most 4 servers");
  return seeds.map((seed, index) => {
    if (seed.ipVersion !== 4 && seed.ipVersion !== 6) {
      throw new Error(`server seed ${index} has unsupported ipVersion`);
    }
    if (seed.verified && seed.pendingVerification) {
      throw new Error(`server seed ${index} cannot be verified and pending`);
    }
    const netspeed = seed.netspeed ?? 512;
    if (!Number.isInteger(netspeed) || netspeed < 0) {
      throw new Error(`server seed ${index} has invalid netspeed`);
    }
    return { ...seed, netspeed };
  });
}

function normalizeMonitors(seeds: MonitorSeed[]): NormalizedMonitor[] {
  if (seeds.length > 1) throw new Error("fixture allows at most 1 monitor");
  return seeds.map((seed, index) => {
    const normalized: NormalizedMonitor = {};
    for (const name of MONITOR_FAMILIES) {
      const family = seed[name];
      if (!family) continue;
      const status = family.status ?? "pending";
      if (!MONITOR_STATUSES.includes(status)) {
        throw new Error(`monitor seed ${index} ${name} has unsupported status`);
      }
      normalized[name] = status;
    }
    if (!normalized.ipv4 && !normalized.ipv6) {
      throw new Error(`monitor seed ${index} needs ipv4 and/or ipv6`);
    }
    return normalized;
  });
}

function parseServer(value: unknown, index: number, want: NormalizedServer): FixtureServer {
  const label = `fixture server ${index}`;
  const item = record(value, label);
  const ipVersion = intField(item.ip_version, `${label} ip_version`);
  if (ipVersion !== want.ipVersion) throw new Error(`${label} did not preserve request order`);
  const verified = boolField(item.verified, `${label} verified`);
  if (verified !== (want.verified ?? false)) throw new Error(`${label} verified state mismatched`);
  const verificationToken = stringField(item.verification_token ?? "", `${label} verification_token`, true);
  if (Boolean(verificationToken) !== Boolean(want.pendingVerification)) {
    throw new Error(`${label} verification token state mismatched`);
  }
  const deletionOn = stringField(item.deletion_on ?? "", `${label} deletion_on`, true);
  if (deletionOn !== (want.scheduledDeletion ? "2099-01-01" : "")) {
    throw new Error(`${label} deletion state mismatched`);
  }
  const netspeed = intField(item.netspeed, `${label} netspeed`);
  if (netspeed !== want.netspeed) throw new Error(`${label} netspeed mismatched`);
  return {
    serverId: idField(item.server_id, `${label} server_id`),
    ip: stringField(item.ip, `${label} ip`),
    ipVersion: ipVersion as 4 | 6,
    verificationToken,
    verified,
    deletionOn,
    netspeed,
  };
}

function parseMonitor(value: unknown, index: number, want: NormalizedMonitor): FixtureMonitor {
  const item = record(value, `fixture monitor ${index}`);
  const monitor: FixtureMonitor = { tlsName: stringField(item.tls_name, `fixture monitor ${index} tls_name`) };
  for (const name of MONITOR_FAMILIES) {
    const label = `fixture monitor ${index} ${name}`;
    const expected = want[name];
    if (expected === undefined) {
      if (item[name] !== undefined) throw new Error(`${label} was returned but not requested`);
      continue;
    }
    const family = record(item[name], label);
    if (family.status !== expected) throw new Error(`${label} status mismatched`);
    monitor[name] = {
      monitorId: idField(family.monitor_id, `${label} monitor_id`),
      idToken: stringField(family.id_token, `${label} id_token`),
      ip: stringField(family.ip, `${label} ip`),
      status: expected,
    };
  }
  return monitor;
}

async function createFixture(attemptId: string, seed: FixtureSeed): Promise<Fixture> {
  const servers = normalizeServers(seed.servers ?? []);
  const monitors = normalizeMonitors(seed.monitors ?? []);
  if (servers.length === 0 && monitors.length === 0) {
    throw new Error("fixture needs at least one server or monitor");
  }

  const raw = record(await runApiCli<unknown>(
    "e2e fixture create",
    ["e2e", "fixture", "create"],
    {
      attempt_id: attemptId,
      servers: servers.map((server) => ({
        ip_version: server.ipVersion,
        verified: server.verified ?? false,
        pending_verification: server.pendingVerification ?? false,
        scheduled_deletion: server.scheduledDeletion ?? false,
        netspeed: server.netspeed,
      })),
      monitors: monitors.map((monitor) => Object.fromEntries(
        MONITOR_FAMILIES.filter((name) => monitor[name]).map((name) => [name, { status: monitor[name] }]),
      )),
    },
    attemptId,
  ), "e2e fixture create response");

  if (stringField(raw.attempt_id, "fixture attempt_id") !== attemptId) {
    throw new Error("fixture response attempt_id did not match request");
  }
  if (!Array.isArray(raw.servers) || raw.servers.length !== servers.length) {
    throw new Error("fixture response servers did not preserve request count");
  }
  if (!Array.isArray(raw.monitors) || raw.monitors.length !== monitors.length) {
    throw new Error("fixture response monitors did not preserve request count");
  }
  return {
    attemptId,
    accountToken: stringField(raw.account_token, "fixture account_token"),
    accountId: idField(raw.account_id, "fixture account_id"),
    userId: idField(raw.user_id, "fixture user_id"),
    email: stringField(raw.email, "fixture email"),
    sessionToken: stringField(raw.session_token, "fixture session_token"),
    servers: raw.servers.map((value, index) => parseServer(value, index, servers[index])),
    monitors: raw.monitors.map((value, index) => parseMonitor(value, index, monitors[index])),
  };
}

async function cleanupFixture(attemptId: string): Promise<void> {
  const raw = record(await runApiCli<unknown>(
    "e2e fixture cleanup",
    ["e2e", "fixture", "cleanup"],
    { attempt_id: attemptId },
    attemptId,
  ), "e2e fixture cleanup response");
  if (stringField(raw.attempt_id, "cleanup attempt_id") !== attemptId) {
    throw new Error("cleanup response attempt_id did not match request");
  }
  intField(raw.deleted_servers, "cleanup deleted_servers");
  intField(raw.deleted_monitors, "cleanup deleted_monitors");
}

interface AttemptMetadata {
  attemptId: string;
  accountId?: string;
  serverIds?: string[];
  monitorIds?: string[];
}

export const test = base.extend<{ fixtures: Fixtures }>({
  fixtures: [async ({}, use, testInfo) => {
    const attempts: AttemptMetadata[] = [];
    const fixtures: Fixtures = {
      async create(seed) {
        const attemptId = randomUUID();
        const metadata: AttemptMetadata = { attemptId };
        attempts.push(metadata);
        const fixture = await createFixture(attemptId, seed);
        metadata.accountId = fixture.accountId;
        metadata.serverIds = fixture.servers.map((server) => server.serverId);
        metadata.monitorIds = fixture.monitors.flatMap((monitor) =>
          MONITOR_FAMILIES.flatMap((name) => {
            const family = monitor[name];
            return family ? [family.monitorId] : [];
          }));
        return fixture;
      },
    };

    await use(fixtures);

    const failures: AttemptMetadata[] = [];
    const results = [];
    for (const attempt of [...attempts].reverse()) {
      let cleanupStatus = "succeeded";
      try {
        await cleanupFixture(attempt.attemptId);
      } catch {
        cleanupStatus = "failed";
        failures.push(attempt);
      }
      results.push({
        attemptId: attempt.attemptId,
        accountId: attempt.accountId ?? null,
        serverIds: attempt.serverIds ?? null,
        monitorIds: attempt.monitorIds ?? null,
        cleanupStatus,
      });
    }
    if (results.length) {
      await testInfo.attach("fixture-cleanup-results", {
        body: Buffer.from(JSON.stringify(results)),
        contentType: "application/json",
      });
    }
    if (failures.length) {
      const diagnostics = failures.map((failure) =>
        `attempt=${failure.attemptId} account=${failure.accountId ?? "unknown"} servers=${failure.serverIds?.join(",") ?? "unknown"} monitors=${failure.monitorIds?.join(",") ?? "unknown"}`,
      ).join("\n");
      await testInfo.attach("fixture-cleanup-failures", {
        body: Buffer.from(diagnostics),
        contentType: "text/plain",
      });
      if (testInfo.status === testInfo.expectedStatus) {
        throw new Error(`Fixture cleanup failed: ${diagnostics}`);
      }
    }
  }, { timeout: 60_000 }],
});
```

- [ ] **Step 3: Trim `e2e/lib/servers.ts`**

Delete from `e2e/lib/servers.ts`: the `randomUUID` and `@playwright/test` imports, the `runApiCli` import, `export { expect, RpcError };`, the `ServerSeed`, `FixtureServer`, `ServerFixture` and `ServerFixtures` interfaces, `type JsonRecord` and the five validator functions (`record`, `stringField`, `idField`, `intField`, `boolField`), `createFixture`, `cleanupFixture`, `AttemptMetadata`, and the `export const test = base.extend...` block.

Make the top of the file:

```ts
import { connectRpc } from "./auth";
import type { FixtureServer } from "./fixtures";
import { boolField, idField, intField, record, stringField } from "./json";
```

Keep `ServerRead`, `AuditLog`, `serverDeleteUrl`, `getServer` and `getAccountAuditLogs` unchanged.

- [ ] **Step 4: Point the server specs at `fixtures.ts`**

In each spec below, change the imports as shown, then in the whole file replace the test fixture parameter `serverFixtures` with `fixtures`, every `serverFixtures.create([ ... ])` with `fixtures.create({ servers: [ ... ] })` (including the multi-line call in `server-deletion.spec.ts`), and the type `ServerFixture` with `Fixture`.

- `e2e/tests/server-netspeed.spec.ts`: replace `import { expect, getServer, test, type ServerFixture } from "../lib/servers";` with
  ```ts
  import { expect, test, type Fixture } from "../lib/fixtures";
  import { getServer } from "../lib/servers";
  ```
- `e2e/tests/server-deletion.spec.ts`: replace `import { expect, getAccountAuditLogs, getServer, serverDeleteUrl, test, type ServerFixture } from "../lib/servers";` with
  ```ts
  import { expect, test, type Fixture } from "../lib/fixtures";
  import { getAccountAuditLogs, getServer, serverDeleteUrl } from "../lib/servers";
  ```
- `e2e/tests/server-verification.spec.ts`: replace `import { expect, getAccountAuditLogs, getServer, test } from "../lib/servers";` with
  ```ts
  import { expect, test } from "../lib/fixtures";
  import { getAccountAuditLogs, getServer } from "../lib/servers";
  ```
- `e2e/tests/server-scores-context.spec.ts`: replace `import { installSession, mintSession, uniqueTestEmail } from "../lib/auth";` with `import { installSession, mintSession, uniqueTestEmail, type RpcError } from "../lib/auth";` and `import { expect, getServer, test, type FixtureServer, type RpcError } from "../lib/servers";` with
  ```ts
  import { expect, test, type FixtureServer } from "../lib/fixtures";
  import { getServer } from "../lib/servers";
  ```
- `e2e/tests/staff-search.spec.ts`: replace `import { test, expect } from "../lib/servers";` with `import { test, expect } from "../lib/fixtures";`.
- `e2e/tests/staff-server-edit.spec.ts`: replace the `import { expect, getAccountAuditLogs, getServer, test, type ServerFixture, } from "../lib/servers";` block with
  ```ts
  import { expect, test, type Fixture } from "../lib/fixtures";
  import { getAccountAuditLogs, getServer } from "../lib/servers";
  ```

- [ ] **Step 5: Static checks**

Run: `grep -rn "serverFixtures\|ServerFixture\b\|server-fixture" e2e --include='*.ts' --exclude-dir=node_modules`
Expected: no output.
Run: `npm run typecheck`
Expected: no errors.
Run: `npm run test:unit && npx playwright test --list`
Expected: unit tests pass; the list includes every server spec.

- [ ] **Step 6: Live run**

Do the dev site freshness check. Then:
Run: `npx playwright test tests/server-verification.spec.ts tests/server-deletion.spec.ts tests/server-netspeed.spec.ts tests/server-scores-context.spec.ts tests/staff-search.spec.ts tests/staff-server-edit.spec.ts --project=manage --retries=0`
Expected: all pass, and no test reports `Fixture cleanup failed`. If a test fails for a reason unrelated to fixtures (the failure is in page markup or product behavior, not in `e2e fixture create/cleanup` or response parsing), record the test name, error and trace path in the task report, and continue; fixture-related failures must be fixed in this task.

- [ ] **Step 7: Commit**

```bash
git diff --check
git add e2e/lib/json.ts e2e/lib/fixtures.ts e2e/lib/servers.ts e2e/tests/server-verification.spec.ts e2e/tests/server-deletion.spec.ts e2e/tests/server-netspeed.spec.ts e2e/tests/server-scores-context.spec.ts e2e/tests/staff-search.spec.ts e2e/tests/staff-server-edit.spec.ts
git status && git diff --staged --stat
git commit -m "test(e2e): create fixtures through api e2e fixture"
```

---

### Task 2: Monitor helpers

**Files:**
- Create: `e2e/lib/monitors.ts`
- Modify: `e2e/tests/monitor-config.spec.ts`

**Interfaces:**
- Consumes: `connectRpc` (`e2e/lib/auth.ts`), validators (`e2e/lib/json.ts`).
- Produces: `MONITOR_LIST_PATH`, `ADMIN_MONITOR_LIST_PATH`, `MONITOR_CONFIG_PATH`, `monitorListUrl(accountToken): string`, `monitorConfigUrl(accountToken): string`, `type MonitorAccountFlags`, `type ListedMonitor { tlsName: string; accountToken: string; flags?: MonitorAccountFlags }`, `listMonitors(sessionToken, accountToken): Promise<ListedMonitor[]>`, `type MonitorConfigUpdate`, `updateAccountMonitorConfig(sessionToken, accountToken, update): Promise<void>`, `swapMonitorConfig(page, buttonName, method)`, `openMonitorConfigEditor(page)`, `saveMonitorConfig(page)`.

- [ ] **Step 1: Create `e2e/lib/monitors.ts`**

```ts
import { expect, type Page } from "@playwright/test";
import { connectRpc } from "./auth";
import { boolField, record, stringField } from "./json";

// Monitor list and account monitor-config helpers.
//
// Routes: lib/NTPPool/Control/Manage/Monitor.pm render_monitors
// (/manage/monitors?a=<token>) and render_admin_list (/manage/monitors/admin),
// both rendering tpl/monitors/list.html; lib/NTPPool/Control/Manage/Account.pm
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
 * Click a button that swaps #monitor-config-display and assert the fragment
 * request itself returned 200, so a failed swap is reported as the request
 * that failed rather than as a later missing-element timeout.
 */
export async function swapMonitorConfig(page: Page, buttonName: string, method: "GET" | "POST") {
  const responsePromise = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === MONITOR_CONFIG_PATH &&
      response.request().method() === method,
  );
  await page.getByRole("button", { name: buttonName }).click();
  expect((await responsePromise).status()).toBe(200);
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
```

- [ ] **Step 2: Use the helpers in `e2e/tests/monitor-config.spec.ts`**

- Add `import { monitorConfigUrl, openMonitorConfigEditor, saveMonitorConfig } from "../lib/monitors";` after the `../lib/helpers` import.
- Delete the local `const MONITOR_CONFIG_PATH = ...`, `function monitorConfigUrl`, `async function swapMonitorConfig` (with its doc comment) and `async function openMonitorConfigEditor` (with its doc comment).
- Replace `savePerServerLimit` with:

```ts
/** Pick a per-server limit in the open edit form and save it. */
async function savePerServerLimit(page: Page, value: string) {
  await perServerSelect(page).selectOption(value);
  await saveMonitorConfig(page);
}
```

- [ ] **Step 3: Checks and live run**

Run: `npm run typecheck`
Expected: no errors.
Do the dev site freshness check, then run: `npx playwright test tests/monitor-config.spec.ts --project=manage --retries=0`
Expected: 2 passed.

- [ ] **Step 4: Commit**

```bash
git diff --check
git add e2e/lib/monitors.ts e2e/tests/monitor-config.spec.ts
git status && git diff --staged --stat
git commit -m "test(e2e): share monitor list and monitor-config helpers"
```

---

### Task 3: Account flag badge tests (§15)

**Files:**
- Create: `e2e/tests/monitor-badges.spec.ts`

**Interfaces:**
- Consumes: Task 1 `test`, `expect`, `Fixture`; Task 2 helpers; `accountFormUrl` (`e2e/lib/accounts.ts`); `installSession`, `loginAs` (returns `{ email, sessionToken }`), `mintSession(email, opts): Promise<string>`, `uniqueTestEmail` (`e2e/lib/auth.ts`); `bust`, `expectCleanPage` (`e2e/lib/helpers.ts`).
- Produces: test names used in `MANUAL_TEST_PLAN.md`:
  - `monitor admin sees account flag badges in both monitor lists`
  - `non-monitor-admin sees no badges, gets no flags, and can't open the admin list`

- [ ] **Step 1: Write the spec**

```ts
import type { Locator, Page } from "@playwright/test";
import { accountFormUrl } from "../lib/accounts";
import { installSession, loginAs, mintSession, uniqueTestEmail } from "../lib/auth";
import { expect, test, type Fixture } from "../lib/fixtures";
import { bust, expectCleanPage } from "../lib/helpers";
import {
  ADMIN_MONITOR_LIST_PATH,
  listMonitors,
  monitorListUrl,
  openMonitorConfigEditor,
  saveMonitorConfig,
  updateAccountMonitorConfig,
} from "../lib/monitors";

// Account flag badges in the monitor lists. MANUAL_TEST_PLAN.md §15.
//
// tpl/monitors/list.html renders one <h2> per account group inside
// <div class="block">, with tpl/monitors/account_flags_badge.html in it. The
// badge template renders nothing unless the viewer is a monitor admin and the
// API sent mon.account.flags, and no <small> at all when no flag is set. The
// per-account list (/manage/monitors?a=) has one group; the admin list
// (/manage/monitors/admin) has one per account, whose heading links to
// /manage/monitors?a=<token>.
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

type ListView = "account" | "admin";
const VIEWS: ListView[] = ["account", "admin"];

/** Load one monitor list and return the fixture account's group heading. */
async function openAccountHeading(page: Page, view: ListView, fixture: Fixture): Promise<Locator> {
  const path = view === "account" ? monitorListUrl(fixture.accountToken) : ADMIN_MONITOR_LIST_PATH;
  await expectCleanPage(page, bust(path));
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
    await expect(customLimit).toHaveAttribute("title", `Custom monitor limit: ${state.customLimit}`);
  } else {
    await expect(customLimit, `no Custom Limit in the ${view} list`).toHaveCount(0);
  }
  if (state.perServer !== undefined) {
    await expect(perServer, `Per-Server in the ${view} list`).toHaveText(/Per-Server/);
    await expect(perServer).toHaveAttribute("title", `Custom monitors per server limit: ${state.perServer}`);
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

  // The form sets the checkbox and the -1 limit, which §14's spec doesn't cover.
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
```

- [ ] **Step 2: Typecheck and list**

Run: `npm run typecheck && npx playwright test tests/monitor-badges.spec.ts --list`
Expected: no type errors; 2 tests listed.

- [ ] **Step 3: Live run**

Do the dev site freshness check, then run: `npx playwright test tests/monitor-badges.spec.ts --project=manage --retries=0`
Expected: 2 passed; each test's `fixture-cleanup-results` attachment shows `"cleanupStatus":"succeeded"`.

If a badge assertion fails, open the trace (`npx playwright show-trace <path>`) and compare the heading's HTML with `docs/manage/tpl/monitors/account_flags_badge.html` and `list.html` before changing anything.

- [ ] **Step 4: Commit**

```bash
git diff --check
git add e2e/tests/monitor-badges.spec.ts
git status && git diff --staged --stat
git commit -m "test(e2e): cover account flag badges in the monitor lists"
```

---

### Task 4: Dual-stack monitor card test (§16)

**Files:**
- Modify: `e2e/tests/monitor-badges.spec.ts`

**Interfaces:**
- Consumes: Task 1 `monitorFamily`; Task 3 file.
- Produces: test name `dual-stack monitor cards show per-family or combined status`.

- [ ] **Step 1: Add the test**

Change the fixtures import to `import { expect, monitorFamily, test, type Fixture } from "../lib/fixtures";`.

Append to the header comment:

```ts
//
// Dual-stack cards (MANUAL_TEST_PLAN.md §16), tpl/monitors/info_card.html and
// info_details.html: an IPv4 and an IPv6 row sharing a TLS name make one card
// whose header shows the TLS name minus the monitor domain. Each address gets a
// list item with an <h5 class="card-subtitle"> holding its IP. With equal
// statuses (combined_status) one "Status <status>" pill renders in an extra
// list item and none in the address items; otherwise each address item has its
// own. The "Connection" pill isn't asserted: for a monitor that never connected
// it renders with empty text (see the spec's Out of scope).
```

Append at the end of the file:

```ts
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
});
```

- [ ] **Step 2: Typecheck and live run**

Run: `npm run typecheck`
Expected: no errors.
Do the dev site freshness check, then run: `npx playwright test tests/monitor-badges.spec.ts --project=manage --retries=0`
Expected: 3 passed; cleanup attachments succeeded.

- [ ] **Step 3: Commit**

```bash
git diff --check
git add e2e/tests/monitor-badges.spec.ts
git status && git diff --staged --stat
git commit -m "test(e2e): cover dual-stack monitor card statuses"
```

---

### Task 5: Docs and acceptance

**Files:**
- Modify: `MANUAL_TEST_PLAN.md` (§15, new §16)
- Modify: `e2e/README.md`
- Modify: `docs/superpowers/handoffs/2026-09-13-monitor-badge-fixture-design.md`

- [ ] **Step 1: `MANUAL_TEST_PLAN.md` §15**

Replace the paragraph starting `> Browser coverage still needs a bounded monitor fixture:` with:

```markdown
> Browser coverage creates a fresh account with one paused monitor through
> `api e2e fixture create`; a separately minted monitor admin views it. A
> pending monitor alone isn't enough: `/manage/monitors` sends an account
> without a testing, active or paused monitor to the setup instructions. Do not
> mutate a long-lived devel monitor/account to manufacture these states.
```

Replace the seven §15 rows with:

```markdown
- [x] As a **monitor admin** on `/manage/monitors` (all-accounts view), an account with `monitor_enabled` shows the green **Bypass** badge. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] An account with `monitor_limit = -1` shows the red **Disabled** badge (and *not* "Custom Limit"). (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] An account with a custom `monitor_limit` shows the blue **Custom Limit** badge, tooltip naming the number. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] An account with a custom per-server limit shows the yellow **Per-Server** badge, tooltip naming the number. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] An account on **all defaults** shows **no badges at all** — and no stray empty gap beside the account name. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] Badges appear in **both** the per-account list and the admin all-accounts view. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] As a **non-monitor-admin**, no badges render, and the `list_monitors` JSON response contains no `flags` key for the account. (`e2e/tests/monitor-badges.spec.ts` → "non-monitor-admin sees no badges, gets no flags, and can't open the admin list")
```

- [ ] **Step 2: `MANUAL_TEST_PLAN.md` §16**

Run: `grep -n "^## " MANUAL_TEST_PLAN.md | tail -3`
Expected: §15 is the last `## ` section. If a later section exists, insert §16 right after §15 and renumber nothing else; report it.

Add after §15's last row (one blank line between):

```markdown
## 16. Dual-stack monitor cards

> A monitor with an IPv4 and an IPv6 row sharing one TLS name renders as one
> card. When both rows have the same status the card shows it once; otherwise
> each address shows its own status. Browser coverage uses a dual-stack
> monitor from `api e2e fixture create`.

- [x] A dual-stack monitor whose addresses have **different statuses** shows each address with its own status. (`e2e/tests/monitor-badges.spec.ts` → "dual-stack monitor cards show per-family or combined status")
- [x] A dual-stack monitor whose addresses share a status shows **one combined status**. (`e2e/tests/monitor-badges.spec.ts` → "dual-stack monitor cards show per-family or combined status")
```

- [ ] **Step 3: `e2e/README.md`**

- In the `NTP_API_CLI` bullet, change "for test\n  sessions and server fixtures." to "for test\n  sessions and fixtures." (keep the line wrapping style).
- In "## Reaching the API CLI", change "Test sessions and server fixtures come from" to "Test sessions and fixtures come from".
- Replace everything from `## Server fixture deployment` up to (not including) `## Run` with:

````markdown
## Fixture deployment

The verification, deletion, netspeed, scores-context, staff-search,
staff-server-edit and monitor-badges specs use `api e2e fixture create` and
`api e2e fixture cleanup`. A command failure is a setup failure; the tests
don't skip.

Deploy in this order:

1. Deploy an api-dev image with the `api e2e fixture` commands and run its
   Goose migrations with `deployment_mode=devel`. In devel, migration 029
   replaces the migration-027 `server_test_fixtures` tables with
   `e2e_fixtures`, `e2e_fixture_servers` and `e2e_fixture_monitors`, and
   refuses to run while an old attempt is uncleaned. Test and prod record
   027 and 029 as no-ops.
2. Confirm the devel database reports migration version 29 or later and
   contains the three `e2e_fixture*` tables.
3. Deploy the matching web revision with the environment response header and
   the E2E suite.
4. Confirm `api e2e --help` through `NTP_API_CLI` lists `fixture`, then run
   the focused suite twice with `--retries=0`. Each run must use fresh
   attempt IDs and report cleanup.

Each create call owns a fresh ordinary user, a private account, zero to four
servers and at most one monitor, and needs at least one server or monitor.
Fresh accounts can add servers; `can_add_servers` turns false after two active
unverified servers (scheduled servers don't count as active for that check).
Servers use `198.51.100.0/24`, `203.0.113.0/24` and `2001:db8::/32`; monitors
use `192.0.2.0/24` and `2001:db8::/32`. Allocation locks and uniqueness checks
cover active attempts. Server fixtures seed no zones, score rows, log-score
rows or monitor-review rows, and both publication flags are off.

A fixture monitor is an IPv4 row, an IPv6 row, or both sharing the TLS name
`fixture-<attempt>.devel.mon.ntppool.dev`. Each row starts as `pending` (the
default), `testing`, `active` or `paused`, with no API key, so it can't connect
and gets no score rows. Non-pending fixture monitors count toward the devel
account and global monitor limits while they exist. Two things give a
fixture monitor score rows, and cleanup then refuses: the monitor admin
status control (moving it to testing or active), and any server added or
restored on devel while the fixture monitor is `testing` or `active`. The
suite only creates `pending` and `paused` fixture monitors; don't use the
status control on them. If cleanup refuses because of a candidate row that
was never scored, remove those rows for the attempt's monitors and clean up
again (read the monitor IDs from the `fixture-cleanup-failures` attachment):

```sql
DELETE FROM server_scores
 WHERE monitor_id IN (<monitor ids>) AND status = 'candidate' AND score_ts IS NULL;
```

That initial state keeps fixtures out of the normal monitor and selector
queues, but it isn't a permanent no-probe barrier. A concurrent devel monitor
admin status update to active/testing can insert score rows for all undeleted
servers of the same address family, including these reserved addresses. Use a
quiesced devel monitor environment or verified egress policy when a strict
no-probe guarantee is required.

Cleanup uses the attempt ID recorded before create. It deletes only the
fixture's recorded server and monitor IDs and the servers' related rows,
clears any scheduled deletion with the server rows, and leaves the generated
user/account plus the fixture tombstone as inert identities. It refuses, and
leaves the attempt uncleaned, when a recorded server or monitor has moved to
another account or a fixture monitor has score, log-score or API-key rows.
Cleanup is idempotent. Cleaning an unknown attempt creates a tombstone, so a
delayed create with that ID can't add data. If a test loses the create
response or teardown fails, run this from `e2e/`. Replace the example UUID
with the attempt printed in the failure. The script loads `.env`, sends only
`attempt_id`, and calls the harness's own `runApiCli`, so `NTP_API_CLI` is
split the same way as in tests (zsh doesn't word-split `$NTP_API_CLI` in a
shell command).

```sh
node --input-type=module - 00000000-0000-4000-8000-000000000000 <<'NODE'
import "dotenv/config";
import { runApiCli } from "./lib/apicli.ts";

const attemptId = process.argv[2];
if (!attemptId) throw new Error("missing attempt ID");
const result = await runApiCli(
  "e2e fixture cleanup",
  ["e2e", "fixture", "cleanup"],
  { attempt_id: attemptId },
  attemptId,
  process.cwd(),
);
if (result.attempt_id !== attemptId) throw new Error("cleanup returned a different attempt ID");
console.log(`cleaned ${attemptId}; deleted_servers=${result.deleted_servers} deleted_monitors=${result.deleted_monitors}`);
NODE
```

````

- In the acceptance command block under "## Run": append ` tests/staff-search.spec.ts tests/staff-server-edit.spec.ts` before ` --project=manage` on both `npx playwright test tests/...server-...` lines, and add this line after the `tests/monitor-config.spec.ts` line:

```sh
npx playwright test tests/monitor-badges.spec.ts --project=manage --retries=0
```

- [ ] **Step 4: Handoff status**

In `docs/superpowers/handoffs/2026-09-13-monitor-badge-fixture-design.md`, replace the `**Status:**` paragraph (lines starting `**Status:** Scoping only` through `not an implementation plan.`) with:

```markdown
**Status:** Resolved. The design is
`docs/superpowers/specs/2026-09-13-monitor-badge-fixture-design.md`; plans are
`docs/superpowers/plans/2026-09-14-e2e-fixture-monitors-api.md` and
`docs/superpowers/plans/2026-09-14-monitor-badges-e2e.md`.
```

- [ ] **Step 5: Acceptance run**

Run: `npm run test:unit && npm run typecheck && npx playwright test --list`
Expected: pass; list includes `monitor-badges.spec.ts` (3 tests).
Do the dev site freshness check, then run twice (the second run allocates fresh attempts):
`npx playwright test tests/server-verification.spec.ts tests/server-deletion.spec.ts tests/server-netspeed.spec.ts tests/server-scores-context.spec.ts tests/staff-search.spec.ts tests/staff-server-edit.spec.ts tests/monitor-config.spec.ts tests/monitor-badges.spec.ts --project=manage --retries=0`
Expected: the fixture and monitor specs pass both times; any failure already recorded as unrelated in Task 1 is listed again with its error.

- [ ] **Step 6: Leftover check on devel (read-only)**

```bash
kubectl --context dala -n askntp exec -i pg-1 -c postgres -- psql -d askntp -v ON_ERROR_STOP=1 <<'SQL'
BEGIN READ ONLY;
SELECT count(*) AS uncleaned FROM e2e_fixtures WHERE cleaned_on IS NULL;
SELECT count(*) AS fixture_monitors FROM monitors WHERE tls_name LIKE 'fixture-%';
SELECT count(*) AS fixture_range_servers FROM servers
 WHERE ip::inet <<= '198.51.100.0/24' OR ip::inet <<= '203.0.113.0/24' OR ip::inet <<= '2001:db8::/32';
ROLLBACK;
SQL
```

Expected: all three counts 0.

- [ ] **Step 7: Commit**

```bash
git diff --check
git add MANUAL_TEST_PLAN.md e2e/README.md docs/superpowers/handoffs/2026-09-13-monitor-badge-fixture-design.md docs/superpowers/specs/2026-09-13-monitor-badge-fixture-design.md docs/superpowers/plans/2026-09-14-e2e-fixture-monitors-api.md docs/superpowers/plans/2026-09-14-monitor-badges-e2e.md
git status && git diff --staged --stat
git commit -m "docs(e2e): record monitor badge coverage and the e2e fixture command"
```

(The handoff, spec and plans are untracked until this commit; `git add` with their explicit paths is intended.)
