# Staff search: migrate int_api → ConnectRPC (#43)

## Goal

Replace the last non-monitor `int_api()` call site — staff search
(`Manage.pm:507`) — with a ConnectRPC `SearchService`, matching the pattern
already used for Monitor, Account, VendorZone, etc. This does **not** delete
`lib/NP/IntAPI.pm` itself: Monitor.pm's registration slice (#28) and
Account.pm's `monitor/admin/account-config` call (#37) are separate, still-open
follow-ups that also depend on it.

## Scope decisions (confirmed)

- **Highlighting/CSS-class logic stays in Perl.** The regex highlighting of
  matched IP/hostname substrings and the relevance CSS classes
  (`search-result-secondary`, `text-muted`) in `staff_search()` are pure
  presentation logic over already-fetched data. They stay exactly as they are;
  the API response shape is unchanged by this concern.
- **`lib/NP/IntAPI.pm` is not deleted by this issue.** It's still used by
  Account.pm (#37) and indirectly required until #28 finishes dropping its
  `use NP::IntAPI` import. Only the search-specific REST route and
  `int_api()` call are removed here.
- **Single combined change, not a phased rollout.** Since this is a low-risk,
  admin-only endpoint (not the multi-slice Monitor migration), the Go side
  adds the ConnectRPC service *and* removes the REST route/Echo handler in the
  same change, rather than keeping REST alive as a transitional fallback.
- **#36 (duplicate issue) closed**, work tracked under #43 only.

## Go: proto

New `proto/ntppool/search/v1/search.proto`:

```proto
service SearchService {
  // Search performs staff search across accounts, users, servers, and
  // monitors. Staff-only.
  rpc Search(SearchRequest) returns (SearchResponse) {}
}

message SearchRequest {
  string query = 1;
  bool include_deleted = 2;
}

message SearchResponse {
  repeated Account accounts = 1;
  FilterContext filter_context = 2;   // optional message; absent when unset
}

message FilterContext {
  string search_type = 1;
  string zone_name = 2;
  bool show_monitors_only = 3;
  bool show_zone_servers_only = 4;
}

message Account {
  string id_token = 1;
  string name = 2;
  repeated User users = 3;
  repeated Server servers = 4;
  repeated Monitor monitors = 5;
}

message User {
  int64 id = 1;
  string name = 2;
  string username = 3;
  string email = 4;
}

message Server {
  int64 id = 1;
  string ip = 2;
  optional double score = 3;
  int64 netspeed = 4;
  string netspeed_human = 5;
  string created_on = 6;       // RFC3339
  optional string deletion_on = 7;   // RFC3339, absent when not scheduled
  string hostname = 8;
  bool in_pool = 9;
  repeated string zones = 10;
}

message Monitor {
  int64 id = 1;
  string id_token = 2;
  string tls_name = 3;
  string ip = 4;
  string ip_version = 5;
  string hostname = 6;
  string location = 7;
  string status = 8;
  string created_on = 9;       // RFC3339
}
```

Field names and nesting mirror the current REST JSON exactly (already
snake_case), so the Perl template needs no field-name changes. Timestamps are
plain RFC3339 strings (matching the `LastSeenStatus.timestamp` convention in
`monitor.proto`, not `google.protobuf.Timestamp`). `score`/`deletion_on` use
proto3 `optional` for presence, matching today's `omitempty` pointer fields.

## Go: implementation

- Extract the query-type dispatch chain currently inline in
  `SearchAPI.Search(c echo.Context)` (the IP / `id:` / `monitors:` / `zone:` /
  pattern branches in `search.go`) into
  `func (api *SearchAPI) search(ctx context.Context, query string, includeDeleted bool) (*SearchResponse, error)`.
  All the existing helpers (`searchByIP`, `searchByPattern`,
  `populateAccountServersAndMonitors`, etc.) are unchanged — only the
  top-level dispatch moves out of the echo-specific function.
- Add `server/api/search/rpc_search.go`, following the `monitoradmin`
  pattern (`MonitorServiceServer` / `NewMonitorService`):
  - `SearchServiceServer` wraps `*SearchAPI`.
  - `NewSearchService(bapi base.BaseAPI) (*SearchServiceServer, error)`.
  - `Handler() (string, http.Handler)` via the generated
    `searchv1connect.NewSearchServiceHandler`.
  - `Search(ctx, *connect.Request[searchv1.SearchRequest]) (*connect.Response[searchv1.SearchResponse], error)`:
    staff check via `sessions.RequireUser` + `user.IsStaff()` →
    `connect.CodePermissionDenied`; empty query →
    `connect.CodeInvalidArgument`; calls the shared `search()`; converts the
    internal `*SearchResponse` to the proto response.
- Remove `SearchAPI.Search(c echo.Context) error` and the
  `authIntg.GET("/search", searchAPI.Search)` route registration in
  `server/api/api.go`. Mount the new service on `authRpcGroup` alongside
  VendorZone/Monitor/Subscription (same `RequireAuth` + rate-limit
  middleware).
- Tests: rewrite `search_test.go`/`search_integration_test.go` to exercise
  the extracted `search()` function directly (pure logic, no
  transport-specific test double needed) and the new `Search` RPC method
  (mirroring `monitoradmin/rpc_read_integration_test.go`'s fixture +
  `connect.NewRequest`/`connect.CodeOf` pattern) instead of driving
  `echo.Context`.

## Perl: implementation

- Run `make generate` (via the `ntppool -> /Users/ask/src/ntppool` symlink in
  the API repo) to produce `lib/NP/CAPI/Search.pm`, exporting `search()`.
- Port `Manage.pm::staff_search`:
  - Replace the `int_api('get', 'search', {...})` call with
    `NP::CAPI::Search::search($self->api_auth_params, query => $q, include_deleted => $include_deleted ? JSON::XS::true : JSON::XS::false)`.
  - Map the CAPI response shape (`code`/`data`/`error`/`trace_id`) the same
    way other migrated controllers do — `code == 200` → use `data`;
    non-200/error → degrade to `{accounts => [], error => ..., trace_id => ...}`
    (drop the old `code == 404` special case; ConnectRPC returns 200 with
    empty `accounts` for "no results", not 404).
  - No change to the highlighting, CSS-class, or span-attribute logic below
    the API call.
- Template `tpl/admin/search_results.html`: no changes expected (fields
  already match).

## Verification

- `grep -rn "int_api('get', 'search'" lib/` → no matches.
- `grep -rn "authIntg.GET(\"/search\"" server/api/api.go` (go repo) → no
  matches.
- Go unit + integration tests (`go test ./server/api/search/...`).
- Manual staff-search smoke test on the dev site: IP lookup, `id:` lookup,
  pattern search, `include_deleted`, `monitors:`/`zone:` filters — per the
  issue's original verification list.

## Out of scope (tracked elsewhere)

- Deleting `lib/NP/IntAPI.pm` — blocked on #28 (Monitor.pm registration slice
  + import drop) and #37 (Account.pm account-config).
- Moving highlighting/CSS-class computation into Go.
