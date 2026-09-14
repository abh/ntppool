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
