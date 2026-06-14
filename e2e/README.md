# ntppool E2E tests

Playwright end-to-end tests that drive the live dev site as a logged-in user
without going through Auth0. Login works by minting a real session token from
the Go API (`AuthService/CreateTestSession`), then setting it as the browser
`npuid` session cookie.

**Dev only.** The mint RPC refuses to run outside the devel environment, so
these tests cannot be pointed at staging or production.

## Install

```sh
npm install
npx playwright install chromium
```

## Configuration

Copy `.env.example` to `.env` and fill in the values:

- `NTP_BASE_URL` — dev site under test (default
  `https://web.askdev.grundclock.com`).
- `NTP_INTERNAL_API_URL` — base URL of the internal Go API, reachable over
  Tailscale. Must include the `/int/rpc` prefix the ConnectRPC services are
  mounted under (e.g. `http://api-internal.example.ts.net/int/rpc`), no
  trailing slash. The harness appends
  `/ntppool.auth.v1.AuthService/CreateTestSession`.
- `NTP_TEST_SESSION_KEY` — bearer key authorizing `CreateTestSession`.
- `NTP_TEST_DB_URL` — **read-only** Postgres URL for the grey-box DB assertions
  (email sent, audit log, invite expiry). Use a read-only role; the harness
  refuses any DB that isn't the devel `askntp` (see `assertDevelDatabase`).
  Tests that assert side effects **skip** when this is unset, so the UI
  assertions still run without it.
- `NTP_SCORES_TEST_IP` — a real dev server IP for the public score/graph specs
  (default Google NTP). `NTP_SERVER_TEST_IP` / `NTP_EXISTING_SERVER_IP` — IPs
  for the add-server / scheduled-deletion specs (see `.env.example`).

## Provisioning the test session key

The key is a service token granted the `test-session-api` capability. Create
it from the Go API repo with the `--test-session` flag:

```sh
cd ../go/ntp/api
go run . service create e2e-test-session --test-session
```

This prints an `npd_…` API key. Put that value in `NTP_TEST_SESSION_KEY`.

## Run

```sh
npm test            # headless
npm run test:headed # headed
```

List the tests without running them (no live site or key needed):

```sh
npx playwright test --list
```

## How login works

`lib/auth.ts`:

- `mintSession(email, opts?)` — POSTs to
  `${NTP_INTERNAL_API_URL}/ntppool.auth.v1.AuthService/CreateTestSession`
  with `Authorization: Bearer ${NTP_TEST_SESSION_KEY}` and a JSON body of
  `{ email, name, create_if_missing: true }`. Returns the `session_token`.
- `loginAs(context, email, opts?)` — mints a session and sets the `npuid`
  cookie. The cookie attributes mirror the Perl side
  (`lib/NTPPool/Control.pm` and `lib/NTPPool/Control/Login.pm`): value
  `"{session_token};{unix_seconds}"`, path `/`, `secure`, `httpOnly`,
  `SameSite=Lax`, domain = the `NTP_BASE_URL` host. `opts.grantStaff` /
  `opts.grantVendorAdmin` mint a staff / vendor-admin user (dev-only, via the
  RPC's `grant_staff` / `grant_vendor_admin` flags) for the staff specs.
- `uniqueTestEmail(prefix?)` — fresh per-run email so each run gets an
  isolated new user.

## Coverage

Specs map to `MANUAL_TEST_PLAN.md` sections: `login` (§1), `regression-smoke`
(§12), `i18n` (§10), `vendor` (§5 + §5a staff/admin), `scores` (§9), `server`
(§8/§8a), `account-dissolve` (§2), `staff-deletion` (§3/§4), `invites` (§4a).
Staff specs need the `grant_staff` / `grant_vendor_admin` RPC build deployed;
DB-backed assertions need `NTP_TEST_DB_URL`. Selectors are derived from the
templates and may need adjustment against the live site on first run.
