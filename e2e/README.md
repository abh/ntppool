# ntppool E2E tests

Playwright end-to-end tests that drive the live dev site as a logged-in user
without going through Auth0. Login works by minting a real session token with
the api-dev binary's `api e2e session` command (reached through
`NTP_API_CLI`), then setting it as the browser `npuid` session cookie.

**Dev only.** Before minting a session, global setup requires the API's
database-backed `environment` setting and the public and manage sites'
`X-NTPPool-Environment` response headers to all report `devel`. The `api e2e`
commands repeat the check: they refuse to run unless `deployment_mode` and the
database `environment` are both devel.

## Install

```sh
npm install
npx playwright install chromium
```

## Configuration

Copy `.env.example` to `.env` and fill in the values:

- `NTP_BASE_URL` — dev site under test (default
  `https://web.askdev.grundclock.com`).
- `NTP_MANAGE_URL` — authenticated dev management site (default
  `https://manage.askdev.grundclock.com`). Global setup requires this value so
  every tested surface is explicit.
- `NTP_INTERNAL_API_URL` — base URL of the internal Go API, reachable over
  Tailscale, for API reads (`GetSettings`, `GetServer`, `GetAccountAuditLogs`,
  `GetAccount`). Must include the `/int/rpc` prefix the ConnectRPC services
  are mounted under (e.g. `http://api-internal.example.ts.net/int/rpc`), with
  no trailing slash. The harness appends the procedure path.
- `NTP_API_CLI` — command prefix that runs the api-dev binary for test
  sessions and fixtures. See "Reaching the API CLI".
- `NTP_SCORES_TEST_IP` — a real dev server IP for the public score/graph specs
  (default Google NTP). The isolated server-management specs allocate their
  own addresses and don't accept an existing server or caller-selected IP.
- `NTP_SKIP_STRIPE_CHECKOUT` — set to any value to skip
  `tests/stripe-checkout.spec.ts`. That spec buys a real subscription in the
  Stripe sandbox, so it needs outbound access to `checkout.stripe.com` and a
  devel stripe-gw running with a Stripe test key.

## Reaching the API CLI

Test sessions and fixtures come from `api e2e` subcommands that are
only compiled into the api-dev image (build tag `e2efixtures`). The harness
runs them through `NTP_API_CLI`: it splits the value on whitespace, starts it
without a shell from the `e2e/` directory, appends the subcommand, writes a
JSON request on stdin and reads one JSON object from stdout.

```sh
# remote devel (needs exec access to the devel API pod)
NTP_API_CLI=kubectl --context dala -n askntp exec -i deploy/api-internal -c main -- /ko-app/api

# local docker container
NTP_API_CLI=docker exec -i ntp-api /app/api

# local binary, built in the API repo with: go build -tags e2efixtures -o api-e2e .
NTP_API_CLI=../../go/ntp/api/api-e2e --config ../../go/ntp/api/database.yaml
```

- Each call through `kubectl exec` takes about 1 s.
- `go run` would recompile on every call, so the local example uses a built
  binary. The child inherits the environment, so a local binary can get
  `deployment_mode` and `DATABASE_URI` from `e2e/.env`.
- `api e2e session` only accepts emails at `example.com`, `example.net`,
  `example.org` and `ntppool.test`, whether the user is new or existing.
  It creates a new user named with the run's tag (see "Runs and cleanup");
  an existing email fails unless the request sets `existing_user`
  (`opts.existingUser` in `loginAs`), which only works for a user the same
  run created. Use `uniqueTestEmail()` for new users.
- The login preflight in global setup catches a CLI pointed at a different
  database than the site under test, because the minted session won't log in.

## Runs and cleanup

Global setup generates a run ID, prints `e2e run <id>` and sets
`E2E_RUN_ID`; it refuses to start if `E2E_RUN_ID` is already set. Every user
`api e2e session` and `api e2e fixture create` create for the run is named
`E2E run <id>`.

Global teardown runs `api e2e run finish` for that ID. In one transaction the
API schedules the run's users for deletion through the normal user deletion
task (they're purged 7 days later) and deletes their sessions, then teardown
prints `flagged_users`, `already_pending`, `deleted_sessions`,
`canceled_subscriptions` and `reset_zones`. Teardown also runs after a failed
global setup and after the first Ctrl-C. If it fails, the run fails.

`run finish` also cleans up what a checkout leaves behind. Before it schedules
the users it cancels the run's unfinished Stripe subscriptions through
stripe-gw (nothing happens when there are none), and in the transaction it
moves the run's Approved vendor zones back to Pending so account deletion can
remove them 7 days later.

Trace zips in `test-results/` and `playwright-report/` hold `npuid` session
cookies. Those sessions stop working when the run finishes.

If teardown never ran (the process was killed), finish the run by hand with
the printed ID. Finishing a run twice is harmless:

```sh
node --input-type=module - "<run id>" <<'NODE'
import "dotenv/config";
import { runApiCli } from "./lib/apicli.ts";

const runId = process.argv[2];
if (!runId) throw new Error("missing run ID");
const result = await runApiCli(
  "e2e run finish",
  ["e2e", "run", "finish"],
  { run_id: runId },
  runId,
  process.cwd(),
);
if (result.run_id !== runId) throw new Error("run finish returned a different run ID");
console.log(result);
NODE
```

## Fixture deployment

The verification, deletion, netspeed, scores-context, staff-search,
staff-server-edit, monitor-badges and vendor-coverage specs use
`api e2e fixture create` and `api e2e fixture cleanup`. A command failure is a
setup failure; the tests don't skip.

Deploy in this order:

1. Deploy an api-dev image with the `api e2e fixture` commands and run its
   Goose migrations with `deployment_mode=devel`. In devel, migration 029
   replaces the migration-027 `server_test_fixtures` tables with
   `e2e_fixtures`, `e2e_fixture_servers` and `e2e_fixture_monitors`, and
   refuses to run while an old attempt is uncleaned. Test and prod record
   027 and 029 as no-ops.
2. Confirm the devel database reports migration version 29 or later and
   contains the three `e2e_fixture*` tables.
3. Deploy the matching web revision with the environment response header and
   the E2E suite.
4. Confirm `api e2e --help` through `NTP_API_CLI` lists `fixture`, then run
   the focused suite twice with `--retries=0`. Each run must use fresh
   attempt IDs and report cleanup.

Each create call owns a fresh ordinary user, a private account, zero to four
servers, at most one monitor and at most one subscription, and needs at least
one of them.
Fresh accounts can add servers; `can_add_servers` turns false after two active
unverified servers (scheduled servers don't count as active for that check).
Servers use `198.51.100.0/24`, `203.0.113.0/24` and `2001:db8::/32`; monitors
use `192.0.2.0/24` and `2001:db8::/32`. Allocation locks and uniqueness checks
cover active attempts. Server fixtures seed no zones, score rows, log-score
rows or monitor-review rows, and both publication flags are off.

That initial state keeps fixtures out of the normal monitor and selector
queues, but it isn't a permanent no-probe barrier. A concurrent devel monitor
admin status update to active/testing can insert score rows for all undeleted
servers of the same address family, including these reserved addresses. Use a
quiesced devel monitor environment or verified egress policy when a strict
no-probe guarantee is required.

A fixture monitor is an IPv4 row, an IPv6 row, or both sharing the TLS name
`fixture-<attempt>.devel.mon.ntppool.dev`. Each row starts as `pending` (the
default), `testing`, `active` or `paused`, with no API key, so it can't
connect and starts with no score rows. Non-pending fixture monitors count
toward the devel account and global monitor limits while they exist. Two
things give a fixture monitor score rows, and cleanup then refuses: the
monitor admin status control (moving it to testing or active), and any
server added or restored on devel while the fixture monitor is `testing` or
`active`. The suite only creates `pending` and `paused` fixture monitors;
don't use the status control on them. If cleanup refuses because of a
candidate row that was never scored, remove those rows for the attempt's
monitors and clean up again (read the monitor IDs from the
`fixture-cleanup-failures` attachment):

```sql
DELETE FROM server_scores
 WHERE monitor_id IN (<monitor ids>) AND status = 'candidate' AND score_ts IS NULL;
```

A subscription seed adds one `account_subscriptions` row to the fixture
account: status `active`, name `E2E fixture`, the requested `max_zones` and
`max_devices`, optionally `quantity` and `tiered` (both or neither; the
harness sends them only when set), and `stripe_subscription_id`
`e2e_<attempt_id>`. The account's `stripe_customer_id` stays empty. The
harness sends the `subscription` key only for a seed that has one, because an
api-dev image from before the seed rejects unknown fields; deploy an image
with the seed before running `vendor-coverage.spec.ts`. Neither the account
nor the user deletion task removes subscription rows, and the row's account
foreign key doesn't cascade, so don't combine the seed with account or user
deletion flows.

Cleanup uses the attempt ID recorded before create. It deletes only the
fixture's recorded server and monitor IDs and the servers' related rows,
clears any scheduled deletion with the server rows, deletes the subscription
row whose `stripe_subscription_id` is `e2e_<attempt_id>`, and leaves the
generated user/account plus the fixture tombstone as inert identities. It
never deletes subscriptions by account. It refuses, and leaves the attempt
uncleaned, when a recorded server or monitor or the seeded subscription has
moved to another account, or a fixture monitor has score, log-score or
API-key rows.
Cleanup is idempotent. Cleaning an unknown attempt creates a tombstone, so a
delayed create with that ID can't add data. If a test loses the create
response or teardown fails, run this from `e2e/`. Replace the example UUID
with the attempt printed in the failure. The script loads `.env`, sends only
`attempt_id`, and calls the harness's own `runApiCli`, so `NTP_API_CLI` is
split the same way as in tests (zsh doesn't word-split `$NTP_API_CLI` in a
shell command).

```sh
node --input-type=module - 00000000-0000-4000-8000-000000000000 <<'NODE'
import "dotenv/config";
import { runApiCli } from "./lib/apicli.ts";

const attemptId = process.argv[2];
if (!attemptId) throw new Error("missing attempt ID");
const result = await runApiCli(
  "e2e fixture cleanup",
  ["e2e", "fixture", "cleanup"],
  { attempt_id: attemptId },
  attemptId,
  process.cwd(),
);
if (result.attempt_id !== attemptId) throw new Error("cleanup returned a different attempt ID");
console.log(`cleaned ${attemptId}; deleted_servers=${result.deleted_servers} deleted_monitors=${result.deleted_monitors} deleted_subscriptions=${result.deleted_subscriptions}`);
NODE
```

Cleanup finds a seeded subscription only by its `stripe_subscription_id`,
`e2e_<attempt_id>`. If that column is edited by hand, cleanup locks and
deletes nothing, then tombstones the attempt, which can't be cleaned again.
The active row stays behind, and the harness fails the cleanup because it
requires exactly one deleted subscription. To find leftover seeded rows, list
`e2e_` rows on accounts whose attempt is already cleaned, then delete them by
ID:

```sql
SELECT s.id, s.stripe_subscription_id, f.attempt_id
  FROM account_subscriptions s JOIN e2e_fixtures f ON f.account_id = s.account_id
 WHERE s.stripe_subscription_id LIKE 'e2e\_%' AND f.cleaned_on IS NOT NULL;
DELETE FROM account_subscriptions WHERE id IN (<subscription ids>);
```

## Run

```sh
npm test            # headless
npm run test:headed # headed
```

List the tests without running them (no live site or API CLI needed):

```sh
npx playwright test --list
```

After the matching fixture API and schema are deployed, run the acceptance set
with retries disabled, then repeat the fixture-dependent specs so the second
run allocates and cleans fresh attempts:

```sh
npm run test:unit
npm run typecheck
npx playwright test --list
npx playwright test tests/server.spec.ts tests/server-verification.spec.ts tests/server-deletion.spec.ts tests/server-netspeed.spec.ts tests/server-scores-context.spec.ts tests/staff-search.spec.ts tests/staff-server-edit.spec.ts tests/monitor-badges.spec.ts tests/vendor-coverage.spec.ts --project=manage --retries=0
npx playwright test tests/server-verification.spec.ts tests/server-deletion.spec.ts tests/server-netspeed.spec.ts tests/server-scores-context.spec.ts tests/staff-search.spec.ts tests/staff-server-edit.spec.ts tests/monitor-badges.spec.ts tests/vendor-coverage.spec.ts --project=manage --retries=0
npx playwright test tests/scores.spec.ts --project=web --retries=0
npx playwright test tests/monitor-config.spec.ts --project=manage --retries=0
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

- `mintSession(email, opts?)` — runs `api e2e session` through `runApiCli`
  (`lib/apicli.ts`) with `{ email, run_id, existing_user, grant_staff,
  grant_vendor_admin, grant_monitor_admin }` on stdin and returns
  `session_token`. `opts.existingUser` mints another session for a user an
  earlier mint in the same run created, for example to log back in after logout.
- `loginAs(context, email, opts?)` — mints a session and sets the `npuid`
  cookie. The cookie attributes mirror the Perl side
  (`lib/NTPPool/Control.pm` and `lib/NTPPool/Control/Login.pm`): value
  `"{session_token};{unix_seconds}"`, path `/`, `secure`, `httpOnly`,
  `SameSite=Lax`, domain = the `NTP_BASE_URL` host. `opts.grantStaff` /
  `opts.grantVendorAdmin` / `opts.grantMonitorAdmin` mint a staff /
  vendor-admin / monitor-admin user (dev-only, via the command's `grant_staff` /
  `grant_vendor_admin` / `grant_monitor_admin` flags) for the staff and
  monitor-admin-gated specs.
- `uniqueTestEmail(prefix?)` — fresh per-run email so each run gets an
  isolated new user.

## Coverage

Specs map to `MANUAL_TEST_PLAN.md` sections: `login` (§1), `regression-smoke`
(§12), `i18n` (§10), `vendor` (§5, §5a, §5b, §5c, §5e), `vendor-coverage` (§5,
§5b, §5e), `scores` (§9), `server` (§8 add-form baseline),
`server-verification`, `server-deletion`, `server-netspeed` and
`server-scores-context` (§8/§8a/§8b), `account-dissolve` (§2), `staff-deletion`
(§3/§4), `invites` (§4a), `account-frozen` (§2), `account-download` (§4c),
`staff-search` (§13), `staff-server-edit` (§8, staff hostname and zone edits and
their CSRF check), `account-create` (§1 + §4), `account-team` (§4),
`account-update` (§4), `dns-zone` (§6, auth-guard portion), `monitor-config`
(§14), `monitor-badges` (§15 account flag badges, §16 dual-stack monitor cards).
Staff specs rely on the `grant_staff` / `grant_vendor_admin` flags of
`api e2e session`; `monitor-config` and `monitor-badges` use
`grant_monitor_admin`.
Selectors are derived from the templates and may need adjustment against the
live site on first run.

The suite has no DB verification layer — there is no read-only Postgres
connection anywhere in `e2e/`. State is confirmed through the UI (a fresh page
read, as in `cancelAccountDeletionAsStaff` in `lib/accounts.ts`) or through
authorized API calls, never by querying the database directly.
