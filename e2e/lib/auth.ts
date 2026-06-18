import { BrowserContext } from "@playwright/test";

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

  let resp: Response;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
  } catch (err) {
    // Network/DNS failure — almost always a wrong or unreachable
    // NTP_INTERNAL_API_URL (e.g. the .env.example placeholder, or Tailscale
    // down). Surface that rather than a bare "fetch failed".
    throw new Error(
      `CreateTestSession request to ${url} failed (network/DNS). ` +
        `Is NTP_INTERNAL_API_URL correct and reachable? ` +
        `Cause: ${(err as Error).message}`,
    );
  }

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

  return { email, sessionToken };
}

/**
 * A fresh per-run email so each test run gets an isolated new user.
 */
export function uniqueTestEmail(prefix = "test-run"): string {
  const rand = Math.random().toString(36).slice(2, 8);
  return `${prefix}-${Date.now()}-${rand}@example.com`;
}
