# Monitor.pm — int_api → ConnectRPC (CAPI) migration

**Date:** 2026-07-02
**Gitea:** [#28](https://gitea.develooper.com/ntppool/ntppool/issues/28)
**Supersedes the Phase 1 assumptions in:** `plans/issue-28-monitor-capi-migration.md`

## Problem

`lib/NTPPool/Control/Manage/Monitor.pm` is the last large consumer of the legacy
`int_api()` REST wrapper (`lib/NP/IntAPI.pm`). It has 7 `int_api()` calls plus 2
`NP::IntAPI::*` helper calls. Two smaller callers remain elsewhere
(`Manage/Account.pm:1041`, `Manage.pm:507`). The goal is to standardize on
ConnectRPC via `NP::CAPI::*`, matching Server/Account/VendorZone, and delete
`NP::IntAPI`.

## Key discovery (changes the old plan)

The old plan doc assumed Phase 1 meant "copy the SQL and write Go handlers from
scratch." That is wrong. **All the monitor business logic already exists in the
Go `api` project** — it is simply exposed as REST (Echo) handlers under
`/int/monitor/*` and `/int/search`, which is exactly what `int_api()` calls
today:

| Perl call site | REST route | Go handler | SQL |
|---|---|---|---|
| `Monitor.pm:97` | `GET /int/monitor/manage/monitor` | `monitoradmin.GetMonitorData` | `monitor_admin.sql` |
| `Monitor.pm:237,272` | `GET /int/monitor/manage/` | `monitoradmin.GetMonitorList` | `monitor_admin.sql` |
| `Monitor.pm:307,374` | `POST /int/monitor/manage/status` | `monitoradmin.UpdateStatus` | `monitor_admin.sql` |
| `Monitor.pm:506` | `GET /int/monitor/manage/metrics/summary` | `monitoradmin.GetMetricsSummaryHandler` | Prometheus + `monitor_admin.sql` |
| `Monitor.pm:159` | `GET /int/monitor/registration/data` | `monitorreg.ConfirmDataHandler` | `monitor_registrations.sql` |
| `Monitor.pm:196` | `POST /int/monitor/registration/accept` | `monitorreg.UserAcceptanceHandler` | `monitor_registrations.sql` |
| `Account.pm:1041` | `GET/PATCH /int/monitor/admin/account-config` | `monitoradmin.*AccountConfigHandler` | `UpdateAccountFlags` |

The one non-monitor caller — `Manage.pm:507` → `GET /int/search` — is **out of
scope** for #28 and tracked separately as
[#43](https://gitea.develooper.com/ntppool/ntppool/issues/43). Deleting
`lib/NP/IntAPI.pm` happens in #43 once both issues land.

So the work is **transport modernization + logic reuse**, not new business logic:
extract the core of each Echo handler into a plain function, call it from a new
ConnectRPC handler, generate a `NP::CAPI::Monitor` wrapper, port the Perl, and
delete the REST route once nothing calls it.

## Two facts that drive the design

1. **Field-name churn is unavoidable.** The REST handlers use Go default JSON
   marshaling → PascalCase (`Monitors`, `TLSName`, `Account.ID`, `CombinedStatus`,
   `LastSeenStatus.Class`, `StatusColor`). Every ConnectRPC service here uses
   `base.StandardJSONOptions()` with `UseProtoNames: true` → **snake_case**
   (`tls_name`, `account.id`, `combined_status`, …). The migration therefore
   **must** update all `docs/manage/tpl/monitors/*.html` templates to the new
   field names. This is the largest hidden cost and is intrinsic to the change.

2. **No `_permissions` precedent exists.** Existing Connect services enforce auth
   by returning `connect.CodePermissionDenied`/`CodeNotFound`; `server.proto` uses
   a *request-side* `require_edit_permission` flag, not a response block. The old
   plan's `MonitorPermissions{can_view,can_edit,can_delete}` message would be a
   new pattern. We still need per-row editability in **list** views (to show/hide
   action buttons without N extra calls), so this design adds a small set of
   **inline `can_*` bool fields on the `Monitor` message**, computed server-side —
   the minimal amount of the old plan that we actually need.

## Approach

**Chosen: full ConnectRPC end-state, shipped in vertical slices.**

One `proto/ntppool/monitor/v1/monitor.proto` defining the whole service, but
implemented and merged as independent slices so each slice's Perl + template
changes can be verified on the dev site before the next begins. This gives the
consistent end-state the issue wants while keeping each reviewable and each REST
route removable the moment its Perl caller is gone.

Rejected alternatives:
- *CAPI wrapper that still calls REST* — does not retire `NP::IntAPI`; pointless.
- *One big-bang PR* — the template field-rename surface makes a single cutover
  hard to verify and risky to roll back.

## Service definition

`proto/ntppool/monitor/v1/monitor.proto`, mounted on the `authRpcGroup`
(`sessionAPI.RequireAuth`) in `server/api/api.go` under `/int/rpc/`, mirroring
`vendorzone`/`servermgmt`:

```protobuf
service MonitorService {
  rpc GetMonitor(GetMonitorRequest) returns (GetMonitorResponse);
  rpc ListMonitors(ListMonitorsRequest) returns (ListMonitorsResponse);        // account-scoped or all_accounts
  rpc UpdateMonitorStatus(UpdateMonitorStatusRequest) returns (UpdateMonitorStatusResponse);
  rpc GetMetricsSummary(GetMetricsSummaryRequest) returns (GetMetricsSummaryResponse);
  rpc GetRegistrationData(GetRegistrationDataRequest) returns (GetRegistrationDataResponse);
  rpc AcceptRegistration(AcceptRegistrationRequest) returns (AcceptRegistrationResponse);
  rpc GetAccountConfig(GetAccountConfigRequest) returns (GetAccountConfigResponse);
  rpc UpdateAccountConfig(UpdateAccountConfigRequest) returns (UpdateAccountConfigResponse);
}
```

(Delete is not a separate RPC — it is `UpdateMonitorStatus` with `status=deleted`,
matching current behavior.)

`Monitor` message carries **display-ready** data so Perl stops computing:

```protobuf
message Monitor {
  int64  id = 1;
  string id_token = 2;
  string name = 3;
  string tls_name = 4;
  string display_name = 5;          // suffix-stripped in Go (was Perl _monitor_list)
  string hostname = 6;
  string location = 7;
  string status = 8;                // lowercase DB value: pending/testing/active/paused/deleted
  string status_color = 9;
  string client_version = 10;
  MonitorAddr ipv4 = 11;
  MonitorAddr ipv6 = 12;
  bool   is_dualstack = 13;
  bool   combined_status = 14;
  bool   combined_last_seen = 15;
  LastSeenStatus last_seen_status = 16;
  MonitorAccount account = 17;

  // server-computed permissions (new; minimal inline bools)
  bool can_edit = 30;
  bool can_delete = 31;
  bool can_set_status = 32;         // admin-only status transitions
}
```

Lists return `repeated Monitor monitors` **already sorted** in Go (by account id,
tls_name, ip) — dropping Perl's `_monitor_list` sort/map entirely. Metrics
responses include pre-formatted `breakdown_1h`/`breakdown_24h` strings so
`_format_metrics_breakdown` is deleted from Perl.

**Wire-format note:** `status` (and `registration_state` below) are plain proto
`string` fields, **not** proto `enum`s. With `UseProtoNames: true` a proto enum
would serialize as `MONITOR_STATUS_ACTIVE`-style constants, forcing extra
template churn and diverging from the lowercase values the DB and templates
already use (`active`, `pending`, …). Keep them as lowercase strings.

## Permission rules (preserve current Go behavior)

Reuse the existing checks the REST handlers already apply — do not invent new policy:

- **List / Get:** SQL already scopes to the user's accounts unless
  `user.IsMonitorAdmin()`. `all_accounts` requires `IsMonitorAdmin()` (else 403 +
  `LogPrivilegeEscalation`). A `GetMonitor` for a monitor the caller can't see
  returns `CodeNotFound` (never `PermissionDenied`) so the API isn't an
  existence oracle — matching the current REST 404.
- **Which bool gates which control** (templates must follow this exactly):
  - `can_delete` → the delete button. True when monitor-admin OR the caller owns
    the monitor (a non-admin owner *can* delete their own monitor).
  - `can_set_status` → the admin status dropdown (arbitrary pending↔active↔paused
    transitions). Monitor-admin **only**. A non-admin owner has
    `can_set_status = false` but `can_delete = true` — deletion is the one status
    change they may make, and it flows through the delete control, not the
    dropdown.
  - `can_edit` → any future edit affordance; monitor-admin OR account member.
  These mirror the existing Go rule: non-admins may set status only to `deleted`
  and only on monitors they own.
- **UpdateMonitorStatus:** non-admins may only set `deleted`, and only on monitors
  they own (existing rule in `ntpdb.UpdateMonitorStatus`).
- **AccountConfig (get + update):** monitor-admin only (existing rule).
- **Registration:** existing account-write-freeze + ownership-on-reuse checks.
- **Search:** staff-only (existing rule) — see open decision.

## Audit logging

Status changes and deletes currently only `slog`-log; they write no `logs` row.
This design adds `logs` rows **in the same transaction** as the status change
(matching ServerManagement's `createAuditLog` → `CreateLogEntry`), so audit is
atomic and Perl never logs. This is a deliberate enhancement over current
behavior; flagged so it is a conscious choice, not an accident.

## Error handling & degradation

Registration control-flow is covered above; the other endpoints keep their
current Perl error behavior, re-expressed against the CAPI response contract
(`code`/`connect_code`/`error`/`trace_id`) via the existing `_handle_capi_error`:

- **List / Get / Status:** hard errors (403/404/500) render the normal error
  page through `_handle_capi_error` — same as today's `$data->{code} >= 300`
  branches.
- **Metrics must degrade gracefully.** `monitor_metrics` today catches a failed
  metrics call and still renders the page (metrics come from Prometheus, which
  can be down independently of the DB). `GetMetricsSummary` failure must **not**
  fail the whole monitor page — Perl keeps returning `{success=>0, error, trace_id}`
  and the template shows the existing degraded state. Do not let a Prometheus
  outage 500 the monitor list.

## Deployment ordering (per slice)

Perl and Go deploy independently, so each slice is a **2–3 step sequence**, not a
single PR: (1) deploy Go with the new RPC *and* the old REST route both live;
(2) cut the Perl controller/templates over to CAPI and deploy; (3) once no caller
remains, delete the REST route in a later Go deploy. Never collapse a slice into
one deploy that removes the REST route before the Perl cutover ships, or the dev
site breaks mid-deploy.

## Phases (each independently verifiable)

1. **Go scaffold.** `monitor.proto` + regen; empty `MonitorService` struct +
   `Handler()`; mount on `authRpcGroup`. No behavior yet.
2. **Manage read path.** Extract `GetMonitorData`/`GetMonitorList` logic into
   shared funcs; implement `GetMonitor`/`ListMonitors` (with `can_*` + sorting +
   `display_name`). Generate `NP::CAPI::Monitor`. Port `render_monitor`,
   `render_monitors`, `render_admin_list`, `_fetch_monitor_details`; update
   `list.html`, `show.html`, `admin_list.html`, `info_*`. Delete `_monitor_list`.
   *This is the fattest slice (2 RPCs, 4 render methods, 4+ templates). If it
   stalls, `GetMonitor`+`show.html` can ship separately from
   `ListMonitors`+`list.html`/`admin_list.html`. Watch for a monitor template
   fragment shared with a not-yet-migrated phase-3/4/5 page — a shared partial
   can't be field-renamed atomically until all its consumers are migrated.*
3. **Status / delete.** Implement `UpdateMonitorStatus` (+ in-tx audit log). Port
   `render_admin_status`, `render_delete_monitor`, `render_confirm_delete`.
4. **Metrics.** Implement `GetMetricsSummary` with pre-formatted breakdowns. Port
   `monitor_metrics`; delete `_format_metrics_breakdown`; update `metrics.html`.
5. **Registration.** Implement `GetRegistrationData`/`AcceptRegistration`. Port
   `render_confirm_monitor`; update `confirm_*` templates. Drop
   `use NP::IntAPI` from `Monitor.pm`; delete `Monitor.pm.bak`.

   **Control-flow note:** `render_confirm_monitor` currently branches on the
   REST **HTTP status** (`201` created, `202` accepted, `409`/`410` precheck
   conflict/gone) and a `status != 'pending'` check to choose between
   `confirm_form` / `confirm_status` / `confirm_accept`. ConnectRPC has no such
   per-call HTTP status, so the response carries an explicit
   `registration_state` **string** field plus the `precheck` result object, and
   the Perl branches on that field instead of `$data->{code}`. This is the only
   slice that changes control-flow semantics, not just field names.

   Crucially, `conflict` and `gone` are **normal user-flow outcomes returned in a
   successful response**, not connect errors — the handler must return them as
   payload, not as `CodeAlreadyExists`/`CodeNotFound`, or Perl would be forced
   back into `connect_code` branching. State → template mapping:

   | registration_state | condition (from current code) | template |
   |---|---|---|
   | `pending`  | precheck OK, registration still pending | `confirm_form` |
   | `accepted` | user accepted; awaiting monitor (was 202) | `confirm_status` |
   | `created`  | monitor set up (was 201) | `confirm_status` |
   | `conflict` | precheck failed / duplicate (was 409) | `confirm_status` (+ precheck msg) |
   | `gone`     | registration expired/invalid (was 410) | `confirm_status` |

   Verify this table is exhaustive against the Go precheck branches during
   implementation (esp. precheck-OK-but-already-accepted) before finalizing the
   proto.
6. **Account config.** Implement `GetAccountConfig`/`UpdateAccountConfig`. Port
   `Account.pm:1041`.
After each Perl slice lands, remove the REST route it replaced (all `/int/monitor/*`
routes are Perl-web-only consumers — verify none are hit by the monitor client
daemon before deleting). `lib/NP/IntAPI.pm` itself is deleted in #43, not here,
because `search` is the last caller.

## Verification

```bash
# 0 after phase 5 (both int_api() calls and the 2 NP::IntAPI::* registration
# helpers — get_monitoring_registration_data / accept_monitoring_registration —
# are gone; those two helpers are the Monitor.pm:159/196 sites handled by phase 5)
grep -rn "int_api\|NP::IntAPI" lib/NTPPool/Control/Manage/Monitor.pm    # 0 after phase 5

# 0 after phase 6 EXCEPT Manage.pm:507 (search) and lib/NP/IntAPI.pm itself,
# which are #43's job, not #28's. Within #28 this never reaches global 0:
grep -rn "int_api\|NP::IntAPI" lib/ | grep -v 'Manage.pm:\|NP/IntAPI.pm'  # 0 after phase 6
```

Manual smoke on `web.askdev.grundclock.com`: monitor list + metrics render;
single monitor page + status actions; admin cross-account list; registration
confirm + accept; user delete and admin status change; account-config update;
permission behavior for logged-out / non-owning member / staff.

## Resolved decisions

1. **Search scope — deferred.** `/int/search` is out of scope, tracked as #43.
   #28 is monitor-only. `NP::IntAPI` is deleted in #43.
2. **Permissions shape — inline bools.** `can_edit`/`can_delete`/`can_set_status`
   on the `Monitor` message, computed server-side. No nested `_permissions`
   message.
3. **Audit logging — included.** Status changes and deletes write in-transaction
   `logs` rows, matching ServerManagement.

## Out of scope

- Monitor data model / scoring changes.
- The monitor client daemon API (`monitorapi` package) — untouched.
- Translation files — monitor page text is unchanged.
