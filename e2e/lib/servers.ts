import { connectRpc } from "./auth";
import type { FixtureServer } from "./fixtures";
import { boolField, idField, intField, record, stringField } from "./json";

export interface ServerRead {
  id: string;
  ip: string;
  hostname: string;
  netspeed: number;
  deletionOn: string;
  verification: { verified: boolean };
  /** Zone names, excluding the root '.' zone. */
  zones: string[];
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
  const zones = server.zones ?? [];
  if (!Array.isArray(zones)) throw new Error("GetServer server.zones is malformed");
  const result: ServerRead = {
    id: idField(server.id, "GetServer server.id"),
    ip: stringField(server.ip, "GetServer server.ip"),
    hostname: stringField(server.hostname ?? "", "GetServer server.hostname", true),
    netspeed: intField(server.netspeed, "GetServer server.netspeed"),
    deletionOn: stringField(server.deletion_on ?? "", "GetServer server.deletion_on", true),
    verification: { verified: boolField(verification.verified, "GetServer verification.verified") },
    zones: zones.map((zone, index) => stringField(record(zone, `GetServer zone ${index}`).name, `GetServer zone ${index} name`)),
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
