import { BrowserContext } from "@playwright/test";

// The browser session cookie. Attributes below are mirrored from the Perl
// side so the live dev site treats the minted session like a real login.
//
// Source: lib/NTPPool/Control.pm `plain_cookie` and
// lib/NTPPool/Control/Login.pm `_set_session_cookie`:
//   - name:     npuid
//   - value:    "{session_token};{unix_seconds}"
//   - domain:   site cookie_domain, else the request host (we use the
//               NTP_BASE_URL host, which is what the dev site serves under)
//   - path:     /
//   - secure:   true   ($args->{secure}   = 1)
//   - httpOnly: true   ($args->{httpOnly} = 1)
//   - sameSite: Lax    (samesite => "Lax")
const COOKIE_NAME = "npuid";

interface MintOptions {
  name?: string;
  createIfMissing?: boolean;
  // Grant the minted user the support_staff privilege. Dev only and
  // capability-gated, same as the mint itself. Lets staff-gated flows
  // (account dissolution, staff deletion) run as a fresh, isolated user
  // instead of mutating a real staff account.
  grantStaff?: boolean;
  // Grant the minted user the vendor_admin privilege. The vendor admin
  // route (/manage/vendor/admin) and the approve/reject RPC require
  // vendor_admin specifically — support_staff is not enough.
  grantVendorAdmin?: boolean;
}

interface MintResult {
  sessionToken: string;
}

/**
 * Mint a real session token via the Go AuthService.CreateTestSession RPC.
 * Dev only: the RPC refuses to run outside the devel environment.
 */
export async function mintSession(
  email: string,
  opts: MintOptions = {},
): Promise<string> {
  const apiBase = process.env.NTP_INTERNAL_API_URL;
  if (!apiBase) {
    throw new Error("NTP_INTERNAL_API_URL is not set");
  }
  const key = process.env.NTP_TEST_SESSION_KEY;
  if (!key) {
    throw new Error("NTP_TEST_SESSION_KEY is not set");
  }

  const url = `${apiBase.replace(/\/$/, "")}/ntppool.auth.v1.AuthService/CreateTestSession`;

  const body = {
    email,
    name: opts.name ?? "",
    create_if_missing: opts.createIfMissing ?? true,
    // snake_case to match the ConnectRPC JSON fields (grant_staff = 4,
    // grant_vendor_admin = 5).
    grant_staff: opts.grantStaff ?? false,
    grant_vendor_admin: opts.grantVendorAdmin ?? false,
  };

  const resp = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(
      `CreateTestSession failed: ${resp.status} ${resp.statusText} - ${text}`,
    );
  }

  // ConnectRPC JSON encodes the field as snake_case: session_token.
  const data = (await resp.json()) as { session_token?: string };
  if (!data.session_token) {
    throw new Error(
      `CreateTestSession response missing session_token: ${JSON.stringify(data)}`,
    );
  }

  return data.session_token;
}

function baseHost(): string {
  const base = process.env.NTP_BASE_URL || "https://web.askdev.grundclock.com";
  // hostname (not host) so a non-default port never leaks into the cookie domain.
  return new URL(base).hostname;
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
  const value = `${sessionToken};${Math.floor(Date.now() / 1000)}`;

  await context.addCookies([
    {
      name: COOKIE_NAME,
      value,
      domain: baseHost(),
      path: "/",
      secure: true,
      httpOnly: true,
      sameSite: "Lax",
    },
  ]);

  return { email, sessionToken };
}

/**
 * A fresh per-run email so each test run gets an isolated new user.
 */
export function uniqueTestEmail(prefix = "test-run"): string {
  const rand = Math.random().toString(36).slice(2, 8);
  return `${prefix}-${Date.now()}-${rand}@example.com`;
}
