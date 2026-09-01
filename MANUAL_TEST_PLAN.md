# Manual Test Plan — changes since 2025-12-01

Covers features touched in `ntppool` (Perl web) and `../go/ntp/api` (Go API) since
2025-12-01. Check items off as you go.

- **Dev site**: https://web.askdev.grundclock.com/
- **Cache busting**: append `?x=12345` (random) to URLs when content looks stale.
- Test as both a **regular logged-in user** and a **staff/admin user** where noted.

Sections below that mention `int_api` or `NP::IntAPI` describe what a migration
moved *away from*. `lib/NP/IntAPI.pm` was deleted in `a4f06c76` and no Perl call
site remains — don't go looking for it.

---

## 1. Login & automatic account creation (Auth0)

- [x] Log in with an existing user — lands on `/manage` with the right account, username populated.
- [x] Log in as a **brand-new** Auth0 identity — a user + account are auto-created, no dead-end.
- [x] New user sees a sensible landing/next step (not an empty "no pending invitations" page).
- [x] Login page copy reflects the broader scope (not just "add a server").
- [x] Log out and back in — session restored correctly, no duplicate account created.

## 2. Account scheduled deletion / dissolve

> **Scheduling is staff-only; cancelling is self-service.** The
> `/manage/account/dissolve` route
> (`return 403 unless $self->user_is_staff || $member_cancel`) and the UI link
> (`form.html`, `[% IF combust.user_is_staff %]`) are gated on `support_staff`
> for viewing and scheduling. A non-staff user getting a **403** on a bare GET is
> correct. Cancelling is a POST carrying `cancel=1` from the banner on
> `/manage/account`, which any account member may do (#38).
>
> `user_is_staff` reads the `support_staff` flag from the ValidateSession privileges, which
> come from the `user_privileges` row for the logged-in user. A user with **no
> `user_privileges` row** (e.g. `ask@perl.org`, user_id 5) is treated as non-staff. To test
> this section, log in as a staff account (e.g. `ask@develooper.com`, user_id 1) or add a
> `user_privileges` row with `support_staff = true`.

- [x] As **staff**, the "Delete account" link is visible at the bottom of `/manage/account` (red, destructive).
- [ ] As a **non-staff** user with no scheduled deletion, the link is hidden and `/manage/account/dissolve` returns 403.
- [x] Visit `/manage/account/dissolve` as staff — confirmation page renders.
- [x] Schedule deletion — shows scheduled date (~7 days out), confirmation message.
- [x] Revisit `/manage/account/dissolve` — shows the pending scheduled deletion with a cancel option.
- [x] Cancel the scheduled deletion — state clears, account back to normal.
- [ ] Confirm the deletion-scheduled email is sent (check dev mail / logs).
- [ ] Account form (`/manage/account`) clearly labels the dissolve/delete action as destructive.

#### Frozen-account UI (fixed in #38)

> Once `deletion_on` is set, `permissions.can_edit` is false for **everyone**,
> staff included (`AccountWritable` = `!DeletionOn.Valid`). `manage_dispatch`
> excepts the `/manage/account` URI for a frozen account so the non-staff cancel
> banner (`form.html:3-23`) and the staff "Account deletion scheduled — manage"
> link (`form.html:156-167`) both render. The edit POST is refused there with a
> message; the Go API returns `FailedPrecondition` regardless.
>
> The staff half is covered by `e2e/tests/account-dissolve.spec.ts`. The two
> non-staff items below are manual until the accept-invite helper in #46 lands —
> they need a second member on the account, invited *before* it is frozen.

- [ ] As a **non-staff member** of a frozen account, `/manage/account` renders and shows the red "Account scheduled for deletion" banner with the scheduled date.
- [ ] Clicking **Cancel scheduled deletion** in that banner clears the deletion and returns the account to normal.
- [ ] As **staff** on a frozen account, `/manage/account` renders and shows the "Account deletion scheduled — manage" link pointing at the dissolve page.
- [ ] A member of a frozen account still **cannot edit** it: submitting the account form shows "This account is scheduled for deletion and cannot be changed", not a raw API error.

## 3. Staff-targeted user & account deletion

- [ ] As **staff**, open another account's team page (`/manage/account/team` with account context).
- [ ] Delete/schedule deletion for another **user** via `u=` — targets the correct user, not yourself.
- [ ] Schedule another **account's** deletion as staff — works and is scoped to that account.
- [ ] Confirm a non-staff user **cannot** target other users/accounts (only their own).
- [ ] `delete_scheduled` / `user_deletion_scheduled` page shows correct target + date.

## 4. Account / team management UI

- [ ] Team page destructive actions (remove user, delete) are clearly marked and scoped to own account.
- [ ] Delete/download links use the correct user id_token (not the wrong user).

### 4a. Resend account invitations

> Rule (enforced by the Go API): a pending invite can be resent at most once
> every **5 minutes** and at most **3 times per 24h** (the initial send counts
> as 1; the counter resets once the last send is older than 24h). Each resend
> extends the invite expiry to **30 days** out. The button state and the "next
> available" time come from the API (`can_resend` / `resend_available_at`).

- [ ] Pending invite on `/manage/account/team` shows a **Resend** button (account with edit access).
- [ ] Click **Resend** — success badge ("Invitation email resent"); a new invite email arrives.
- [ ] Immediately resend again — button is **disabled** with an "available after …" time, or a rate-limit warning if forced (5-minute cooldown).
- [ ] Exceed **3 sends in 24h** — resend is blocked with a "too many … (limit: 3)" warning.
- [ ] A resent invite's **expiry moves out to ~30 days** from the resend.
- [ ] **Accepted/expired** invites show no Resend button; the accept link still works.
- [ ] Non-edit / wrong account context cannot resend (permission denied, no button).

## 5. Vendor zones (migrated to CAPI)

> §5–5d are e2e-covered end to end by `e2e/tests/vendor.spec.ts`, including the
> issue #31 ORM-removal surface: `dns_root_origin` display on both the new-zone
> and edit forms (Vendor.pm render_form), and `id_token`-based edit/create
> routing (form.html + `_get_id`).

- [x] `/manage/vendor` — zone list loads from the API (no ORM/DB errors). (`e2e/tests/vendor.spec.ts`)
- [x] `/manage/vendor/new` — request form renders with API-provided metadata, incl. `dns_root_origin`. (`e2e/tests/vendor.spec.ts`)
- [x] Submit a new vendor zone request — validation works, success path completes. (`e2e/tests/vendor.spec.ts`)
- [x] View a single zone (`/manage/vendor/<id>`) — details correct, edit form id correct. (`e2e/tests/vendor.spec.ts`)
- [x] As **staff**, `/manage/vendor/admin` — admin list loads; approve/reject status change works. (`e2e/tests/vendor.spec.ts`)
- [ ] Subscription/plan checks on vendor pages still work (no redundant account fetch errors).

### 5a. Editability matrix (status × role)

> A zone goes `New → (submit) Pending → (admin) Approved/Rejected`; admins can
> re-approve a Rejected zone. Editable content fields never include `id`,
> `status`, or approval state — those move only through the admin status RPC.

- [ ] Regular user, **New**: edit all fields, save persists.
- [ ] Regular user, **Pending**: edit all fields, save persists (previously dead-ended with a blank form).
- [ ] Regular user, **Rejected**: edit fields, then "Resubmit for production" → status returns to Pending.
- [ ] Regular user, **Approved**: no Edit button; opening the edit URL falls through to the read-only show page.
- [ ] Staff, **Approved**: edit form opens; `zone_name` is read-only; other fields save.
- [ ] Staff, **Approved**: attempting to change `zone_name` is rejected by the API (name locked once live).

### 5b. Open-source path (regression — was silently dropped)

- [ ] Submit a zone with the **open-source** option + justification — `opensource`/`opensource_info` reach the API (zone records as open source, not blank).
- [ ] Resubmit a **Rejected** open-source zone — open-source flag/justification still applied.
- [ ] Edit a Pending/Rejected **open-source** zone (change e.g. org name) — save succeeds and does **not** error with "opensource_info is required" or blank the stored justification.

### 5c. Error surfacing (always show errors, with trace_id)

- [ ] Induce an API error on edit/submit (e.g. duplicate zone name) — a red alert renders with the message and a Trace ID; the page is **not** blank and keeps the entered context.
- [ ] Same on the admin approve/reject path — failures show the alert + Trace ID rather than a silent no-op.

### 5d. Read-path error surfacing (list & subscription pages — fixed 2026-06)

> These read paths previously swallowed API errors: a failure rendered as an
> empty list, or — on `/manage/vendor` — a misleading redirect to "create your
> first zone". They now return the error via the shared `capi_error_status`.

- [ ] `/manage/vendor` while the zone-list API errors/times out — shows an error page, **not** a redirect to `/manage/vendor/new` (which would mislead a vendor who already has zones).
- [ ] `/manage/vendor` zone list when the subscription-status or subscriptions fetch errors — the error surfaces instead of a silently empty/partial page.
- [ ] `/manage/vendor/plan` when the subscriptions fetch errors — error surfaces rather than a blank subscription list.

### 5e. Coverage gate on submit (Go API — authoritative, issue #39 follow-up)

> `SubmitVendorZone` in the Go API is now the authoritative gate: it rejects a
> production submit from an account with **no subscription coverage and no
> open-source claim**, returning `FailedPrecondition` with the message exactly
> `a subscription is required, or apply as open source`. The check reads the
> **zone's** account (a `vendor_admin` submitting for another account is gated
> on *that* account, not the admin's), runs inside the submit transaction, and
> applies with **no admin bypass**. The subscription-status response also gained
> a `submit_state` enum (`COVERED` / `NEEDS_SUBSCRIPTION` / `OVER_LIMIT`).
> **The Perl/template consumption of `submit_state` is a deferred Phase 2**, so
> today this gate is a backstop behind the existing template — which already
> offers a plain production submit only to covered vendors. Needs the deployed
> Go API; the Go integration tests already cover the four cases below.

- [ ] **Covered** vendor (live subscription within limits): plain production submit succeeds → Pending.
- [ ] **Uncovered** vendor **with** an open-source claim + justification: submit still succeeds → Pending (open-source path is allowed through the gate).
- [ ] **Uncovered** vendor **without** an open-source claim: submit is rejected with `a subscription is required, or apply as open source` (reachable via the resubmit path or a direct/admin submit, since the normal form hides the plain-submit button for uncovered vendors).
- [ ] **Over-limit** vendor (has a subscription but exceeds zone/device limits), no open-source claim: submit is rejected with the same message (a distinct OVER_LIMIT wording is a Phase 2 decision, not a bug).
- [ ] `vendor_admin` submitting on another account's behalf is gated on **that account's** coverage, not the admin's own.

## 6. DNS zone generation (Go API)

> `/api/dns-zone` (`NTPPool::Control::DNSZone`) requires a "dns"-type service
> bearer token — infrastructure-provisioned, not something the e2e harness's
> dev-only `CreateTestSession` (user sessions only) can mint. Its auth guard
> (missing/malformed/invalid token → 403) is e2e-covered:
> `e2e/tests/dns-zone.spec.ts`. Everything below needs a real dns service
> token and stays manual.

- [ ] Generated DNS zone data pulls active servers via the Go API (`GetDnsZoneData` / `GetZoneActiveServers`).
- [ ] Spot-check a zone's server list matches expected active servers for that zone.
- [x] DNS service auth required — request without service token is rejected. (`e2e/tests/dns-zone.spec.ts`)
- [ ] Vendor/custom zone tokens resolve and produce correct zone output.

## 7. Subscriptions / Stripe (CAPI + SubscriptionService)

- [ ] Subscription summary appears in session/account context after login.
- [ ] Subscription management screens read/write via CAPI (create/update subscription).
- [ ] Stripe-gateway service path works end to end (checkout → subscription recorded).

## 8. Server verification & management

- [ ] Verify-server page (`/verify`) loads server verification via CAPI (`GetServerVerification`).
- [ ] Complete a server verification — success and audit logged by API.
- [ ] Add a new server — full setup (scores + review schedule) done in one API call.
- [ ] Re-add a server that was **deleted in the past** — allowed, no false "already exists".
- [ ] Add server with a hostname — DNS validation runs on `UpdateServer`.
- [ ] IPv6 server lookups normalize correctly; permission-aware `GetServer` hides other accounts' detail.
- [ ] Scores page (`/scores/<ip>`) loads with correct account context for admin edit buttons.

### 8a. Scheduled server deletion (schedule / cancel — auth + error-surfacing fix)

> Both `delete_server` calls in `handle_delete` were missing `api_auth_params`
> and silently **401**'d; the failure was swallowed (only `->{data}` was checked,
> inside an `eval`) and a broken `$server->load` would have died. Schedule and
> cancel now pass auth, surface errors, and redirect on success so the page
> re-fetches state via CAPI.

- [ ] Schedule a server for deletion (pick a date on `/manage/server/delete`) — succeeds and the page shows the **scheduled state** (date + cancel), **not** the date-picker again.
- [ ] Induce a schedule failure (logged-out/expired session, or an API error) — a red error alert renders on the date-picker page instead of a silent no-op.
- [ ] Cancel a scheduled deletion — succeeds; the server returns to normal with no deletion date.
- [ ] Cancel without the `can_add_servers` permission — shows the "verify active servers first" error, not a silent failure.
- [ ] Schedule/cancel are recorded in the audit log (written by the Go API in the same transaction).

### 8b. Netspeed update (`int_api` → CAPI migration, issue #35)

> `handle_update_netspeed` now calls `NP::CAPI::ServerManagement::update_server`
> instead of the legacy `int_api('post', 'server/netspeed', ...)`. The
> verification-required and not-found conditions are detected from the
> ConnectRPC `connect_code` instead of old REST status codes, and the
> success path reuses the API response's server data instead of re-fetching.

- [ ] Increase netspeed on a **verified** server via the HTMX select on `/manage/servers` — succeeds, updated value shown, no page reload.
- [ ] Increase netspeed on an **unverified** server — shows "Please verify your server before increasing the netspeed" inline, value not changed.
- [ ] Submit a non-numeric netspeed value (bypass the `<select>`, e.g. via curl) — returns **400**.
- [ ] Submit without the CSRF auth token — returns **403**.
- [ ] Non-HTMX request (no `HX-Request` header) — redirects to `/manage/servers` instead of rendering the fragment.

## 9. Score graphs / PNG endpoints

- [ ] `/scores/<ip>/offset.png` renders a graph.
- [x] An unmatched/legacy graph path returns **404** (not a broken/blank image).
- [ ] `score.png` requests normalize to `offset.png` as expected.
- [ ] Graph score-offset thresholds visually match the monitor scorer values.

## 10. Internationalization

- [x] Switch UI to **Thai (th)** — new language renders, key pages translated.
- [ ] Switch to **Traditional Chinese (zh-tw)** — doc pages render, "scheduled for deletion" string present.
- [x] Spot-check Portuguese (pt) and Czech (cs) tweaks didn't break layout.

## 11. API auth & infrastructure (mostly API-side smoke checks)

- [ ] Service tokens authenticate (`WhoAmI` recognizes service auth; DNS/service keys work).
- [x] Token hashing is SHA256 — existing tokens still validate after deploy.
- [ ] Rate limiting: service/monitor/account auth use correct limits; DNS service keys skip rate limiting.
- [ ] `X-Forwarded-For` trusted only from infrastructure IPs; client IP resolves correctly.
- [ ] CORS responses expose `TraceID` and `Request-ID` headers (check a cross-origin request).
- [ ] Scheduled account/user deletion **background sweep** actually deletes after the date passes
  (cleans user_sessions, clears monitor FKs, excludes soft-deleted from counts).
- [ ] Server-removal task notifies **all** account users, not just the first.
- [ ] OpenTelemetry traces flush on SIGTERM (pod restart doesn't lose the last traces).

## 12. Regression smoke (after large ORM removal)

The Perl `NP::Model` ORM layer was largely removed; sanity-check core flows still work:

- [ ] `/manage` dashboard loads.
- [ ] Server list + per-server pages load.
- [ ] Account switching (multi-account users) works.
- [ ] No 500s / "can't locate NP::Model::*" errors in logs while clicking through the above.

### 12a. Consolidated CAPI error helper (`capi_error_status` / `_handle_capi_error`)

> `_handle_capi_error` is now a thin adapter over `capi_error_status` (single
> source of truth). Behaviour to spot-check: success paths unchanged; error
> paths still return the right status, and an **upstream-down (5xx)** condition
> now surfaces as **503** (was 500) with caching suppressed.

- [ ] Server **move** (`/manage/servers/move`) — happy path works; on a forced API error the page returns an error status (not a blank/partial move-done page).
- [ ] **Monitor** management pages (list / delete) — load normally; a forced upstream error surfaces a 503 error page rather than a wrong 404 or blank.
- [ ] Spot-check a public read page that uses the helper (`/scores/<ip>`, a zone page) still renders normally and returns a clean 404 for a genuinely missing record.

## 13. Staff search (`int_api` → ConnectRPC, issue #43)

> `staff_search` (`Manage.pm`) now calls the Go **SearchService** ConnectRPC
> (`NP::CAPI::Search::search`) instead of the removed `int_api('get', 'search')`
> REST endpoint. Staff-only: the handler checks `support_staff` (non-staff →
> `PermissionDenied`). Response field names and the `tpl/admin/search_results.html`
> layout are unchanged. No matches come back as a 200 with an empty account list
> (never a 404); a real API failure falls to the degraded "Search temporarily
> unavailable" path with a Trace ID. Each query type must return sane results and
> the page/HTMX fragment must render without console errors.

- [ ] As **staff**, run an **IP lookup** (known server IP) — matching servers/monitors grouped by account.
- [ ] `id:<account-id>` lookup — returns that account with its users/servers/monitors.
- [ ] Free-text **pattern** search (hostname or account-name substring) — matches across accounts/users/servers/monitors; highlighting on matched IPs/hostnames still renders.
- [ ] Toggle **include deleted** on/off — deleted servers/monitors appear only when checked.
- [ ] `monitors:` search — shows the monitors-only default view plus the "show all results" toggle.
- [ ] `zone:<zonename>` search — shows the zone-servers-only default view for that zone.
- [ ] A query with **no matches** renders an empty result set cleanly (no error alert, no 404 page).
- [ ] As a **non-staff** user, the search is denied (no staff results leak through).

## 14. Monitor-config "Default (1)" for monitors per server

> The `monitors_per_server_limit` `<select>` on the account monitor-config form
> now offers **Default (1)** worth `0`, which clears the per-account override —
> matching how `monitor_limit` already offers "Default (3)" worth `0`. The old
> `value="1"` option is gone: the API returns the *effective* limit, so a stored
> `0` and a stored `1` both come back as `1` and behave identically. The Perl
> guard in `render_monitor_config_update` no longer rejects `0`. Monitor admins
> only.

- [ ] As a **monitor admin**, open an account's monitor config — the per-server select shows **Default (1)** selected for an account with no override.
- [ ] Set it to **3**, save — the display card shows 3, and reopening the form has 3 selected.
- [ ] Set it back to **Default (1)**, save — succeeds (this is the path that was unreachable before), display card shows 1.
- [ ] An account with a stored value outside 1–5 shows a **"(current)"** option rather than silently selecting the first entry.
- [ ] As a **non-monitor-admin**, the form is not reachable and a direct POST is denied.

## 15. Account flag badges in the monitor list

> `MonitorAccount` in the monitor proto gained a `flags` message carrying the
> account's monitor config **resolved server-side** (defaults applied,
> override-vs-default and registration-disabled already decided). It is sent
> only to monitor admins. `account_flags_badge.html` now compares those
> booleans instead of regex-matching a JSON blob — before this it had never
> rendered, because `mon.account.flags` was never populated. Needs the deployed
> Go API.

- [ ] As a **monitor admin** on `/manage/monitors` (all-accounts view), an account with `monitor_enabled` shows the green **Bypass** badge.
- [ ] An account with `monitor_limit = -1` shows the red **Disabled** badge (and *not* "Custom Limit").
- [ ] An account with a custom `monitor_limit` shows the blue **Custom Limit** badge, tooltip naming the number.
- [ ] An account with a custom per-server limit shows the yellow **Per-Server** badge, tooltip naming the number.
- [ ] An account on **all defaults** shows **no badges at all** — and no stray empty gap beside the account name.
- [ ] Badges appear in **both** the per-account list and the admin all-accounts view.
- [ ] As a **non-monitor-admin**, no badges render, and the `list_monitors` JSON response contains no `flags` key for the account.
