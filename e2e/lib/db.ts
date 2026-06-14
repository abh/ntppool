import { Pool, PoolClient, QueryResultRow } from "pg";

// Read-only Postgres verification layer for grey-box assertions.
//
// The harness *acts* through the UI / mint-RPC (never fabricating state) and
// *verifies* side effects through this read-only client. Many plan items are
// side effects with no UI surface — "email sent", "audit log written", "invite
// expiry moved", "sessions swept" — and a read-only query turns each into a
// one-line precise assertion. See docs/plans/2026-06-14-e2e-test-automation-design.md
// section C.
//
// This module is READ-ONLY by contract: only SELECTs, all inputs parameterized
// ($1, …), never string-interpolated. Writes / DDL / time-travel stay out; if
// ever needed they go behind a separate, equally loud guard and a distinct
// read/write credential.

let pool: Pool | undefined;

/**
 * Lazily create the singleton read-only connection pool from NTP_TEST_DB_URL.
 * Throws loudly if the URL is unset — the harness should never silently skip DB
 * verification.
 *
 * NTP_TEST_DB_URL must point at a READ-ONLY role (see .env.example);
 * assertDevelDatabase() additionally refuses any non-devel database.
 */
export function getDb(): Pool {
  if (pool) {
    return pool;
  }
  const url = process.env.NTP_TEST_DB_URL;
  if (!url) {
    throw new Error(
      "NTP_TEST_DB_URL is not set — required for the read-only DB verification layer",
    );
  }
  pool = new Pool({ connectionString: url });
  return pool;
}

/**
 * Close the pool. Call from global teardown so the Node process can exit.
 */
export async function closeDb(): Promise<void> {
  if (pool) {
    const p = pool;
    pool = undefined;
    await p.end();
  }
}

// Cache the asserted-devel state so assertDevelDatabase() is safe and cheap to
// call before every query. Reset by closeDb() implicitly (new pool, new module
// state only on reload), so within a run the sentinel runs exactly once.
let develAsserted = false;

/**
 * Abort unless the connection is the devel database.
 *
 * Mirrors the Go RPC's devel guard (server/setup.go checkDeploymentEnv): refuse
 * to even *read* an unexpected database. Two independent checks must both hold:
 *   1. the connected database name is `askntp`, and
 *   2. system_settings key `environment` reads `devel`.
 *
 * The settings column is jsonb (migration 021), so a string scalar arrives
 * JSON-encoded ("devel"); older un-migrated rows store the bare string (devel).
 * We accept either form, matching server/setup.go.
 *
 * Safe to call repeatedly — the result is cached after the first success.
 */
export async function assertDevelDatabase(): Promise<void> {
  if (develAsserted) {
    return;
  }

  const db = getDb();

  const dbNameRes = await db.query<{ current_database: string }>(
    "SELECT current_database() AS current_database",
  );
  const dbName = dbNameRes.rows[0]?.current_database;
  if (dbName !== "askntp") {
    throw new Error(
      `Refusing to use database ${JSON.stringify(
        dbName,
      )}: expected the devel database "askntp". ` +
        "assertDevelDatabase will not read an unexpected database.",
    );
  }

  // value::text yields the raw stored bytes whether the column is jsonb or text.
  const envRes = await db.query<{ value: string | null }>(
    "SELECT value::text AS value FROM system_settings WHERE key = $1",
    ["environment"],
  );
  const raw = envRes.rows[0]?.value;
  if (raw == null) {
    throw new Error(
      'Refusing to use database: system_settings has no "environment" key. ' +
        "Cannot confirm this is the devel database.",
    );
  }
  // Accept both JSON-encoded ("devel") and bare (devel) forms.
  let env = raw;
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed === "string") {
      env = parsed;
    }
  } catch {
    // Not JSON — use the raw value as-is (un-migrated bare string).
  }
  if (env !== "devel") {
    throw new Error(
      `Refusing to use database: system_settings environment is ${JSON.stringify(
        env,
      )}, expected "devel". ` +
        "assertDevelDatabase will not read a non-devel database.",
    );
  }

  develAsserted = true;
}

/**
 * Run a read-only query after confirming the connection is the devel database.
 * Every public helper goes through this so misuse can't read prod.
 */
async function query<T extends QueryResultRow>(
  text: string,
  params: unknown[],
): Promise<T[]> {
  await assertDevelDatabase();
  const db = getDb();
  const res = await db.query<T>(text, params);
  return res.rows;
}

/**
 * The most recent email addressed to `email`, or null if none.
 *
 * Table `emails` (db/migrations/011_create_emails_table.sql): recipients live in
 * `to_addresses TEXT[]`, so we match with `$1 = ANY(to_addresses)`. Emails are
 * written even in devel mode (no SMTP sent), which is the established way to
 * assert "email sent".
 *
 * `sent_at` is null in devel (nothing actually sent); order by `created_on` —
 * the row-creation time — to get the latest.
 */
export interface EmailRow {
  id: string;
  subject: string;
  created_on: Date;
  sent_at: Date | null;
  email_type: string;
}

export async function latestEmailTo(email: string): Promise<EmailRow | null> {
  const rows = await query<EmailRow>(
    `SELECT id, subject, created_on, sent_at, email_type
       FROM emails
      WHERE $1 = ANY(to_addresses)
      ORDER BY created_on DESC, id DESC
      LIMIT 1`,
    [email],
  );
  return rows[0] ?? null;
}

/**
 * Recent audit-log rows, optionally filtered by action and/or subject.
 *
 * Audit log = table `logs` (db/migrations/005_create_remaining_tables.sql):
 *   - `type`    — the action (e.g. "server-delete"); the Go API writes these.
 *   - `message` — human-readable description.
 *   - `changes` — serialized change detail.
 *   - subject columns: `account_id`, `server_id`, `user_id`, `vendor_zone_id`.
 *   - `created_on` — timestamp.
 *
 * Pass any subset of filters; the caller asserts on the returned rows. Returns
 * newest first, limited to `limit` (default 20).
 */
export interface AuditLogRow {
  id: string;
  type: string | null;
  message: string | null;
  changes: string | null;
  account_id: string | null;
  server_id: string | null;
  user_id: string | null;
  vendor_zone_id: string | null;
  created_on: Date;
}

export interface AuditLogQuery {
  /** Match `logs.type` exactly (the action). */
  action?: string;
  /** Match `logs.account_id`. */
  accountId?: number;
  /** Match `logs.server_id`. */
  serverId?: number;
  /** Match `logs.user_id`. */
  userId?: number;
  /** Max rows to return (default 20). */
  limit?: number;
}

export async function auditLogFor(opts: AuditLogQuery): Promise<AuditLogRow[]> {
  // Build a parameterized WHERE; never interpolate values.
  const conditions: string[] = [];
  const params: unknown[] = [];

  if (opts.action !== undefined) {
    params.push(opts.action);
    conditions.push(`type = $${params.length}`);
  }
  if (opts.accountId !== undefined) {
    params.push(opts.accountId);
    conditions.push(`account_id = $${params.length}`);
  }
  if (opts.serverId !== undefined) {
    params.push(opts.serverId);
    conditions.push(`server_id = $${params.length}`);
  }
  if (opts.userId !== undefined) {
    params.push(opts.userId);
    conditions.push(`user_id = $${params.length}`);
  }

  const where = conditions.length ? `WHERE ${conditions.join(" AND ")}` : "";
  const limit = opts.limit ?? 20;
  params.push(limit);
  const limitPlaceholder = `$${params.length}`;

  return query<AuditLogRow>(
    `SELECT id, type, message, changes,
            account_id, server_id, user_id, vendor_zone_id, created_on
       FROM logs
       ${where}
      ORDER BY created_on DESC, id DESC
      LIMIT ${limitPlaceholder}`,
    params,
  );
}

/**
 * The expiry timestamp of an invite, looked up by invitee email or invite code.
 *
 * Table `account_invites` (db/migrations/005_create_remaining_tables.sql +
 * 024_add_resend_tracking_to_account_invites.sql):
 *   - `email`       — the invitee address.
 *   - `code`        — the invite token (VARCHAR(25)).
 *   - `expires_on`  — expiry timestamp (used for the §4a "~30 days" assertion).
 *
 * Matches on `email` OR `code` so callers can pass whichever they have. Returns
 * the most recent matching invite's expiry, or null if none. When multiple
 * invites exist for an email, the newest (by created_on) wins.
 */
export interface InviteExpiry {
  id: string;
  email: string;
  code: string;
  expires_on: Date;
  created_on: Date;
}

export async function inviteExpiry(
  emailOrCode: string,
): Promise<InviteExpiry | null> {
  const rows = await query<InviteExpiry>(
    `SELECT id, email, code, expires_on, created_on
       FROM account_invites
      WHERE email = $1 OR code = $1
      ORDER BY created_on DESC, id DESC
      LIMIT 1`,
    [emailOrCode],
  );
  return rows[0] ?? null;
}

/**
 * Count of active (non-stale) browser sessions for a user — for the §11 sweep
 * assertion.
 *
 * Table `user_sessions` (db/migrations/003/005 + 014). There is no explicit
 * expiry/deleted column; "active" is the complement of the sweep's staleness
 * rule in ntpdb/sessions.sql.go (DeleteExpiredSessions), which deletes a session
 * when:
 *   - last_seen < now - 45 days, OR
 *   - last_seen IS NULL AND created_on < now - 2 days.
 *
 * We count the rows that rule would NOT delete, mirroring it exactly so the
 * count matches what survives the sweep.
 */
export async function sessionCountFor(userId: number): Promise<number> {
  const rows = await query<{ count: string }>(
    `SELECT COUNT(*) AS count
       FROM user_sessions
      WHERE user_id = $1
        AND NOT (
          (last_seen < CURRENT_TIMESTAMP - INTERVAL '45 days')
          OR (last_seen IS NULL AND created_on < CURRENT_TIMESTAMP - INTERVAL '2 days')
        )`,
    [userId],
  );
  // COUNT() comes back as a string (bigint); parse to a number.
  return Number(rows[0]?.count ?? "0");
}

// PoolClient is re-exported so a future read/write layer (behind its own guard)
// can share types without importing pg directly.
export type { PoolClient };
