# Issue #28: Monitor.pm — int_api → CAPI (ConnectRPC)

**Status:** Complete (2026-08-15) — all five slices shipped, `lib/NP/IntAPI.pm`
deleted. Dev-site smoke tests below are still unrun.
**Gitea:** [#28](https://gitea.develooper.com/ntppool/ntppool/issues/28)
**Related:** retires most uses of `lib/NP/IntAPI.pm`

## Progress (2026-07-04)

Read path is migrated (commits `9549eb46`, `0ae46680`): `MonitorService.GetMonitor`
+ `ListMonitors` back `get_monitor` / `list_monitors`, already wired into
`render_monitor` (via `_fetch_monitor_details`), `render_monitors`, and
`render_admin_list`. `Monitor.pm` netspeed-adjacent Phase-4 work (`Server.pm`)
also landed separately (`7df45965`).

**Remaining `int_api`/`NP::IntAPI` call sites in `Manage/Monitor.pm`:**

| Line | Call | Slice | Backing Go handler (legacy Echo) |
|------|------|-------|----------------------------------|
| 297  | POST `monitor/manage/status` (admin set status) | **A** | `monitoradmin.UpdateStatus` |
| 363  | POST `monitor/manage/status` `status=deleted` (user delete) | **A** | `monitoradmin.UpdateStatus` |
| 495  | GET `monitor/manage/metrics/summary` | **B** | `monitoradmin.GetMetricsSummaryHandler` |
| 161  | `NP::IntAPI::get_monitoring_registration_data` | **C** | `monitorreg.ConfirmDataHandler` |
| 198  | `NP::IntAPI::accept_monitoring_registration` | **C** | `monitorreg.UserAcceptanceHandler` |

Delete is *not* a separate path — it is `UpdateStatus` with `status=deleted`, so
slice A covers both admin status-change and user delete via one
`UpdateMonitorStatus` RPC. `q.UpdateMonitorStatus`
(`ntpdb/helpers_monitor_update.go`) already exists with authorization baked in
(monitor_admin → any status; non-admin → delete-own only), so the write handler
is a thin wrapper — no new SQL.

## Slice designs

**Codegen:** `../go/ntp/api/ntppool` is a symlink to this repo, so `make generate`
(in the Go repo) regenerates Go stubs *and* writes `lib/NP/CAPI/Monitor.pm` here.
Workflow per slice: edit `monitor.proto` → `make generate` → implement handler →
`go test` → port Perl call site → verify Perl compiles.

**A — write path.** Add `UpdateMonitorStatus(name, ids[], status)` RPC returning an
empty/minimal response. Handler wraps `database.WithTransaction` +
`q.UpdateMonitorStatus` (mirrors `monitoradmin_update.go`). Port `render_admin_status`
(line 297) and `render_delete_monitor` (line 363). The REST 204-means-deleted signal
disappears (ConnectRPC always 200 on success), so the ported Perl branches on the
**status value it sent**, not the HTTP code: delete → redirect to list; admin
status=deleted → redirect to admin list; else → redirect to monitor page.
Behavior-faithful: no audit logging added (the REST endpoint had none; issue is
transport-only).

**B — metrics.** Add `GetMonitorMetricsSummary` RPC. The existing REST response is
loose JSON with polymorphic fields (`tests_per_minute_1h` is a breakdown object for
account/all-accounts queries but a bare float for names queries). Model it as strict
proto and move `_format_metrics_breakdown` into Go so the API returns display-ready
`breakdown_1h`/`breakdown_24h` strings. Port `monitor_metrics` (line 495); drop the
Perl `_format_metrics_breakdown` helper. Prometheus-dependent — preserve the graceful
"metrics unavailable" degradation as a non-error empty result.

**C — registration.** The big one. Ports `render_confirm_monitor` (lines 161, 198),
which call `NP::IntAPI::get_monitoring_registration_data` (GET
`monitor/registration/data`) and `accept_monitoring_registration` (POST
`monitor/registration/accept`). Both are backed by `monitorreg`'s
`ConfirmDataHandler` / `UserAcceptanceHandler`.

Why this slice is larger and riskier than A/B:
- **HTTP-status semantics.** The flow signals state through status codes —
  200 pending (show form), 201 completed, 202 accepted, 409 precheck conflict,
  410 gone — and the Perl branches on `$data->{code} == 201/202`. ConnectRPC
  success is always 200, so the response must carry an explicit
  `RegistrationState` enum and Perl/templates branch on that, not the HTTP code.
- **Response shape.** `ConfirmDataHandler` returns a loose `map[string]any`:
  status, client, hostname, tls_name, ip4, ip6, `precheck` (a
  `RegistrationPrecheck{ code: DuplicateHandlingCode(text), message, monitors:
  []ntpdb.Monitor, delete_monitors, new_ips }`), and `locations` (airport list).
  Templates read `data.precheck.code` ("None"/"ResetName"/"ResetKey"/"Add"),
  `data.precheck.monitors.0.tls_name`, `data.locations`, etc. All of this needs
  strict proto modeling — including a trimmed Monitor sub-message for the
  precheck list.
- **Echo coupling.** `ConfirmDataHandler` / `UserAcceptanceHandler` are deeply
  echo-coupled (`c.FormValue("token")`, `c.JSON(status, …)`, transaction
  management). They must be refactored into transport-agnostic core functions
  returning `(result, RegistrationState)` before a ConnectRPC handler can reuse
  them without duplicating the TOFU/precheck/vault logic.
- **Templates.** `confirm_form.html`, `confirm_status.html`, `confirm_accept.html`
  will need updates to branch on `RegistrationState` instead of the numeric `code`.
- **Local-verification gap.** The Perl+template side can't be compiled/run in this
  workspace (no Combust config / CPAN deps), so the Go contract has to be exactly
  right the first time and the Perl side verified on the dev site.

**Service placement (decision):** registration logic lives in the `monitorreg`
package, not `monitoradmin` where `MonitorService` is. Recommended: a **new
`MonitorRegistrationService`** ConnectRPC service in `monitorreg` (its own
handler wiring), rather than bolting these RPCs onto `MonitorService` and forcing
a cross-package dependency. Proto can still live under `ntppool/monitor/v1` or a
new `ntppool/monitorreg/v1`.

After C, `Monitor.pm` is `int_api`-free: drop `use NP::IntAPI`, delete leftover
`lib/NTPPool/Control/Manage/Monitor.pm.bak`. (Phase-4 non-monitor callers —
`Manage.pm:507` search, `Account.pm:1026` account-config — remain out of #28's
Monitor.pm scope and can be a follow-up before deleting `lib/NP/IntAPI.pm`.
Both shipped: search as #43, account-config as slice E.)

## Status

- **Slice A (write path)** — done. Go `56f1c12`, Perl `bd4cc0c0`.
- **Slice B (metrics)** — done. Go `ce8da00`, Perl `42c31876`.
- **Slice C (registration)** — Go side done: `MonitorRegistrationService`
  (`GetRegistrationData` + `AcceptRegistration`) implemented in the `monitorreg`
  package, wired into the authenticated RPC group, unit + integration tested;
  the accept transaction was shared with the REST `UserAcceptanceHandler` via
  `runAcceptRegistration` (that REST pair has since been removed — Go
  `00cc892`). Go `6910eb4` (proto was `b228260`). The generated
  `NP::CAPI::MonitorRegistration` wrapper is committed here. **Remaining
  (follow-up):** port `render_confirm_monitor` (Monitor.pm lines 161/198) to the
  wrapper, branch on `registration_state`/`code`, update the confirm templates,
  then drop `use NP::IntAPI` from Monitor.pm and delete `Monitor.pm.bak`.

- **Slice C Perl port** — done. `render_confirm_monitor` uses
  `NP::CAPI::MonitorRegistration`; `Monitor.pm` no longer references `NP::IntAPI`
  and `Monitor.pm.bak` is gone.
- **Slice D (search)** — done, shipped as #43 (`Manage.pm` → `NP::CAPI::Search`).
- **Slice E (account monitor config)** — done. `AccountService.UpdateAccountMonitorConfig`
  plus `GetAccount`'s `include_monitor_config`; `Manage.pm::account_monitor_config`
  and `Account.pm::render_monitor_config_update` ported; the dead `/int/monitor/manage/*`
  and `/int/monitor/admin/*` echo handlers removed; `lib/NP/IntAPI.pm` deleted.
  Details below. **Not yet verified on the dev site** — see Verification.

## Slice E — account monitor config, and retiring `NP::IntAPI`

`lib/NTPPool/Control/Manage/Account.pm:1026` (`PATCH
/int/monitor/admin/account-config`) is the only remaining `int_api()` caller.
Backed by `monitoradmin.PatchAccountConfigHandler`; the matching
`GetAccountConfigHandler` has no caller at all.

Two defects in the current code that the port fixes rather than preserves:

1. **Stale display after update.** On success the handler discards the API's
   updated config and re-renders `render_monitor_config_display($account)`, which
   recomputes from the *pre-update* `$account->{flags}`. The admin sees the old
   values until a page reload.
2. **Two owners of the effective-value defaults.** `Manage.pm:847`
   (`account_monitor_config`) parses `accounts.flags` JSON in Perl and applies
   `monitor_limit || 3` / `monitors_per_server_limit || 1`. Go owns that data.
   `GetAccountResponse.monitor_config` and `include_monitor_config` already exist
   in `account.proto` but are never populated by the handler.

### Go — `proto/ntppool/account/v1/account.proto`

`MonitorConfig` becomes the **effective** config (defaults applied), documented
as such. Nothing populates it today, so there is no wire-compat concern.

```protobuf
service AccountService {
  // Requires monitor_admin privileges.
  rpc UpdateAccountMonitorConfig(UpdateAccountMonitorConfigRequest)
      returns (UpdateAccountMonitorConfigResponse) {}
}

// Unset fields are not modified. monitor_limit = 0 or
// monitors_per_server_limit = 0 clears the per-account override;
// monitor_enabled = false clears the override.
message UpdateAccountMonitorConfigRequest {
  optional bool  monitor_enabled = 1;
  optional int64 monitor_limit = 2;
  optional int64 monitors_per_server_limit = 3;
}

message UpdateAccountMonitorConfigResponse {
  MonitorConfig monitor_config = 1;  // effective values after the update
}
```

Account resolves from the `a` parameter via `sessions.GetAccount(ctx)`, as with
the other account RPCs.

### Go — handlers (`server/api/account/`)

- **`UpdateAccountMonitorConfig`.** Requires `monitor_admin`; on failure
  `security.LogPrivilegeEscalation` + `PermissionDenied`, matching the REST
  handler. Merge the set fields into `ntpdb.AccountConfig`, reject a request that
  sets nothing (`InvalidArgument`), then inside `database.WithTransaction`:
  `UpdateAccountFlags` + `q.CreateLog` (`type = "account"`, admin user id, message
  naming the new values). Same transaction, following `mutations.go:245`.
  Return the effective config.
- **`GetAccount`.** Honor `include_monitor_config`: populate `MonitorConfig` from
  `account.Flags` with `monitor_limit == 0 → 3`, `monitors_per_server_limit == 0
  → 1`, `-1` preserved (means "disabled"). If the flag is set by a caller without
  `monitor_admin`, return `PermissionDenied` — do not silently omit. `mode` and
  the other `include_*` flags stay unimplemented; out of scope.
- Effective-value logic lives in one helper shared by both RPCs.

Tests: privilege matrix (monitor_admin / staff / member / outsider) on both RPCs,
partial-update merge semantics, 0-clears-override, empty request rejected, audit
row written in the same transaction, effective defaults incl. `-1`.

### Go — REST removal

Delete the echo handlers now that no consumer in this deployment remains.

Precondition verified: prod `ntppool-main` is served by a build of the API
repo's separate long-lived `mysql` branch, which still carries every one of
these handlers. Removing them from `main` does not affect production.

- `server/api/monitoradmin/account_config.go` + `account_config_test.go`
- `monitoradmin.go`: `GetMonitorData`, `GetMonitorList`, and `getMonitorByName`
  (only `GetMonitorData` called it). Keep `formatMonitorList`, `statusColor`,
  `LastSeenInfo` — used by the RPCs.
- `monitoradmin_update.go`: `UpdateStatus` (keep `q.UpdateMonitorStatus` usage in
  `rpc_update_status.go`); the file is then empty, so delete it
- `eligibility.go`: `GetEligibilityHandler`
- `metrics_summary.go`: `GetMetricsSummaryHandler`, its echo-coupled helpers
  `handleAccountQuery` / `handleMonitorNamesQuery`, and the `generate*Metrics`
  functions those two were the only callers of. Keep `queryPrometheus*`,
  `buildPromQLQuery`, `parsePrometheusVectorWithBreakdown`,
  `getMonitorAccountMapping` — used by `rpc_metrics_summary.go`.
  (An earlier draft of this list said to keep `getMonitorByName` and the
  `generate*Metrics` set; a reference check showed all of them die with the
  echo handlers. Go does not flag unused package-level functions, so verify
  by grep rather than by build.)
- `server/api/api.go`: the `monManage` and `monAdminConfig` groups
- Re-point or delete the REST-shaped tests (`update_status_test.go`,
  `eligibility_test.go`, and the `_integration_test.go` files that drive
  `httptest` requests) at the RPC handlers.

**Not** removed: `/int/monitor/registration/{data,accept}`. Sharing
`runAcceptRegistration` with the REST path was deliberate and it is a separate
route group — worth its own decision.

### Perl

- Regenerate `lib/NP/CAPI/Account.pm` (`make generate` in the Go repo writes
  through the `ntppool` symlink) → `update_account_monitor_config`.
- `Manage.pm::account_monitor_config` — drop the flags parsing and the Perl
  defaults; call `get_account(..., account => $account->{id_token},
  include_monitor_config => 1)` and return `$result->{data}{monitor_config}`.
  Cache successes only; on error log the message and trace id and return undef.
  No account → undef.
- `Account.pm::render_monitor_config_update` — call
  `update_account_monitor_config`, seed the request cache with
  `$result->{data}{monitor_config}` so the display re-renders from the API's
  authoritative values (fixes defect 1 with no second round trip). Errors go
  through `capi_error_status` / the `error` template param.
- `render_account_form` hides the monitor-config section when the fetch fails
  (display degrades, error still logged); the HTMX handlers surface it.
- Field naming: use the API's `monitors_per_server_limit` end to end — rename the
  form field and the three template reads rather than remapping in Perl.
  Templates: `monitor_config_edit_form.html`, `monitor_config_section.html`,
  `monitor_config_display_clean.html`.
- Drop `use NP::IntAPI qw(int_api)` and the now-unused `my $json` from
  `Account.pm`; drop `decode_json` from `Manage.pm` if unused after the change.
- Delete `lib/NP/IntAPI.pm`.
- Remove the `warn "DEBUG: ..."` lines in the monitor-config path while touching
  it.
- Docs: drop the `NP::IntAPI` sections from `CLAUDE.md` and `configuration.md:508`
  (`Makefile.old` left alone).

### Verification

No Perl unit tests here — verify on https://web.askdev.grundclock.com/ as a
monitor admin: account page renders the config section; Edit → form is populated;
save → display shows the *new* values immediately; limit `0`/`-1` round-trip
correctly; a non-admin gets 403 on `/manage/account/monitor-config`; the audit
entry appears in the account log. Go side: `go test ./...`.

## Context

`lib/NTPPool/Control/Manage/Monitor.pm` is the last large consumer of the legacy
`int_api()` REST wrapper (`NP::IntAPI`). It already has no `NP::Model` access —
`can_edit` is commented out at `lib/NTPPool/Control/Manage/Monitor.pm:78` — so
migrating it is purely a transport change: REST endpoints → ConnectRPC, and
permission enforcement moves into the Go handlers via `_permissions` on the
response (same pattern as Server/Account/VendorZone).

Retiring `NP::IntAPI` also requires porting three smaller sites
(`Manage.pm:529`, `Manage/Server.pm:387`, `Manage/Account.pm:808`), tracked at
the end of this plan.

## Current REST surface (to replace)

All inside `lib/NTPPool/Control/Manage/Monitor.pm`:

| Line | Method | Endpoint                           | Purpose                                    |
|------|--------|------------------------------------|--------------------------------------------|
| 97   | GET    | `monitor/manage/monitor`           | fetch single monitor by `name` for account |
| 159  | —      | `NP::IntAPI::get_monitoring_registration_data` | registration TOFU lookup     |
| 196  | —      | `NP::IntAPI::accept_monitoring_registration`   | confirm registration         |
| 237  | GET    | `monitor/manage/`                  | list monitors for current account          |
| 272  | GET    | `monitor/manage/` (`all_accounts=1`) | admin: list across all accounts          |
| 307  | POST   | `monitor/manage/status`            | admin: set status (pending/active/etc.)    |
| 374  | POST   | `monitor/manage/status` (`status=deleted`) | user delete                        |
| 506  | GET    | `monitor/manage/metrics/summary`   | tests-per-minute metrics summary           |

All endpoints authenticate with session cookie (`user`) + account context (`a`).

## Target: `monitor/v1/monitor.proto`

Create `../go/ntp/api/proto/ntppool/monitor/v1/monitor.proto`, mirroring the
existing VendorZone / Server services:

```protobuf
service MonitorService {
  rpc ListMonitors(ListMonitorsRequest) returns (ListMonitorsResponse);
  rpc ListMonitorsAdmin(ListMonitorsAdminRequest) returns (ListMonitorsAdminResponse);
  rpc GetMonitor(GetMonitorRequest) returns (GetMonitorResponse);
  rpc UpdateMonitorStatus(UpdateMonitorStatusRequest) returns (UpdateMonitorStatusResponse);
  rpc DeleteMonitor(DeleteMonitorRequest) returns (DeleteMonitorResponse);
  rpc GetMonitorMetricsSummary(GetMonitorMetricsSummaryRequest) returns (GetMonitorMetricsSummaryResponse);
  rpc GetRegistrationData(GetRegistrationDataRequest) returns (GetRegistrationDataResponse);
  rpc AcceptRegistration(AcceptRegistrationRequest) returns (AcceptRegistrationResponse);
}

message Monitor {
  int64  monitor_id = 1;
  string id_token = 2;
  string name = 3;
  string tls_name = 4;
  string status = 5;                // pending, testing, active, paused, deleted
  int32  ip_version = 6;
  string ip = 7;
  string hostname = 8;
  string created_on = 9;
  string modified_on = 10;

  MonitorAccountContext account = 20;   // included when caller has permission
  MonitorPermissions _permissions = 21; // computed server-side
}

message MonitorPermissions {
  bool can_view = 1;
  bool can_edit = 2;     // vendor_admin OR support_staff OR account member
  bool can_delete = 3;
  bool can_set_status = 4;   // admin-only statuses
}
```

Pre-formatted display strings (breakdowns for `tests_per_minute_1h`/`24h`)
should be computed in the Go handler so Perl can drop
`_format_metrics_breakdown` — matches the architecture rule that Go returns
display-ready data.

## Phase 1 — Go API

1. **Proto.** Author `monitor/v1/monitor.proto` with RPCs above. Regenerate Go
   + Perl CAPI stubs.
2. **SQL.** Copy the queries that back `int/monitor/manage/*` into
   `../go/ntp/api/sql/monitors.sql` (or reuse existing if already present from
   prior monitor work). Ensure `ListMonitors` joins monitor↔account↔user for
   permission computation and metrics summary joins whatever
   `monitor/manage/metrics/summary` currently reads.
3. **Handlers.**
   `../go/ntp/api/server/api/monitor/{get,list,list_admin,status,delete,metrics,registration}.go`.
   Permission computation follows the VendorZone pattern: compute `_permissions`
   server-side based on authenticated user + account membership + `support_staff`/`vendor_admin`
   privileges, return it on every Monitor message.
4. **Audit logging.** Status changes and deletes must write
   `ntppool/audit/v1` log entries in the same transaction, matching
   ServerManagement.
5. **Registration flow.** `GetRegistrationData` + `AcceptRegistration` replace
   the two `NP::IntAPI::*` helpers. The shape should match what
   `render_confirm_monitor` and friends currently consume.
6. **Tests.** Go unit + integration; include permission matrix coverage for
   owner, account-member, staff, vendor-admin, and outsider.

## Phase 2 — Perl CAPI wrapper

Create `lib/NP/CAPI/Monitor.pm` with generated wrappers. Target exports:

```perl
use NP::CAPI::Monitor qw(
    list_monitors
    list_monitors_admin
    get_monitor
    update_monitor_status
    delete_monitor
    get_monitor_metrics_summary
    get_registration_data
    accept_registration
);
```

All follow the standard `NP::CAPI` response contract (`code`, `data`, `error`,
`trace_id`).

## Phase 3 — Port `Manage/Monitor.pm`

Replace each `int_api()` / `NP::IntAPI::*` call with the matching CAPI
function. Pattern per call site:

```perl
my $result = get_monitor(
    $self->api_auth_params,
    account => $self->current_account->{id_token},
    name    => $name,
);
return $self->_handle_capi_error($result) if $result->{error};
my $monitor = $result->{data}{monitor};
return 403 unless $monitor->{_permissions}{can_view};
```

Replace `_format_metrics_breakdown` usage with pre-formatted strings from the
Go side. Remove the inline permission comment at line 78 and either reinstate
the check via `_permissions` or delete the dead comment.

Drop `use NP::IntAPI` from this file once all sites are ported.

## Phase 4 — Retire `NP::IntAPI`

Port the remaining three callers so `lib/NP/IntAPI.pm` can be deleted:

- `lib/NTPPool/Control/Manage.pm:529` — look at its endpoint and add the matching CAPI method (likely in `NP::CAPI::Server` or `Account`).
- `lib/NTPPool/Control/Manage/Server.pm:387` — netspeed update; extend `NP::CAPI::Server::update_server` (or a dedicated RPC) and switch over.
- `lib/NTPPool/Control/Manage/Account.pm:808` — audit which endpoint; fold into `NP::CAPI::Account`.

After all four files are clean, `rm lib/NP/IntAPI.pm` and drop the `use
NP::IntAPI` imports.

## Verification

```bash
# After Phase 3
grep -rn "int_api\|NP::IntAPI" lib/NTPPool/Control/Manage/Monitor.pm   # expect zero

# After Phase 4
grep -rn "int_api\|NP::IntAPI" lib/                                     # expect zero outside lib/NP/IntAPI.pm (before delete)
ls lib/NP/IntAPI.pm                                                     # expect "No such file" after delete
```

Manual smoke tests:

- `/manage/monitors/` — account list renders with metrics + breakdowns
- `/manage/monitors/<name>` — single monitor page renders, status actions work
- `/manage/monitors/admin` — admin cross-account listing
- Monitor registration flow — registration token accept + pending → active transition
- Delete monitor via user flow and admin status-change flow
- Permission checks: a logged-out user, a non-owning account member, a staff user

## Out of scope

- Changes to monitor data model or scoring — this is transport migration only.
- Translation files (text on these pages is unchanged).

## Related plans

- `plans/account-model-complete-removal.md` — tracks #28 as "lower priority" relative to #22.
- `plans/account-model-removal-phases.md` — Phase 3 entry.
- `plans/issue-22-stripe-billing-migration.md` — unrelated but runs in parallel.
