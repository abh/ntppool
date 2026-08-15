# Follow-ups after retiring `NP::IntAPI`

**Context:** issue #28 slice E landed 2026-08-08 — `ntppool` `a4f06c76`, Go API
`465f33b`. That change migrated the last `int_api()` call site to ConnectRPC,
deleted `lib/NP/IntAPI.pm`, and removed the dead `/int/monitor/manage/*` and
`/int/monitor/admin/*` echo handlers.

These are the loose ends found along the way. None of them blocked that work.
Each is independent — pick them off in any order.

**Status (2026-08-15):** 1, 2, 5, 6, 8 and 10 are done — code written, Go tests
passing. 2 and 10 are user-visible and still need the browser check on the dev
site (added as §14 and §15 of `MANUAL_TEST_PLAN.md`); 10 also needs the Go API
deployed there. Still open: **3** (template dedup), **4** (perltidy policy),
**7** (who calls `/int/monitor/registration/*`), **9** (recorded, no action).

---

## 1. `registration_disabled` is unreachable in eligibility metrics

**Where:** `../go/ntp/api/server/api/account/account_status.go:61`
**Severity:** real bug, wrong data, low blast radius

**DONE 2026-08-15.** Added `MonitorEligibilityInfo.RegistrationDisabled`, set from
the new `AccountConfig.MonitorRegistrationDisabled()` — now the single definition of
the `-1` sentinel, also used by `CanRegister`. `account_status.go` branches on it.
No dashboard selected on the label (`monitor-operations.json` groups `by (reason)`),
so this adds a series rather than breaking a query. Note the reason chain describes
the `Enabled` verdict, so a *disabled* account that still has monitors reports
`existing_monitors`; surfacing the `CanRegister` blocker would be a separate change.

```go
} else if info.MonitorLimit == -1 {
    reason = "registration_disabled"
}
```

`info.MonitorLimit` can never be `-1`. `GetMonitorEligibilityInfo`
(`ntpdb/helpers_monitor_eligibility.go`) only overrides the default when
`config.MonitorLimit > 0`, so a stored `-1` reports as `3`. The disable is
enforced separately in the `CanRegister` expression, against the raw value.

So the `MonitorEligibilityChecks` Prometheus counter never emits
`reason="registration_disabled"`. An account with monitoring switched off is
counted as `no_servers` (or `existing_monitors` if it has any), which is
misleading if anyone is reading that metric to find disabled accounts.

Fix: branch on the raw `config.MonitorLimit == -1` rather than the derived
`info.MonitorLimit`, or add the disabled state to `MonitorEligibilityInfo`
explicitly. Worth checking whether any dashboard or alert selects on that
label before changing it.

Pre-dates #28; slice E only made it visible.

---

## 2. `monitors_per_server_limit = 0` is documented but unreachable

**Where:** `proto/ntppool/account/v1/account.proto` (the
`UpdateAccountMonitorConfigRequest` doc comment) vs.
`docs/manage/tpl/account/monitor_config_edit_form.html` and
`lib/NTPPool/Control/Manage/Account.pm`
**Severity:** doc/UI mismatch, no user impact today

**DONE 2026-08-15.** Took the form option. The per-server `<select>` now offers
**Default (1)** worth `0` and drops the old `value="1"`: the API returns the
*effective* limit, so stored-0 and stored-1 both arrive as `1` and are behaviourally
identical — keeping both would have been two indistinguishable choices. Added the
same "(current)" fallback option `monitor_limit` has, so an out-of-range stored value
can't be silently rewritten by the browser picking option one. The Perl guard no
longer rejects `0`. Verified end to end: the generated wrapper uses `exists` (not
truthiness) and `connect_rpc` encodes the request verbatim, so `0` reaches the API.

The proto says `monitors_per_server_limit = 0` clears the per-account
override. Nothing can send it: the `<select>` offers only 1–5, and the Perl
guard requires `$per_server > 0`.

Harmless in practice — stored `1` and stored-absent behave identically
everywhere — but the API documents a path its only client cannot reach.
Either add a "Default (1)" option worth `0` to the form (matching how
`monitor_limit` already does it), or note in the proto that the field is
write-only-nonzero from the web UI.

Note the asymmetry is real: `monitor_limit` *does* offer `0` as
"Default (3)", so the two fields behave differently in the same form.

---

## 3. The monitor-config display card is duplicated across two templates

**Where:** `docs/manage/tpl/account/monitor_config_section.html:32-72` is a
near-verbatim copy of `docs/manage/tpl/account/monitor_config_display_clean.html`
**Severity:** maintenance hazard, already bit us once

Same card, same three columns, same `-1 → Disabled` logic, same edit button.
The `monitors_per_server` → `monitors_per_server_limit` rename in #28 had to be
made in both files; the next field change will too.

`section.html` is `INCLUDE`d from `form.html:129` (full page render);
`display_clean.html` is rendered directly by the controller for HTMX
fragments. Neither wraps the other.

Fix: reduce `section.html` to the `<h4>`, the HTMX error div, and a
`[% PROCESS tpl/account/monitor_config_display_clean.html %]`.

Deliberately not done in #28: the two files also carry their own
success/error alert blocks, and they intentionally degrade differently on a
failed fetch (the section hides itself; the HTMX fragment shows an error
alert). Collapsing them relocates those alerts, so it needs a browser check
rather than a blind edit.

---

## 4. `make generate` and `perltidy` fight over the generated CAPI modules

**Severity:** ongoing diff noise on every regeneration

Every generated wrapper drifts from `perltidy`:

```
DRIFT lib/NP/CAPI/Account.pm
DRIFT lib/NP/CAPI/Auth.pm
DRIFT lib/NP/CAPI/Server.pm
```

The checked-in copies were hand-tidied at some point, so `make generate` now
un-tidies them and produces changes unrelated to whatever proto was actually
edited. `lib/NP/CAPI/Auth.pm` rode along in `a4f06c76` for exactly this
reason, with no behavior change.

Pick one and enforce it:
- teach `cmd/protoc-gen-perl-capi` (Go repo) to emit perltidy-clean output; or
- exclude `lib/NP/CAPI/*.pm` from perltidy and stop tidying them.

Related: the repo as a whole is **not** perltidy-clean —
`Manage/Server.pm`, `Manage/Vendor.pm`, and `Manage/Monitor.pm` all fail it at
HEAD, while `Control.pm` passes. So "run perltidy before committing" (CLAUDE.md)
currently means "reformat several hundred unrelated lines" on most files.
Worth either tidying the tree once, in its own commit, or softening the rule
to touched lines only.

---

## 5. Stale `int_api` / `NP::IntAPI` references in docs

**Severity:** trivial

**DONE 2026-08-15.** `MANUAL_TEST_PLAN.md`: the mentions are all past-tense migration
context ("instead of the legacy `int_api`") and read correctly as history, so they
stay; added a header note that `lib/NP/IntAPI.pm` is deleted so nobody hunts for it.
`.github/copilot-instructions.md` was rewritten — it was stale well beyond `IntAPI`:
it documented `lib/NP/Model.pm` and Rose::DB, which no longer exist anywhere in
`lib/` (0 references). Now covers PostgreSQL-via-Go-API, `NP::CAPI`, the CSP rule,
and no-Perl-unit-tests.

Note the same Rose::DB claim is still in the root `CLAUDE.md` ("models use Rose::DB")
and is equally false — not fixed here, worth a follow-up.

`lib/` is clean. Two files still name the deleted module:

- `MANUAL_TEST_PLAN.md` — documents already-completed migrations; arguably a
  historical record, but it reads as current.
- `.github/copilot-instructions.md` — 2 references. This file is stale in
  other ways too (it recommends Perl unit tests, and still describes the
  system as MySQL-only), so it wants a pass of its own rather than a
  find-and-replace.

Left alone in #28 because neither was in scope and both need a judgement call
about what the file is *for*.

---

## 6. `GetUpdateStatusTestIDs` is orphaned

**Where:** `../go/ntp/api/testhelpers/integration_cleanup.go:200`
**Severity:** trivial

**DONE 2026-08-15.** Deleted. The replacement `rpc_update_status_test.go` uses its own
990201-990210 range with inline `defer db.Exec(DELETE ...)`, so pointing it at the
registry would have meant rewriting working cleanup for no gain. Freed ranges recorded
in `testhelpers/CLAUDE.md` and the id-management skill, along with a note that the RPC
test's own range is spoken for.

`update_status_integration_test.go` was deleted in `465f33b` (its meaningful
cases were ported to `rpc_update_status_test.go`, which uses its own ID
range). Its entry in the shared cleanup registry has no callers left.

`GetEligibilityTestIDs` was in the same state and is referenced again by the
restored `ntpdb/eligibility_integration_test.go`; this one wasn't rescued.
Either delete the helper and free the ID range, or point the RPC test at it.

---

## 7. `/int/monitor/registration/{data,accept}` still serve REST

**Where:** `../go/ntp/api/server/api/api.go:422-423`
**Severity:** needs a decision, not a fix

These two echo routes survived the #28 cleanup deliberately. This repo's Perl
no longer calls them — slice C moved `render_confirm_monitor` to
`NP::CAPI::MonitorRegistration` — and the accept transaction is shared with
the RPC path via `runAcceptRegistration`, so they are not duplicated logic.

Before removing them, establish who else calls them: the monitor client, the
registration tooling, or `ntppool-main`. Unlike the `/int/monitor/manage/*`
routes (whose only caller was this repo's Perl), that isn't obvious from
inside this tree.

---

## 8. `API.md` drifts from the routes

**Severity:** low, recurring

**DONE 2026-08-15.** Took the CI-check option. `TestAPIMarkdownIntRoutesMatchSource`
(`server/api/api_doc_routes_test.go`) parses the Echo group/route registrations out of
`api.go`, resolves the group prefixes, and compares the `/int/` set against API.md's
`#### METHOD /int/...` headings. Verified it fails in both directions, and it asserts
it parsed a non-empty set so it can't pass by comparing two empty lists.

It immediately caught fresh drift: `POST /int/session` and `DELETE /int/session/:lookup`
were still documented but had moved to ConnectRPC. Removed, with a pointer to
`ValidateSession`/`DeleteSession`.

The routes are registered inside `APIServer.Run`, which needs a live DB and config, so
the test cannot build the Echo instance and call `e.Routes()` — hence parsing source.
If route registration is ever extracted into a declarative table, switch to that.

`465f33b` removed six stale entries: the five `/int/monitor/manage/*` routes
it deleted, plus `GET /int/search`, which had been wrong since `ec0bf52e`
without anyone noticing.

The pattern is the problem, not the entries. The file is maintained by hand
and nothing checks it against `server/api/api.go`. Options: generate the
internal-route section, add a CI check that every documented `/int/` path
still resolves, or drop the hand-written route list in favor of the proto
docs now that most of the surface is ConnectRPC.

---

## 9. The account page costs monitor admins an extra RPC

**Severity:** by design; recorded so it isn't rediscovered as a bug

`render_account_form` now calls `GetAccount(include_monitor_config => 1)` for
monitor admins, where it previously read `flags` off the already-fetched
account hashref. That is one extra blocking round trip per account-page load,
for monitor admins only.

It is the consequence of the permission model, not an oversight: `GetAccount`
returns `PermissionDenied` when a caller without `monitor_admin` sets the
flag, so the main account fetch cannot simply request it unconditionally.

If it ever matters, the fix is to have the shared account fetch pass the flag
when the session is a monitor admin, rather than issuing a second call.

---

## 10. `account_flags_badge.html` has never rendered

**Where:** `docs/manage/tpl/monitors/account_flags_badge.html`
**Severity:** a built feature that has never worked — decide: finish or delete

**DONE 2026-08-15 — wired up, not deleted.** `MonitorAccount` gained a
`MonitorAccountFlags flags` message carrying the config *resolved server-side*:
defaults applied, plus explicit `monitor_limit_override`,
`monitors_per_server_limit_override` and `registration_disabled` booleans. The
override flags are needed because `EffectiveMonitorLimit()` can't distinguish a
deliberate `3` from no setting; `registration_disabled` exists because proto3 JSON
encodes int64 as a *string*, so the template comparing `== -1` would have been a trap.
New `AccountConfig` helpers keep all of that meaning in one place.

Admin-only at the source: `monitorPerms.isMonitorAdmin` gates the field in
`buildMonitorProto`, so a non-admin's response omits it entirely rather than relying on
the template guard. A test marshals with the server's real codec options to prove the
unset message is omitted, the names are snake_case, and zero values are present.

The template now compares booleans, and only emits its `<small>` wrapper when at least
one badge applies — otherwise every account would render an empty element, since
`flags` is always set for admins. No Perl controller change: `render_monitors` passes
the decoded response straight through.

Still needs the browser check on the dev site (`MANUAL_TEST_PLAN.md` §15), which needs
the Go API deployed there.

The template is gated on `combust.user.privileges.monitor_admin` and then on
`mon.account.flags`. When both pass it regex-matches the flags string to show
one to three badges beside an account name in the monitor list: "Bypass"
(`monitor_enabled`), "Disabled"/"Custom Limit" (`monitor_limit`), and
"Per-Server" (`monitors_per_server`).

**The `INCLUDE` is live — it is the badge's own guard that never passes.**
Worth stating plainly, because grepping finds the include and it looks wired
up. It is: `docs/manage/tpl/monitors/list.html:39` includes it from inside
`[% FOR mon = monitors %]`, in the account-header `<h2>` emitted whenever
`mon.account.id` changes, with `mon` correctly in scope. That serves both the
per-account list (`render_monitors`) and — via `PROCESS tpl/monitors/list.html`
in `admin_list.html` — the admin all-accounts view (`render_admin_list`).
Template Toolkit processes the file once per account heading and it returns an
empty string, because of its second line:

```
[% IF combust.user.privileges.monitor_admin %]   <- passes for a monitor admin
    [% IF mon.account.flags %]                   <- always false
```

**It has never rendered.** `mon.account.flags` is always empty:

```protobuf
message MonitorAccount {
  int64 id = 1;
  string id_token = 2;
  string name = 3;
}
```

No `flags`. And this is not a proto-only gap: `MonitorData.Account` in
`server/api/monitoradmin/monitoradmin.go` is `{ID, IDToken, Name}` too, and
`buildMonitorProto` copies only those three. `accounts.flags` *is* loaded from
Postgres into `ntpdb.Account.Flags` inside `formatMonitorList` — as a
`*dbtypes.AccountConfig` carrying exactly the three values the template's
regexes look for — and then dropped before the response is built.

**Not a ConnectRPC regression.** The template was written 2025-06-26
(`78700f20`), when it was fed by the legacy `int_api('get', 'monitor/manage/')`
call — and that handler's `Account` struct never had `flags` either, on any
branch. The 2026-07-03 cutover (`0ae46680`) only renamed `mon.Account.flags`
to `mon.account.flags` for the proto's snake_case, against a guard that was
already permanently false. That cutover's own plan says so and asks for this
exact follow-up:

> The Go `Account` struct carries no `flags` field (it never has — the REST
> `Account` was `{ID,IDToken,Name}` too), so these badges already render
> nothing today [...] either wire `flags` into the `MonitorAccount` proto or
> delete `account_flags_badge.html`; worth a separate issue, not this cutover.
> — `docs/superpowers/plans/2026-07-03-monitor-capi-perl-read-cutover.md`

So the badge UI was built complete and simply wired to a field that was never
populated, for over a year. Nobody has missed it, which is itself a signal.

**If wiring it up:** the data is already in hand, so this is small — under a
day.

1. Add the account flags to `MonitorAccount` in `monitor.proto` and
   regenerate.
2. Populate it: `ntpdb.Account.Flags` → `MonitorData.Account` →
   `buildMonitorProto`. No new queries.
3. Send **structured** values (`monitor_enabled`, `monitor_limit`,
   `monitors_per_server_limit`), not a JSON string. The template currently
   regex-matches a serialized blob, which is precisely the "Perl parses what
   the API should format" pattern CLAUDE.md forbids — and the patterns are
   unsafe as written: `monitor_enabled.*true` matches any *later* field that
   is true, and `monitor_limit.*-1` any later `-1`, so simply passing the JSON
   through would light up badges that are wrong rather than badges that are
   missing. Slice E already added `AccountConfig.EffectiveMonitorLimit()` —
   reuse it so the badge and the account page agree on what a stored `0` or
   `-1` means.
4. No new permission concern: the `monitor_admin` guard is already correct in
   both views (fixed in `0eeab41a`), so account flags stay admin-only.

**If deleting:** remove the template and its `INCLUDE` in `list.html:39`.

Recommendation: decide deliberately rather than by default. The badge is
genuinely useful to a monitor admin scanning the all-accounts list — it is why
it was written — but it has been absent for a year without complaint, so
deleting is defensible. What is not defensible is leaving a third file that
looks live and isn't.
