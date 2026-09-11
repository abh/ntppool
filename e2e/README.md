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
  mounted under (e.g. `http://api-internal.example.ts.net/int/rpc`), with no
  trailing slash. The harness appends the AuthService procedure path.
- `NTP_TEST_SESSION_KEY` — bearer key authorizing `CreateTestSession` and the
  server fixture RPCs.
- `NTP_SCORES_TEST_IP` — a real dev server IP for the public score/graph specs
  (default Google NTP). The isolated server-management specs allocate their
  own addresses and don't accept an existing server or caller-selected IP.

## Provisioning the test session key

The key is a service token granted the `test-session-api` capability. Create
it from the Go API repo with the `--test-session` flag:

```sh
cd ../go/ntp/api
go run . service create e2e-test-session --test-session
```

This prints an `npd_…` API key. Put that value in `NTP_TEST_SESSION_KEY`.

## Server fixture deployment

The verification, deletion, netspeed and scores-context specs use
`CreateServerTestFixture` and `CleanupServerTestFixture`. Both RPCs refuse to
run unless the API is in the devel environment and the bearer key has the
`test-session-api` audience. A missing capability is a setup failure; the
tests don't skip.

Deploy in this order:

1. Apply `027_server_test_fixtures.sql` to the devel API database.
2. Deploy API commit `21d49ee6172a4ac4931d7fba526eead58bc1fd6b`.
3. Deploy the matching web revision containing generated `Auth.pm` commit
   `27091be29c4ed929c85be8f71d6a5f5a385cdfc4` and the E2E suite.
4. Probe `CreateServerTestFixture`, then run the focused suite twice with
   `--retries=0`. Each run must use fresh attempt IDs and report cleanup.

Each create call owns a fresh ordinary user, a private account and one to four
servers. Fresh accounts can add servers; `can_add_servers` turns false after
two active unverified servers (scheduled servers don't count as active for
that check). The fixture uses `198.51.100.0/24`, `203.0.113.0/24` and
`2001:db8::/32`, with allocation locks and uniqueness checks across active
attempts. It seeds no zones, score rows, log-score rows or monitor-review rows,
and both publication flags are off.

That initial state keeps fixtures out of the normal monitor and selector
queues, but it isn't a permanent no-probe barrier. A concurrent devel monitor
admin status update to active/testing can insert score rows for all undeleted
servers of the same address family, including these reserved addresses. Use a
quiesced devel monitor environment or verified egress policy when a strict
no-probe guarantee is required.

Cleanup uses the attempt ID recorded before create. It deletes only the
fixture's recorded server IDs and related rows, clears any scheduled deletion
with the server rows, and leaves the generated user/account plus the fixture
tombstone as inert identities. Cleanup is idempotent. Cleaning an unknown
attempt creates a tombstone, so a delayed create with that ID can't add data.
If a test loses the create response or teardown fails, run this from `e2e/`
with `.env` already loaded. Replace the example UUID with the attempt printed
in the failure. The script sends only `attempt_id` in the request body and
doesn't print request headers or credentials.

```sh
node --input-type=module - 00000000-0000-4000-8000-000000000000 <<'NODE'
const attemptId = process.argv[2];
const apiBase = process.env.NTP_INTERNAL_API_URL;
const key = process.env.NTP_TEST_SESSION_KEY;
if (!apiBase || !key || !attemptId) throw new Error("missing API URL, key, or attempt ID");

const response = await fetch(
  `${apiBase.replace(/\/$/, "")}/ntppool.auth.v1.AuthService/CleanupServerTestFixture`,
  {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({ attempt_id: attemptId }),
  },
);
if (!response.ok) throw new Error(`cleanup failed: HTTP ${response.status}`);
const result = await response.json();
if (result.attempt_id !== attemptId) throw new Error("cleanup returned a different attempt ID");
console.log(`cleaned ${attemptId}; deleted_servers=${result.deleted_servers ?? 0}`);
NODE
```

## Run

```sh
npm test            # headless
npm run test:headed # headed
```

List the tests without running them (no live site or key needed):

```sh
npx playwright test --list
```

After the matching fixture API and schema are deployed, run the acceptance set
with retries disabled, then repeat the fixture-dependent specs so the second
run allocates and cleans fresh attempts:

```sh
npm run typecheck
npx playwright test --list
npx playwright test tests/server.spec.ts tests/server-verification.spec.ts tests/server-deletion.spec.ts tests/server-netspeed.spec.ts tests/server-scores-context.spec.ts --project=manage --retries=0
npx playwright test tests/server-verification.spec.ts tests/server-deletion.spec.ts tests/server-netspeed.spec.ts tests/server-scores-context.spec.ts --project=manage --retries=0
npx playwright test tests/scores.spec.ts --project=web --retries=0
```

Ordinary suite runs keep the retries configured in `playwright.config.ts`.
Acceptance reports count passed, failed, retried, skipped, did-not-run and
teardown failures separately.

## Saving validation-run logs

Playwright clears its `outputDir` (`test-results/`) at the start of every run,
so a second run deletes the first run's output and can even unlink the log
it's currently writing. When a run's output needs to survive past the next
run — a coverage/validation pass, for example — redirect it into
`e2e/test-logs/` instead, which is gitignored and never touched by Playwright:

```sh
mkdir -p test-logs
npx playwright test --project=manage --reporter=list > test-logs/run-1.log 2>&1
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
(§8 add-form baseline), `server-verification`, `server-deletion`,
`server-netspeed` and `server-scores-context` (§8/§8a/§8b),
`account-dissolve` (§2), `staff-deletion` (§3/§4), `invites` (§4a),
`account-frozen` (§2), `account-download` (§4c), `staff-search` (§13).
Staff specs need the `grant_staff` / `grant_vendor_admin` RPC build deployed.
Selectors are derived from the templates and may need adjustment against the
live site on first run.

The suite has no DB verification layer — there is no read-only Postgres
connection anywhere in `e2e/`. State is confirmed through the UI (a fresh page
read, as in `cancelAccountDeletionAsStaff` in `lib/accounts.ts`) or through
authorized API calls, never by querying the database directly.
