import { randomUUID } from "node:crypto";
import { test as base, expect } from "@playwright/test";
import { connectRpc, RpcError } from "./auth";

export { expect, RpcError };

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

export interface ServerFixture {
  attemptId: string;
  accountToken: string;
  accountId: string;
  userId: string;
  email: string;
  sessionToken: string;
  servers: FixtureServer[];
}

export interface ServerFixtures {
  create(seeds: ServerSeed[]): Promise<ServerFixture>;
}

export interface ServerRead {
  id: string;
  ip: string;
  netspeed: number;
  deletionOn: string;
  verification: { verified: boolean };
  account?: {
    idToken: string;
    displayName: string;
    publicUrl: string;
    publicProfile: boolean;
  };
}

export interface AuditLog {
  type: string;
  message: string;
  user?: { userId: string; email: string };
  server?: { serverId: string; ip: string };
  account?: { accountToken: string };
}

type JsonRecord = Record<string, unknown>;

function record(value: unknown, label: string): JsonRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value as JsonRecord;
}

function stringField(value: unknown, label: string, allowEmpty = false): string {
  if (typeof value !== "string" || (!allowEmpty && value.length === 0)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value;
}

function idField(value: unknown, label: string): string {
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value;
}

function intField(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value;
}

function boolField(value: unknown, label: string, omittedDefault = false): boolean {
  if (value === undefined) return omittedDefault;
  if (typeof value !== "boolean") throw new Error(`${label} is malformed`);
  return value;
}

function fixtureKey(): string {
  const key = process.env.NTP_TEST_SESSION_KEY;
  if (!key) throw new Error("NTP_TEST_SESSION_KEY is not set");
  return key;
}

async function createFixture(attemptId: string, seeds: ServerSeed[]): Promise<ServerFixture> {
  if (seeds.length < 1 || seeds.length > 4) {
    throw new Error("server fixture requires 1 to 4 seeds");
  }
  const normalized = seeds.map((seed, index) => {
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

  const raw = record(await connectRpc<unknown>(
    "CreateServerTestFixture",
    "ntppool.auth.v1.AuthService/CreateServerTestFixture",
    { Authorization: `Bearer ${fixtureKey()}` },
    {
      attempt_id: attemptId,
      servers: normalized.map((seed) => ({
        ip_version: seed.ipVersion,
        verified: seed.verified ?? false,
        pending_verification: seed.pendingVerification ?? false,
        scheduled_deletion: seed.scheduledDeletion ?? false,
        netspeed: seed.netspeed,
      })),
    },
    attemptId,
  ), "CreateServerTestFixture response");

  const responseAttempt = stringField(raw.attempt_id, "fixture attempt_id");
  if (responseAttempt !== attemptId) throw new Error("fixture response attempt_id did not match request");
  if (!Array.isArray(raw.servers) || raw.servers.length !== normalized.length) {
    throw new Error("fixture response servers did not preserve request count");
  }
  const servers = raw.servers.map((value, index): FixtureServer => {
    const item = record(value, `fixture server ${index}`);
    const ipVersion = intField(item.ip_version, `fixture server ${index} ip_version`);
    if (ipVersion !== normalized[index].ipVersion) {
      throw new Error(`fixture server ${index} did not preserve request order`);
    }
    const verified = boolField(item.verified, `fixture server ${index} verified`);
    const expectedVerified = normalized[index].verified ?? false;
    if (verified !== expectedVerified) throw new Error(`fixture server ${index} verified state mismatched`);
    const verificationToken = stringField(item.verification_token ?? "", `fixture server ${index} verification_token`, true);
    if (Boolean(verificationToken) !== Boolean(normalized[index].pendingVerification)) {
      throw new Error(`fixture server ${index} verification token state mismatched`);
    }
    const deletionOn = stringField(item.deletion_on ?? "", `fixture server ${index} deletion_on`, true);
    const expectedDeletion = normalized[index].scheduledDeletion ? "2099-01-01" : "";
    if (deletionOn !== expectedDeletion) throw new Error(`fixture server ${index} deletion state mismatched`);
    const netspeed = intField(item.netspeed, `fixture server ${index} netspeed`);
    if (netspeed !== normalized[index].netspeed) throw new Error(`fixture server ${index} netspeed mismatched`);
    return {
      serverId: idField(item.server_id, `fixture server ${index} server_id`),
      ip: stringField(item.ip, `fixture server ${index} ip`),
      ipVersion: ipVersion as 4 | 6,
      verificationToken,
      verified,
      deletionOn,
      netspeed,
    };
  });

  return {
    attemptId: responseAttempt,
    accountToken: stringField(raw.account_token, "fixture account_token"),
    accountId: idField(raw.account_id, "fixture account_id"),
    userId: idField(raw.user_id, "fixture user_id"),
    email: stringField(raw.email, "fixture email"),
    sessionToken: stringField(raw.session_token, "fixture session_token"),
    servers,
  };
}

async function cleanupFixture(attemptId: string): Promise<void> {
  const raw = record(await connectRpc<unknown>(
    "CleanupServerTestFixture",
    "ntppool.auth.v1.AuthService/CleanupServerTestFixture",
    { Authorization: `Bearer ${fixtureKey()}` },
    { attempt_id: attemptId },
    attemptId,
  ), "CleanupServerTestFixture response");
  if (stringField(raw.attempt_id, "cleanup attempt_id") !== attemptId) {
    throw new Error("cleanup response attempt_id did not match request");
  }
  if (raw.deleted_servers !== undefined) intField(raw.deleted_servers, "cleanup deleted_servers");
}

export function serverDeleteUrl(server: FixtureServer, accountToken: string): string {
  return `/manage/server/delete?server=${encodeURIComponent(server.ip)}&a=${encodeURIComponent(accountToken)}`;
}

export async function getServer(
  sessionToken: string | undefined,
  accountToken: string | undefined,
  ip: string,
  requireEditPermission = false,
): Promise<ServerRead> {
  const headers: Record<string, string> = {};
  if (sessionToken) headers.Authorization = `Bearer ${sessionToken}`;
  if (accountToken) headers["X-Account"] = accountToken;
  const raw = record(await connectRpc<unknown>(
    "GetServer",
    "ntppool.server.v1.ServerService/GetServer",
    headers,
    { ip, ...(requireEditPermission ? { require_edit_permission: true } : {}) },
    ip,
  ), "GetServer response");
  const server = record(raw.server, "GetServer server");
  const verification = record(server.verification ?? {}, "GetServer verification");
  const result: ServerRead = {
    id: idField(server.id, "GetServer server.id"),
    ip: stringField(server.ip, "GetServer server.ip"),
    netspeed: intField(server.netspeed, "GetServer server.netspeed"),
    deletionOn: stringField(server.deletion_on ?? "", "GetServer server.deletion_on", true),
    verification: { verified: boolField(verification.verified, "GetServer verification.verified") },
  };
  if (server.account !== undefined) {
    const account = record(server.account, "GetServer account");
    result.account = {
      idToken: stringField(account.id_token, "GetServer account.id_token"),
      displayName: stringField(account.display_name, "GetServer account.display_name"),
      publicUrl: stringField(account.public_url ?? "", "GetServer account.public_url", true),
      publicProfile: boolField(account.public_profile, "GetServer account.public_profile"),
    };
  }
  return result;
}

export async function getAccountAuditLogs(staffSession: string, accountToken: string): Promise<AuditLog[]> {
  const raw = record(await connectRpc<unknown>(
    "GetAccountAuditLogs",
    "ntppool.audit.v1.AuditService/GetAccountAuditLogs",
    { Authorization: `Bearer ${staffSession}`, "X-Account": accountToken },
    { limit: 200, sort_by: "created_on", sort_order: "desc" },
    accountToken,
  ), "GetAccountAuditLogs response");
  if (!Array.isArray(raw.logs)) throw new Error("GetAccountAuditLogs logs is missing or malformed");
  return raw.logs.map((value, index) => {
    const log = record(value, `audit log ${index}`);
    const mapped: AuditLog = {
      type: stringField(log.type, `audit log ${index} type`),
      message: stringField(log.message, `audit log ${index} message`, true),
    };
    if (log.user !== undefined) {
      const user = record(log.user, `audit log ${index} user`);
      mapped.user = { userId: idField(user.user_id, `audit log ${index} user_id`), email: stringField(user.email, `audit log ${index} email`) };
    }
    if (log.server !== undefined) {
      const server = record(log.server, `audit log ${index} server`);
      mapped.server = { serverId: idField(server.server_id, `audit log ${index} server_id`), ip: stringField(server.ip, `audit log ${index} ip`) };
    }
    if (log.account !== undefined) {
      const account = record(log.account, `audit log ${index} account`);
      mapped.account = { accountToken: stringField(account.account_token, `audit log ${index} account_token`) };
    }
    return mapped;
  });
}

interface AttemptMetadata {
  attemptId: string;
  accountId?: string;
  serverIds?: string[];
}

export const test = base.extend<{ serverFixtures: ServerFixtures }>({
  serverFixtures: [async ({}, use, testInfo) => {
    const attempts: AttemptMetadata[] = [];
    const serverFixtures: ServerFixtures = {
      async create(seeds) {
        const attemptId = randomUUID();
        const metadata: AttemptMetadata = { attemptId };
        attempts.push(metadata);
        const fixture = await createFixture(attemptId, seeds);
        metadata.accountId = fixture.accountId;
        metadata.serverIds = fixture.servers.map((server) => server.serverId);
        return fixture;
      },
    };

    await use(serverFixtures);

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
        cleanupStatus,
      });
    }
    if (results.length) {
      await testInfo.attach("server-fixture-cleanup-results", {
        body: Buffer.from(JSON.stringify(results)),
        contentType: "application/json",
      });
    }
    if (failures.length) {
      const diagnostics = failures.map((failure) =>
        `attempt=${failure.attemptId} account=${failure.accountId ?? "unknown"} servers=${failure.serverIds?.join(",") ?? "unknown"}`,
      ).join("\n");
      await testInfo.attach("server-fixture-cleanup-failures", {
        body: Buffer.from(diagnostics),
        contentType: "text/plain",
      });
      if (testInfo.status === testInfo.expectedStatus) {
        throw new Error(`Server fixture cleanup failed: ${diagnostics}`);
      }
    }
  }, { timeout: 60_000 }],
});
