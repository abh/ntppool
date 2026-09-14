# E2E fixture monitors (Go API) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `api e2e server-fixture create|cleanup` with `api e2e fixture create|cleanup`, which also creates and removes a dual-stack-capable monitor, and deploy it to devel.

**Architecture:** A devel-only Go migration (029) swaps the migration-027 registry tables for `e2e_fixtures`, `e2e_fixture_servers` and `e2e_fixture_monitors`. The `e2efixture` package is renamed from server fixtures to fixtures, then gains monitor seeds (one logical monitor, per-family status) and monitor cleanup that refuses when score/log-score/API-key rows exist. The `cmd` e2e plugin exposes it.

**Tech Stack:** Go, PostgreSQL, sqlc (`go tool sqlc`), mockery (`go generate ./ntpdb/`), goose Go migrations, kong CLI, testify.

**Spec:** `docs/superpowers/specs/2026-09-13-monitor-badge-fixture-design.md` (in `~/src/ntppool`)

## Global Constraints

- Repo: `~/src/go/ntp/api`, branch `main`. All paths below are relative to it unless absolute.
- The working tree has unrelated modified/untracked files (for example `plans/active/perl-model-migration-status.md`, `.air.toml`, `devel/`). Never stage them. Never `git add -A`, `git add .` or `git commit -a`; stage explicit paths. Before each commit run `git status` and `git diff --staged` and stop if the staged set isn't exactly this task's files.
- Before each commit: `gofumpt -w` on changed `.go` files, `git diff --check` clean (no trailing whitespace), and stage every generated file (`ntpdb/*.sql.go`, `ntpdb/querier.go`, `ntpdb/otel.go`, `ntpdb/mocks.go`).
- Integration tests only through `./scripts/test-integration [package] [pattern]` (tags `integration,e2efixtures`). Never set env vars inline on test commands.
- Test emails at `example.com`; IPv4 from RFC 5737 ranges, IPv6 from `2001:db8::/32`.
- Don't mask errors: return them; no fallbacks except the spec's "empty status means pending".
- Commit messages: Conventional Commits, no "comprehensive"/"business".
- Monitor fixture IPv4 range: `192.0.2.1`–`192.0.2.254`. Server fixture IPv4 ranges stay `198.51.100.0/24`, `203.0.113.0/24`.
- Fixture monitor TLS name: `fixture-<attempt_id>.devel.mon.ntppool.dev` (`"fixture-" + attempt + "." + depenv.DeployDevel.MonitorDomain()`).
- Monitor statuses accepted: `pending`, `testing`, `active`, `paused`; empty = `pending`.
- Fixture user email: `fixture-<attempt>-<random uuid>@example.com`, name `E2E fixture`.

---

### Task 1: Migration 029 — e2e fixture tables

**Files:**
- Create: `db/migrations/schema_e2e_fixtures.sql`
- Create: `db/migrations/029_e2e_fixtures.go`
- Create: `db/migrations/e2e_fixtures_integration_test.go`
- Modify: `db/migrations/migrations.go` (the `goose.WithGoMigrations(...)` call in `newProvider`)
- Modify: `db/migrations/schema_server_test_fixtures.sql` (comment only)

**Interfaces:**
- Consumes: `serverTestFixturesSchema` (027), `validateDeploymentEnvironment`, test helpers `migrationTestTransaction`, `migrationTableExists` (in `server_test_fixtures_integration_test.go`).
- Produces: `e2eFixturesSchema string`, `e2eFixturesMigration(depenv.DeploymentEnvironment) *goose.Migration`, `migrateE2EFixturesUp/Down(ctx, *sql.Tx, depenv.DeploymentEnvironment) error`; tables `e2e_fixtures`, `e2e_fixture_servers`, `e2e_fixture_monitors`.

- [ ] **Step 1: Write the failing test** — `db/migrations/e2e_fixtures_integration_test.go`:

```go
//go:build integration

package migrations

import (
	"context"
	"database/sql"
	"strings"
	"testing"

	"go.ntppool.org/common/config/depenv"
)

var (
	e2eFixtureTables        = []string{"e2e_fixtures", "e2e_fixture_servers", "e2e_fixture_monitors"}
	serverTestFixtureTables = []string{"server_test_fixtures", "server_test_fixture_servers"}
)

func requireMigrationTables(t *testing.T, tx *sql.Tx, tables []string, want bool) {
	t.Helper()
	for _, table := range tables {
		if got := migrationTableExists(t, tx, table); got != want {
			t.Errorf("table %s exists=%t, want %t", table, got, want)
		}
	}
}

func TestE2EFixturesMigrationUpByEnvironment(t *testing.T) {
	tests := []struct {
		name        string
		environment depenv.DeploymentEnvironment
		seedOld     bool
		wantNew     bool
		wantOld     bool
		wantError   bool
	}{
		{name: "devel", environment: depenv.DeployDevel, seedOld: true, wantNew: true},
		{name: "test", environment: depenv.DeployTest},
		{name: "prod", environment: depenv.DeployProd},
		{name: "undefined", environment: depenv.DeployUndefined, seedOld: true, wantOld: true, wantError: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			tx := migrationTestTransaction(t)
			if tt.seedOld {
				if _, err := tx.ExecContext(ctx, serverTestFixturesSchema); err != nil {
					t.Fatalf("seed 027 tables: %v", err)
				}
			}
			err := migrateE2EFixturesUp(ctx, tx, tt.environment)
			if tt.wantError {
				if err == nil {
					t.Fatal("expected invalid deployment environment to fail")
				}
			} else if err != nil {
				t.Fatalf("migration up: %v", err)
			}
			requireMigrationTables(t, tx, e2eFixtureTables, tt.wantNew)
			requireMigrationTables(t, tx, serverTestFixtureTables, tt.wantOld)
		})
	}
}

func TestE2EFixturesMigrationRefusesUncleanedAttempts(t *testing.T) {
	ctx := context.Background()
	tx := migrationTestTransaction(t)
	if _, err := tx.ExecContext(ctx, serverTestFixturesSchema); err != nil {
		t.Fatalf("seed 027 tables: %v", err)
	}
	// A tombstone doesn't block the migration; an uncleaned attempt does.
	if _, err := tx.ExecContext(ctx, `INSERT INTO server_test_fixtures (attempt_id, cleaned_on) VALUES ('00000000-0000-4000-8000-000000000001', CURRENT_TIMESTAMP)`); err != nil {
		t.Fatalf("insert tombstone: %v", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO server_test_fixtures (attempt_id, user_id, account_id) VALUES ('00000000-0000-4000-8000-000000000002', 1, 1)`); err != nil {
		t.Fatalf("insert uncleaned attempt: %v", err)
	}
	err := migrateE2EFixturesUp(ctx, tx, depenv.DeployDevel)
	if err == nil || !strings.Contains(err.Error(), "1 server test fixture attempt") {
		t.Fatalf("migration up error = %v, want a refusal naming 1 uncleaned attempt", err)
	}
	requireMigrationTables(t, tx, serverTestFixtureTables, true)
	requireMigrationTables(t, tx, e2eFixtureTables, false)
}

func TestE2EFixturesMigrationTombstonesOnlyMigrate(t *testing.T) {
	ctx := context.Background()
	tx := migrationTestTransaction(t)
	if _, err := tx.ExecContext(ctx, serverTestFixturesSchema); err != nil {
		t.Fatalf("seed 027 tables: %v", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO server_test_fixtures (attempt_id, cleaned_on) VALUES ('00000000-0000-4000-8000-000000000003', CURRENT_TIMESTAMP)`); err != nil {
		t.Fatalf("insert tombstone: %v", err)
	}
	if err := migrateE2EFixturesUp(ctx, tx, depenv.DeployDevel); err != nil {
		t.Fatalf("migration up: %v", err)
	}
	requireMigrationTables(t, tx, e2eFixtureTables, true)
	requireMigrationTables(t, tx, serverTestFixtureTables, false)
}

func TestE2EFixturesMigrationDownByEnvironment(t *testing.T) {
	tests := []struct {
		name        string
		environment depenv.DeploymentEnvironment
		wantNew     bool
		wantOld     bool
		wantError   bool
	}{
		{name: "devel", environment: depenv.DeployDevel, wantOld: true},
		{name: "test", environment: depenv.DeployTest, wantNew: true},
		{name: "prod", environment: depenv.DeployProd, wantNew: true},
		{name: "undefined", environment: depenv.DeployUndefined, wantNew: true, wantError: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			tx := migrationTestTransaction(t)
			if _, err := tx.ExecContext(ctx, e2eFixturesSchema); err != nil {
				t.Fatalf("seed e2e fixture tables: %v", err)
			}
			err := migrateE2EFixturesDown(ctx, tx, tt.environment)
			if tt.wantError {
				if err == nil {
					t.Fatal("expected invalid deployment environment to fail")
				}
			} else if err != nil {
				t.Fatalf("migration down: %v", err)
			}
			requireMigrationTables(t, tx, e2eFixtureTables, tt.wantNew)
			requireMigrationTables(t, tx, serverTestFixtureTables, tt.wantOld)
		})
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/test-integration ./db/migrations/ "TestE2EFixturesMigration"`
Expected: build failure — `undefined: migrateE2EFixturesUp`, `undefined: e2eFixturesSchema`.

- [ ] **Step 3: Write the schema** — `db/migrations/schema_e2e_fixtures.sql`:

```sql
-- Schema input for sqlc. Migration 029 applies these tables only in devel,
-- replacing the migration-027 server_test_fixtures tables.
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

In `db/migrations/schema_server_test_fixtures.sql`, replace the first comment line with:

```sql
-- Schema input for sqlc. Migration 027 applies these tables only in devel;
-- migration 029 replaces them with schema_e2e_fixtures.sql.
```

- [ ] **Step 4: Write the migration** — `db/migrations/029_e2e_fixtures.go`:

```go
package migrations

import (
	"context"
	"database/sql"
	_ "embed"
	"fmt"

	"github.com/pressly/goose/v3"
	"go.ntppool.org/common/config/depenv"
)

// SQLC reads this schema for query types even though the live tables only
// exist in devel databases.
//
//go:embed schema_e2e_fixtures.sql
var e2eFixturesSchema string

// e2eFixturesMigration replaces the migration-027 server fixture registry with
// the e2e fixture registry, which also records monitors. Devel only.
func e2eFixturesMigration(environment depenv.DeploymentEnvironment) *goose.Migration {
	return goose.NewGoMigration(
		29,
		&goose.GoFunc{RunTx: func(ctx context.Context, tx *sql.Tx) error {
			return migrateE2EFixturesUp(ctx, tx, environment)
		}},
		&goose.GoFunc{RunTx: func(ctx context.Context, tx *sql.Tx) error {
			return migrateE2EFixturesDown(ctx, tx, environment)
		}},
	)
}

// migrateE2EFixturesUp refuses while an old attempt is uncleaned: dropping its
// registry row would leave its servers with no command able to remove them.
func migrateE2EFixturesUp(ctx context.Context, tx *sql.Tx, environment depenv.DeploymentEnvironment) error {
	if err := validateDeploymentEnvironment(environment); err != nil {
		return err
	}
	if environment != depenv.DeployDevel {
		return nil
	}
	var uncleaned int
	if err := tx.QueryRowContext(ctx, `SELECT count(*) FROM server_test_fixtures WHERE cleaned_on IS NULL`).Scan(&uncleaned); err != nil {
		return fmt.Errorf("count uncleaned server test fixture attempts: %w", err)
	}
	if uncleaned > 0 {
		return fmt.Errorf("%d server test fixture attempt(s) are not cleaned up; clean them with the previous api-dev image's `api e2e server-fixture cleanup` before migrating", uncleaned)
	}
	if _, err := tx.ExecContext(ctx, `
		DROP TABLE server_test_fixture_servers;
		DROP TABLE server_test_fixtures;
	`); err != nil {
		return fmt.Errorf("drop server test fixture tables: %w", err)
	}
	if _, err := tx.ExecContext(ctx, e2eFixturesSchema); err != nil {
		return fmt.Errorf("create e2e fixture tables: %w", err)
	}
	return nil
}

func migrateE2EFixturesDown(ctx context.Context, tx *sql.Tx, environment depenv.DeploymentEnvironment) error {
	if err := validateDeploymentEnvironment(environment); err != nil {
		return err
	}
	if environment != depenv.DeployDevel {
		return nil
	}
	if _, err := tx.ExecContext(ctx, `
		DROP TABLE e2e_fixture_monitors;
		DROP TABLE e2e_fixture_servers;
		DROP TABLE e2e_fixtures;
	`); err != nil {
		return fmt.Errorf("drop e2e fixture tables: %w", err)
	}
	if _, err := tx.ExecContext(ctx, serverTestFixturesSchema); err != nil {
		return fmt.Errorf("recreate server test fixture tables: %w", err)
	}
	return nil
}
```

In `db/migrations/migrations.go`, change the Go migrations list to:

```go
		goose.WithGoMigrations(
			serverTestFixturesMigration(environment),
			deleteTestSessionKeysMigration(),
			e2eFixturesMigration(environment),
		),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./scripts/test-integration ./db/migrations/`
Expected: PASS, including the four `TestE2EFixturesMigration*` tests and the existing 027/028 tests.

- [ ] **Step 6: Apply 029 to the local test database and check sqlc**

Run: `./scripts/test-db.sh start`
Expected: "Database migrations completed" (the database exists; pending migration 29 applies).
Run: `psql "postgres://ntppool:test123@localhost:5432/ntppool_test?sslmode=disable" -c '\dt e2e_fixture*'`
Expected: `e2e_fixture_monitors`, `e2e_fixture_servers`, `e2e_fixtures`.
Run: `go tool sqlc compile`
Expected: no errors.

The `e2efixture` integration tests now fail against this database (their tables are gone) until Task 2 lands. Don't commit Task 1 alone to a pushed branch; the push happens in Task 5.

- [ ] **Step 7: Commit**

```bash
gofumpt -w db/migrations/029_e2e_fixtures.go db/migrations/e2e_fixtures_integration_test.go db/migrations/migrations.go
git diff --check
git add db/migrations/schema_e2e_fixtures.sql db/migrations/029_e2e_fixtures.go db/migrations/e2e_fixtures_integration_test.go db/migrations/migrations.go db/migrations/schema_server_test_fixtures.sql
git status && git diff --staged --stat
git commit -m "feat(migrations): replace server fixture tables with e2e fixture tables"
```

---

### Task 2: Rename server fixtures to e2e fixtures (servers only)

A pure rename: behavior, validation (1–4 servers) and JSON fields stay as they are, except the command name, table names, lock keys, the fixture email/name and error text.

**Files:**
- Rename: `sql/server_test_fixtures.sql` → `sql/e2e_fixtures.sql` (rewrite contents below)
- Delete: `ntpdb/server_test_fixtures.sql.go` (sqlc regenerates `ntpdb/e2e_fixtures.sql.go`)
- Regenerate: `ntpdb/querier.go`, `ntpdb/otel.go`, `ntpdb/mocks.go`
- Rename: `e2efixture/server_fixture.go` → `e2efixture/fixture.go`
- Rename: `e2efixture/server_fixture_integration_test.go` → `e2efixture/fixture_integration_test.go`
- Modify: `testhelpers/integration_cleanup.go` (`RemoveServerFixtureIdentity`, ~line 1118)
- Modify: `testhelpers/CLAUDE.md` ("Server fixture integration tests" section, ~line 414)
- Modify: `cmd/e2e.go`, `cmd/e2e_test.go`, `cmd/e2e_integration_test.go`

**Interfaces:**
- Consumes: Task 1 tables.
- Produces (used by Tasks 3–4):
  - ntpdb: `LockE2EFixture(ctx, attemptID string) error`, `LockE2EFixtureAllocator(ctx) error`, `GetE2EFixture(ctx, pgtype.UUID)`, `CreateE2EFixtureRegistry(ctx, CreateE2EFixtureRegistryParams)`, `TombstoneE2EFixture(ctx, pgtype.UUID)`, `E2EFixtureServerIPInUse(ctx, ip string) (pgtype.Bool, error)`, `InsertE2EFixtureServer`, `RecordE2EFixtureServer`, `InsertE2EFixtureVerification`, `LockE2EFixtureServers`, `DeleteE2EFixtureServerLogs`, `DeleteE2EFixtureServerEmails`, `DeleteE2EFixtureServers`, `CountE2EFixtureServers`.
  - e2efixture: `CreateFixture(ctx, ntpdb.QuerierTx, CreateFixtureRequest) (*CreateFixtureResponse, error)`, `CleanupFixture(ctx, ntpdb.QuerierTx, CleanupFixtureRequest) (*CleanupFixtureResponse, error)`, types `CreateFixtureRequest`, `CreateFixtureResponse`, `CleanupFixtureRequest`, `CleanupFixtureResponse`, `FixtureServer`, `ServerFixtureSpec` (unchanged); errors unchanged in name.
  - testhelpers: `RemoveFixtureIdentity(t *testing.T, ctx context.Context, db *pgxpool.Pool, attemptID string)`.
  - CLI: `api e2e fixture create`, `api e2e fixture cleanup`.

- [ ] **Step 1: Update the tests first (they define the new names)**

```bash
git mv e2efixture/server_fixture_integration_test.go e2efixture/fixture_integration_test.go
```

In `e2efixture/fixture_integration_test.go` apply exactly these replacements (every occurrence):

| Old | New |
| --- | --- |
| `TestServerFixtureIntegration` | `TestFixtureIntegration` |
| `e2efixture.CleanupServerFixtureRequest` | `e2efixture.CleanupFixtureRequest` |
| `e2efixture.CleanupServerFixture(` | `e2efixture.CleanupFixture(` |
| `e2efixture.CreateServerFixtureRequest` | `e2efixture.CreateFixtureRequest` |
| `e2efixture.CreateServerFixtureResponse` | `e2efixture.CreateFixtureResponse` |
| `e2efixture.CreateServerFixture(` | `e2efixture.CreateFixture(` |
| `testhelpers.RemoveServerFixtureIdentity` | `testhelpers.RemoveFixtureIdentity` |
| `server_test_fixture_servers` | `e2e_fixture_servers` |
| `server_test_fixtures` | `e2e_fixtures` |
| `"server-fixture-"` | `"fixture-"` |

In `cmd/e2e_test.go`, replace the two `server-fixture` arg lists with `{"e2e", "fixture", "create"}` and `{"e2e", "fixture", "cleanup"}`, and append to `TestE2ECommandsRegistered` after the loop:

```go
	if _, err := parser.Parse([]string{"e2e", "server-fixture", "create"}); err == nil {
		t.Error("e2e server-fixture create still parses; the command was renamed to e2e fixture")
	}
```

In `cmd/e2e_integration_test.go`:
- subtest name `"server fixture create and cleanup"` → `"fixture create and cleanup"`;
- `e2efixture.CleanupServerFixture(` → `e2efixture.CleanupFixture(`, `e2efixture.CleanupServerFixtureRequest` → `e2efixture.CleanupFixtureRequest`, `testhelpers.RemoveServerFixtureIdentity` → `testhelpers.RemoveFixtureIdentity`;
- `"e2e", "server-fixture", "create"` → `"e2e", "fixture", "create"` and `"e2e", "server-fixture", "cleanup"` → `"e2e", "fixture", "cleanup"` (including the `"invalid attempt"` bad-input row).

- [ ] **Step 2: Run the unit command test to verify it fails**

Run: `go test -tags e2efixtures ./cmd/ -run TestE2ECommandsRegistered`
Expected: FAIL — `parse [e2e fixture create]: unexpected argument fixture`.

- [ ] **Step 3: Rewrite the SQL**

```bash
git mv sql/server_test_fixtures.sql sql/e2e_fixtures.sql
git rm ntpdb/server_test_fixtures.sql.go
```

`git mv` and `git rm` stage the rename and the deletion; the commit step only `git add`s paths that exist.

Replace the contents of `sql/e2e_fixtures.sql` with:

```sql
-- name: LockE2EFixture :exec
SELECT pg_advisory_xact_lock(hashtextextended('e2e-fixture:' || sqlc.arg(attempt_id)::text, 0));

-- name: LockE2EFixtureAllocator :exec
SELECT pg_advisory_xact_lock(hashtextextended('e2e-fixture-address-allocator', 0));

-- name: GetE2EFixture :one
SELECT * FROM e2e_fixtures WHERE attempt_id = $1;

-- name: CreateE2EFixtureRegistry :exec
INSERT INTO e2e_fixtures (attempt_id, user_id, account_id)
VALUES ($1, $2, $3);

-- name: TombstoneE2EFixture :exec
INSERT INTO e2e_fixtures (attempt_id, cleaned_on)
VALUES ($1, CURRENT_TIMESTAMP)
ON CONFLICT (attempt_id) DO UPDATE SET cleaned_on = CURRENT_TIMESTAMP;

-- name: E2EFixtureServerIPInUse :one
SELECT EXISTS (SELECT 1 FROM servers existing WHERE existing.ip = sqlc.arg(ip)::varchar) OR EXISTS (
    SELECT 1 FROM e2e_fixture_servers s
    JOIN e2e_fixtures f USING (attempt_id)
    WHERE s.ip = sqlc.arg(ip)::varchar AND f.cleaned_on IS NULL
) AS in_use;

-- name: InsertE2EFixtureServer :one
INSERT INTO servers (ip, ip_version, account_id, user_id, netspeed,
                     netspeed_target, in_pool, in_server_list, created_on, deletion_on)
VALUES (sqlc.arg(ip), sqlc.arg(ip_version), sqlc.arg(account_id), sqlc.arg(user_id),
        sqlc.arg(netspeed), sqlc.arg(netspeed), 0, 0, CURRENT_TIMESTAMP,
        sqlc.narg(deletion_on)) RETURNING *;

-- name: RecordE2EFixtureServer :exec
INSERT INTO e2e_fixture_servers (attempt_id, ordinal, server_id, ip)
VALUES ($1, $2, $3, $4);

-- name: InsertE2EFixtureVerification :exec
INSERT INTO server_verifications (server_id, user_id, verified_on, token, created_on)
VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP);

-- name: LockE2EFixtureServers :many
SELECT s.id, s.account_id FROM servers s
JOIN e2e_fixture_servers f ON f.server_id = s.id
WHERE f.attempt_id = $1 ORDER BY s.id FOR UPDATE OF s;

-- name: DeleteE2EFixtureServerLogs :exec
DELETE FROM logs WHERE server_id IN (
    SELECT server_id FROM e2e_fixture_servers WHERE attempt_id = $1
);

-- name: DeleteE2EFixtureServerEmails :exec
DELETE FROM emails WHERE server_id IN (
    SELECT server_id FROM e2e_fixture_servers WHERE attempt_id = $1
);

-- name: DeleteE2EFixtureServers :execrows
DELETE FROM servers WHERE id IN (
    SELECT server_id FROM e2e_fixture_servers WHERE attempt_id = $1
) AND account_id = $2;

-- name: CountE2EFixtureServers :one
SELECT count(*) FROM servers s JOIN e2e_fixture_servers f ON f.server_id = s.id
WHERE f.attempt_id = $1;
```

Run: `make sqlc && go generate ./ntpdb/`
Expected: `ntpdb/e2e_fixtures.sql.go` created; `git status` shows `ntpdb/querier.go`, `ntpdb/otel.go`, `ntpdb/mocks.go` modified. `grep -c ServerTestFixture ntpdb/*.go` prints 0 for every file.

- [ ] **Step 4: Rename the package code**

```bash
git mv e2efixture/server_fixture.go e2efixture/fixture.go
```

In `e2efixture/fixture.go` apply exactly these replacements:

| Old | New |
| --- | --- |
| `"invalid server fixture request"` | `"invalid fixture request"` |
| `"server fixture transaction failed"` (both the `ErrTransactionFailed` text and the log line in `fixtureError`) | `"fixture transaction failed"` |
| `ServerFixtureServer` (type and uses) | `FixtureServer` |
| `CreateServerFixtureRequest` / `CreateServerFixtureResponse` | `CreateFixtureRequest` / `CreateFixtureResponse` |
| `CleanupServerFixtureRequest` / `CleanupServerFixtureResponse` | `CleanupFixtureRequest` / `CleanupFixtureResponse` |
| `func CreateServerFixture` / `func CleanupServerFixture` | `func CreateFixture` / `func CleanupFixture` |
| `` `api e2e server-fixture create` `` / `` `api e2e server-fixture cleanup` `` in doc comments | `` `api e2e fixture create` `` / `` `api e2e fixture cleanup` `` |
| `q.LockServerTestFixture(` | `q.LockE2EFixture(` |
| `q.GetServerTestFixture(` | `q.GetE2EFixture(` |
| `q.LockServerTestFixtureAllocator(` | `q.LockE2EFixtureAllocator(` |
| `q.CreateServerTestFixtureRegistry(ctx, ntpdb.CreateServerTestFixtureRegistryParams{` | `q.CreateE2EFixtureRegistry(ctx, ntpdb.CreateE2EFixtureRegistryParams{` |
| `q.InsertServerTestFixtureServer(ctx, ntpdb.InsertServerTestFixtureServerParams{` | `q.InsertE2EFixtureServer(ctx, ntpdb.InsertE2EFixtureServerParams{` |
| `q.RecordServerTestFixtureServer(ctx, ntpdb.RecordServerTestFixtureServerParams{` | `q.RecordE2EFixtureServer(ctx, ntpdb.RecordE2EFixtureServerParams{` |
| `ntpdb.InsertServerTestFixtureVerificationParams` / `q.InsertServerTestFixtureVerification(` | `ntpdb.InsertE2EFixtureVerificationParams` / `q.InsertE2EFixtureVerification(` |
| `q.ServerTestFixtureIPInUse(` | `q.E2EFixtureServerIPInUse(` |
| `q.TombstoneServerTestFixture(` | `q.TombstoneE2EFixture(` |
| `q.LockServerTestFixtureServers(` | `q.LockE2EFixtureServers(` |
| `q.DeleteServerTestFixtureLogs(` / `q.DeleteServerTestFixtureEmails(` | `q.DeleteE2EFixtureServerLogs(` / `q.DeleteE2EFixtureServerEmails(` |
| `q.DeleteServerTestFixtureServers(ctx, ntpdb.DeleteServerTestFixtureServersParams{` | `q.DeleteE2EFixtureServers(ctx, ntpdb.DeleteE2EFixtureServersParams{` |
| `q.CountServerTestFixtureServers(` | `q.CountE2EFixtureServers(` |
| `fmt.Sprintf("server-fixture-%s-%s@example.com", ...)` | `fmt.Sprintf("fixture-%s-%s@example.com", ...)` |
| `authsvc.CreateUser(ctx, q, email, "Server E2E fixture")` | `authsvc.CreateUser(ctx, q, email, "E2E fixture")` |

Also rename the `Servers []ServerFixtureServer` field type in `CreateFixtureResponse` to `[]FixtureServer` (covered by the table) and update `// CreateServerFixture provisions ...` / `// CleanupServerFixture uses ...` doc comments to the new function names.

- [ ] **Step 5: Rename the testhelper**

In `testhelpers/integration_cleanup.go`, replace the `RemoveServerFixtureIdentity` function and its doc comment with:

```go
// RemoveFixtureIdentity deletes a cleaned e2e fixture attempt's registry row
// and the user and account the attempt created. Call it after
// e2efixture.CleanupFixture has removed the attempt's servers and monitors.
// The IDs come from the attempt registry, which survives a lost create
// response, so no email-pattern sweep is needed; fixture emails
// (fixture-<attempt>-<random>@example.com) are disjoint from
// e2efixture.CreateSession and other integration suites.
func RemoveFixtureIdentity(t *testing.T, ctx context.Context, db *pgxpool.Pool, attemptID string) {
	t.Helper()
	allocation := TestIDAllocation{TestName: "fixture_identity"}
	var userID, accountID int64
	if err := db.QueryRow(ctx,
		"SELECT COALESCE(user_id, 0), COALESCE(account_id, 0) FROM e2e_fixtures WHERE attempt_id = $1",
		attemptID,
	).Scan(&userID, &accountID); err != nil {
		t.Fatalf("read fixture registry for attempt %s: %v", attemptID, err)
	}
	if userID != 0 {
		allocation.UserIDs = []uint32{uint32(userID)}
		allocation.AccountIDs = []uint32{uint32(accountID)}
	}
	if _, err := db.Exec(ctx, "DELETE FROM e2e_fixtures WHERE attempt_id = $1", attemptID); err != nil {
		t.Fatalf("delete fixture registry for attempt %s: %v", attemptID, err)
	}
	CleanupIntegrationTestData(t, ctx, db, allocation)
}
```

In `testhelpers/CLAUDE.md`, replace the "### Server fixture integration tests" section with:

```markdown
### E2E fixture integration tests

`RemoveFixtureIdentity()` uses dynamically recorded user/account IDs; no
fixed ID range or broad email sweep. Identities use the dedicated
`fixture-<attempt>-<random>@example.com` namespace. Register teardown
before create. In it, call `e2efixture.CleanupFixture` for the attempt,
then `RemoveFixtureIdentity`, which reads the exact identity IDs from the
durable attempt registry (`e2e_fixtures`), removes the registry row and passes
the IDs to `CleanupIntegrationTestData`. This keeps concurrent runs isolated
and recovers IDs after a discarded create response.
```

- [ ] **Step 6: Rename the command**

In `cmd/e2e.go`, replace the `e2eCmd` struct through the `Run` methods for the server fixture commands with:

```go
type e2eCmd struct {
	Session e2eSessionCmd `cmd:"" help:"create a new user (or, with existing_user, reuse one) and mint a browser session"`
	Fixture e2eFixtureCmd `cmd:"" help:"create or clean up isolated server and monitor fixtures"`
}

type e2eFixtureCmd struct {
	Create  e2eFixtureCreateCmd  `cmd:"" help:"create a fixture user, account and 1 to 4 servers"`
	Cleanup e2eFixtureCleanupCmd `cmd:"" help:"remove a fixture attempt's servers"`
}

type (
	e2eSessionCmd        struct{}
	e2eFixtureCreateCmd  struct{}
	e2eFixtureCleanupCmd struct{}
)

func (c *e2eSessionCmd) Run(ctx context.Context, parent *ApiCmd) error {
	return runE2E(ctx, parent.Config, e2efixture.CreateSession)
}

func (c *e2eFixtureCreateCmd) Run(ctx context.Context, parent *ApiCmd) error {
	return runE2E(ctx, parent.Config, e2efixture.CreateFixture)
}

func (c *e2eFixtureCleanupCmd) Run(ctx context.Context, parent *ApiCmd) error {
	return runE2E(ctx, parent.Config, e2efixture.CleanupFixture)
}
```

- [ ] **Step 7: Verify no old names remain and everything builds**

Run: `grep -rn "ServerTestFixture\|server_test_fixture\|server-fixture\|ServerFixtureServer\|CreateServerFixture\|CleanupServerFixture\|RemoveServerFixtureIdentity" --include='*.go' --include='*.sql' --include='*.md' . | grep -v "^./db/migrations/\|^./plans/\|^./docs/"`
Expected: no output. (Migration files keep the old table names on purpose; the `cmd/e2e_test.go` assertion that `server-fixture` no longer parses is the one allowed hit — if it's listed, that line alone is fine.)
Run: `go build ./... && go build -tags e2efixtures ./... && go vet -tags integration,e2efixtures ./e2efixture/ ./cmd/ ./testhelpers/ ./db/migrations/`
Expected: no output.

- [ ] **Step 8: Run the tests**

Run: `go test -tags e2efixtures ./cmd/`
Expected: PASS.
Run: `./scripts/test-integration ./e2efixture/`
Expected: PASS (all eight server subtests plus session tests).
Run: `./scripts/test-integration ./cmd/ TestE2ECommands`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
gofumpt -w e2efixture/fixture.go e2efixture/fixture_integration_test.go testhelpers/integration_cleanup.go cmd/e2e.go cmd/e2e_test.go cmd/e2e_integration_test.go
git diff --check
git add sql/e2e_fixtures.sql ntpdb/e2e_fixtures.sql.go ntpdb/querier.go ntpdb/otel.go ntpdb/mocks.go e2efixture/fixture.go e2efixture/fixture_integration_test.go testhelpers/integration_cleanup.go testhelpers/CLAUDE.md cmd/e2e.go cmd/e2e_test.go cmd/e2e_integration_test.go
git status && git diff --staged --stat
# Expected staged: renames sql/server_test_fixtures.sql -> sql/e2e_fixtures.sql,
# e2efixture/server_fixture.go -> e2efixture/fixture.go,
# e2efixture/server_fixture_integration_test.go -> e2efixture/fixture_integration_test.go;
# deletion of ntpdb/server_test_fixtures.sql.go; the other paths above.
git commit -m "refactor(e2e): rename api e2e server-fixture to api e2e fixture"
```

---

### Task 3: Create monitors in e2e fixtures

**Files:**
- Modify: `sql/e2e_fixtures.sql` (append)
- Regenerate: `ntpdb/e2e_fixtures.sql.go`, `ntpdb/querier.go`, `ntpdb/otel.go`, `ntpdb/mocks.go`
- Modify: `e2efixture/fixture.go`
- Modify: `e2efixture/fixture_integration_test.go`
- Modify: `cmd/e2e.go` (help text)

**Interfaces:**
- Consumes: Task 2 names.
- Produces:
  - ntpdb: `E2EFixtureMonitorIPInUse(ctx, ip string) (pgtype.Bool, error)`, `InsertE2EFixtureMonitor(ctx, InsertE2EFixtureMonitorParams) (int64, error)`, `RecordE2EFixtureMonitor(ctx, RecordE2EFixtureMonitorParams) error`.
  - e2efixture: `MonitorFamilySpec{Status string}`, `MonitorFixtureSpec{IPv4, IPv6 *MonitorFamilySpec}`, `CreateFixtureRequest.Monitors []MonitorFixtureSpec`, `FixtureMonitorFamily{MonitorID int64 (json string), IDToken, IP, Status string}`, `FixtureMonitor{TLSName string; IPv4, IPv6 *FixtureMonitorFamily}`, `CreateFixtureResponse.Monitors []FixtureMonitor`.
  - JSON: request `monitors: [{"ipv4": {"status": "active"}, "ipv6": {...}}]`; response `monitors: [{"tls_name", "ipv4": {"monitor_id": "<digits>", "id_token", "ip", "status"}, "ipv6": {...}}]`, unrequested family omitted, `servers`/`monitors` always arrays.

- [ ] **Step 1: Write the failing tests** — in `e2efixture/fixture_integration_test.go`:

Add imports `"connectrpc.com/connect"`, `"github.com/jackc/pgx/v5/pgtype"`, `monitorv1 "go.ntppool.org/api/gen/ntppool/monitor/v1"`, `"go.ntppool.org/api/server/api/monitoradmin"`, `"go.ntppool.org/api/server/api/sessions"`, `"go.ntppool.org/api/server/base"`, `"go.ntppool.org/common/config/depenv"`.

After `type spec = e2efixture.ServerFixtureSpec` add:

```go
	type monitorSpec = e2efixture.MonitorFixtureSpec
	type family = e2efixture.MonitorFamilySpec
	createRequest := func(t *testing.T, req e2efixture.CreateFixtureRequest) *e2efixture.CreateFixtureResponse {
		t.Helper()
		response, err := e2efixture.CreateFixture(ctx, q, req)
		require.NoError(t, err)
		return response
	}
	tlsName := func(id string) string { return "fixture-" + id + ".devel.mon.ntppool.dev" }
	// listMonitors calls the real ListMonitors handler as the fixture's own user,
	// optionally with the monitor_admin privilege.
	listMonitors := func(t *testing.T, fixture *e2efixture.CreateFixtureResponse, monitorAdmin bool) []*monitorv1.Monitor {
		t.Helper()
		svc, err := monitoradmin.NewMonitorService(base.BaseAPI{DB: db, Env: depenv.DeployDevel})
		require.NoError(t, err)
		user := ntpdb.UserX{User: ntpdb.User{ID: fixture.UserID}}
		if monitorAdmin {
			user.Privilege.MonitorAdmin = pgtype.Bool{Bool: true, Valid: true}
		}
		reqCtx := sessions.SetTestAccountInContext(sessions.SetTestUserInContext(ctx, user), ntpdb.Account{ID: fixture.AccountID})
		resp, err := svc.ListMonitors(reqCtx, connect.NewRequest(&monitorv1.ListMonitorsRequest{}))
		require.NoError(t, err)
		return resp.Msg.Monitors
	}
```

Add these rows to the `invalid` slice in `"validation before mutation"`:

```go
			{AttemptID: attempt(t), Monitors: []monitorSpec{{IPv4: &family{}}, {IPv6: &family{}}}},
			{AttemptID: attempt(t), Monitors: []monitorSpec{{}}},
			{AttemptID: attempt(t), Monitors: []monitorSpec{{IPv4: &family{Status: "deleted"}}}},
			{AttemptID: attempt(t), Monitors: []monitorSpec{{IPv6: &family{Status: "bogus"}}}},
			{AttemptID: attempt(t), Servers: []spec{{IPVersion: 4}, {IPVersion: 4}, {IPVersion: 4}, {IPVersion: 4}, {IPVersion: 4}}, Monitors: []monitorSpec{{IPv4: &family{}}}},
```

and inside that loop, after the users count assertion:

```go
			require.Zero(t, count(t, "SELECT count(*) FROM monitors WHERE tls_name = $1", tlsName(invalid.AttemptID)))
```

Add these subtests before `"create rollback leaves no partial fixture"`:

```go
	t.Run("monitor rows and listing", func(t *testing.T) {
		id := attempt(t)
		fixture := createRequest(t, e2efixture.CreateFixtureRequest{AttemptID: id, Monitors: []monitorSpec{{IPv4: &family{}}}})
		require.NotNil(t, fixture.Servers)
		require.Empty(t, fixture.Servers)
		require.Len(t, fixture.Monitors, 1)
		monitor := fixture.Monitors[0]
		require.Equal(t, tlsName(id), monitor.TLSName)
		require.Nil(t, monitor.IPv6)
		require.NotNil(t, monitor.IPv4)
		require.Equal(t, "pending", monitor.IPv4.Status)
		require.True(t, strings.HasPrefix(monitor.IPv4.IDToken, ntpdb.TokenPrefixMonitor))
		addr, err := netip.ParseAddr(monitor.IPv4.IP)
		require.NoError(t, err)
		require.True(t, netip.MustParsePrefix("192.0.2.0/24").Contains(addr), "monitor IPv4 %s", addr)
		validateSession(t, ctx, db, fixture.SessionToken)
		require.Equal(t, 1, count(t, `SELECT count(*) FROM monitors
			WHERE id=$1 AND id_token=$2 AND type='monitor' AND user_id=$3 AND account_id=$4
			  AND ip=$5 AND ip_version='v4' AND tls_name=$6 AND status='pending' AND is_current
			  AND config='{}'::jsonb AND api_key IS NULL AND last_seen IS NULL AND hostname='' AND location=''`,
			monitor.IPv4.MonitorID, monitor.IPv4.IDToken, fixture.UserID, fixture.AccountID, monitor.IPv4.IP, monitor.TLSName))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM e2e_fixture_monitors WHERE attempt_id=$1 AND ip_version=4 AND monitor_id=$2 AND ip=$3", id, monitor.IPv4.MonitorID, monitor.IPv4.IP))

		asMember := listMonitors(t, fixture, false)
		require.Len(t, asMember, 1)
		require.Equal(t, monitor.TLSName, asMember[0].TlsName)
		require.Nil(t, asMember[0].Account.Flags, "non-admin callers get no account flags")
		asAdmin := listMonitors(t, fixture, true)
		require.Len(t, asAdmin, 1)
		require.NotNil(t, asAdmin[0].Account.Flags, "monitor admins get account flags")
	})

	t.Run("every status starts without score rows", func(t *testing.T) {
		for _, status := range []string{"pending", "testing", "active", "paused"} {
			fixture := createRequest(t, e2efixture.CreateFixtureRequest{AttemptID: attempt(t), Monitors: []monitorSpec{{IPv4: &family{Status: status}}}})
			got := fixture.Monitors[0].IPv4
			require.Equal(t, status, got.Status)
			require.Equal(t, 1, count(t, "SELECT count(*) FROM monitors WHERE id=$1 AND status::text=$2", got.MonitorID, status))
			require.Zero(t, count(t, "SELECT count(*) FROM server_scores WHERE monitor_id=$1", got.MonitorID))
		}
	})

	t.Run("dual-stack monitors group by TLS name", func(t *testing.T) {
		split := createRequest(t, e2efixture.CreateFixtureRequest{AttemptID: attempt(t), Monitors: []monitorSpec{{IPv4: &family{Status: "active"}, IPv6: &family{Status: "paused"}}}})
		combined := createRequest(t, e2efixture.CreateFixtureRequest{AttemptID: attempt(t), Monitors: []monitorSpec{{IPv4: &family{Status: "testing"}, IPv6: &family{Status: "testing"}}}})
		for _, tc := range []struct {
			fixture        *e2efixture.CreateFixtureResponse
			combinedStatus bool
			v4, v6         string
		}{
			{split, false, "active", "paused"},
			{combined, true, "testing", "testing"},
		} {
			monitor := tc.fixture.Monitors[0]
			require.NotNil(t, monitor.IPv4)
			require.NotNil(t, monitor.IPv6)
			v6, err := netip.ParseAddr(monitor.IPv6.IP)
			require.NoError(t, err)
			require.True(t, netip.MustParsePrefix("2001:db8::/32").Contains(v6), "monitor IPv6 %s", v6)
			listed := listMonitors(t, tc.fixture, false)
			require.Len(t, listed, 1)
			require.True(t, listed[0].IsDualstack)
			require.Equal(t, tc.combinedStatus, listed[0].CombinedStatus)
			require.Equal(t, monitor.IPv4.IP, listed[0].Ipv4.Ip)
			require.Equal(t, tc.v4, listed[0].Ipv4.Status)
			require.Equal(t, monitor.IPv6.IP, listed[0].Ipv6.Ip)
			require.Equal(t, tc.v6, listed[0].Ipv6.Status)
		}
	})

	t.Run("servers and a monitor in one attempt", func(t *testing.T) {
		fixture := createRequest(t, e2efixture.CreateFixtureRequest{
			AttemptID: attempt(t),
			Servers:   []spec{{IPVersion: 4, Netspeed: 512}},
			Monitors:  []monitorSpec{{IPv6: &family{}}},
		})
		require.Len(t, fixture.Servers, 1)
		require.Len(t, fixture.Monitors, 1)
		require.Nil(t, fixture.Monitors[0].IPv4)
		require.NotNil(t, fixture.Monitors[0].IPv6)
		require.Equal(t, 1, count(t, "SELECT count(*) FROM servers WHERE account_id=$1", fixture.AccountID))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM monitors WHERE account_id=$1", fixture.AccountID))
	})

	t.Run("parallel monitor address uniqueness", func(t *testing.T) {
		ids := []string{attempt(t), attempt(t), attempt(t), attempt(t)}
		responses := make([]*e2efixture.CreateFixtureResponse, len(ids))
		errs := make([]error, len(ids))
		var wg sync.WaitGroup
		for i, id := range ids {
			wg.Add(1)
			go func() {
				defer wg.Done()
				responses[i], errs[i] = e2efixture.CreateFixture(ctx, q, e2efixture.CreateFixtureRequest{AttemptID: id, Monitors: []monitorSpec{{IPv4: &family{}, IPv6: &family{}}}})
			}()
		}
		wg.Wait()
		seen := map[string]bool{}
		for i, response := range responses {
			require.NoError(t, errs[i])
			for _, ip := range []string{response.Monitors[0].IPv4.IP, response.Monitors[0].IPv6.IP} {
				require.False(t, seen[ip], "duplicate monitor address %s", ip)
				seen[ip] = true
			}
		}
	})
```

Teardown note: `attempt(t)` teardown calls `e2efixture.CleanupFixture`, which doesn't delete monitors until Task 4. Running the `e2efixture` integration tests now would leave fixture monitor rows in the local test database. Don't run them in this task; Task 4, Step 6 runs them once cleanup handles monitors. Run only the build and vet checks below, then continue straight to Task 4.

- [ ] **Step 2: Verify it fails to compile**

Run: `go vet -tags integration ./e2efixture/`
Expected: FAIL — `undefined: e2efixture.MonitorFixtureSpec`.

- [ ] **Step 3: Add the SQL** — append to `sql/e2e_fixtures.sql`:

```sql

-- name: E2EFixtureMonitorIPInUse :one
SELECT EXISTS (SELECT 1 FROM monitors existing WHERE existing.ip = sqlc.arg(ip)::varchar) OR EXISTS (
    SELECT 1 FROM e2e_fixture_monitors m
    JOIN e2e_fixtures f USING (attempt_id)
    WHERE m.ip = sqlc.arg(ip)::varchar AND f.cleaned_on IS NULL
) AS in_use;

-- name: InsertE2EFixtureMonitor :one
INSERT INTO monitors (id_token, type, user_id, account_id, hostname, location,
                      ip, ip_version, tls_name, status, config, is_current, created_on)
VALUES (sqlc.arg(id_token), 'monitor', sqlc.arg(user_id), sqlc.arg(account_id), '', '',
        sqlc.arg(ip), sqlc.arg(ip_version), sqlc.arg(tls_name), sqlc.arg(status), '{}', true,
        CURRENT_TIMESTAMP)
RETURNING id;

-- name: RecordE2EFixtureMonitor :exec
INSERT INTO e2e_fixture_monitors (attempt_id, ip_version, monitor_id, ip)
VALUES ($1, $2, $3, $4);
```

Run: `make sqlc && go generate ./ntpdb/`
Expected: `InsertE2EFixtureMonitorParams` exists in `ntpdb/e2e_fixtures.sql.go`. Open it and note the field types; the code below assumes `IDToken pgtype.Text`, `UserID pgtype.Int8`, `AccountID pgtype.Int8`, `IP pgtype.Text`, `IpVersion ntpdb.NullMonitorsIpVersion`, `TlsName pgtype.Text`, `Status ntpdb.MonitorsStatus`, and `RecordE2EFixtureMonitorParams{AttemptID pgtype.UUID, IpVersion int16, MonitorID int64, IP string}`. If sqlc generated a different type for a field, use the generated type.

- [ ] **Step 4: Implement** — in `e2efixture/fixture.go`:

Add imports `"slices"` and `"go.ntppool.org/common/config/depenv"`.

Replace the `CreateFixtureRequest` and `CreateFixtureResponse` declarations with the following, and add the new types:

```go
// MonitorFamilySpec is one address family of a fixture monitor.
type MonitorFamilySpec struct {
	Status string `json:"status"` // pending (also when empty), testing, active or paused.
}

// MonitorFixtureSpec describes one logical monitor: an IPv4 row, an IPv6 row,
// or both sharing one TLS name. A JSON null family is absent.
type MonitorFixtureSpec struct {
	IPv4 *MonitorFamilySpec `json:"ipv4"`
	IPv6 *MonitorFamilySpec `json:"ipv6"`
}

// CreateFixtureRequest is the stdin JSON for `api e2e fixture create`.
type CreateFixtureRequest struct {
	AttemptID string               `json:"attempt_id"` // Canonical lowercase UUID v4, generated before calling.
	Servers   []ServerFixtureSpec  `json:"servers"`    // 0..4; response order preserved.
	Monitors  []MonitorFixtureSpec `json:"monitors"`   // 0..1; at least one server or monitor.
}

// FixtureMonitorFamily is one created monitors row.
type FixtureMonitorFamily struct {
	MonitorID int64  `json:"monitor_id,string"`
	IDToken   string `json:"id_token"`
	IP        string `json:"ip"` // Canonical reserved address allocated here.
	Status    string `json:"status"`
}

// FixtureMonitor is one created logical monitor. A family that wasn't
// requested is omitted.
type FixtureMonitor struct {
	TLSName string                `json:"tls_name"`
	IPv4    *FixtureMonitorFamily `json:"ipv4,omitempty"`
	IPv6    *FixtureMonitorFamily `json:"ipv6,omitempty"`
}

// CreateFixtureResponse is the stdout JSON for `api e2e fixture create`.
type CreateFixtureResponse struct {
	AttemptID    string           `json:"attempt_id"`
	AccountToken string           `json:"account_token"`
	AccountID    int64            `json:"account_id,string"`
	UserID       int64            `json:"user_id,string"`
	Email        string           `json:"email"`
	SessionToken string           `json:"session_token"` // Secret browser session; never log.
	Servers      []FixtureServer  `json:"servers"`       // Always an array.
	Monitors     []FixtureMonitor `json:"monitors"`      // Always an array.
}
```

Replace `validateFixtureSpecs` with:

```go
// fixtureMonitorStatuses are the statuses a fixture monitor row may start in.
// deleted is excluded: ListMonitors hides deleted rows.
var fixtureMonitorStatuses = []ntpdb.MonitorsStatus{
	ntpdb.MonitorsStatusPending,
	ntpdb.MonitorsStatusTesting,
	ntpdb.MonitorsStatusActive,
	ntpdb.MonitorsStatusPaused,
}

// fixtureMonitorStatus maps a requested status to the database value. Empty
// means pending.
func fixtureMonitorStatus(value string) (ntpdb.MonitorsStatus, error) {
	if value == "" {
		return ntpdb.MonitorsStatusPending, nil
	}
	status := ntpdb.MonitorsStatus(value)
	if !slices.Contains(fixtureMonitorStatuses, status) {
		return "", fmt.Errorf("%w: unsupported monitor status %q", ErrInvalidRequest, value)
	}
	return status, nil
}

// validateFixtureRequest rejects a JSON null server too: it decodes to a zero
// spec, whose IP version is 0.
func validateFixtureRequest(req CreateFixtureRequest) error {
	invalid := fmt.Errorf("%w: provide 0..4 servers with IP version 4 or 6, exclusive verification states and a supported netspeed, 0..1 monitors with an ipv4 and/or ipv6 entry whose status is pending, testing, active or paused, and at least one server or monitor", ErrInvalidRequest)
	if len(req.Servers) > 4 || len(req.Monitors) > 1 || len(req.Servers)+len(req.Monitors) == 0 {
		return invalid
	}
	for _, spec := range req.Servers {
		if (spec.IPVersion != 4 && spec.IPVersion != 6) || (spec.Verified && spec.PendingVerification) {
			return invalid
		}
		switch spec.Netspeed {
		case 0, 512, 1500, 3000, 6000, 12000, 25000, 50000, 100000, 250000, 500000, 1000000, 1500000, 2000000, 3000000:
		default:
			return invalid
		}
	}
	for _, spec := range req.Monitors {
		if spec.IPv4 == nil && spec.IPv6 == nil {
			return invalid
		}
		for _, family := range []*MonitorFamilySpec{spec.IPv4, spec.IPv6} {
			if family == nil {
				continue
			}
			if _, err := fixtureMonitorStatus(family.Status); err != nil {
				return invalid
			}
		}
	}
	return nil
}
```

In `CreateFixture`:
- replace `validateFixtureSpecs(req.Servers)` with `validateFixtureRequest(req)`;
- replace `response := &CreateFixtureResponse{AttemptID: req.AttemptID}` with `response := &CreateFixtureResponse{AttemptID: req.AttemptID, Servers: []FixtureServer{}, Monitors: []FixtureMonitor{}}`;
- replace `ip, err := allocateFixtureIP(ctx, q, spec.IPVersion)` with `ip, err := allocateFixtureIP(ctx, spec.IPVersion, serverIPv4Prefixes, q.E2EFixtureServerIPInUse)`;
- after the `for ordinal, spec := range req.Servers { ... }` loop and before `key, err := apiauth.MakeSessionKey(...)`, insert:

```go
		for _, spec := range req.Monitors {
			monitor, err := createFixtureMonitor(ctx, q, id, userID, accountID, fixtureMonitorTLSName(req.AttemptID), spec)
			if err != nil {
				return err
			}
			response.Monitors = append(response.Monitors, monitor)
		}
```

Replace `allocateFixtureIP` with:

```go
// IPv4 documentation /24s fixtures allocate from. Servers and monitors use
// disjoint ranges.
var (
	serverIPv4Prefixes  = [][3]byte{{198, 51, 100}, {203, 0, 113}}
	monitorIPv4Prefixes = [][3]byte{{192, 0, 2}}
)

// ipInUse reports whether an address is taken for one fixture kind.
type ipInUse func(ctx context.Context, ip string) (pgtype.Bool, error)

// allocateFixtureIP runs while the caller holds the allocator advisory lock for
// its whole transaction. Reserved documentation addresses can't reach
// third-party production NTP servers. No DNS/NTP calls, zone assignments or
// monitor scheduling happen here.
func allocateFixtureIP(ctx context.Context, version int32, v4Prefixes [][3]byte, inUse ipInUse) (string, error) {
	candidates := 254 * len(v4Prefixes)
	if version == 6 {
		candidates = 16
	}
	for i := range candidates {
		var addr netip.Addr
		if version == 4 {
			prefix := v4Prefixes[i/254]
			addr = netip.AddrFrom4([4]byte{prefix[0], prefix[1], prefix[2], byte(i%254 + 1)})
		} else {
			raw := [16]byte{0x20, 0x01, 0x0d, 0xb8}
			if _, err := rand.Read(raw[4:]); err != nil {
				return "", err
			}
			addr = netip.AddrFrom16(raw)
		}
		used, err := inUse(ctx, addr.String())
		if err != nil {
			return "", err
		}
		if used.Valid && !used.Bool {
			return addr.String(), nil
		}
	}
	return "", ErrNoAddress
}

// fixtureMonitorTLSName is shared by a monitor's IPv4 and IPv6 rows, which is
// how ListMonitors groups them into one dual-stack monitor.
func fixtureMonitorTLSName(attemptID string) string {
	return "fixture-" + attemptID + "." + depenv.DeployDevel.MonitorDomain()
}

// createFixtureMonitor inserts and records one monitors row per requested
// family. It sets no API key, so the monitor can't connect, and inserts no
// server_scores rows in any status.
func createFixtureMonitor(ctx context.Context, q ntpdb.QuerierTx, attempt pgtype.UUID, userID, accountID pgtype.Int8, tlsName string, spec MonitorFixtureSpec) (FixtureMonitor, error) {
	monitor := FixtureMonitor{TLSName: tlsName}
	for _, family := range []struct {
		version int32
		spec    *MonitorFamilySpec
		out     **FixtureMonitorFamily
	}{
		{4, spec.IPv4, &monitor.IPv4},
		{6, spec.IPv6, &monitor.IPv6},
	} {
		if family.spec == nil {
			continue
		}
		status, err := fixtureMonitorStatus(family.spec.Status)
		if err != nil {
			return FixtureMonitor{}, err
		}
		ip, err := allocateFixtureIP(ctx, family.version, monitorIPv4Prefixes, q.E2EFixtureMonitorIPInUse)
		if err != nil {
			return FixtureMonitor{}, err
		}
		idToken, err := ntpdb.GenerateIDToken(ntpdb.TokenPrefixMonitor)
		if err != nil {
			return FixtureMonitor{}, err
		}
		ipVersion := ntpdb.MonitorsIpVersionV4
		if family.version == 6 {
			ipVersion = ntpdb.MonitorsIpVersionV6
		}
		monitorID, err := q.InsertE2EFixtureMonitor(ctx, ntpdb.InsertE2EFixtureMonitorParams{
			IDToken:   pgtype.Text{String: idToken, Valid: true},
			UserID:    userID,
			AccountID: accountID,
			IP:        pgtype.Text{String: ip, Valid: true},
			IpVersion: ntpdb.NullMonitorsIpVersion{MonitorsIpVersion: ipVersion, Valid: true},
			TlsName:   pgtype.Text{String: tlsName, Valid: true},
			Status:    status,
		})
		if err != nil {
			return FixtureMonitor{}, err
		}
		if err := q.RecordE2EFixtureMonitor(ctx, ntpdb.RecordE2EFixtureMonitorParams{
			AttemptID: attempt,
			IpVersion: int16(family.version),
			MonitorID: monitorID,
			IP:        ip,
		}); err != nil {
			return FixtureMonitor{}, err
		}
		*family.out = &FixtureMonitorFamily{MonitorID: monitorID, IDToken: idToken, IP: ip, Status: string(status)}
	}
	return monitor, nil
}
```

In `cmd/e2e.go` change the create help to `help:"create a fixture user and account with 0 to 4 servers and 0 or 1 monitor"`.

- [ ] **Step 5: Build and vet**

Run: `go build ./... && go build -tags e2efixtures ./... && go vet -tags integration,e2efixtures ./e2efixture/ ./cmd/`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
gofumpt -w e2efixture/fixture.go e2efixture/fixture_integration_test.go cmd/e2e.go
git diff --check
git add sql/e2e_fixtures.sql ntpdb/e2e_fixtures.sql.go ntpdb/querier.go ntpdb/otel.go ntpdb/mocks.go e2efixture/fixture.go e2efixture/fixture_integration_test.go cmd/e2e.go
git status && git diff --staged --stat
git commit -m "feat(e2e): create monitors in e2e fixtures"
```

---

### Task 4: Clean up fixture monitors

**Files:**
- Modify: `sql/e2e_fixtures.sql` (append)
- Regenerate: `ntpdb/e2e_fixtures.sql.go`, `ntpdb/querier.go`, `ntpdb/otel.go`, `ntpdb/mocks.go`
- Modify: `e2efixture/fixture.go` (`CleanupFixture`, `CleanupFixtureResponse`, errors, `fixtureError`)
- Modify: `e2efixture/fixture_integration_test.go`
- Modify: `cmd/e2e.go` (cleanup help), `cmd/e2e_integration_test.go`

**Interfaces:**
- Consumes: Task 3.
- Produces: `ErrMonitorInUse`; `CleanupFixtureResponse.DeletedMonitors int64` (`json:"deleted_monitors"`); ntpdb `LockE2EFixtureMonitors(ctx, pgtype.UUID) ([]LockE2EFixtureMonitorsRow{ID int64, AccountID pgtype.Int8}, error)`, `E2EFixtureMonitorsInUse(ctx, pgtype.UUID) (pgtype.Bool, error)`, `DeleteE2EFixtureMonitors(ctx, DeleteE2EFixtureMonitorsParams{AttemptID, AccountID}) (int64, error)`, `CountE2EFixtureMonitors(ctx, pgtype.UUID) (int64, error)`.

- [ ] **Step 1: Write the failing tests** — add before `"create rollback leaves no partial fixture"` in `e2efixture/fixture_integration_test.go`:

```go
	t.Run("cleanup removes monitors and reports counts", func(t *testing.T) {
		id := attempt(t)
		fixture := createRequest(t, e2efixture.CreateFixtureRequest{
			AttemptID: id,
			Servers:   []spec{{IPVersion: 4, Netspeed: 512}},
			Monitors:  []monitorSpec{{IPv4: &family{Status: "active"}, IPv6: &family{Status: "paused"}}},
		})
		cleaned, err := e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.NoError(t, err)
		require.EqualValues(t, 1, cleaned.DeletedServers)
		require.EqualValues(t, 2, cleaned.DeletedMonitors)
		for _, family := range []*e2efixture.FixtureMonitorFamily{fixture.Monitors[0].IPv4, fixture.Monitors[0].IPv6} {
			require.Zero(t, count(t, "SELECT count(*) FROM monitors WHERE id=$1", family.MonitorID))
		}
		again, err := e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.NoError(t, err)
		require.Zero(t, again.DeletedServers)
		require.Zero(t, again.DeletedMonitors)
	})

	t.Run("monitor score rows refuse cleanup", func(t *testing.T) {
		id := attempt(t)
		fixture := createRequest(t, e2efixture.CreateFixtureRequest{
			AttemptID: id,
			Servers:   []spec{{IPVersion: 4, Netspeed: 512}},
			Monitors:  []monitorSpec{{IPv4: &family{Status: "active"}}},
		})
		monitorID := fixture.Monitors[0].IPv4.MonitorID
		_, err := db.Exec(ctx, "INSERT INTO server_scores (monitor_id, server_id, score_raw, created_on) VALUES ($1, $2, 0, CURRENT_TIMESTAMP)", monitorID, fixture.Servers[0].ServerID)
		require.NoError(t, err)
		// Registered after attempt(t), so it runs first and lets the fixture teardown succeed.
		t.Cleanup(func() {
			_, err := db.Exec(ctx, "DELETE FROM server_scores WHERE monitor_id=$1", monitorID)
			require.NoError(t, err)
		})
		_, err = e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.ErrorIs(t, err, e2efixture.ErrMonitorInUse)
		require.Equal(t, 1, count(t, "SELECT count(*) FROM monitors WHERE id=$1", monitorID))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM servers WHERE id=$1", fixture.Servers[0].ServerID))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM e2e_fixtures WHERE attempt_id=$1 AND cleaned_on IS NULL", id))

		_, err = db.Exec(ctx, "DELETE FROM server_scores WHERE monitor_id=$1", monitorID)
		require.NoError(t, err)
		cleaned, err := e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.NoError(t, err)
		require.EqualValues(t, 1, cleaned.DeletedMonitors)
	})

	t.Run("moved monitor aborts cleanup", func(t *testing.T) {
		id := attempt(t)
		fixture := createRequest(t, e2efixture.CreateFixtureRequest{AttemptID: id, Monitors: []monitorSpec{{IPv4: &family{}}}})
		other := create(t, attempt(t), spec{IPVersion: 6, Netspeed: 512})
		monitorID := fixture.Monitors[0].IPv4.MonitorID
		// Restore this deliberately moved row before registered fixture teardown.
		t.Cleanup(func() {
			_, err := db.Exec(ctx, "UPDATE monitors SET account_id=$1 WHERE id=$2", fixture.AccountID, monitorID)
			require.NoError(t, err)
		})
		_, err := db.Exec(ctx, "UPDATE monitors SET account_id=$1 WHERE id=$2", other.AccountID, monitorID)
		require.NoError(t, err)
		_, err = e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.ErrorIs(t, err, e2efixture.ErrOwnershipChanged)
		require.Equal(t, 1, count(t, "SELECT count(*) FROM monitors WHERE id=$1 AND account_id=$2", monitorID, other.AccountID))
		require.Equal(t, 1, count(t, "SELECT count(*) FROM e2e_fixtures WHERE attempt_id=$1 AND cleaned_on IS NULL", id))
	})
```

In `cmd/e2e_integration_test.go`, in the `"fixture create and cleanup"` subtest:
- change the create input to `` `{"attempt_id":"`+attempt+`","servers":[{"ip_version":4,"netspeed":512,"pending_verification":true}],"monitors":[{"ipv4":{"status":"active"},"ipv6":{"status":"paused"}}]}` ``;
- add to the `created` struct:

```go
			Monitors []struct {
				TLSName string `json:"tls_name"`
				IPv4    *struct {
					MonitorID string `json:"monitor_id"`
					IDToken   string `json:"id_token"`
					IP        string `json:"ip"`
					Status    string `json:"status"`
				} `json:"ipv4"`
				IPv6 *struct {
					MonitorID string `json:"monitor_id"`
					IDToken   string `json:"id_token"`
					IP        string `json:"ip"`
					Status    string `json:"status"`
				} `json:"ipv6"`
			} `json:"monitors"`
```

- after the server assertions add:

```go
		require.Len(t, created.Monitors, 1)
		require.Equal(t, "fixture-"+attempt+".devel.mon.ntppool.dev", created.Monitors[0].TLSName)
		require.NotNil(t, created.Monitors[0].IPv4)
		require.NotNil(t, created.Monitors[0].IPv6)
		require.Regexp(t, `^\d+$`, created.Monitors[0].IPv4.MonitorID)
		require.Equal(t, "active", created.Monitors[0].IPv4.Status)
		require.Equal(t, "paused", created.Monitors[0].IPv6.Status)
```

- add `DeletedMonitors int `json:"deleted_monitors"`` to the `cleaned` struct and `require.Equal(t, 2, cleaned.DeletedMonitors)` after the servers count;
- after the subtest, add:

```go
	t.Run("server-fixture command is gone", func(t *testing.T) {
		stdout, _, code := run(t, `{"attempt_id":"`+uuid.NewString()+`"}`, nil, "e2e", "server-fixture", "cleanup")
		require.NotEqual(t, 0, code)
		require.Empty(t, stdout)
	})
```

- [ ] **Step 2: Verify it fails to compile**

Run: `go vet -tags integration,e2efixtures ./e2efixture/ ./cmd/`
Expected: FAIL — `undefined: e2efixture.ErrMonitorInUse`, `cleaned.DeletedMonitors undefined`.

- [ ] **Step 3: Add the SQL** — append to `sql/e2e_fixtures.sql`:

```sql

-- name: LockE2EFixtureMonitors :many
SELECT m.id, m.account_id FROM monitors m
JOIN e2e_fixture_monitors f ON f.monitor_id = m.id
WHERE f.attempt_id = $1 ORDER BY m.id FOR UPDATE OF m;

-- name: E2EFixtureMonitorsInUse :one
SELECT EXISTS (
    SELECT 1 FROM server_scores WHERE monitor_id IN (SELECT monitor_id FROM e2e_fixture_monitors WHERE attempt_id = sqlc.arg(attempt_id)::uuid)
) OR EXISTS (
    SELECT 1 FROM log_scores WHERE monitor_id IN (SELECT monitor_id FROM e2e_fixture_monitors WHERE attempt_id = sqlc.arg(attempt_id)::uuid)
) OR EXISTS (
    SELECT 1 FROM api_keys_monitors WHERE monitor_id IN (SELECT monitor_id FROM e2e_fixture_monitors WHERE attempt_id = sqlc.arg(attempt_id)::uuid)
) OR EXISTS (
    SELECT 1 FROM scorer_status WHERE scorer_id IN (SELECT monitor_id FROM e2e_fixture_monitors WHERE attempt_id = sqlc.arg(attempt_id)::uuid)
) AS in_use;

-- name: DeleteE2EFixtureMonitors :execrows
DELETE FROM monitors WHERE id IN (
    SELECT monitor_id FROM e2e_fixture_monitors WHERE attempt_id = $1
) AND account_id = $2;

-- name: CountE2EFixtureMonitors :one
SELECT count(*) FROM monitors m JOIN e2e_fixture_monitors f ON f.monitor_id = m.id
WHERE f.attempt_id = $1;
```

Run: `make sqlc && go generate ./ntpdb/`
Expected: the four methods exist in `ntpdb/querier.go`.
Run: `grep -n "ON public.log_scores" schema.sql`
Expected: an index whose column list starts with `monitor_id`. If there is none, note it in the task report (the devel cleanup would scan `log_scores`); don't add an index in this plan.

- [ ] **Step 4: Implement** — in `e2efixture/fixture.go`:

Change `ErrOwnershipChanged` and add `ErrMonitorInUse` in the `var (...)` block:

```go
	// ErrOwnershipChanged means a recorded server or monitor moved to another account.
	ErrOwnershipChanged = errors.New("fixture server or monitor ownership changed; cleanup refused")
	// ErrMonitorInUse means a fixture monitor picked up score, log-score or API
	// key rows (for example after an admin status change). Cleanup never
	// deletes those rows itself.
	ErrMonitorInUse = errors.New("fixture monitor has score, log-score or API key rows; cleanup refused")
```

Replace `CleanupFixtureResponse` with:

```go
// CleanupFixtureResponse is the stdout JSON for `api e2e fixture cleanup`.
type CleanupFixtureResponse struct {
	AttemptID       string `json:"attempt_id"`
	DeletedServers  int64  `json:"deleted_servers"`  // Zero on repeated cleanup.
	DeletedMonitors int64  `json:"deleted_monitors"` // Zero on repeated cleanup.
}
```

Replace the transaction body of `CleanupFixture` (from `owned, err := q.LockE2EFixtureServers(ctx, id)` through `return q.TombstoneE2EFixture(ctx, id)`) with:

```go
		owned, err := q.LockE2EFixtureServers(ctx, id)
		if err != nil {
			return err
		}
		monitors, err := q.LockE2EFixtureMonitors(ctx, id)
		if err != nil {
			return err
		}
		if len(owned) > 4 || len(monitors) > 2 || !fixture.AccountID.Valid {
			return errors.New("invalid fixture registry")
		}
		for _, server := range owned {
			if !server.AccountID.Valid || server.AccountID.Int64 != fixture.AccountID.Int64 {
				return ErrOwnershipChanged
			}
		}
		for _, monitor := range monitors {
			if !monitor.AccountID.Valid || monitor.AccountID.Int64 != fixture.AccountID.Int64 {
				return ErrOwnershipChanged
			}
		}
		inUse, err := q.E2EFixtureMonitorsInUse(ctx, id)
		if err != nil {
			return err
		}
		if !inUse.Valid {
			return errors.New("fixture monitor dependency check returned NULL")
		}
		if inUse.Bool {
			return ErrMonitorInUse
		}
		if err = q.DeleteE2EFixtureServerLogs(ctx, id); err != nil {
			return err
		}
		if err = q.DeleteE2EFixtureServerEmails(ctx, id); err != nil {
			return err
		}
		response.DeletedServers, err = q.DeleteE2EFixtureServers(ctx, ntpdb.DeleteE2EFixtureServersParams{AttemptID: id, AccountID: fixture.AccountID})
		if err != nil {
			return err
		}
		response.DeletedMonitors, err = q.DeleteE2EFixtureMonitors(ctx, ntpdb.DeleteE2EFixtureMonitorsParams{AttemptID: id, AccountID: fixture.AccountID})
		if err != nil {
			return err
		}
		remainingServers, err := q.CountE2EFixtureServers(ctx, id)
		if err != nil {
			return err
		}
		if remainingServers != 0 {
			return errors.New("fixture servers remain")
		}
		remainingMonitors, err := q.CountE2EFixtureMonitors(ctx, id)
		if err != nil {
			return err
		}
		if remainingMonitors != 0 {
			return errors.New("fixture monitors remain")
		}
		return q.TombstoneE2EFixture(ctx, id)
```

Update the `CleanupFixture` doc comment to: `// CleanupFixture uses durable recorded IDs, never account-wide deletion. Row locks on the recorded servers and monitors prevent ownership changes between check and delete. An unknown attempt becomes a tombstone, so a delayed create with that ID fails.`

In `fixtureError`, change the known list to `[]error{ErrAttemptUsed, ErrOwnershipChanged, ErrNoAddress, ErrMonitorInUse}`.

In `cmd/e2e.go` change the cleanup help to `help:"remove a fixture attempt's servers and monitors"`.

- [ ] **Step 5: Build and vet**

Run: `go build ./... && go build -tags e2efixtures ./... && go vet -tags integration,e2efixtures ./e2efixture/ ./cmd/`
Expected: no output.

- [ ] **Step 6: Run the tests**

Run: `./scripts/test-integration ./e2efixture/`
Expected: PASS, including every subtest from Tasks 3 and 4.
Run: `./scripts/test-integration ./cmd/`
Expected: PASS.
Run: `psql "postgres://ntppool:test123@localhost:5432/ntppool_test?sslmode=disable" -At -c "SELECT count(*) FROM monitors WHERE tls_name LIKE 'fixture-%'"`
Expected: `0` (teardown removed every fixture monitor).

- [ ] **Step 7: Commit**

```bash
gofumpt -w e2efixture/fixture.go e2efixture/fixture_integration_test.go cmd/e2e.go cmd/e2e_integration_test.go
git diff --check
git add sql/e2e_fixtures.sql ntpdb/e2e_fixtures.sql.go ntpdb/querier.go ntpdb/otel.go ntpdb/mocks.go e2efixture/fixture.go e2efixture/fixture_integration_test.go cmd/e2e.go cmd/e2e_integration_test.go
git status && git diff --staged --stat
git commit -m "feat(e2e): clean up fixture monitors and refuse when they have score rows"
```

---

### Task 5: Verify, push and deploy to devel

**Files:** none in the API repo. Local, uncommitted edit to `~/src/flux-ntp/askntp/api/api-config-local.yaml`.

**Interfaces:**
- Produces: devel `api-internal` running the new image, goose version 29, `api e2e fixture create|cleanup` available through `NTP_API_CLI`.

- [ ] **Step 1: Full local verification**

Run: `go test ./...`
Expected: PASS.
Run: `go build -tags e2efixtures ./...`
Expected: no output.
Run: `./scripts/test-integration ./db/migrations/ && ./scripts/test-integration ./e2efixture/ && ./scripts/test-integration ./cmd/ && ./scripts/test-integration ./server/api/monitoradmin/`
Expected: PASS for all four.
Run: `git log --oneline origin/main..HEAD`
Expected: exactly the four commits from Tasks 1–4.

- [ ] **Step 2: Re-check devel for uncleaned attempts (read-only)**

```bash
kubectl --context dala -n askntp exec -i pg-1 -c postgres -- psql -d askntp -v ON_ERROR_STOP=1 <<'SQL'
BEGIN READ ONLY;
SELECT count(*) AS uncleaned FROM server_test_fixtures WHERE cleaned_on IS NULL;
SELECT version_id FROM goose_db_version ORDER BY id DESC LIMIT 1;
ROLLBACK;
SQL
```

Expected: `uncleaned` 0 and version 28. If `uncleaned` > 0, list them (`SELECT attempt_id FROM server_test_fixtures WHERE cleaned_on IS NULL`) and clean each through the still-deployed binary before continuing:
`printf '{"attempt_id":"%s"}' <attempt> | kubectl --context dala -n askntp exec -i deploy/api-internal -c main -- /ko-app/api e2e server-fixture cleanup`

- [ ] **Step 3: Push**

Run: `git push origin main`
Expected: the four commits pushed. Note the new HEAD: `git rev-parse --short=8 HEAD`.

- [ ] **Step 4: Wait for CI**

Use the `abh:woodpecker-logs` skill's commands to find the pipeline for that commit and wait until it finishes. Expected: success, including the `docker` step that pushes `ntporg/api-dev:sha-<first 8 of HEAD>`. On failure, fetch the failed step's log with the same skill and fix before continuing.

- [ ] **Step 5: Deploy**

Edit `~/src/flux-ntp/askntp/api/api-config-local.yaml`: in the `x-image-tag: &image-tag sha-...` line, replace the tag with `sha-<first 8 of HEAD>`.
Run: `cd ~/src/flux-ntp/askntp/api && ./update-api`
Expected: helm upgrade succeeds (its pre-upgrade `api-setup` hook runs migration 029). Do not commit or push flux-ntp.

- [ ] **Step 6: Verify devel**

Run: `kubectl --context dala -n askntp get deploy api-internal -o jsonpath='{.spec.template.spec.containers[0].image}'`
Expected: `harbor.ntppool.org/ntporg/api-dev:sha-<first 8 of HEAD>`.
Run: `kubectl --context dala -n askntp rollout status deploy/api-internal`
Expected: successfully rolled out.
Run: `kubectl --context dala -n askntp exec deploy/api-internal -c main -- /ko-app/api migrate status`
Expected: version 29 applied.
Run: `kubectl --context dala -n askntp exec deploy/api-internal -c main -- /ko-app/api e2e --help`
Expected: lists `fixture` with `create` and `cleanup`; no `server-fixture`.
Run (read-only):

```bash
kubectl --context dala -n askntp exec -i pg-1 -c postgres -- psql -d askntp -v ON_ERROR_STOP=1 <<'SQL'
BEGIN READ ONLY;
SELECT to_regclass('e2e_fixtures') AS e2e_fixtures, to_regclass('e2e_fixture_servers') AS servers, to_regclass('e2e_fixture_monitors') AS monitors, to_regclass('server_test_fixtures') AS old;
ROLLBACK;
SQL
```

Expected: the three new tables resolve; `old` is empty.
