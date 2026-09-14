import { BrowserContext } from "@playwright/test";
import { runApiCli } from "./apicli";

// The browser session cookie. Attributes below are mirrored from the Perl
// side so the live dev site treats the minted session like a real login.
//
// Source: lib/NTPPool/Control.pm `plain_cookie` and
// lib/NTPPool/Control/Login.pm `_set_session_cookie`:
//   - name:     npuid
//   - value:    "{session_token};{unix_seconds}", URL-encoded as Plack's
//               Cookie::Baker bakes it (the ";" stored as "%3B"); see loginAs

//   - domain:   site cookie_domain, else the request host (we use the
//               NTP_BASE_URL host, which is what the dev site serves under)
//   - path:     /
//   - secure:   true   ($args->{secure}   = 1)
//   - httpOnly: true   ($args->{httpOnly} = 1)
//   - sameSite: Lax    (samesite => "Lax")
const COOKIE_NAME = "npuid";

interface MintOptions {
  name?: string;
  // Grant the minted user the support_staff privilege. Dev only, same as the
  // mint itself. Lets staff-gated flows (account dissolution, staff deletion)
  // run as a fresh, isolated user instead of mutating a real staff account.
  grantStaff?: boolean;
  // Grant the minted user the vendor_admin privilege. The vendor admin
  // route (/manage/vendor/admin) and the approve/reject RPC require
  // vendor_admin specifically — support_staff is not enough.
  grantVendorAdmin?: boolean;
  // Grant the minted user the monitor_admin privilege. The account
  // monitor-config route (/manage/account/monitor-config) checks
  // monitor_admin specifically — support_staff is not enough.
  grantMonitorAdmin?: boolean;
  // Mint another session for the user an earlier mint created for this email,
  // instead of creating a user. Without it an email that already belongs to a
  // user fails, so two tests that pick the same address never share a user.
  existingUser?: boolean;
}

export class RpcError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: string,
    // The Connect error JSON's `message`. It stays out of `message`, so it
    // only shows up in a report when a test asserts on it.
    readonly connectMessage?: string,
  ) {
    super(message);
    this.name = "RpcError";
  }
}

/**
 * POST a ConnectRPC method as JSON against NTP_INTERNAL_API_URL and return the
 * parsed body. Callers supply their own auth headers and validate the response
 * shape; everything here is transport.
 *
 * `label` names the procedure in error messages, and `subject` adds the thing
 * the call was about, so failures stay as greppable as before the transport was
 * shared (e.g. "GetServer failed for 192.0.2.1: 404 …").
 */
export async function connectRpc<T>(
  label: string,
  procedure: string,
  headers: Record<string, string>,
  body: unknown,
  subject = "",
): Promise<T> {
  const apiBase = process.env.NTP_INTERNAL_API_URL;
  if (!apiBase) {
    throw new Error("NTP_INTERNAL_API_URL is not set");
  }
  const url = `${apiBase.replace(/\/$/, "")}/${procedure}`;

  let resp: Response;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...headers },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (err) {
    // Network/DNS failure — almost always a wrong or unreachable
    // NTP_INTERNAL_API_URL (e.g. the .env.example placeholder, or Tailscale
    // down). Surface that rather than a bare "fetch failed".
    throw new Error(
      `${label} request to ${url} failed (network/DNS). ` +
        `Is NTP_INTERNAL_API_URL correct and reachable? ` +
        `Cause: ${(err as Error).message}`,
    );
  }

  if (!resp.ok) {
    let code = "unknown";
    let connectMessage: string | undefined;
    try {
      const errorBody = (await resp.json()) as { code?: unknown; message?: unknown };
      if (typeof errorBody.code === "string" && errorBody.code) {
        code = errorBody.code;
      }
      if (typeof errorBody.message === "string") {
        connectMessage = errorBody.message;
      }
    } catch {
      // An HTML/empty error response is still reported by status without
      // attaching the body, which can contain credentials or fixture secrets.
    }
    throw new RpcError(
      `${label} failed${subject && ` for ${subject}`}: ` +
        `${resp.status} ${resp.statusText} (Connect code: ${code})`,
      resp.status,
      code,
      connectMessage,
    );
  }

  try {
    return (await resp.json()) as T;
  } catch {
    throw new Error(`${label} returned malformed JSON`);
  }
}

/**
 * Mint a real session token through `api e2e session` (NTP_API_CLI). The
 * command creates a new user, so `email` must not belong to an existing user
 * unless `opts.existingUser` is set; uniqueTestEmail() gives a fresh one. It
 * only accepts example.com, example.net, example.org and ntppool.test
 * addresses. Dev only: the command refuses to run unless the API and its
 * database are devel.
 */
export async function mintSession(
  email: string,
  opts: MintOptions = {},
): Promise<string> {
  const data = await runApiCli<{ session_token?: unknown }>(
    "e2e session",
    ["e2e", "session"],
    {
      email,
      name: opts.name ?? "",
      existing_user: opts.existingUser ?? false,
      grant_staff: opts.grantStaff ?? false,
      grant_vendor_admin: opts.grantVendorAdmin ?? false,
      grant_monitor_admin: opts.grantMonitorAdmin ?? false,
    },
    email,
  );

  if (typeof data.session_token !== "string" || !data.session_token) {
    throw new Error("e2e session response missing session_token");
  }

  return data.session_token;
}

/**
 * Read an account's numeric `accounts.id` through AccountService.GetAccount.
 *
 * The staff search `id:<n>` query matches `a.id = $1` (api sql/search.sql
 * SearchAccountByID), and that number is not rendered anywhere in the UI — the
 * templates only ever test `account_id` for truthiness. This is the supported
 * read for it (verified 2026-09-09, readiness handoff R5); the harness must not
 * decode the acc_ token or reach for SQL.
 *
 * Auth is the USER's session token from loginAs/mintSession. Account context
 * travels in X-Account, the same header lib/NP/CAPI.pm:256 sets.
 */
export async function getAccountNumericId(
  sessionToken: string,
  accountToken: string,
): Promise<string> {
  // account_id is a proto int64, so ConnectRPC JSON encodes it as a string.
  const data = await connectRpc<{
    account?: { account_id?: string | number };
  }>(
    "GetAccount",
    "ntppool.account.v1.AccountService/GetAccount",
    {
      Authorization: `Bearer ${sessionToken}`,
      "X-Account": accountToken,
    },
    {},
    accountToken,
  );

  // One check covers every way this can go wrong: a missing field stringifies
  // to "undefined"/"null"/"", and a shape change to "[object Object]" — none of
  // which match /^\d+$/.
  const numericId = String(data.account?.account_id ?? "");
  if (!/^\d+$/.test(numericId)) {
    throw new Error("GetAccount returned no usable account.account_id");
  }
  return numericId;
}

// The authenticated app (/manage) is a separate Combust site served from the
// manage host, NOT the public web host. The session cookie is host-scoped
// (the deployed config sets no cookie_domain, so plain_cookie falls back to the
// request host), so it must be installed for the manage host or it never
// reaches the app under test.
export const MANAGE_URL =
  process.env.NTP_MANAGE_URL || "https://manage.askdev.grundclock.com";

function manageHost(): string {
  // hostname (not host) so a non-default port never leaks into the cookie domain.
  return new URL(MANAGE_URL).hostname;
}

/**
 * Mint a session for `email` and install it as the browser session cookie.
 * Returns info useful for assertions in tests.
 */
export async function loginAs(
  context: BrowserContext,
  email: string,
  opts: MintOptions = {},
): Promise<{ email: string; sessionToken: string }> {
  const sessionToken = await mintSession(email, opts);
  await installSession(context, sessionToken);
  return { email, sessionToken };
}

/** Install an already-minted session as the manage host's browser cookie. */
export async function installSession(
  context: BrowserContext,
  sessionToken: string,
): Promise<void> {
  // The Perl value is "{session_token};{unix_seconds}", but that is never what
  // the browser actually stores: Plack bakes the Set-Cookie header through
  // Cookie::Baker, which URL-encodes the value (the ";" becomes "%3B"), and
  // crush_cookie URL-decodes it back on the next request. So we install the
  // encoded form — both to faithfully mirror a real login and because Chrome's
  // CDP (Storage.setCookies) rejects a raw ";" in a cookie value as an
  // "Invalid cookie fields" error.
  const value = encodeURIComponent(
    `${sessionToken};${Math.floor(Date.now() / 1000)}`,
  );

  await context.addCookies([
    {
      name: COOKIE_NAME,
      value,
      domain: manageHost(),
      path: "/",
      secure: true,
      httpOnly: true,
      sameSite: "Lax",
    },
  ]);
}

/**
 * A fresh per-run email so each test run gets an isolated new user.
 */
export function uniqueTestEmail(prefix = "test-run"): string {
  const rand = Math.random().toString(36).slice(2, 8);
  return `${prefix}-${Date.now()}-${rand}@example.com`;
}
