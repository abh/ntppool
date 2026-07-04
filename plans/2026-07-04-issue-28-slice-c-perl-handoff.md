# Handoff: #28 Slice C — Perl/template port of the monitor registration flow

**Date:** 2026-07-04
**Prereq done:** Go side of `MonitorRegistrationService` is implemented, wired,
and tested (api repo `6910eb4`; proto `b228260`). The generated Perl client
`lib/NP/CAPI/MonitorRegistration.pm` is committed (ntppool `02674009`).
**This doc:** everything needed to port `render_confirm_monitor` off
`NP::IntAPI` and retire `int_api` from `Manage/Monitor.pm`.

Related: `plans/issue-28-monitor-capi-migration.md` (overall slicing + status).

---

## Goal

Replace the two legacy calls in
`lib/NTPPool/Control/Manage/Monitor.pm::render_confirm_monitor`:

| Line | Legacy call | New wrapper |
|------|-------------|-------------|
| ~161 | `NP::IntAPI::get_monitoring_registration_data($token, $user, $account, $ctx)` | `NP::CAPI::MonitorRegistration::get_registration_data(...)` |
| ~198 | `NP::IntAPI::accept_monitoring_registration($token, $user, $account, $location, $ctx)` | `NP::CAPI::MonitorRegistration::accept_registration(...)` |

Then drop `use NP::IntAPI qw(int_api);`, delete
`lib/NTPPool/Control/Manage/Monitor.pm.bak`, and (optionally) remove the now-dead
`get_monitoring_registration_data` / `accept_monitoring_registration` helpers
from `lib/NP/IntAPI.pm`.

After this, `Manage/Monitor.pm` has **zero** `int_api`/`NP::IntAPI` references.

---

## The one thing that will trip you up

ConnectRPC success is **always HTTP 200** at the transport layer. The templates
(`confirm_form.html`, `confirm_status.html`, `confirm_accept.html`) branch on a
`code` template var that used to be the REST **semantic** status (200 pending /
201 completed / 202 accepted / 409 conflict / 410 gone).

The Go handlers preserve that semantic status in a **`code` field inside the
response body** (`registration_state` enum is also there if you prefer it). So:

```
template `code`  <=  $result->{data}{code}      # on success (transport 200)
template `code`  <=  $result->{code}            # on transport error (404/500/…)
template `data`  <=  $result->{data}
template `error` <=  $result->{error}           # only set on transport error
```

Do **not** feed the transport `$result->{code}` into the template on success —
it's always 200 and the confirm/status pages will render the wrong branch.

Transport errors happen only for: bad/empty token (`not_found` → 404), account
mismatch (`permission_denied` → 403), frozen account (`failed_precondition`),
bad location on accept (`invalid_argument` → 400), internal (`internal` → 500).
Everything else (pending/accepted/completed/gone/conflict) is a **successful**
RPC whose meaning is in `data.code` / `data.registration_state`.

---

## Response shapes (what `$result->{data}` contains)

`NP::CAPI` responses always have `{ code, status_line, connect_code, data,
error, trace_id }`. `code`/`error` are the *transport* fields. The registration
payload is in `data`, with snake_case keys (StandardJSONOptions), matching the
templates:

### get_registration_data → `data`
```
{
  registration_state => "PENDING" | "CONFLICT" | "ACCEPTED" | "COMPLETED" | "GONE",
  code               => 200 | 409 | 202 | 201 | 410,   # semantic status
  status             => "pending" | ...,               # raw monitor_registrations.status
  client             => "...",
  hostname           => "...",
  tls_name           => "...",
  ip4                => "...",
  ip6                => "...",
  precheck => {
    code    => "None" | "Add" | "ResetName" | "ResetKey" | "Blocked",
    message => "...",
    monitors        => [ { id, id_token, tls_name, hostname, ip4, ip6, status }, ... ],
    delete_monitors => [ ... ],
    new_ips         => [ "192.0.2.5", ... ],
  },
  locations => [ { code => "SJC", name => "San Jose" }, ... ],   # omitted for ResetKey/Add
}
```

### accept_registration → `data`
```
{
  registration_state => "ACCEPTED" | "CONFLICT" | "COMPLETED" | "ACCEPTED" | "GONE",
  code               => 202 | 409 | 201 | 410,
  status             => "accepted" | ...,
  tls_name           => "...",   # set on ACCEPTED
}
```

Note: `EmitDefaultValues` is on, so zero values are present (e.g. `code => 0`
never happens here because the handler always sets it; empty strings/arrays may
appear). There is **no `Message` field** — the old `data.Message` block in
`confirm_status.html` will simply not render (harmless; leave or delete it).

---

## Edit 1 — imports (`Manage/Monitor.pm`)

Add the wrapper import; the file already imports the other CAPI monitor fns.

```perl
use NP::CAPI::MonitorRegistration qw(get_registration_data accept_registration);
```

After the whole slice, remove `use NP::IntAPI qw(int_api);` (nothing else in the
file uses it once registration is ported — verify with
`grep -n 'int_api\|NP::IntAPI' lib/NTPPool/Control/Manage/Monitor.pm`).

## Edit 2 — `render_confirm_monitor` GET branch (~line 159–193)

**Before:**
```perl
my $data = NP::IntAPI::get_monitoring_registration_data(
    $validation_token,
    $self->plain_cookie($self->user_cookie_name),
    $self->current_account->{id_token},
    $self->_get_request_context(),
);
if ($data->{error}) {
    $self->tpl_param('error', $data->{error});
}
$self->tpl_param('message', $data->{message});
$self->tpl_param('code',    $data->{code});
$self->tpl_param('data',    $data->{data});
$self->tpl_param('error',   $data->{error});

if ($status_check) { ... }
if ($data->{code} == 201 || $data->{code} == 202
    || ($data->{data} && $data->{data}->{status} && $data->{data}->{status} ne 'pending')) {
    return OK, $self->evaluate_template('tpl/monitors/confirm_status.html');
}
return OK, $self->evaluate_template('tpl/monitors/confirm_form.html');
```

**After:**
```perl
my $result = get_registration_data(
    $self->api_auth_params,
    account => $self->current_account->{id_token},
    token   => $validation_token,
);

# ConnectRPC transport is always 200 on success; the semantic status the
# templates branch on lives in data.code (see handoff doc).
my $rdata = $result->{data} || {};
my $code  = $result->{error} ? $result->{code} : $rdata->{code};

$self->tpl_param('error', $result->{error}) if $result->{error};
$self->tpl_param('code',  $code);
$self->tpl_param('data',  $rdata);

if ($status_check) {
    return OK, $self->evaluate_template('tpl/monitors/confirm_status.html');
}

if (   $code == 201
    || $code == 202
    || ($rdata->{status} && $rdata->{status} ne 'pending'))
{
    return OK, $self->evaluate_template('tpl/monitors/confirm_status.html');
}
return OK, $self->evaluate_template('tpl/monitors/confirm_form.html');
```

(The old `message` tpl_param had no consumer besides the vanished `data.Message`;
drop it. Keep the `$status_check` early-return semantics unchanged.)

## Edit 3 — `render_confirm_monitor` POST branch (~line 195–212)

**Before:**
```perl
my $data = NP::IntAPI::accept_monitoring_registration(
    $validation_token,
    $self->plain_cookie($self->user_cookie_name),
    $self->current_account->{id_token},
    $self->req_param("location_code"),
    $self->_get_request_context(),
);
if ($data->{error}) { $self->tpl_param('error', $data->{error}); }
$self->tpl_param('message', $data->{message});
$self->tpl_param('code',    delete $data->{code});
$self->tpl_param('data',    $data->{data});
return OK, $self->evaluate_template('tpl/monitors/confirm_accept.html');
```

**After:**
```perl
my $result = accept_registration(
    $self->api_auth_params,
    account       => $self->current_account->{id_token},
    token         => $validation_token,
    location_code => $self->req_param("location_code"),
);

my $rdata = $result->{data} || {};
$self->tpl_param('error', $result->{error}) if $result->{error};
$self->tpl_param('code',  $result->{error} ? $result->{code} : $rdata->{code});
$self->tpl_param('data',  $rdata);
return OK, $self->evaluate_template('tpl/monitors/confirm_accept.html');
```

## Edit 4 — `confirm_form.html` (the only required template change)

The proto `Location` message serializes as `{ code, name }` (snake, lowercase),
but the template reads capitalized `.Code` / `.Name`. Lines ~103–104:

```diff
- <option [% IF (first OR (location_code==locode.Code)); "selected" ; END %]
-     value="[% locode.Code | html %]">[% locode.Code | html %] ([% locode.Name | html %])</option>
+ <option [% IF (first OR (location_code==locode.code)); "selected" ; END %]
+     value="[% locode.code | html %]">[% locode.code | html %] ([% locode.name | html %])</option>
```

Everything else in `confirm_form.html` already matches the new shape:
`data.status`, `data.tls_name`, `data.ip4/ip6`, `data.client`, `data.hostname`,
`data.precheck.code` ("None"/"ResetName"/…), `data.precheck.monitors.0.tls_name`,
and the submit-disable guard `code != 200 OR error`.

## Edit 5 — `confirm_status.html` / `confirm_accept.html`

No changes required if `code` is populated from `data.code` (Edits 2–3). Verify:
- `confirm_status.html` branches on `code == 201 / 202 / <300`, uses
  `data.tls_name`, `data.status`. The `data.Message` block never fires now
  (no such field) — leave it or delete it.
- `confirm_accept.html` branches on `error OR code > 299` and `code == 404/400/500`.
  For a transport error, `error` + `code` are set (Edit 3). For a semantic
  conflict/gone on a *successful* RPC, `code` is 409/410 (> 299) so the error
  block renders — matches old behavior.

## Edit 6 — cleanup

```bash
git rm lib/NTPPool/Control/Manage/Monitor.pm.bak
```
Remove `use NP::IntAPI qw(int_api);` from `Monitor.pm`. Optionally delete the
now-unused `get_monitoring_registration_data` / `accept_monitoring_registration`
subs from `lib/NP/IntAPI.pm` (grep first — confirm no other caller).

---

## Verification (no local Perl runtime here)

The app can't be compiled/run in this workspace (no Combust config / CPAN deps),
so verify on the dev site: **https://web.askdev.grundclock.com/** (cache-bust with
`?x=<rand>`). Deploy the api repo + ntppool branch, then walk the flow:

1. **Register a monitor** (client) to get a confirmation token, or reuse a
   pending `monitor_registrations` row; open
   `/manage/monitors/confirm/<token>` — expect the **form** (PENDING) with the
   location dropdown populated (confirms `locations` + Edit 4), the correct
   client/hostname/IPs, and any precheck note ("ResetName"/"ResetKey").
2. **Submit** the form → `confirm_accept.html` should show success and then the
   status poller (`confirm_status.html`, `code==202`).
3. **Re-open** a completed token → COMPLETED (`code==201`) with the "continue"
   link to the monitor page.
4. **Bad token** `/manage/monitors/confirm/nope` → error path (transport 404).
5. Check the network tab: calls go to `/int/rpc/ntppool.monitorreg.v1.MonitorRegistrationService/...`.

Watch the api-server logs for the RPC spans and any `precheck` / accept warnings.

### Edge cases to eyeball
- **Frozen account**: accept returns transport `failed_precondition` → `error`
  set, `code` from `$result->{code}`. Confirm the accept page shows an error.
- **Conflict precheck** on GET: `data.code == 409`, still renders the form with
  `data.precheck` populated (the submit stays enabled unless you also gate on
  precheck — matches old behavior, which only disabled on `code != 200`).
  NOTE: old REST returned form on 409-with-pending too; keep that.
- **ResetKey/Add**: `locations` is omitted — the form's `IF data.locations`
  guard already handles that.

---

## Then: retire `lib/NP/IntAPI.pm` entirely (separate follow-up, not #28-Monitor)

Two non-monitor callers remain across the codebase:
- `lib/NTPPool/Control/Manage.pm:507` — `int_api('get','search', …)`
- `lib/NTPPool/Control/Manage/Account.pm:1026` — `int_api('patch','monitor/admin/account-config', …)`

Port those to CAPI (new RPCs or fold into existing services), then
`git rm lib/NP/IntAPI.pm` and drop its imports. (`Server.pm` netspeed was already
migrated in `7df45965`.)

---

## Quick reference — Go contract source

- Proto: `../go/ntp/api/proto/ntppool/monitorreg/v1/registration.proto`
- Handlers: `../go/ntp/api/server/api/monitorreg/rpc_registration.go`
  - `runAcceptRegistration` (shared with REST `UserAcceptanceHandler`) in
    `user_acceptance_handlers.go`
- Wiring: `../go/ntp/api/server/api/api.go` (authenticated RPC group)
- Tests: `../go/ntp/api/server/api/monitorreg/rpc_registration_test.go`
- Generated Perl client: `lib/NP/CAPI/MonitorRegistration.pm` (do not edit)
