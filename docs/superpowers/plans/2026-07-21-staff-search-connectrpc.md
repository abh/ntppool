# Staff Search: int_api → ConnectRPC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `int_api('get', 'search', ...)` call in `Manage.pm::staff_search` with a ConnectRPC `SearchService`, and remove the now-dead `/int/search` REST route — closing out gitea issue #43.

**Architecture:** Extract the existing REST handler's query-dispatch logic (IP / `id:` / `monitors:` / `zone:` / pattern) into a plain Go function shared by a temporary Echo wrapper and a new ConnectRPC handler. Once the ConnectRPC path is tested and Perl is switched over, delete the Echo wrapper and REST route in the same branch (single combined change — this is a low-risk, staff-only admin endpoint, not a phased multi-slice migration).

**Tech Stack:** Go (Echo, ConnectRPC, protobuf, pgx/sqlc), Perl (Combust, NP::CAPI generated ConnectRPC client), buf (proto codegen incl. the local `protoc-gen-perl-capi` plugin).

## Global Constraints

- Design doc: `docs/superpowers/specs/2026-07-21-staff-search-connectrpc-design.md` — read it for the full rationale; this plan implements it as-is.
- Field names in the new proto mirror the current REST JSON exactly (already snake_case) — `tpl/admin/search_results.html` must need zero changes.
- Highlighting/CSS-class computation stays in Perl, unchanged. Do not move it to Go.
- Do **not** delete `lib/NP/IntAPI.pm` or touch `lib/NTPPool/Control/Manage/Account.pm:1026` — both are out of scope (tracked in #28 and #37).
- Timestamps in the new proto are plain RFC3339 strings (not `google.protobuf.Timestamp`), matching `monitor.proto`'s `LastSeenStatus.timestamp` convention.
- Two repos are touched: the Go API at `/Users/ask/src/go/ntp/api` and this repo (`/Users/ask/src/ntppool`) at `/Users/ask/src/ntppool`. They are separate git repos with separate commits — the `ntppool` directory inside the Go API repo is a symlink to `/Users/ask/src/ntppool`, which is how `make buf-generate` writes generated Perl directly into this repo.
- Go pre-commit: run `gofumpt -w` on modified `.go` files and `go test ./...` before committing, per the user's global Go conventions.
- Perl pre-commit: trim trailing whitespace, end files with a newline.

---

## Task 1: Author the search proto and generate code

**Files:**
- Create (go repo): `/Users/ask/src/go/ntp/api/proto/ntppool/search/v1/search.proto`
- Generated (go repo, do not hand-edit): `/Users/ask/src/go/ntp/api/gen/ntppool/search/v1/search.pb.go`, `/Users/ask/src/go/ntp/api/gen/ntppool/search/v1/searchv1connect/search.connect.go`
- Generated (this repo via symlink, do not hand-edit): `/Users/ask/src/ntppool/lib/NP/CAPI/Search.pm`

**Interfaces:**
- Produces: `searchv1.SearchRequest{Query string, IncludeDeleted bool}`, `searchv1.SearchResponse{Accounts []*Account, FilterContext *FilterContext}`, `searchv1.Account{IdToken, Name string; Users []*User; Servers []*Server; Monitors []*Monitor}`, `searchv1.User{Id int64; Name, Username, Email string}`, `searchv1.Server{Id int64; Ip string; Score *float64; Netspeed int64; NetspeedHuman string; CreatedOn string; DeletionOn *string; Hostname string; InPool bool; Zones []string}`, `searchv1.Monitor{Id int64; IdToken, TlsName, Ip, IpVersion, Hostname, Location, Status, CreatedOn string}`, `searchv1.FilterContext{SearchType, ZoneName string; ShowMonitorsOnly, ShowZoneServersOnly bool}`, and the Connect server interface `searchv1connect.SearchServiceHandler` (method `Search(context.Context, *connect.Request[searchv1.SearchRequest]) (*connect.Response[searchv1.SearchResponse], error)`) plus `searchv1connect.NewSearchServiceHandler(svc searchv1connect.SearchServiceHandler, opts ...connect.HandlerOption) (string, http.Handler)`.
- Produces (Perl): `NP::CAPI::Search::search(auth => ..., context => ..., account => ..., query => ..., include_deleted => ...)` returning the standard `{code, status_line, connect_code, data, error, trace_id}` hashref, with `data => {accounts => [...], filter_context => {...} | undef}`.

- [ ] **Step 1: Write the proto file**

Create `/Users/ask/src/go/ntp/api/proto/ntppool/search/v1/search.proto`:

```proto
syntax = "proto3";

package ntppool.search.v1;

option go_package = "go.ntppool.org/api/gen/ntppool/search/v1;searchv1";

// SearchService provides staff search across accounts, users, servers, and
// monitors. This is an internal-only service for use by the management
// interface.
service SearchService {
  // Search dispatches a query across accounts, users, servers, and monitors.
  // The query is interpreted by prefix/shape: an IP address searches
  // servers/monitors by IP; "id:N" looks up an account by numeric ID;
  // "monitors:" lists accounts that have monitors; "zone:NAME" lists
  // accounts with servers in that zone; anything else is a pattern search
  // across account/user/server/monitor fields.
  // Authentication: Required via session middleware.
  // Authorization: Staff only (support_staff privilege required).
  rpc Search(SearchRequest) returns (SearchResponse) {
    option idempotency_level = NO_SIDE_EFFECTS;
  }
}

// SearchRequest carries the raw query string and search options.
message SearchRequest {
  // query is the raw search string (IP, "id:N", "monitors:", "zone:NAME",
  // or a free-text pattern). Required, must be non-empty after trimming.
  string query = 1;

  // include_deleted includes servers/monitors that have a deletion_on set.
  bool include_deleted = 2;
}

// SearchResponse contains matched accounts and optional filter metadata.
message SearchResponse {
  // accounts is the list of matched accounts with their nested users,
  // servers, and monitors. Empty (not an error) when nothing matches.
  repeated Account accounts = 1;

  // filter_context provides UI hints for "monitors:"/"zone:" searches
  // (e.g. which section to highlight). Absent for other query types.
  optional FilterContext filter_context = 2;
}

// FilterContext gives the UI metadata about which search-type filter is
// active, so it can highlight the relevant subset of results.
message FilterContext {
  // search_type is one of "monitors", "zone", "pattern", "ip", "id".
  string search_type = 1;

  // zone_name is the zone searched, set only when search_type is "zone".
  string zone_name = 2;

  // show_monitors_only hints the UI to highlight the monitors section.
  bool show_monitors_only = 3;

  // show_zone_servers_only hints the UI to highlight servers in zone_name.
  bool show_zone_servers_only = 4;
}

// Account is a matched account with its nested users, servers, and
// monitors.
message Account {
  // id_token is the account's public identifier token.
  string id_token = 1;

  string name = 2;

  repeated User users = 3;

  repeated Server servers = 4;

  repeated Monitor monitors = 5;
}

// User is a minimal user record for display in search results.
message User {
  int64 id = 1;

  string name = 2;

  string username = 3;

  string email = 4;
}

// Server is a matched server, display-ready.
message Server {
  int64 id = 1;

  string ip = 2;

  // score is the server's current score, rounded to 1 decimal place.
  // Absent if the server has no score yet.
  optional double score = 3;

  int64 netspeed = 4;

  // netspeed_human is netspeed formatted like "100K"/"1M"/"1G".
  string netspeed_human = 5;

  // created_on is RFC3339.
  string created_on = 6;

  // deletion_on is RFC3339, present only when deletion is scheduled.
  optional string deletion_on = 7;

  string hostname = 8;

  bool in_pool = 9;

  // zones is the list of DNS zone names this server belongs to.
  repeated string zones = 10;
}

// Monitor is a matched monitor, display-ready.
message Monitor {
  int64 id = 1;

  string id_token = 2;

  string tls_name = 3;

  string ip = 4;

  string ip_version = 5;

  string hostname = 6;

  string location = 7;

  string status = 8;

  // created_on is RFC3339.
  string created_on = 9;
}
```

- [ ] **Step 2: Build the local Perl generator plugin**

```bash
cd /Users/ask/src/go/ntp/api
make build-perl-gen
```

Expected: `Perl generator built successfully` (installs `protoc-gen-perl-capi` into `$(go env GOPATH)/bin`).

- [ ] **Step 3: Generate Go, Connect, and Perl code**

```bash
cd /Users/ask/src/go/ntp/api
make buf-generate
```

Expected: no errors. Then verify the outputs landed:

```bash
ls gen/ntppool/search/v1/search.pb.go
ls gen/ntppool/search/v1/searchv1connect/search.connect.go
ls /Users/ask/src/ntppool/lib/NP/CAPI/Search.pm
```

All three must exist.

- [ ] **Step 4: Lint and build**

```bash
cd /Users/ask/src/go/ntp/api
buf lint
go build ./...
```

Expected: both succeed with no output (`buf lint` prints nothing on success).

- [ ] **Step 5: Commit (go repo)**

```bash
cd /Users/ask/src/go/ntp/api
git add proto/ntppool/search/v1/search.proto gen/ntppool/search/v1
gofumpt -w gen/ntppool/search/v1/search.pb.go
git commit -m "feat(search): add SearchService proto and generated code (#43)"
```

- [ ] **Step 6: Commit (ntppool repo)**

```bash
cd /Users/ask/src/ntppool
git add lib/NP/CAPI/Search.pm
git commit -m "feat(search): generated NP::CAPI::Search wrapper (#43)"
```

---

## Task 2: Extract the search dispatch function

**Files:**
- Modify: `/Users/ask/src/go/ntp/api/server/api/search/search.go`
- Modify: `/Users/ask/src/go/ntp/api/server/api/search/search_test.go`
- Modify: `/Users/ask/src/go/ntp/api/server/api/search/search_integration_test.go`

**Interfaces:**
- Consumes: existing `SearchAPI` helpers unchanged — `searchByIP`, `searchByAccountID`, `searchByPattern`, `searchByMonitors`, `searchByZone`, `addResultMetricsToSpan(span trace.Span, response *SearchResponse)`.
- Produces: `func (api *SearchAPI) search(ctx context.Context, query string, includeDeleted bool) (*SearchResponse, error)` — no auth/param validation, caller's responsibility. `var errEmptyZoneName = errors.New("zone name is required after 'zone:'")` — sentinel for `search()` returning on `zone:` with no name.

- [ ] **Step 1: Write the failing test**

Add to `/Users/ask/src/go/ntp/api/server/api/search/search_test.go` (after `TestUserExists`):

```go
func TestSearchZoneEmptyName(t *testing.T) {
	api := &SearchAPI{}

	_, err := api.search(context.Background(), "zone:", false)
	if !errors.Is(err, errEmptyZoneName) {
		t.Errorf("search(\"zone:\") error = %v, want errEmptyZoneName", err)
	}
}
```

Add `"context"` and `"errors"` to the file's import block:

```go
import (
	"context"
	"errors"
	"testing"

	"go.ntppool.org/api/server/base"
)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/ask/src/go/ntp/api
go test ./server/api/search/... -run TestSearchZoneEmptyName -v
```

Expected: FAIL to compile — `api.search undefined` and `errEmptyZoneName undefined`.

- [ ] **Step 3: Extract `search()` from the Echo handler**

In `/Users/ask/src/go/ntp/api/server/api/search/search.go`, replace the entire `Search` function (currently lines 169–269, from `// Search performs comprehensive staff search...` through its closing `}`) with:

```go
var errEmptyZoneName = errors.New("zone name is required after 'zone:'")

// Search performs comprehensive staff search across accounts, users, servers, and monitors
func (api *SearchAPI) Search(c echo.Context) error {
	ctx := c.Request().Context()

	user := sessions.GetUser(ctx)
	if user.ID == 0 {
		return echo.NewHTTPError(http.StatusUnauthorized, "no user")
	}
	if !user.IsStaff() {
		return echo.NewHTTPError(http.StatusForbidden, "staff access required")
	}

	query := strings.TrimSpace(c.QueryParam("q"))
	if query == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "query parameter 'q' is required")
	}

	includeDeleted := false
	if includeDeletedParam := c.QueryParam("include_deleted"); includeDeletedParam != "" {
		var err error
		includeDeleted, err = strconv.ParseBool(includeDeletedParam)
		if err != nil {
			return echo.NewHTTPError(http.StatusBadRequest, "invalid include_deleted parameter")
		}
	}

	response, err := api.search(ctx, query, includeDeleted)
	if err != nil {
		if errors.Is(err, errEmptyZoneName) {
			return echo.NewHTTPError(http.StatusBadRequest, err.Error())
		}
		return echo.NewHTTPError(http.StatusInternalServerError, "search failed").SetInternal(err)
	}

	return c.JSON(http.StatusOK, response)
}

// search dispatches a staff search query across accounts, users, servers,
// and monitors based on its prefix (id:, monitors:, zone:) or shape (an IP
// address), falling back to pattern search. The caller is responsible for
// authorization and for rejecting an empty query.
func (api *SearchAPI) search(ctx context.Context, query string, includeDeleted bool) (*SearchResponse, error) {
	ctx, span := tracing.Start(ctx, "search.Search")
	defer span.End()

	log := logger.FromContext(ctx)
	log.InfoContext(ctx, "staff search", "query", query, "include_deleted", includeDeleted)

	span.SetAttributes(
		attribute.String("search.query", query),
		attribute.Bool("search.include_deleted", includeDeleted),
	)

	response := &SearchResponse{
		Accounts: []AccountResult{},
	}

	// Check if query is an IP address
	if ip := net.ParseIP(query); ip != nil {
		span.SetAttributes(attribute.String("search.query_type", "ip"))
		if err := api.searchByIP(ctx, query, includeDeleted, response); err != nil {
			return nil, fmt.Errorf("IP search failed: %w", err)
		}
		api.addResultMetricsToSpan(span, response)
		return response, nil
	}

	// Check if query is ID format (id:123)
	if strings.HasPrefix(strings.ToLower(query), "id:") {
		span.SetAttributes(attribute.String("search.query_type", "id"))
		idStr := strings.TrimPrefix(strings.ToLower(query), "id:")
		if id, err := strconv.ParseInt(idStr, 10, 64); err == nil {
			if err := api.searchByAccountID(ctx, id, includeDeleted, response); err != nil {
				return nil, fmt.Errorf("ID search failed: %w", err)
			}
			api.addResultMetricsToSpan(span, response)
			return response, nil
		}
	}

	// Check if query is monitors search (monitors:)
	if strings.HasPrefix(strings.ToLower(query), "monitors:") {
		span.SetAttributes(attribute.String("search.query_type", "monitors"))
		if err := api.searchByMonitors(ctx, includeDeleted, response); err != nil {
			return nil, fmt.Errorf("monitors search failed: %w", err)
		}
		api.addResultMetricsToSpan(span, response)
		return response, nil
	}

	// Check if query is zone search (zone:zonename)
	if strings.HasPrefix(strings.ToLower(query), "zone:") {
		span.SetAttributes(attribute.String("search.query_type", "zone"))
		zoneName := strings.TrimSpace(strings.TrimPrefix(strings.ToLower(query), "zone:"))
		if zoneName == "" {
			return nil, errEmptyZoneName
		}
		if err := api.searchByZone(ctx, zoneName, includeDeleted, response); err != nil {
			return nil, fmt.Errorf("zone search failed: %w", err)
		}
		api.addResultMetricsToSpan(span, response)
		return response, nil
	}

	// Perform pattern-based search
	span.SetAttributes(attribute.String("search.query_type", "pattern"))
	if err := api.searchByPattern(ctx, query, includeDeleted, response); err != nil {
		return nil, fmt.Errorf("pattern search failed: %w", err)
	}

	api.addResultMetricsToSpan(span, response)
	return response, nil
}
```

Add `"errors"` to `search.go`'s import block (alongside the existing `"context"`, `"fmt"`, etc.).

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/ask/src/go/ntp/api
go test ./server/api/search/... -run TestSearchZoneEmptyName -v
```

Expected: PASS.

- [ ] **Step 5: Rewrite the integration test to exercise `search()` directly**

Replace `/Users/ask/src/go/ntp/api/server/api/search/search_integration_test.go` in full with:

```go
package search

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go.ntppool.org/api/server/base"
)

func TestSearchIntegration(t *testing.T) {
	// Skip if no test database
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set, skipping integration tests")
	}

	// Connect to test database
	db, err := pgxpool.New(context.Background(), dbURL)
	require.NoError(t, err)
	defer db.Close()

	api := &SearchAPI{BaseAPI: base.BaseAPI{DB: db}}
	ctx := context.Background()

	// Create test data
	setupSearchTestData(t, ctx, db)
	defer cleanupSearchTestData(t, ctx, db)

	// Test cases
	testCases := []struct {
		name       string
		query      string
		expectData bool
	}{
		{name: "Staff search by IP", query: "192.168.1.100", expectData: true},
		{name: "Staff search by email", query: "testuser", expectData: true},
		{name: "Staff search by hostname", query: "testhost", expectData: true},
		{name: "Staff search by partial hostname", query: "host", expectData: true},
		{name: "Staff search by hostname substring (nict)", query: "nict", expectData: true},
		{name: "Staff search by account ID", query: "id:5020", expectData: true},
		{name: "No results", query: "nonexistent", expectData: false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			response, err := api.search(ctx, tc.query, false)
			require.NoError(t, err)

			if tc.expectData {
				assert.NotEmpty(t, response.Accounts)
			} else {
				assert.Empty(t, response.Accounts)
			}
		})
	}
}

func setupSearchTestData(t *testing.T, ctx context.Context, db *pgxpool.Pool) {
	// Clean up first
	cleanupSearchTestData(t, ctx, db)

	// Create test account
	_, err := db.Exec(ctx, `
		INSERT INTO accounts (id, id_token, name, created_on, modified_on)
		VALUES (5020, 'test-account-token', 'Test Account', NOW(), NOW())
	`)
	assert.NoError(t, err)

	// Create test user
	_, err = db.Exec(ctx, `
		INSERT INTO users (id, id_token, email, username, name)
		VALUES (5021, 'test-user-token', 'testuser@example.com', 'testuser', 'Test User')
	`)
	assert.NoError(t, err)

	// Link user to account
	_, err = db.Exec(ctx, `
		INSERT INTO account_users (account_id, user_id)
		VALUES (5020, 5021)
	`)
	assert.NoError(t, err)

	// Create test server
	_, err = db.Exec(ctx, `
		INSERT INTO servers (id, ip, account_id, hostname, created_on)
		VALUES (5022, '192.168.1.100', 5020, 'testhost.example.com', NOW())
	`)
	assert.NoError(t, err)

	// Create additional test server with ntp.nict.jp pattern
	_, err = db.Exec(ctx, `
		INSERT INTO servers (id, ip, account_id, hostname, created_on)
		VALUES (5023, '192.168.1.101', 5020, 'ntp.nict.jp', NOW())
	`)
	assert.NoError(t, err)

	// Create test monitor
	_, err = db.Exec(ctx, `
		INSERT INTO monitors (id, id_token, account_id, ip, hostname, tls_name, status, is_current, type, config, created_on)
		VALUES (5024, 'test-monitor-token', 5020, '192.168.1.101', 'monitor.example.com', 'monitor.test.local', 'active', true, 'monitor', '{}', NOW())
	`)
	assert.NoError(t, err)
}

func cleanupSearchTestData(t *testing.T, ctx context.Context, db *pgxpool.Pool) {
	db.Exec(ctx, "DELETE FROM server_zones WHERE server_id IN (5022, 5023)")
	db.Exec(ctx, "DELETE FROM monitors WHERE id = 5024")
	db.Exec(ctx, "DELETE FROM servers WHERE id IN (5022, 5023)")
	db.Exec(ctx, "DELETE FROM account_users WHERE account_id = 5020")
	db.Exec(ctx, "DELETE FROM users WHERE id = 5021")
	db.Exec(ctx, "DELETE FROM accounts WHERE id = 5020")
}
```

This drops `TestSearchAuthenticationRequired` and `TestSearchStaffRequired` — that coverage moves to the new RPC handler's integration test in Task 4, since authorization now lives there, not in `search()`.

- [ ] **Step 6: Run tests to verify everything still passes**

```bash
cd /Users/ask/src/go/ntp/api
go build ./...
go test ./server/api/search/... -v
```

Expected: PASS (integration tests skip if `TEST_DATABASE_URL` is unset — that's fine).

- [ ] **Step 7: Commit**

```bash
cd /Users/ask/src/go/ntp/api
gofumpt -w server/api/search/search.go server/api/search/search_test.go server/api/search/search_integration_test.go
git add server/api/search/search.go server/api/search/search_test.go server/api/search/search_integration_test.go
git commit -m "refactor(search): extract query dispatch into search() (#43)"
```

---

## Task 3: Proto conversion helpers

**Files:**
- Create: `/Users/ask/src/go/ntp/api/server/api/search/proto_mapping.go`
- Create: `/Users/ask/src/go/ntp/api/server/api/search/proto_mapping_test.go`

**Interfaces:**
- Consumes: `SearchResponse`, `AccountResult`, `UserResult`, `ServerResult`, `MonitorResult`, `FilterContext` (all defined in `search.go`); `searchv1.SearchResponse`/`Account`/`User`/`Server`/`Monitor`/`FilterContext` (generated in Task 1).
- Produces: `func toProtoSearchResponse(r *SearchResponse) *searchv1.SearchResponse`.

- [ ] **Step 1: Write the failing test**

Create `/Users/ask/src/go/ntp/api/server/api/search/proto_mapping_test.go`:

```go
package search

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestToProtoSearchResponse(t *testing.T) {
	created := time.Date(2026, 7, 21, 12, 0, 0, 0, time.UTC)
	deletion := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	score := 42.5

	internal := &SearchResponse{
		Accounts: []AccountResult{
			{
				IdToken: "acct-token",
				Name:    "Test Account",
				Users: []UserResult{
					{ID: 1, Name: "Test User", Username: "testuser", Email: "test@example.com"},
				},
				Servers: []ServerResult{
					{
						ID:            10,
						IP:            "192.0.2.1",
						Score:         &score,
						Netspeed:      1000,
						NetspeedHuman: "1M",
						CreatedOn:     created,
						DeletionOn:    &deletion,
						Hostname:      "ntp.example.net",
						InPool:        true,
						Zones:         []string{"us", "north-america"},
					},
					{
						ID:        11,
						IP:        "192.0.2.2",
						CreatedOn: created,
						Hostname:  "no-deletion.example.net",
					},
				},
				Monitors: []MonitorResult{
					{
						ID:        20,
						IDToken:   "mon-token",
						TLSName:   "mon1.devel.mon.ntppool.dev",
						IP:        "192.0.2.10",
						IPVersion: "v4",
						Hostname:  "mon1.example.net",
						Location:  "Earth",
						Status:    "active",
						CreatedOn: created,
					},
				},
			},
		},
		FilterContext: &FilterContext{
			SearchType:          "zone",
			ZoneName:            "north-america",
			ShowZoneServersOnly: true,
		},
	}

	proto := toProtoSearchResponse(internal)

	require.Len(t, proto.Accounts, 1)
	account := proto.Accounts[0]
	assert.Equal(t, "acct-token", account.IdToken)
	assert.Equal(t, "Test Account", account.Name)

	require.Len(t, account.Users, 1)
	assert.Equal(t, "test@example.com", account.Users[0].Email)

	require.Len(t, account.Servers, 2)
	assert.Equal(t, &score, account.Servers[0].Score)
	assert.Equal(t, created.Format(time.RFC3339), account.Servers[0].CreatedOn)
	require.NotNil(t, account.Servers[0].DeletionOn)
	assert.Equal(t, deletion.Format(time.RFC3339), *account.Servers[0].DeletionOn)
	assert.Nil(t, account.Servers[1].DeletionOn)
	assert.Nil(t, account.Servers[1].Score)

	require.Len(t, account.Monitors, 1)
	assert.Equal(t, "mon1.devel.mon.ntppool.dev", account.Monitors[0].TlsName)

	require.NotNil(t, proto.FilterContext)
	assert.Equal(t, "north-america", proto.FilterContext.ZoneName)
	assert.True(t, proto.FilterContext.ShowZoneServersOnly)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/ask/src/go/ntp/api
go test ./server/api/search/... -run TestToProtoSearchResponse -v
```

Expected: FAIL to compile — `toProtoSearchResponse undefined`.

- [ ] **Step 3: Write the mapping implementation**

Create `/Users/ask/src/go/ntp/api/server/api/search/proto_mapping.go`:

```go
package search

import (
	"time"

	searchv1 "go.ntppool.org/api/gen/ntppool/search/v1"
)

// toProtoSearchResponse converts the internal search result into the
// ConnectRPC response shape.
func toProtoSearchResponse(r *SearchResponse) *searchv1.SearchResponse {
	accounts := make([]*searchv1.Account, 0, len(r.Accounts))
	for _, a := range r.Accounts {
		accounts = append(accounts, toProtoAccount(a))
	}

	resp := &searchv1.SearchResponse{Accounts: accounts}
	if r.FilterContext != nil {
		resp.FilterContext = &searchv1.FilterContext{
			SearchType:          r.FilterContext.SearchType,
			ZoneName:            r.FilterContext.ZoneName,
			ShowMonitorsOnly:    r.FilterContext.ShowMonitorsOnly,
			ShowZoneServersOnly: r.FilterContext.ShowZoneServersOnly,
		}
	}
	return resp
}

func toProtoAccount(a AccountResult) *searchv1.Account {
	users := make([]*searchv1.User, 0, len(a.Users))
	for _, u := range a.Users {
		users = append(users, &searchv1.User{
			Id:       u.ID,
			Name:     u.Name,
			Username: u.Username,
			Email:    u.Email,
		})
	}

	servers := make([]*searchv1.Server, 0, len(a.Servers))
	for _, s := range a.Servers {
		servers = append(servers, toProtoServer(s))
	}

	monitors := make([]*searchv1.Monitor, 0, len(a.Monitors))
	for _, m := range a.Monitors {
		monitors = append(monitors, &searchv1.Monitor{
			Id:        m.ID,
			IdToken:   m.IDToken,
			TlsName:   m.TLSName,
			Ip:        m.IP,
			IpVersion: m.IPVersion,
			Hostname:  m.Hostname,
			Location:  m.Location,
			Status:    m.Status,
			CreatedOn: m.CreatedOn.Format(time.RFC3339),
		})
	}

	return &searchv1.Account{
		IdToken:  a.IdToken,
		Name:     a.Name,
		Users:    users,
		Servers:  servers,
		Monitors: monitors,
	}
}

func toProtoServer(s ServerResult) *searchv1.Server {
	server := &searchv1.Server{
		Id:            s.ID,
		Ip:            s.IP,
		Score:         s.Score,
		Netspeed:      s.Netspeed,
		NetspeedHuman: s.NetspeedHuman,
		CreatedOn:     s.CreatedOn.Format(time.RFC3339),
		Hostname:      s.Hostname,
		InPool:        s.InPool,
		Zones:         s.Zones,
	}
	if s.DeletionOn != nil {
		deletionOn := s.DeletionOn.Format(time.RFC3339)
		server.DeletionOn = &deletionOn
	}
	return server
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/ask/src/go/ntp/api
go test ./server/api/search/... -run TestToProtoSearchResponse -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ask/src/go/ntp/api
gofumpt -w server/api/search/proto_mapping.go server/api/search/proto_mapping_test.go
git add server/api/search/proto_mapping.go server/api/search/proto_mapping_test.go
git commit -m "feat(search): add internal-to-proto response mapping (#43)"
```

---

## Task 4: ConnectRPC Search handler

**Files:**
- Create: `/Users/ask/src/go/ntp/api/server/api/search/rpc_search.go`
- Create: `/Users/ask/src/go/ntp/api/server/api/search/rpc_search_integration_test.go`

**Interfaces:**
- Consumes: `search.New` (existing), `api.search(ctx, query, includeDeleted)` (Task 2), `toProtoSearchResponse` (Task 3), `sessions.RequireUser(ctx) (ntpdb.UserX, error)`, `base.StandardJSONOptions()`.
- Produces: `type SearchServiceServer struct { *SearchAPI }`, `func NewSearchService(bapi base.BaseAPI) (*SearchServiceServer, error)`, `func (api *SearchServiceServer) Handler() (string, http.Handler)`, `func (api *SearchServiceServer) Search(ctx context.Context, req *connect.Request[searchv1.SearchRequest]) (*connect.Response[searchv1.SearchResponse], error)` — these are what `api.go` wires up in Task 5.

- [ ] **Step 1: Write the failing test**

Create `/Users/ask/src/go/ntp/api/server/api/search/rpc_search_integration_test.go`:

```go
package search

import (
	"context"
	"os"
	"testing"

	"connectrpc.com/connect"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	searchv1 "go.ntppool.org/api/gen/ntppool/search/v1"
	"go.ntppool.org/api/ntpdb"
	"go.ntppool.org/api/server/api/sessions"
	"go.ntppool.org/api/server/base"
)

func TestSearchRPC(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set, skipping integration test")
	}
	ctx := context.Background()

	db, err := pgxpool.New(ctx, dbURL)
	require.NoError(t, err)
	defer db.Close()

	svc, err := NewSearchService(base.BaseAPI{DB: db})
	require.NoError(t, err)

	setupSearchTestData(t, ctx, db)
	defer cleanupSearchTestData(t, ctx, db)

	staffUser := ntpdb.UserX{
		User: ntpdb.User{ID: 5001, Email: "staff@example.com"},
		Privilege: ntpdb.UserPrivilege{
			UserID:       pgtype.Int8{Int64: 5001, Valid: true},
			SupportStaff: pgtype.Bool{Bool: true, Valid: true},
		},
	}
	staffCtx := sessions.SetTestUserInContext(ctx, staffUser)

	t.Run("found", func(t *testing.T) {
		resp, err := svc.Search(staffCtx,
			connect.NewRequest(&searchv1.SearchRequest{Query: "192.168.1.100"}))
		require.NoError(t, err)
		assert.NotEmpty(t, resp.Msg.Accounts)
	})

	t.Run("no_results", func(t *testing.T) {
		resp, err := svc.Search(staffCtx,
			connect.NewRequest(&searchv1.SearchRequest{Query: "nonexistent"}))
		require.NoError(t, err)
		assert.Empty(t, resp.Msg.Accounts)
	})

	t.Run("empty_query_is_invalid_argument", func(t *testing.T) {
		_, err := svc.Search(staffCtx,
			connect.NewRequest(&searchv1.SearchRequest{Query: ""}))
		require.Error(t, err)
		assert.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err))
	})

	t.Run("unauthenticated", func(t *testing.T) {
		_, err := svc.Search(ctx, // no user in context
			connect.NewRequest(&searchv1.SearchRequest{Query: "test"}))
		require.Error(t, err)
		assert.Equal(t, connect.CodeUnauthenticated, connect.CodeOf(err))
	})

	t.Run("non_staff_is_permission_denied", func(t *testing.T) {
		nonStaffUser := ntpdb.UserX{
			User: ntpdb.User{ID: 5010, Email: "user@example.com"},
			Privilege: ntpdb.UserPrivilege{
				UserID:       pgtype.Int8{Int64: 5010, Valid: true},
				SupportStaff: pgtype.Bool{Bool: false, Valid: true},
			},
		}
		nonStaffCtx := sessions.SetTestUserInContext(ctx, nonStaffUser)

		_, err := svc.Search(nonStaffCtx,
			connect.NewRequest(&searchv1.SearchRequest{Query: "test"}))
		require.Error(t, err)
		assert.Equal(t, connect.CodePermissionDenied, connect.CodeOf(err))
	})
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/ask/src/go/ntp/api
go test ./server/api/search/... -run TestSearchRPC -v
```

Expected: FAIL to compile — `NewSearchService undefined`.

- [ ] **Step 3: Write the RPC handler**

Create `/Users/ask/src/go/ntp/api/server/api/search/rpc_search.go`:

```go
package search

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"connectrpc.com/connect"

	searchv1 "go.ntppool.org/api/gen/ntppool/search/v1"
	"go.ntppool.org/api/gen/ntppool/search/v1/searchv1connect"
	"go.ntppool.org/api/server/api/sessions"
	"go.ntppool.org/api/server/base"
)

// SearchServiceServer implements the ConnectRPC SearchService. It reuses the
// existing SearchAPI (search, formatNetspeed, formatScore) so no query logic
// or SQL is duplicated.
type SearchServiceServer struct {
	*SearchAPI
}

// NewSearchService constructs the ConnectRPC search service.
func NewSearchService(bapi base.BaseAPI) (*SearchServiceServer, error) {
	api, err := New(bapi)
	if err != nil {
		return nil, err
	}
	return &SearchServiceServer{SearchAPI: api}, nil
}

// Handler returns the Connect HTTP handler for this service.
func (api *SearchServiceServer) Handler() (string, http.Handler) {
	return searchv1connect.NewSearchServiceHandler(api, base.StandardJSONOptions())
}

// Search performs staff search across accounts, users, servers, and
// monitors. Staff-only.
func (api *SearchServiceServer) Search(
	ctx context.Context,
	req *connect.Request[searchv1.SearchRequest],
) (*connect.Response[searchv1.SearchResponse], error) {
	user, err := sessions.RequireUser(ctx)
	if err != nil {
		return nil, err
	}
	if !user.IsStaff() {
		return nil, connect.NewError(connect.CodePermissionDenied,
			fmt.Errorf("staff access required"))
	}

	query := strings.TrimSpace(req.Msg.Query)
	if query == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument,
			fmt.Errorf("query is required"))
	}

	response, err := api.search(ctx, query, req.Msg.IncludeDeleted)
	if err != nil {
		if errors.Is(err, errEmptyZoneName) {
			return nil, connect.NewError(connect.CodeInvalidArgument, err)
		}
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	return connect.NewResponse(toProtoSearchResponse(response)), nil
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/ask/src/go/ntp/api
go build ./...
go test ./server/api/search/... -v
```

Expected: PASS (integration tests skip without `TEST_DATABASE_URL`; if you have a test database available, set `TEST_DATABASE_URL` and confirm `TestSearchRPC` passes for real).

- [ ] **Step 5: Commit**

```bash
cd /Users/ask/src/go/ntp/api
gofumpt -w server/api/search/rpc_search.go server/api/search/rpc_search_integration_test.go
git add server/api/search/rpc_search.go server/api/search/rpc_search_integration_test.go
git commit -m "feat(search): add ConnectRPC Search handler (#43)"
```

---

## Task 5: Wire up ConnectRPC, remove the REST route

**Files:**
- Modify: `/Users/ask/src/go/ntp/api/server/api/api.go:255-258` (search service init), `:441-442` (REST route)
- Modify: `/Users/ask/src/go/ntp/api/server/api/search/search.go` (delete the Echo wrapper, prune now-unused imports)

**Interfaces:**
- Consumes: `search.NewSearchService(bapi base.BaseAPI) (*SearchServiceServer, error)` (Task 4), `(*SearchServiceServer).Handler() (string, http.Handler)` (Task 4).

- [ ] **Step 1: Swap the service init in api.go**

In `/Users/ask/src/go/ntp/api/server/api/api.go`, replace:

```go
		searchAPI, err := search.New(apisrv.BaseAPI)
		if err != nil {
			return err
		}
```

with:

```go
		searchService, err := search.NewSearchService(apisrv.BaseAPI)
		if err != nil {
			return err
		}
```

- [ ] **Step 2: Mount the ConnectRPC service, remove the REST route**

In the same file, remove:

```go
		// Staff search endpoint (requires staff privileges)
		authIntg.GET("/search", searchAPI.Search)
```

Then, in the `authRpcGroup` mounting block (immediately after the existing `// Mount SubscriptionService` block, i.e. after the line `authRpcGroup.Any(subscriptionPattern+"*", echo.WrapHandler(strippedSubscriptionHandler))`), add:

```go

		// Mount SearchService (requires authentication; staff-only checked in handler)
		searchPattern, searchHandler := searchService.Handler()
		strippedSearchHandler := http.StripPrefix("/int/rpc", searchHandler)
		authRpcGroup.Any(searchPattern+"*", echo.WrapHandler(strippedSearchHandler))
```

- [ ] **Step 3: Delete the Echo wrapper from search.go**

In `/Users/ask/src/go/ntp/api/server/api/search/search.go`, delete the `Search(c echo.Context) error` function added in Task 2 (keep `search()` and `errEmptyZoneName`).

Update the import block to drop what's now unused — the file's final imports:

```go
import (
	"context"
	"errors"
	"fmt"
	"math"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"go.ntppool.org/common/logger"
	"go.ntppool.org/common/tracing"

	"go.ntppool.org/api/ntpdb"
	"go.ntppool.org/api/server/base"
)
```

(This drops `"net/http"`, `"github.com/labstack/echo/v4"`, and `"go.ntppool.org/api/server/api/sessions"` — all now unused in this file since auth and HTTP-status mapping live in `rpc_search.go`.)

- [ ] **Step 4: Build and test**

```bash
cd /Users/ask/src/go/ntp/api
go build ./...
go vet ./...
go test ./server/api/search/... ./server/api/... -v
```

Expected: PASS. `go build ./...` confirms `api.go` compiles with the new mounting and no dangling references to `searchAPI.Search`.

- [ ] **Step 5: Confirm the REST route is gone**

```bash
cd /Users/ask/src/go/ntp/api
grep -n 'authIntg.GET("/search"' server/api/api.go
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
cd /Users/ask/src/go/ntp/api
gofumpt -w server/api/api.go server/api/search/search.go
git add server/api/api.go server/api/search/search.go
git commit -m "feat(search): mount SearchService, drop /int/search REST route (#43)"
```

---

## Task 6: Port Manage.pm to NP::CAPI::Search

**Files:**
- Modify: `/Users/ask/src/ntppool/lib/NTPPool/Control/Manage.pm:15` (imports), `:482-621` (`staff_search`)

**Interfaces:**
- Consumes: `NP::CAPI::Search::search($self->api_auth_params, query => $q, include_deleted => JSON::XS::true|false)` returning `{code, status_line, connect_code, data, error, trace_id}` where `data => {accounts => [...], filter_context => {...}|undef}` (generated in Task 1).

- [ ] **Step 1: Swap the import**

In `/Users/ask/src/ntppool/lib/NTPPool/Control/Manage.pm`, replace line 15:

```perl
use NP::IntAPI qw(int_api);
```

with (keeping the surrounding `use NP::CAPI::*` block in alphabetical order):

```perl
use NP::CAPI::Search qw(search);
```

The full import block (lines 14-20) becomes:

```perl
use NP::UA;
use NP::CAPI::Account
  qw(get_account_status validate_session get_user_accounts get_account_invites);
use NP::CAPI::Auth             qw(get_oauth_login_url process_auth0_login);
use NP::CAPI::Search           qw(search);
use NP::CAPI::Server           qw(get_server);
use NP::CAPI::ServerManagement qw(update_server);
```

- [ ] **Step 2: Swap the API call in `staff_search`**

In the same file, replace the `int_api(...)` call and its result handling (currently the block starting `# Call the new internal API search endpoint` through the closing `}` of the `else` branch, right before `# Add highlighting to IP addresses and hostnames`):

```perl
    # Call the new internal API search endpoint
    my $data = int_api(
        'get', 'search',
        {   q               => $q,
            user            => $self->plain_cookie($self->user_cookie_name),
            include_deleted => $include_deleted ? 'true' : 'false',
        },
        $self->_get_request_context()
    );

    my $results = {};
    if ($data->{code} == 200) {
        $results = $data->{data} || {};
    }
    elsif ($data->{code} == 404) {

        # No results found - return empty results
        $results = {accounts => []};
    }
    else {
        # API error - log and return empty results for degraded experience
        $results = {
            accounts => [],
            error    => 'Search temporarily unavailable',
            trace_id => $data->{trace_id}
        };
    }
```

with:

```perl
    # Call the search ConnectRPC API
    my $data = search(
        $self->api_auth_params,
        query           => $q,
        include_deleted => $include_deleted ? JSON::XS::true : JSON::XS::false,
    );

    my $results = {};
    if (!$data->{error}) {
        $results = $data->{data} || {};
    }
    else {
        # API error - log and return empty results for degraded experience
        $results = {
            accounts => [],
            error    => 'Search temporarily unavailable',
            trace_id => $data->{trace_id}
        };
    }
```

Everything below this (highlighting, CSS-class computation, telemetry, template rendering) is unchanged — it already reads `$results` and `$data->{code}`, and `NP::CAPI::Search::search`'s response hashref still carries `code` (HTTP status) the same way `int_api()`'s did.

- [ ] **Step 3: Verify it compiles**

```bash
cd /Users/ask/src/ntppool
perl -c lib/NTPPool/Control/Manage.pm
```

Expected: `lib/NTPPool/Control/Manage.pm syntax OK`.

- [ ] **Step 4: Run the Perl test suite**

```bash
cd /Users/ask/src/ntppool
make test
```

Expected: all tests pass (no existing test covers `staff_search` directly — this run just guards against a syntax/import regression elsewhere in the module).

- [ ] **Step 5: Commit**

```bash
cd /Users/ask/src/ntppool
perltidy -b lib/NTPPool/Control/Manage.pm
git add lib/NTPPool/Control/Manage.pm
git commit -m "feat(search): migrate staff_search from int_api to CAPI (#43)"
```

---

## Task 7: End-to-end verification

No code changes — this closes out the issue's verification checklist.

- [ ] **Step 1: Confirm no int_api search call remains**

```bash
cd /Users/ask/src/ntppool
grep -rn "int_api('get', 'search'" lib/
```

Expected: no output.

- [ ] **Step 2: Confirm the dead REST route is gone**

```bash
cd /Users/ask/src/go/ntp/api
grep -n 'authIntg.GET("/search"' server/api/api.go
```

Expected: no output (already verified in Task 5, re-confirming here as part of the issue's own checklist).

- [ ] **Step 3: Confirm `lib/NP/IntAPI.pm` is untouched**

```bash
cd /Users/ask/src/ntppool
git log --oneline -1 -- lib/NP/IntAPI.pm
```

Expected: shows a commit from before this branch's work — this file must not appear in any commit from Tasks 1-6. (It stays; deleting it is out of scope — see Global Constraints.)

- [ ] **Step 4: Manual staff-search smoke test on the dev site**

Using the dev site (`https://web.askdev.grundclock.com/manage/admin`, per `CLAUDE.local.md`), logged in as a staff user, verify each of the following returns sane results and the page/HTMX fragment renders without errors:

- IP lookup (e.g. a known server IP)
- `id:<account-id>` lookup
- Free-text pattern search (hostname or account name substring)
- `include_deleted` checkbox toggled on and off
- `monitors:` search (shows the "show all results" toggle and monitors-only default view)
- `zone:<zonename>` search (shows the zone-servers-only default view)

- [ ] **Step 5: Update the gitea issue**

```bash
cd /Users/ask/src/ntppool
tea comment 43 "Implemented: SearchService ConnectRPC added (go.ntppool.org/api), Manage.pm::staff_search migrated to NP::CAPI::Search, /int/search REST route removed. lib/NP/IntAPI.pm intentionally left in place — still needed by #28 and #37."
tea issues close 43
```

(Only run this after the manual smoke test in Step 4 passes and both repos' changes are pushed/merged per your normal workflow.)
