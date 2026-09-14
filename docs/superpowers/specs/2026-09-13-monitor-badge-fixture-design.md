# Monitor fixtures and §15 badge coverage

**Date:** 2026-09-14 (interview started 2026-09-13)
**Status:** Implemented 2026-09-14. Go API: ntppool/api main 2d6f512..dbe6272, deployed to devel as api-dev sha-dbe6272b with migration 29. Harness: ntppool commits f8752c11, 2f6e38f7, d96e6015 and the follow-ups.
**Spans:** the Go API (`../go/ntp/api`) and this repo's `e2e/` harness. No Perl
or template changes.
**Supersedes:** `docs/superpowers/handoffs/2026-09-13-monitor-badge-fixture-design.md`.
**Builds on:** `docs/superpowers/specs/2026-09-13-e2e-fixtures-cli-design.md`
(test-only setup lives in `api e2e` subcommands in the api-dev build, never in
network-reachable handlers).

## Goal

1. Live E2E coverage for every `MANUAL_TEST_PLAN.md` §15 row (account flag
   badges in the monitor lists).
2. One E2E test of how a dual-stack monitor card renders its statuses (a new
   §16).
3. To get there, generalize `api e2e server-fixture create|cleanup` into
   `api e2e fixture create|cleanup`, which creates servers and monitors for a
   fresh account in one attempt.

## Decisions

1. **One generalized command.** `api e2e fixture create|cleanup` replaces
   `api e2e server-fixture create|cleanup`. The old subcommands, Go names,
   tables and TS names go away; there is no compatibility layer.
2. **Monitor seeds:** at most one logical monitor per attempt, with an `ipv4`
   and/or `ipv6` entry, each carrying its own status.
3. **Statuses:** `pending`, `testing`, `active` or `paused`. An empty or
   omitted status means `pending`.
4. **Cleanup fails loudly** when a fixture monitor has picked up score,
   log-score or API-key rows, or has moved to another account. It never
   deletes those rows itself.
5. **Migration:** a devel-only Go migration refuses to run while any old
   attempt is uncleaned, then drops the migration-027 tables and creates the
   renamed ones. Devel was inventoried on 2026-09-14 (see Findings) and needed
   no cleanup.
6. **Flag setup in the badge test:** the monitor-config form once (it covers
   the `monitor_enabled` checkbox and the `-1` limit, which §14 doesn't),
   `UpdateAccountMonitorConfig` over ConnectRPC for the remaining transition.
7. **Test layout:** the admin badge test walks one fixture through the states
   in order. The non-admin test and the dual-stack card test use their own
   fixtures. All live in a new `e2e/tests/monitor-badges.spec.ts`.
8. **Viewers:** a separately minted monitor-admin session views the fixture
   account; the fixture's own session is the non-admin viewer. No privilege
   grants on the fixture command.

## Findings that shaped the design (verified 2026-09-14)

- **What `ListMonitors` lists.** `GetMonitorsByAccountUser`
  (`sql/monitor_admin.sql`) requires `is_current`, a non-null `account_id`,
  `status != 'deleted'` and `type = 'monitor'`. `formatMonitorList` skips a
  row whose `ip` doesn't parse, and groups rows by `tls_name` (else `ip`,
  else `id_token`). Two rows sharing a `tls_name` with both IPs valid become
  one dual-stack monitor; `combined_status` is set when their statuses match.
- **Access.** `UserX.IsStaff()` includes monitor_admin, so the ConnectRPC
  `X-Account` middleware (`getRequestAccount`) and `ValidateSession`'s staff
  override both let a monitor admin act on an account they aren't a member of,
  with `can_edit` true for a non-frozen account. A monitor admin can open
  `/manage/monitors?a=<fixture>`, `/manage/account?a=<fixture>` and its
  monitor-config form.
- **Flags disclosure.** `buildMonitorProto` sets `account.flags` only for
  monitor admins. A non-admin's `ListMonitors` JSON has no `flags` key.
  `all_accounts` from a non-admin is `PermissionDenied`, which
  `_handle_capi_error` passes through as HTTP 403.
- **Where score rows come from.** For `monitor`-type rows, `server_scores`
  rows are inserted in two places. `UpdateMonitorStatus` →
  `InsertMonitorServerScores` (`ntpdb/helpers_monitor_update.go`) runs when an
  admin moves a monitor to testing/active and inserts a candidate row for
  every undeleted server of the same IP family on other accounts.
  `AddServer` → `InitializeServerScoresForServer`
  (`sql/server_management.sql`) runs on every server add or restore and
  inserts a candidate row for every `active` or `testing` monitor of the same
  IP family on another account. The selector only acts on existing rows, the
  scorer only inserts rows for `score`-type monitors, and monitor-api needs
  credentials a fixture monitor doesn't have. So a fixture monitor starts
  with no score rows in any status, but an `active` or `testing` one picks up
  a candidate row whenever someone adds a server on devel, and its cleanup
  then refuses (Decision 4). Pending and paused fixture monitors never do.
  (Corrected 2026-09-14 after the final API review.)
- **Limits.** `testing`, `active` and `paused` rows count toward
  `GetAccountMonitorCount` and `GetGlobalMonitorCount`; `pending` doesn't.
- **Pending-only accounts don't see the list.** `/manage/monitors` redirects
  to `/manage/monitors/new` unless `GetAccountStatus` reports a non-zero
  monitor count (`Monitor.pm` `manage_dispatch`), and that count excludes
  `pending`. The badge tests therefore use a `paused` monitor. (Found in the
  first live run, 2026-09-14.)
- **Foreign keys to `monitors`:** `api_keys_monitors.monitor_id`,
  `log_scores.monitor_id`, `server_scores.monitor_id`,
  `scorer_status.scorer_id`, and `monitor_registrations.monitor_id`
  (`ON DELETE CASCADE`). `logs` has no monitor column.
- **Unique indexes on `monitors`:** `(ip, is_current)`, `(tls_name,
  ip_version)`, `id_token`, `api_key`.
- **Devel baseline (read-only queries, 2026-09-14):** 317 attempts in
  `server_test_fixtures`, none uncleaned (8 tombstone-only); 0 servers in the
  fixture ranges; 0 monitors in any documentation range or with a
  `fixture-` TLS name; 37 active and 2 testing monitors; goose version 28;
  deployed image `api-dev:sha-be3c11d8`. The monitor selector and scorer are
  deployed in askntp.

## Go API

### Command

`cmd/e2e.go` (build tag `e2efixtures`): the `server-fixture` command group
becomes `fixture`, with `create` ("create a fixture user, account, and servers
and/or a monitor") and `cleanup` ("remove a fixture attempt's servers and
monitors"). Both keep `runE2E`: devel `deployment_mode` and database
environment, one JSON object in, one out.

### Request

```json
{
  "attempt_id": "<canonical lowercase UUID v4>",
  "servers": [
    {"ip_version": 4, "verified": true, "pending_verification": false,
     "scheduled_deletion": false, "netspeed": 512}
  ],
  "monitors": [
    {"ipv4": {"status": "active"}, "ipv6": {"status": "paused"}}
  ]
}
```

Validation, all before any database work (`ErrInvalidRequest`):

- `attempt_id` rules are unchanged.
- `servers`: 0 to 4 entries; per-server rules are unchanged.
- `monitors`: 0 or 1 entries.
- At least one server or one monitor.
- A monitor needs at least one of `ipv4` and `ipv6` (a JSON `null` family is
  absent). Each family's `status` is `pending`, `testing`, `active`,
  `paused`, or empty (meaning `pending`). Anything else, `deleted` included,
  is rejected.
- Unknown JSON fields are already rejected by `decodeE2ERequest`.

### Monitor rows

One `monitors` row per requested family, in the create transaction:

| Column | Value |
| --- | --- |
| `type` | `monitor` |
| `user_id`, `account_id` | the fixture's new user and account |
| `tls_name` | `fixture-<attempt_id>.` + `depenv.DeployDevel.MonitorDomain()` (shared by both families) |
| `ip`, `ip_version` | allocated address, `v4`/`v6` |
| `status` | the family's status |
| `is_current` | true |
| `config` | `{}` |
| `id_token` | `ntpdb.GenerateIDToken(ntpdb.TokenPrefixMonitor)` |
| `hostname`, `location`, `client_version` | empty |
| `api_key`, `last_seen`, `last_submit`, `deleted_on` | NULL |
| `created_on` | now |

Address allocation runs under the existing allocator advisory lock:

- IPv4 from `192.0.2.1`–`192.0.2.254` (TEST-NET-1, unused by server
  fixtures); IPv6 random in `2001:db8::/32`, 16 tries, as for servers.
- An address is in use if any `monitors` row has that `ip` (whatever
  `is_current` is) or an uncleaned attempt recorded it for a monitor.
- Exhaustion returns `ErrNoAddress`.

Each row is recorded in `e2e_fixture_monitors` in the same transaction.

### Response

```json
{
  "attempt_id": "…", "account_token": "acc_…", "account_id": "123",
  "user_id": "456", "email": "fixture-<attempt>-<random>@example.com",
  "session_token": "…",
  "servers": [ … unchanged shape … ],
  "monitors": [
    {
      "tls_name": "fixture-<attempt>.devel.mon.ntppool.dev",
      "ipv4": {"monitor_id": "789", "id_token": "mon_…", "ip": "192.0.2.1", "status": "active"},
      "ipv6": {"monitor_id": "790", "id_token": "mon_…", "ip": "2001:db8:…", "status": "paused"}
    }
  ]
}
```

`servers` and `monitors` are always arrays (empty, never null). A family that
wasn't requested is omitted. IDs are strings, as today.

### Cleanup

`{"attempt_id": "…"}` → `{"attempt_id": "…", "deleted_servers": N,
"deleted_monitors": M}`. In one transaction:

1. Take the attempt lock. An unknown attempt becomes a tombstone; a cleaned
   attempt returns zero counts.
2. Lock the recorded servers and monitors (`FOR UPDATE`). A registry with
   more than 4 servers, more than 2 monitors or no account is invalid.
3. Every recorded server and monitor must still belong to the fixture
   account, else `ErrOwnershipChanged`.
4. If any `server_scores`, `log_scores` or `api_keys_monitors` row references
   a recorded monitor, or any `scorer_status.scorer_id` does, return
   `ErrMonitorInUse` ("fixture monitor has score, log-score or API key rows;
   cleanup refused"). The attempt stays uncleaned.
5. Delete server logs and emails, then servers (unchanged), then the
   recorded monitors (by recorded ID and fixture account).
6. Require that no recorded server or monitor remains, then tombstone.

`fixtureError` passes `ErrMonitorInUse` through like the other known errors.
The generated user and account stay behind, as they do today.

### Renames

| Before | After |
| --- | --- |
| `e2efixture/server_fixture.go` | `e2efixture/fixture.go` |
| `CreateServerFixture`, `CleanupServerFixture` | `CreateFixture`, `CleanupFixture` |
| `CreateServerFixtureRequest/Response`, `CleanupServerFixtureRequest/Response` | `CreateFixtureRequest/Response`, `CleanupFixtureRequest/Response` |
| `ServerFixtureServer` | `FixtureServer` (`ServerFixtureSpec` stays) |
| new | `MonitorFixtureSpec`, `MonitorFamilySpec`, `FixtureMonitor`, `FixtureMonitorFamily` |
| `ErrTransactionFailed` "server fixture transaction failed" | "fixture transaction failed" |
| email `server-fixture-<attempt>-<random>@example.com`, name "Server E2E fixture" | `fixture-<attempt>-<random>@example.com`, "E2E fixture" |
| `sql/server_test_fixtures.sql` and its queries (`LockServerTestFixture`, …) | `sql/e2e_fixtures.sql` (`LockE2EFixture`, …) |
| advisory lock keys `server-test-fixture:<attempt>`, `server-test-fixture-address-allocator` | `e2e-fixture:<attempt>`, `e2e-fixture-address-allocator` |
| `testhelpers.RemoveServerFixtureIdentity` | `testhelpers.RemoveFixtureIdentity` (reads `e2e_fixtures`) |
| `api e2e server-fixture create|cleanup` | `api e2e fixture create|cleanup` |

`testhelpers/CLAUDE.md` and the command help text follow the new names.

### Migration 029: e2e fixture tables

A Go migration registered in `newProvider` next to 027 and 028, following
027's shape (`validateDeploymentEnvironment`, devel-only body).

- **Up, devel:** if `server_test_fixtures` has a row with `cleaned_on IS
  NULL`, fail with the count. Otherwise drop `server_test_fixture_servers`
  and `server_test_fixtures`, then create the tables below from an embedded
  `schema_e2e_fixtures.sql`.
- **Up, test and prod:** no-op (the 027 tables never existed there).
- **Down, devel:** drop the three new tables and recreate the 027 tables empty
  from 027's embedded schema. Test and prod: no-op.
- sqlc reads every `.sql` file in `db/migrations/`, so it sees both schema
  files. With `omit_unused_structs`, the old tables generate nothing once no
  query uses them. goose ignores the unnumbered `schema_*.sql` files.

```sql
CREATE TABLE e2e_fixtures (
    attempt_id uuid PRIMARY KEY,
    user_id bigint,
    account_id bigint,
    created_on timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cleaned_on timestamptz,
    CHECK ((user_id IS NULL) = (account_id IS NULL)),
    CHECK (account_id IS NOT NULL OR cleaned_on IS NOT NULL)
);

CREATE TABLE e2e_fixture_servers (
    attempt_id uuid NOT NULL REFERENCES e2e_fixtures(attempt_id) ON DELETE CASCADE,
    ordinal smallint NOT NULL CHECK (ordinal BETWEEN 0 AND 3),
    server_id bigint NOT NULL,
    ip varchar(40) NOT NULL,
    PRIMARY KEY (attempt_id, ordinal),
    UNIQUE (server_id)
);

CREATE TABLE e2e_fixture_monitors (
    attempt_id uuid NOT NULL REFERENCES e2e_fixtures(attempt_id) ON DELETE CASCADE,
    ip_version smallint NOT NULL CHECK (ip_version IN (4, 6)),
    monitor_id bigint NOT NULL,
    ip varchar(40) NOT NULL,
    PRIMARY KEY (attempt_id, ip_version),
    UNIQUE (monitor_id)
);
```

### Go tests

Run through `scripts/test-integration` (tags `integration,e2efixtures`).

`e2efixture` integration tests (the existing server-fixture file, renamed):

- The eight existing server cases, against `CreateFixture`/`CleanupFixture`
  with `servers` only.
- Validation before mutation: an empty request; 2 monitors; a monitor with no
  family; statuses `deleted` and `bogus`; 5 servers alongside a monitor.
- Monitor-only fixture: row columns as in the table above, a valid session,
  zero `server_scores` rows for the monitor in every status, and the real
  `ListMonitors` handler listing it — with `account.flags` for a monitor-admin
  caller and without for the fixture owner.
- Dual-stack: equal statuses give one monitor with `combined_status` true and
  both IPs; different statuses give `combined_status` false with each
  family's status.
- Servers and a monitor in one attempt.
- Parallel creates allocate distinct monitor IPv4 addresses.
- Cleanup deletes servers and monitors, reports both counts, and is
  idempotent; an unknown attempt tombstones.
- A `server_scores` row referencing the fixture monitor makes cleanup return
  `ErrMonitorInUse` and leaves the attempt uncleaned; after the test removes
  the row, cleanup succeeds.
- A monitor moved to another account makes cleanup return
  `ErrOwnershipChanged`.

Command test (`cmd/e2e_integration_test.go`): JSON round trip for `fixture
create` with a monitor and `fixture cleanup`; `server-fixture` exits non-zero.

Migration tests (`db/migrations`): devel up with no uncleaned rows drops the
old tables and creates the new ones; devel up with an uncleaned row fails and
leaves the old tables; test and prod are no-ops; devel down restores the 027
tables.

Before committing: `gofumpt -w` on changed Go files, `go test ./...`, the
integration tests above, `go build -tags e2efixtures ./...`, and `git status`
to stage every file `make generate` or sqlc changed.

## E2E harness (this repo)

### `e2e/lib/fixtures.ts` (new)

Takes over the fixture half of `e2e/lib/servers.ts`:

- Types: `ServerSeed` and `FixtureServer` (moved unchanged), `MonitorStatus`
  (`"pending" | "testing" | "active" | "paused"`), `MonitorFamilySeed
  { status?: MonitorStatus }`, `MonitorSeed { ipv4?: MonitorFamilySeed;
  ipv6?: MonitorFamilySeed }`, `FixtureSeed { servers?: ServerSeed[];
  monitors?: MonitorSeed[] }`, `FixtureMonitorFamily { monitorId, idToken,
  ip, status }`, `FixtureMonitor { tlsName, ipv4?, ipv6? }`, and `Fixture`
  (today's `ServerFixture` plus `monitors`).
- Client-side validation mirrors the command's rules, and response
  validation checks count, order, family presence and statuses the same way
  `createFixture` checks servers today. The TS side sends an explicit status
  for every requested family.
- `test = base.extend<{ fixtures: Fixtures }>` with `fixtures.create(seed)`.
  Teardown keeps today's behavior: reverse order, `testInfo.attach` of
  `fixture-cleanup-results` (now with `monitorIds`) and, on failure,
  `fixture-cleanup-failures`, and a hard failure when the test otherwise
  passed.
- The JSON field validators (`record`, `stringField`, `idField`,
  `intField`, `boolField`) move to `e2e/lib/json.ts`, shared by
  `fixtures.ts`, `servers.ts` and `monitors.ts`.

`e2e/lib/servers.ts` keeps `getServer`, `getAccountAuditLogs`,
`serverDeleteUrl` and their types. The server specs
(`server-verification`, `server-deletion`, `server-netspeed`,
`server-scores-context`, `staff-search`, `staff-server-edit`) import `test`/`expect` from
`fixtures.ts` and call `fixtures.create({ servers: [...] })`.

### `e2e/lib/monitors.ts` (new)

- `listMonitors(sessionToken, accountToken)`: ConnectRPC
  `ntppool.monitor.v1.MonitorService/ListMonitors` with `X-Account`. Returns
  each monitor's `tlsName`, `account.idToken`, and `account.flags` as
  `undefined` when the key is absent, else its parsed booleans.
- `updateAccountMonitorConfig(sessionToken, accountToken, fields)`:
  `ntppool.account.v1.AccountService/UpdateAccountMonitorConfig`, sending
  only the fields given (`monitor_enabled`, `monitor_limit`,
  `monitors_per_server_limit`).
- `monitorListUrl(accountToken)` and `ADMIN_MONITOR_LIST_PATH`.
- The monitor-config form helpers now private to `monitor-config.spec.ts`
  (`monitorConfigUrl`, `swapMonitorConfig`, `openMonitorConfigEditor`) move
  here; `monitor-config.spec.ts` imports them.

### `e2e/tests/monitor-badges.spec.ts` (new)

Locating the account heading:

- Per-account list (`/manage/monitors?a=<token>`): the page has one account
  group; its `h2`.
- Admin list (`/manage/monitors/admin`): the `h2` containing
  `a[href*="a=<token>"]`.
- "No badges" means that `h2` contains no `.badge` and no `small`.

Pages are loaded with `expectCleanPage` and `bust()`. The tests don't assert
the absence of `.alert-warning`: the lists render a metrics warning when
devel Prometheus is unavailable, which is unrelated to badges.

**Test 1 — "monitor admin sees account flag badges in both monitor lists"**

1. `fixtures.create({ monitors: [{ ipv4: { status: "paused" } }] })`;
   `loginAs(context, uniqueTestEmail("monitor-badges-admin"),
   { grantMonitorAdmin: true })`.
2. Defaults: in both lists the fixture heading has no badges.
3. Form: open `/manage/account?a=<token>`, "Edit Configuration", check
   `monitor_enabled`, select `monitor_limit` `-1` and
   `monitors_per_server_limit` `3`, "Save Changes", see "Updated". In both
   lists: `.badge-success` "Bypass", `.badge-danger` "Disabled",
   `.badge-warning` "Per-Server" with title "Custom monitors per server
   limit: 3", and no `.badge-info`.
4. RPC: `updateAccountMonitorConfig(adminSession, token, { monitorLimit: 10
   })`. In both lists: Bypass, `.badge-info` "Custom Limit" with title
   "Custom monitor limit: 10", Per-Server, and no `.badge-danger`.

**Test 2 — "non-monitor-admin sees no badges, gets no flags, and can't open
the admin list"**

1. Fixture with one paused IPv4 monitor. `mintSession` a monitor admin (no
   browser) and set `monitor_enabled` true and `monitors_per_server_limit` 3
   by RPC, so an admin *would* see badges.
2. Positive control: `listMonitors(adminSession, token)` has `flags` on the
   fixture account's monitor.
3. `installSession(context, fixture.sessionToken)`. `/manage/monitors?a=<token>`
   is 200, shows the fixture monitor's card, and the heading has no badges.
4. `listMonitors(fixture.sessionToken, token)` lists the monitor with no
   `flags` key.
5. `page.request.get("/manage/monitors/admin")` is 403.

**Test 3 — "dual-stack monitor cards show per-family or combined status"**

1. Split fixture: `ipv4` pending, `ipv6` paused. Combined fixture: both
   paused. The suite never creates `active` or `testing` fixture monitors,
   which would pick up score rows from any concurrent server add on devel.
2. For each, `installSession` with the fixture's session and open
   `/manage/monitors?a=<token>`. Find the card whose header contains
   `fixture-<attemptId>`.
3. Split: both IPs visible; "Status pending" in the IPv4 address's list item,
   "Status paused" in the IPv6 one; exactly two "Status" badges in the card.
4. Combined: both IPs visible; exactly one "Status" badge, reading "Status
   paused".

The tests don't assert the "Connection" pill (see Out of scope).

### Docs

- `MANUAL_TEST_PLAN.md` §15: replace the "still needs a bounded monitor
  fixture" note with a short line naming the fixture, tick all seven rows
  with `(e2e/tests/monitor-badges.spec.ts → "<test name>")`.
- `MANUAL_TEST_PLAN.md`: new §16 "Dual-stack monitor cards" with two ticked
  rows (per-family statuses; combined status).
- `e2e/README.md`: "Server fixture deployment" becomes "Fixture deployment":
  the new command names and migration 029; monitor ranges and statuses; the
  warning that non-pending fixture monitors count toward devel's account and
  global monitor limits, that the admin status control must not be used on
  fixture monitors, and that an `active` or `testing` fixture monitor picks up
  a candidate score row from any server add on devel (both make cleanup
  refuse), with recovery SQL; the cleanup
  snippet calls `e2e fixture cleanup` and prints both counts; the acceptance
  command list adds `tests/monitor-badges.spec.ts`.
- `docs/superpowers/handoffs/2026-09-13-monitor-badge-fixture-design.md`:
  one status line pointing at this spec.
- Historical plans, specs and coverage reports stay as written.

### Harness checks

`npm run test:unit`, `npm run typecheck`, `npx playwright test --list`.

## Rollout

1. API repo: commit on `main` and push; Woodpecker builds
   `ntporg/api-dev:sha-<8>` with `GO_TAGS=e2efixtures`.
2. Right before deploying, rerun the read-only query for uncleaned
   `server_test_fixtures` rows on devel; clean any with the still-deployed
   `api e2e server-fixture cleanup`.
3. Bump `x-image-tag` in `~/src/flux-ntp/askntp/api/api-config-local.yaml`
   and run `./update-api` there. Never push flux-ntp for askntp.
4. Verify: `api migrate status` reports 29; `api e2e --help` lists `fixture`
   and not `server-fixture`; `\dt e2e_fixture*` shows three tables.
5. This repo, as commits (not pushed): the harness and spec changes, then the
   docs. The old harness can't create server fixtures after step 3.
6. Run against devel: the harness checks, then
   `npx playwright test tests/server-verification.spec.ts
   tests/server-deletion.spec.ts tests/server-netspeed.spec.ts
   tests/server-scores-context.spec.ts tests/staff-search.spec.ts
   tests/staff-server-edit.spec.ts tests/monitor-config.spec.ts
   tests/monitor-badges.spec.ts --project=manage
   --retries=0`, twice so the second run allocates fresh attempts.
7. Confirm afterwards (read-only) that no `e2e_fixtures` row is uncleaned and
   no `fixture-%` monitor remains.

The web app has no code change here. If a badge assertion fails on markup,
check whether the dev site runs the current templates before changing tests.

## Out of scope

- `metricsByAccount` with no TLS names: an empty, non-nil `names` slice makes
  `buildPromQLQuery` query every monitor. Fixture monitors always have a TLS
  name.
- Never-connected, non-pending monitors render an empty "Connection" pill:
  `formatMonitorList` only sets `LastSeenStatus` when `last_seen` is set, so
  `LastSeenInfo`'s "Never connected" branch never runs.
- Changing fixture monitor status through the admin status control.
- A purge command for old harness users and accounts.
- The §14 "(current)" option row, which needs an out-of-range stored limit.
