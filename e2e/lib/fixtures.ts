import { randomUUID } from "node:crypto";
import { test as base, expect } from "@playwright/test";
import { runApiCli } from "./apicli";
import { runId } from "./run";
import { boolField, idField, intField, record, stringField } from "./json";

export { expect };

// Isolated fixtures from `api e2e fixture create|cleanup` (api-dev build only).
// One attempt owns a fresh user (named with the run's tag, so global teardown
// flags it for deletion) and private account, 0 to 4 servers, at most one
// monitor and at most one subscription, and needs at least one of them. Cleanup
// removes the servers, monitors and subscription and leaves the identity
// behind.

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

export const MONITOR_STATUSES = ["pending", "testing", "active", "paused"] as const;
export type MonitorStatus = (typeof MONITOR_STATUSES)[number];

export const MONITOR_FAMILIES = ["ipv4", "ipv6"] as const;
export type MonitorFamilyName = (typeof MONITOR_FAMILIES)[number];

export interface MonitorFamilySeed {
  /** Defaults to "pending". */
  status?: MonitorStatus;
}

/** One logical monitor: an IPv4 row, an IPv6 row, or both sharing a TLS name. */
export type MonitorSeed = Partial<Record<MonitorFamilyName, MonitorFamilySeed>>;

/**
 * One live subscription on the fixture account (status active). quantity and
 * tiered are what the item bought: set both for a synced row, or neither for
 * a row not synced since they were added.
 */
export interface SubscriptionSeed {
  maxZones: number;
  maxDevices: number;
  quantity?: number;
  tiered?: boolean;
}

export interface FixtureSeed {
  servers?: ServerSeed[];
  monitors?: MonitorSeed[];
  subscription?: SubscriptionSeed;
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

export interface FixtureSubscription {
  subscriptionId: string;
  /** e2e_<attemptId>, which is how cleanup finds the row. */
  stripeSubscriptionId: string;
  status: "active";
  maxZones: number;
  maxDevices: number;
  /** null when the seed left it unset. */
  quantity: number | null;
  /** null when the seed left it unset. */
  tiered: boolean | null;
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
  /** null when the seed had no subscription. */
  subscription: FixtureSubscription | null;
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
      if (!(MONITOR_STATUSES as readonly string[]).includes(status)) {
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

function normalizeSubscription(seed: SubscriptionSeed | undefined): SubscriptionSeed | undefined {
  if (seed === undefined) return undefined;
  for (const [name, value] of [["maxZones", seed.maxZones], ["maxDevices", seed.maxDevices]] as const) {
    if (!Number.isInteger(value) || value < 1) {
      throw new Error(`subscription seed ${name} must be an integer of at least 1`);
    }
  }
  if ((seed.quantity === undefined) !== (seed.tiered === undefined)) {
    throw new Error("subscription seed quantity and tiered go together");
  }
  if (seed.quantity !== undefined && (!Number.isInteger(seed.quantity) || seed.quantity < 1)) {
    throw new Error("subscription seed quantity must be an integer of at least 1");
  }
  return { maxZones: seed.maxZones, maxDevices: seed.maxDevices, quantity: seed.quantity, tiered: seed.tiered };
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

function parseSubscription(value: unknown, attemptId: string, want: SubscriptionSeed | undefined): FixtureSubscription | null {
  const label = "fixture subscription";
  if (!want) {
    if (value !== undefined && value !== null) throw new Error(`${label} was returned but not requested`);
    return null;
  }
  const item = record(value, label);
  if (item.status !== "active") throw new Error(`${label} status is not active`);
  const stripeSubscriptionId = stringField(item.stripe_subscription_id, `${label} stripe_subscription_id`);
  if (stripeSubscriptionId !== `e2e_${attemptId}`) {
    throw new Error(`${label} stripe_subscription_id did not match the attempt`);
  }
  const maxZones = intField(item.max_zones, `${label} max_zones`);
  const maxDevices = intField(item.max_devices, `${label} max_devices`);
  if (maxZones !== want.maxZones || maxDevices !== want.maxDevices) {
    throw new Error(`${label} limits mismatched`);
  }
  // An api-dev image from before the tiered seed omits both; treat that as null.
  const quantity = item.quantity == null ? null : intField(item.quantity, `${label} quantity`);
  const tiered = item.tiered == null ? null : boolField(item.tiered, `${label} tiered`);
  if (quantity !== (want.quantity ?? null) || tiered !== (want.tiered ?? null)) {
    throw new Error(`${label} quantity or tiered mismatched`);
  }
  return {
    subscriptionId: idField(item.subscription_id, `${label} subscription_id`),
    stripeSubscriptionId,
    status: "active",
    maxZones,
    maxDevices,
    quantity,
    tiered,
  };
}

async function createFixture(attemptId: string, seed: FixtureSeed): Promise<Fixture> {
  const servers = normalizeServers(seed.servers ?? []);
  const monitors = normalizeMonitors(seed.monitors ?? []);
  const subscription = normalizeSubscription(seed.subscription);
  if (servers.length === 0 && monitors.length === 0 && !subscription) {
    throw new Error("fixture needs at least one server, monitor or subscription");
  }

  const request: Record<string, unknown> = {
    attempt_id: attemptId,
    run_id: runId(),
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
  };
  // Only a seed with a subscription sends the key, and only a tiered seed
  // sends quantity and tiered. The CLI rejects unknown fields, so specs
  // without them keep working against an older api-dev image.
  if (subscription) {
    const seeded: Record<string, unknown> = {
      max_zones: subscription.maxZones,
      max_devices: subscription.maxDevices,
    };
    if (subscription.quantity !== undefined) {
      seeded.quantity = subscription.quantity;
      seeded.tiered = subscription.tiered;
    }
    request.subscription = seeded;
  }

  const raw = record(await runApiCli<unknown>(
    "e2e fixture create",
    ["e2e", "fixture", "create"],
    request,
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
    subscription: parseSubscription(raw.subscription, attemptId, subscription),
  };
}

/**
 * What cleanup must report for an attempt's subscription: "none" when the seed
 * had none, "created" when create returned the row, and "unconfirmed" when one
 * was requested but create's response was lost or failed to parse.
 */
type SubscriptionCleanup = "none" | "created" | "unconfirmed";

async function cleanupFixture(attemptId: string, subscription: SubscriptionCleanup): Promise<void> {
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
  const label = "cleanup deleted_subscriptions";
  if (subscription === "none") {
    // Older api-dev images don't send deleted_subscriptions, so it may be absent.
    if (raw.deleted_subscriptions !== undefined && intField(raw.deleted_subscriptions, label) !== 0) {
      throw new Error(`${label} is not 0 for an attempt that seeded no subscription`);
    }
    return;
  }
  const deleted = intField(raw.deleted_subscriptions, label);
  if (subscription === "created" && deleted !== 1) {
    throw new Error(`${label} is ${deleted}; the subscription create returned must be deleted exactly once`);
  }
  if (subscription === "unconfirmed" && deleted !== 0 && deleted !== 1) {
    throw new Error(`${label} is ${deleted}; expected 0 or 1 for a seed whose create response was lost`);
  }
}

interface AttemptMetadata {
  attemptId: string;
  seededSubscription: boolean;
  accountId?: string;
  serverIds?: string[];
  monitorIds?: string[];
  subscriptionId?: string;
  cleanupError?: string;
}

function subscriptionCleanup(attempt: AttemptMetadata): SubscriptionCleanup {
  if (!attempt.seededSubscription) return "none";
  return attempt.subscriptionId === undefined ? "unconfirmed" : "created";
}

export const test = base.extend<{ fixtures: Fixtures }>({
  fixtures: [async ({}, use, testInfo) => {
    const attempts: AttemptMetadata[] = [];
    const fixtures: Fixtures = {
      async create(seed) {
        const attemptId = randomUUID();
        const metadata: AttemptMetadata = { attemptId, seededSubscription: seed.subscription !== undefined };
        attempts.push(metadata);
        const fixture = await createFixture(attemptId, seed);
        metadata.accountId = fixture.accountId;
        metadata.serverIds = fixture.servers.map((server) => server.serverId);
        metadata.monitorIds = fixture.monitors.flatMap((monitor) =>
          MONITOR_FAMILIES.flatMap((name) => {
            const family = monitor[name];
            return family ? [family.monitorId] : [];
          }));
        metadata.subscriptionId = fixture.subscription?.subscriptionId;
        return fixture;
      },
    };

    await use(fixtures);

    const failures: AttemptMetadata[] = [];
    const results = [];
    for (const attempt of [...attempts].reverse()) {
      let cleanupStatus = "succeeded";
      try {
        await cleanupFixture(attempt.attemptId, subscriptionCleanup(attempt));
      } catch (err) {
        cleanupStatus = "failed";
        attempt.cleanupError = err instanceof Error ? err.message : String(err);
        failures.push(attempt);
      }
      results.push({
        attemptId: attempt.attemptId,
        accountId: attempt.accountId ?? null,
        serverIds: attempt.serverIds ?? null,
        monitorIds: attempt.monitorIds ?? null,
        subscriptionId: attempt.subscriptionId ?? null,
        cleanupStatus,
        cleanupError: attempt.cleanupError ?? null,
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
        `attempt=${failure.attemptId} account=${failure.accountId ?? "unknown"} servers=${failure.serverIds?.join(",") ?? "unknown"} monitors=${failure.monitorIds?.join(",") ?? "unknown"} subscription=${failure.seededSubscription ? failure.subscriptionId ?? "unknown" : "none"} error=${failure.cleanupError ?? "unknown"}`,
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
