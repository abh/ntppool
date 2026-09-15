# Manual Test Plan — changes since 2025-12-01

Covers features touched in `ntppool` (Perl web) and `../go/ntp/api` (Go API) since
2025-12-01. Check items off as you go.

- **Dev site**: https://web.askdev.grundclock.com/
- **Cache busting**: append `?x=12345` (random) to URLs when content looks stale.
- Test as both a **regular logged-in user** and a **staff/admin user** where noted.
- Items marked with a spec path and test name — e.g. (`e2e/tests/foo.spec.ts` →
  "test name") — have an automated Playwright scenario in `e2e/`. A checked
  box means that scenario has passed live. Items explicitly marked
  **implemented; live-unverified** stay unchecked until the matching revisions
  and fixture schema are deployed and the scenario passes.
- Automated items assert through the browser and, where noted, authenticated
  API reads. They don't inspect backend process logs, so a log check (§12's "no
  500s in logs" item, for example) stays manual.

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
- [x] As a **non-staff** user with no scheduled deletion, the link is hidden and `/manage/account/dissolve` returns 403. (`e2e/tests/account-dissolve.spec.ts` → "non-staff user: link hidden and dissolve route returns 403")
- [x] Visit `/manage/account/dissolve` as staff — confirmation page renders.
- [x] Schedule deletion — shows scheduled date (~7 days out), confirmation message.
- [x] Revisit `/manage/account/dissolve` — shows the pending scheduled deletion with a cancel option.
- [x] Cancel the scheduled deletion — state clears, account back to normal.
- [ ] Confirm the deletion-scheduled email is sent (check dev mail / logs).
- [x] Account form (`/manage/account`) clearly labels the dissolve/delete action as destructive. (`e2e/tests/account-dissolve.spec.ts` → "staff sees the destructive Delete account link on /manage/account")

#### Frozen-account UI (fixed in #38)

> Once `deletion_on` is set, `permissions.can_edit` is false for **everyone**,
> staff included (`AccountWritable` = `!DeletionOn.Valid`). `manage_dispatch`
> excepts the `/manage/account` URI for a frozen account so the non-staff cancel
> banner (`form.html:3-23`) and the staff "Account deletion scheduled — manage"
> link (`form.html:156-167`) both render. The edit POST is refused there with a
> message; the Go API returns `FailedPrecondition` regardless.
>
> All four items below are automated in `e2e/tests/account-frozen.spec.ts`,
> which pairs a non-staff owner with a separate staff identity. The owner's
> *second* account supplies the non-staff membership, so no accept-invite
> helper is needed (this section previously said otherwise, blocking on #46).

- [x] As a **non-staff member** of a frozen account, `/manage/account` renders and shows the red "Account scheduled for deletion" banner with the scheduled date. (`e2e/tests/account-frozen.spec.ts` → "a non-staff owner sees the deletion banner on a frozen account")
- [x] Clicking **Cancel scheduled deletion** in that banner clears the deletion and returns the account to normal — the account is editable again, and the staff dissolve page offers scheduling once more. (`e2e/tests/account-frozen.spec.ts` → "the owner cancels from the banner and the account is editable again")
- [x] As **staff** on a frozen account, `/manage/account` renders and shows the "Account deletion scheduled — manage" link, pointing at the dissolve page for that account. (`e2e/tests/account-dissolve.spec.ts` → "staff: a frozen account still renders /manage/account with the scheduled-deletion link")
- [x] A **member** of a frozen account still cannot edit it: submitting the account form shows "This account is scheduled for deletion and cannot be changed", not a raw API error. (`e2e/tests/account-frozen.spec.ts` → "a frozen account refuses a name edit from its non-staff owner")
- [x] **Staff** are refused the same edit with the same message — `can_edit` is false for everyone on a frozen account. (`e2e/tests/account-frozen.spec.ts` → "a frozen account refuses a name edit from staff too")

## 3. Staff-targeted user & account deletion

- [ ] As **staff**, open another account's team page (`/manage/account/team` with account context).
- [ ] Delete/schedule deletion for another **user** via `u=` — targets the correct user, not yourself.
- [ ] Schedule another **account's** deletion as staff — works and is scoped to that account.
- [ ] Confirm a non-staff user **cannot** target other users/accounts (only their own).
- [ ] `delete_scheduled` / `user_deletion_scheduled` page shows correct target + date.

### 3a. Scheduled deletion actually completes (issue #40)

> The failure this guards against was silent: the user was told "deletion
> scheduled" and emailed, but the purge task failed on its first and only run and
> was never retried, so the data was never deleted. Perl no longer computes any
> timestamp here — `ScheduleUserDeletion` writes `users.deletion_on` and
> `user_tasks.execute_on` from one value in one transaction
> (`server/api/user/schedule_deletion.go`), and the purge guard compares against
> the **database** clock via `GetDatabaseTime` (`tasks/userdelete/userdelete.go:103`)
> rather than the runner host's. Nothing in the UI shows this, so it needs a
> direct check against a scheduled deletion.

- [ ] After scheduling a user deletion, the `user_tasks` delete row's `execute_on` equals the user's `deletion_on` **exactly** (not "about the same").
- [ ] Let a scheduled deletion come due (or backdate one) — the task runs and lands in a terminal **succeeded** state, not `failed`.
- [ ] Same check for a scheduled **account** deletion (`tasks/accountdelete`, same clock guard).
- [ ] Deliberately skew the runner host's clock behind the database and re-run — the task still succeeds (this is the exact regression that stranded deletions).

## 4. Account / team management UI

- [ ] Team page destructive actions (remove user, delete) are clearly marked and scoped to own account.
- [ ] Delete/download links use the correct user id_token (not the wrong user).

### 4a. Resend account invitations

> Rule (enforced by the Go API): a pending invite can be resent at most once
> every **5 minutes** and at most **3 times per 24h** (the initial send counts
> as 1; the counter resets once the last send is older than 24h). Each resend
> extends the invite expiry to **30 days** out. The button state and the "next
> available" time come from the API (`can_resend` / `resend_available_at`).

- [x] Pending invite on `/manage/account/team` shows a **Resend** button (account with edit access). (`e2e/tests/invites.spec.ts` → "pending invite shows a Resend button for an account with edit access")
- [x] Click **Resend** — the success badge ("Invitation email resent") renders. (`e2e/tests/invites.spec.ts` → "clicking Resend shows the success badge")
- [ ] A new invite email actually arrives — not observable on the dev site, which runs in `deployment_mode=devel` and logs "development mode - not sending email" instead of sending.
- [x] Immediately resend again — button is **disabled** by the 5-minute cooldown. (`e2e/tests/invites.spec.ts` → "an immediate second resend is blocked by the 5-minute cooldown")
- [ ] The cooldown state always includes the API-provided "available after …" time, or a forced resend shows a rate-limit warning. The existing test only validates the time when the UI renders it.
- [ ] Exceed **3 sends in 24h** — resend is blocked with a "too many … (limit: 3)" warning.
- [ ] A resent invite's **expiry moves out to ~30 days** from the resend.
- [x] **Accepted** invites show no Resend button; the accept link still works. (`e2e/tests/invites.spec.ts` → "accepted invite hides Resend and the accept link still works")
- [ ] Same for an **expired** invite — needs a way to age an invite past expiry through the harness.
- [x] A wrong-account context cannot see the owner's invite and renders no Resend control. (`e2e/tests/invites.spec.ts` → "a user without access to the account cannot resend")
- [ ] A forced resend POST from the wrong account context is denied without mutation.

### 4b. Removing a user from the team (issue #14)

> The removal rules themselves are covered by Go integration tests
> (`server/api/account/mutations_integration_test.go:275`); most of the UI half
> is now automated too, via the browser-only invite/accept flow (`acceptInvite`,
> `e2e/lib/helpers.ts` — #46).
>
> The **stale-list bug is fixed** (#14): `_account_users` is request-scoped
> cached (`Account.pm:30-33`) and `_remove_user_from_account` populated that
> cache before calling the removal API, so the team page rendered immediately
> after a removal used to replay the stale list. `_remove_user_from_account`
> now invalidates the cache after a successful removal, before re-rendering.
>
> Error surfacing changed 2026-08-15: Perl no longer short-circuits self-removal
> (the Go API owns that rule and always denied it), `_remove_user_from_account`
> now passes the API's message through instead of a generic retry prompt, and
> `team.html` actually renders it — the `error` param had no template to land in
> before.

- [x] Remove a second member from `/manage/account/team` — they lose access to the account, and the team page rendered right after the removal (no reload needed) no longer lists them. (`e2e/tests/account-team.spec.ts` → "removing a second member drops them from the team and notifies them")
- [ ] The removed user gets the `account_user_removed` email, CC'd to the remaining members (check dev mail) — not observable on the dev site (devel mode logs instead of sending).
- [x] The **Remove from team** button is absent on a sole-member account (`e2e/tests/account-team.spec.ts` → "a sole-member account shows no Remove control"), and absent for your own row as a **non-staff** member of a 2-member account (`e2e/tests/account-team.spec.ts` → "a member cannot remove themselves from a multi-member account").
- [ ] As **staff**, clicking **Remove from team** on your own row shows "you cannot remove yourself from an account" — not a generic "please try again".
- [x] A hand-crafted POST removing yourself as a **non-staff** user shows that message (it used to silently no-op with nothing on screen). (`e2e/tests/account-team.spec.ts` → "a member cannot remove themselves from a multi-member account")
- [ ] Staff cannot remove the **last** member of an account — "cannot remove the last user from an account" renders on the page.
- [ ] A forced API failure on removal shows the API's message plus a Trace ID (`team.html` now processes `tpl/common/error_alert.html`; before this the `error` param was set but never rendered).

### 4c. Personal data download requests (issue #15)

> The duplicate-request rule lives only in Perl
> (`Account.pm:704-726`): while a request is pending, a POST silently falls
> through to a plain render — no new task, no message beyond whatever
> `pending_requests` drives in the template. There is no API-side guard, so no Go
> test can catch a regression.

- [x] `GET /manage/account/download` renders cleanly for a user with no prior requests. (`e2e/tests/account-download.spec.ts` → "a fresh user submits one personal data download request")
- [x] Submit a request — POST redirects back to the download page (POST/redirect/GET) and the new request appears in the list. (`e2e/tests/account-download.spec.ts` → "a fresh user submits one personal data download request")
- [ ] Submit again while the first is still pending — **no** second request is created and the pending state is shown. Needs a task held pending for the duration of the test; the worker could otherwise finish between the two POSTs and make a second request legitimate.
- [ ] Once a request completes, its download link works: `/manage/account/download/data/<traceid>/<filename>`. Needs a completed archive seeded through a supported test surface.
- [ ] A **mismatched** filename on that URL returns 404 (`Account.pm:686-687` checks the filename against the API's `download_url`). Needs a completed archive seeded through a supported test surface.
- [ ] The request's trace ID (UUIDv7) appears in the web logs and correlates to the background worker's log lines for the same task. Needs a completed archive seeded through a supported test surface.

> Two defects in `render_download` as of 2026-09-09: the create-failure message
> at `Account.pm:743-747` is set but never rendered (`docs/manage/tpl/user/download.html`
> has no error output), and `list_user_tasks` errors are swallowed at
> `Account.pm:722-726` into an empty list. An API failure therefore looks like a
> missing row rather than an error.

## 5. Vendor zones (migrated to CAPI)

> `e2e/tests/vendor.spec.ts` covers fresh, uncovered vendors and vendor
> admins, including the issue #31 ORM-removal surface: `dns_root_origin`
> display on both the new-zone and edit forms (Vendor.pm render_form), and
> `id_token`-based edit/create routing (form.html + `_get_id`).
> `e2e/tests/vendor-coverage.spec.ts` covers vendors with a live subscription,
> which `api e2e fixture create` seeds. Together they cover §5a, §5b and §5e.
> §5c's admin failure row and §5d need a failure-injection hook in a network
> handler, which the E2E fixture rule forbids, so they stay manual; the admin
> invalid-transition test asserts a safe no-op, which isn't evidence of error
> rendering. Design:
> `docs/superpowers/specs/2026-09-14-vendor-zone-e2e-coverage-design.md`.

- [x] `/manage/vendor` — zone list loads from the API (no ORM/DB errors). (`e2e/tests/vendor.spec.ts` → "create a New vendor zone request")
- [x] `/manage/vendor/new` — request form renders with API-provided metadata, incl. `dns_root_origin`. (`e2e/tests/vendor.spec.ts`)
- [x] Submit a new vendor zone request — validation works, success path completes. (`e2e/tests/vendor.spec.ts` → "create a New vendor zone request")
- [x] View a single zone (`/manage/vendor/<id>`) — details correct, edit form id correct. (`e2e/tests/vendor.spec.ts`)
- [x] As **staff**, `/manage/vendor/admin` — admin list loads; approve/reject status change works. (`e2e/tests/vendor.spec.ts`)
- [x] Subscription/plan checks on vendor pages still work (no redundant account fetch errors). `/manage/vendor/plan` is blank until a product is chosen; the subscription shows on `/manage/vendor` as "Current plan" with its limits, and a Pending zone reads "Processing". (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor gets a plain submit and stays off the open-source path")

### 5a. Editability matrix (status × role)

> A zone goes `New → (submit) Pending → (admin) Approved/Rejected`; admins can
> re-approve a Rejected zone. Editable content fields never include `id`,
> `status`, or approval state — those move only through the admin status RPC.

- [x] Regular user, **New**: edit an ordinary content field and the save persists. (`e2e/tests/vendor.spec.ts` → "edit a New/Pending zone and persist a changed field")
- [x] Regular user, **New**: repeat the edit/save assertion for every other writable field (`zone_name`, `request_information`, `device_count`, `device_information`; a regular user never sees `contact_information`). (`e2e/tests/vendor.spec.ts` → "every writable field saves on a New zone")
- [x] Regular user, **Pending**: edit an ordinary content field and the save persists without a blank form. (`e2e/tests/vendor.spec.ts` → "open-source submit retains justification and edits without error")
- [x] Regular user, **Pending**: repeat the edit/save assertion for every other writable field. (`e2e/tests/vendor.spec.ts` → "every writable field saves on a Pending zone")
- [x] Regular user, **Rejected**: edit fields before resubmitting. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
- [x] Regular user, **Rejected**: "Resubmit for production" returns the status to Pending. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
- [x] Regular user, **Approved**: no Edit button; opening the edit URL falls through to the read-only show page. (`e2e/tests/vendor.spec.ts` → "owner sees no edit on an Approved zone; edit URL is read-only")
- [x] Staff, **Approved**: edit form opens; `zone_name` is read-only; another content field saves. (`e2e/tests/vendor.spec.ts` → "vendor admin can edit an Approved zone; zone_name is read-only; other fields save")
- [x] Staff, **Approved**: attempting to change `zone_name` is explicitly rejected by the API (name locked once live): the form re-renders with "zone name cannot be changed after approval" and a Trace ID, and the stored name is unchanged. (`e2e/tests/vendor.spec.ts` → "renaming an Approved zone shows the API's refusal")

### 5b. Open-source claim vs staff determination (issue #39)

> Rewritten 2026-08-15. The single `opensource` boolean is **gone** (migrations
> 025/026): a submit now records the vendor's *claim* (`opensource_requested`),
> and the open-source grant is a separate staff *determination*
> (`opensource_approved`, the "Grant open-source (non-revenue) plan" checkbox on
> the admin approve form). A submit can no longer set the grant.
>
> The routing bug this fixes: `show.html` used to send **every** New/Rejected zone
> with `!need_subscription` through the open-source justification form, which
> always posts a hidden `opensource_request=1` — so a paying vendor's zone was
> silently reclassified as non-revenue open source. `show.html:83-103` now
> branches on `have_subscription`.
>
> A covered submit sends an empty justification, so it clears one stored by an
> earlier open-source submit: a Rejected open-source zone resubmitted with a
> subscription loses its claim and its justification. That's current
> behavior; whether it's intended is still to be decided, so no test pins it.

- [x] **Covered** vendor (live subscription): a New/Rejected zone shows a plain "Submit for production" / "Resubmit for production" button — **no** open-source justification form, no `opensource_request` field in the posted form. (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor gets a plain submit and stays off the open-source path" and "a vendor admin submits for a covered account, and the owner resubmits after a rejection")
- [x] Submitting as a covered vendor leaves the open-source claim false **and** the grant undecided (the zone page shows no open-source justification text). (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor gets a plain submit and stays off the open-source path")
- [x] **Uncovered** vendor: the same zone shows the open-source justification form instead. (`e2e/tests/vendor.spec.ts` → "uncovered vendor submit page shows the open-source form, not a plain submit")
- [x] Submit with the open-source form + justification — the claim and `opensource_info` reach the API and the zone becomes Pending. (`e2e/tests/vendor.spec.ts` → "open-source submit retains justification and edits without error")
- [x] Confirm separately that the staff open-source grant remains undecided after the vendor submits its claim. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
- [x] Submitting the open-source form with an **empty** justification is rejected with "Please provide open source information", and the zone stays New. (`e2e/tests/vendor.spec.ts` → "open-source submit with an empty justification is refused and the zone stays New")
- [x] Submitting the open-source form with a **whitespace-only** justification is refused by the API with "opensource_info must contain non-whitespace characters" and a Trace ID, and the zone stays New. (`e2e/tests/vendor.spec.ts` → "a whitespace-only justification is refused by the API and the zone stays New")
- [x] Resubmit a **Rejected** open-source zone — the zone returns to Pending. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
- [x] Confirm the open-source claim and justification remain applied after that Rejected-to-Pending resubmit (the new justification is stored and the grant resets to undecided). (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
- [x] Edit a Pending **open-source** zone (change e.g. org name) — save succeeds and does **not** error with "opensource_info is required" or blank the stored justification. (`e2e/tests/vendor.spec.ts` → "open-source submit retains justification and edits without error")
- [x] Repeat the open-source edit assertion while the zone is **Rejected**. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit")
- [x] As `vendor_admin`, approving with **Grant open-source** checked sets the grant; approving without it leaves the zone on the paid path regardless of the vendor's claim. (`e2e/tests/vendor.spec.ts` → "approve/reject status changes and owner resubmit" and "approving with Grant unchecked leaves the zone on the paid path")

### 5c. Error surfacing (always show errors, with trace_id)

- [x] Induce an API error on create/edit (duplicate zone name) — a red alert renders with a Trace ID and the request form remains usable rather than going blank. (`e2e/tests/vendor.spec.ts` → "duplicate zone name surfaces a red error alert with a Trace ID")
- [ ] The duplicate-zone error page repopulates the user's entered context; the current create path does not echo the submitted `zone_name` back into the form.
- [ ] Same on the admin approve/reject path — failures show the alert + Trace ID rather than a silent no-op. Stays manual: making the status RPC fail needs a failure-injection hook in a network handler, which the E2E fixture rule forbids.

### 5d. Read-path error handling: primary fails loudly, decorative degrades (issue #42)

> Corrected 2026-08-15 — the last two items previously asserted the opposite of
> current behaviour. The distinction is deliberate: `capi_error_status` is for
> **primary** data calls whose failure means the page has nothing to show;
> **decorative** calls (a subscription badge, an optional billing block) must
> degrade gracefully, or a transient blip on an optional call takes down a page
> whose real content was already fetched.
>
> Primary: `Vendor.pm:74` (zone existence) and `:168` (the zone list).
> Decorative: `:177` / `:185` in `render_zones`, and `:769` in
> `render_subscription`.
>
> These rows stay manual: forcing a read to fail needs a failure-injection
> hook in a network handler, which the E2E fixture rule forbids.

- [ ] `/manage/vendor` while the zone-list API errors/times out — shows an error page, **not** a redirect to `/manage/vendor/new` (which would mislead a vendor who already has zones).
- [ ] `/manage/vendor` when the **subscription-status** call errors — the zone list still renders; `have_subscription` falls back to false, so a Pending zone simply isn't labelled "Processing". No error page.
- [ ] `/manage/vendor` when the **subscriptions** call errors — the zone list still renders; the optional billing/subscription block is just absent.
- [ ] `/manage/vendor/plan` when the subscriptions fetch errors — the plan page still renders and a vendor can still pick a plan; the current-subscription list is absent rather than the page being replaced by a bare error.

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
> Go API; the Go integration tests already cover the first four cases below
> (the over-limit case only for the device limit).
>
> E2E checks both layers: the Perl gate in the browser, and the Go gate through
> a direct `SubmitVendorZone` call.

- [x] **Covered** vendor (live subscription within limits): plain production submit succeeds → Pending. (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor gets a plain submit and stays off the open-source path")
- [x] **Uncovered** vendor **with** an open-source claim + justification: submit still succeeds → Pending (open-source path is allowed through the gate). (`e2e/tests/vendor.spec.ts` → "open-source submit retains justification and edits without error")
- [x] **Uncovered** vendor **without** an open-source claim: submit is rejected with `a subscription is required, or apply as open source` (reachable via the resubmit path or a direct/admin submit, since the normal form hides the plain-submit button for uncovered vendors). (`e2e/tests/vendor.spec.ts` → "an uncovered plain submit is refused by the site and by the API")
- [x] **Over-limit** vendor (has a subscription but exceeds zone/device limits), no open-source claim: submit is rejected with the same message (a distinct OVER_LIMIT wording is a Phase 2 decision, not a bug). (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor over the device limit is refused by the site and by the API" and "a covered vendor at the zone limit is refused by the site and by the API")
- [x] `vendor_admin` submitting on another account's behalf is gated on **that account's** coverage, not the admin's own. (`e2e/tests/vendor-coverage.spec.ts` → "a vendor admin submits for a covered account, and the owner resubmits after a rejection")

## 6. DNS zone generation (Go API)

> `/api/dns-zone` (`NTPPool::Control::DNSZone`) requires a "dns"-type service
> bearer token — infrastructure-provisioned, not something the e2e harness's
> dev-only `api e2e session` command (user sessions only) can mint. Its auth guard
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

- [x] The pending-token confirmation page redirects into the owner's account,
  shows the expected server and completes verification through the real form.
  The same scenario reads the resulting server audit event.
  (`e2e/tests/server-verification.spec.ts` → "pending verification redirects
  into the owner's account and completes")
- [x] Invalid tokens return not found; missing-CSRF and cross-account
  completion attempts are refused without changing the owner's verification
  state. (`e2e/tests/server-verification.spec.ts` → "invalid verification
  token is not found", "verification without CSRF is refused and stays
  pending", and "another account cannot complete the owner's verification")
- [ ] Add a new server through precheck — full setup (scores + review schedule)
  is done in one API call. **Deferred:** this needs a disposable routable
  address and controlled NTP checks; the clean add form alone doesn't cover it.
- [ ] Re-add a server that was **deleted in the past** — allowed, no false
  "already exists". **Deferred** with the real add flow.
- [ ] Add a server with a hostname through `AddServerPrecheck`. **Deferred:**
  this needs controlled DNS and NTP infrastructure.
- [ ] Successfully change an existing server's hostname through
  `UpdateServer`. **Deferred:** this is a separate DNS-validation path from
  hostname add and needs controlled DNS.
- [ ] Acquire a verification challenge through the external NTP verification
  infrastructure. **Deferred:** the automated confirmation scenario starts
  with a pending token and doesn't claim challenge acquisition.
- [x] Expanded and compressed IPv6 forms
  resolve the same server, and the scores route redirects to the canonical
  address. (`e2e/tests/server-scores-context.spec.ts` → "IPv6 scores normalize
  to the canonical fixture address")
- [x] Staff opening a server while another
  account is active gets an edit request and form targeted at the server's
  account. (`e2e/tests/server-scores-context.spec.ts` → "staff scores edit
  targets the server's account from another active account")
- [x] Owner, unrelated-account and public
  score pages omit staff controls; unrelated and public pages also omit the
  private account's email, token, display name and public URL.
  (`e2e/tests/server-scores-context.spec.ts` → "owner scores omit staff
  controls", "unrelated scores omit private account details and staff
  controls", and "public scores omit private account details and staff
  controls")
- [x] Permission-aware `GetServer` returns
  private account fields to the owner and staff, omits the account object for
  unrelated and unauthenticated reads, and denies edit-required unrelated and
  unauthenticated reads. (`e2e/tests/server-scores-context.spec.ts` →
  "GetServer enforces private account visibility and edit permission")
- [ ] Prove initial score/review scheduling is atomic, audit failure rolls back
  each mutation, and each web action makes the exact expected RPC count.
  **Deferred:** these need Go integration tests or server instrumentation;
  browser success can't establish them.

### 8a. Scheduled server deletion (schedule / cancel — auth + error-surfacing fix)

> Both `delete_server` calls in `handle_delete` were missing `api_auth_params`
> and silently **401**'d; the failure was swallowed (only `->{data}` was checked,
> inside an `eval`) and a broken `$server->load` would have died. Schedule and
> cancel now pass auth, surface errors, and redirect on success so the page
> re-fetches state via CAPI.

- [x] Scheduling the date offered by the UI
  redirects and a fresh read shows that date, the cancel control and no picker.
  (`e2e/tests/server-deletion.spec.ts` → "scheduling deletion persists the
  selected date")
- [x] An independent fixture that starts
  scheduled can be cancelled; a fresh read shows an empty deletion date and
  the picker. (`e2e/tests/server-deletion.spec.ts` → "cancelling deletion
  clears the scheduled date")
- [x] An authenticated, valid-CSRF schedule
  with `2099-1-01` renders the API's exact date-format error in the destructive
  alert and leaves state unchanged. (`e2e/tests/server-deletion.spec.ts` → "API
  date validation is shown on the deletion picker")
- [ ] Render an arbitrary downstream cancellation failure with otherwise-valid
  prerequisites. **Deferred:** permission denial is covered, but controlled
  downstream failure needs a narrowly scoped failure surface.
- [x] Cancellation with two active unverified
  servers shows "Please verify active servers in the account first." and
  preserves the scheduled date. (`e2e/tests/server-deletion.spec.ts` →
  "cancellation is denied with two active unverified servers")
- [x] Missing CSRF returns 403 and a
  valid-CSRF cross-account schedule returns 404; both preserve owner state.
  (`e2e/tests/server-deletion.spec.ts` → "deletion without CSRF is refused
  without mutation" and "another account cannot schedule the owner's server")
- [x] Successful schedule and cancellation
  correlate the observed audit record to actor, account and server in the two
  success scenarios above. Observing the record doesn't prove transactional
  atomicity. `DeleteServer` still performs its mutation and best-effort audit
  as separate operations.

### 8b. Netspeed update (`int_api` → CAPI migration, issue #35)

> `handle_update_netspeed` now calls `NP::CAPI::ServerManagement::update_server`
> instead of the legacy `int_api('post', 'server/netspeed', ...)`. The
> verification-required and not-found conditions are detected from the
> ConnectRPC `connect_code` instead of old REST status codes, and the
> success path reuses the API response's server data instead of re-fetching.

- [x] Increasing a verified server through the
  HTMX select sends `HX-Request`, replaces the server fragment without document
  navigation, and persists the selected speed. (`e2e/tests/server-netspeed.spec.ts`
  → "verified netspeed updates replace the HTMX fragment without navigation")
- [x] Increasing an unverified server shows
  "Please verify your server before increasing the netspeed" inline and keeps
  its effective speed. (`e2e/tests/server-netspeed.spec.ts` → "unverified
  netspeed increase shows the verification error and preserves speed")
- [x] A nonnumeric value with valid CSRF
  returns 400 and doesn't mutate the server. (`e2e/tests/server-netspeed.spec.ts`
  → "nonnumeric netspeed is rejected without mutation")
- [x] A numeric value without CSRF returns
  403 and doesn't mutate the server. (`e2e/tests/server-netspeed.spec.ts` →
  "netspeed without CSRF is rejected without mutation")
- [x] A valid non-HTMX update redirects to
  `/manage/servers` and persists on a fresh read. (`e2e/tests/server-netspeed.spec.ts`
  → "non-HTMX netspeed update redirects and persists")

## 9. Score graphs / PNG endpoints

- [x] The canonical `/graph/<ip>/offset.png` endpoint renders a graph (200, `image/png`). (`e2e/tests/scores.spec.ts` → "offset.png returns a PNG image")
- [x] An unmatched/legacy graph path returns **404** (not a broken/blank image).
- [ ] Graph `score.png` requests normalize to `offset.png` as expected. The existing `/scores/<ip>/score.png` test only proves that the scores-page alias resolves cleanly rather than 404ing.
- [ ] Graph score-offset thresholds visually match the monitor scorer values.

## 10. Internationalization

- [x] Switch UI to **Thai (th)** — new language renders, key pages translated.
- [x] Switch to **Traditional Chinese (zh-tw)** — the public doc page renders with `lang="zh-tw"` and the language switcher shows the native name. (`e2e/tests/i18n.spec.ts` → "Traditional Chinese (zh-tw): doc page renders translated")
- [ ] The authenticated "scheduled for deletion" string renders translated in zh-tw — human check; the automated test only covers a public page.
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

- [ ] No 500s / "can't locate NP::Model::*" errors in logs while clicking through the above.
- [x] `/manage` dashboard loads.
- [x] Server list + per-server pages load.
- [x] Account switching (multi-account users) works.

### 12a. Consolidated CAPI error helper (`capi_error_status` / `_handle_capi_error`)

> `_handle_capi_error` is now a thin adapter over `capi_error_status` (single
> source of truth). Behaviour to spot-check: success paths unchanged; error
> paths still return the right status, and an **upstream-down (5xx)** condition
> now surfaces as **503** (was 500) with caching suppressed.
>
> The helper belongs on **primary** data calls only; decorative calls degrade
> gracefully instead — see §5d.

- [ ] Server **move** (`/manage/servers/move`) — happy path works; on a forced API error the page returns an error status (not a blank/partial move-done page).
- [ ] **Monitor** management pages (list / delete) — load normally; a forced upstream error surfaces a 503 error page rather than a wrong 404 or blank.
- [x] Spot-check a public read page that uses the helper: `/scores/<ip>` renders normally and a genuinely missing server returns a clean 404. (`e2e/tests/scores.spec.ts` → "/scores/<ip> renders the public score page" and "missing record on the scores page returns a clean 404")

## 13. Staff search (`int_api` → ConnectRPC, issue #43)

> `staff_search` (`Manage.pm`) now calls the Go **SearchService** ConnectRPC
> (`NP::CAPI::Search::search`) instead of the removed `int_api('get', 'search')`
> REST endpoint. Staff-only: the handler checks `support_staff` (non-staff →
> `PermissionDenied`). Response field names and the `tpl/admin/search_results.html`
> layout are unchanged. No matches come back as a 200 with an empty account list
> (never a 404); a real API failure falls to the degraded "Search temporarily
> unavailable" path with a Trace ID. Each query type must return sane results and
> the page/HTMX fragment must render without console errors.
>
> The `id:` search takes the decimal `accounts.id`, which is never rendered in
> the UI (search results carry only `id_token`; `account_id` appears in the
> manage templates solely inside truthiness checks). The e2e test reads it from
> `AccountService.GetAccount` — `Authorization: Bearer <user session>` plus
> `X-Account: <account token>` — not by decoding the `acc_…` token.

- [x] As **staff**, run an **IP lookup** for a fixture server — the matching server is grouped under its account, links carry that account's `a=` token, and the matched IP is highlighted. (`e2e/tests/staff-search.spec.ts` → "staff finds a fixture server by exact IP")
- [x] `id:<account-id>` lookup — returns that account with its users. (`e2e/tests/staff-search.spec.ts` → "staff finds an account by exact numeric id: lookup")
- [x] Free-text **pattern** search on an **account-name** substring — finds the account and lists its members, with result links carrying that account's `a=` token. (`e2e/tests/staff-search.spec.ts` → "staff finds an account by a unique name substring")
- [ ] Free-text pattern search on a **hostname** substring, and highlighting on matched IPs/hostnames — needs owned server fixtures.
- [ ] Toggle **include deleted** on/off — deleted servers/monitors appear only when checked.
- [ ] `monitors:` search — shows the monitors-only default view plus the "show all results" toggle.
- [ ] `zone:<zonename>` search — shows the zone-servers-only default view for that zone.
- [x] A query with **no matches** renders an empty result set cleanly (no error alert, no 404 page). (`e2e/tests/staff-search.spec.ts` → "a no-match query replaces earlier results with the no-results message")
- [x] An **empty** query clears earlier results and renders nothing — not a "no results" message, which only appears for a non-empty query. (`e2e/tests/staff-search.spec.ts` → "an empty query clears earlier results without an error")
- [x] As a **non-staff** user, the search is denied (no staff results leak through) — the outer dispatcher 404s before reaching the handler, and no staff-search navigation is offered. (`e2e/tests/staff-search.spec.ts` → "a non-staff user cannot reach staff search")

## 14. Monitor-config "Default (1)" for monitors per server

> The `monitors_per_server_limit` `<select>` on the account monitor-config form
> now offers **Default (1)** worth `0`, which clears the per-account override —
> matching how `monitor_limit` already offers "Default (3)" worth `0`. The old
> `value="1"` option is gone: the API returns the *effective* limit, so a stored
> `0` and a stored `1` both come back as `1` and behave identically. The Perl
> guard in `render_monitor_config_update` no longer rejects `0`. Monitor admins
> only.

- [x] As a **monitor admin**, open an account's monitor config — the per-server select shows **Default (1)** selected for an account with no override. (`e2e/tests/monitor-config.spec.ts` → "monitor admin changes the per-server limit and restores Default (1)")
- [x] Set it to **3**, save — the display card shows 3, and reopening the form has 3 selected. (`e2e/tests/monitor-config.spec.ts` → "monitor admin changes the per-server limit and restores Default (1)")
- [x] Set it back to **Default (1)**, save — succeeds, a fresh display shows 1, and reopening the form selects the default option. (`e2e/tests/monitor-config.spec.ts` → "monitor admin changes the per-server limit and restores Default (1)")
- [ ] An account with a stored value outside 1–5 shows a **"(current)"** option rather than silently selecting the first entry. Needs a fixture or API-supported way to create an out-of-range legacy value.
- [x] As a **non-monitor-admin**, the form is not reachable and direct GET and POST requests are denied. (`e2e/tests/monitor-config.spec.ts` → "non-monitor-admin cannot reach or update monitor configuration")

## 15. Account flag badges in the monitor list

> `MonitorAccount` in the monitor proto gained a `flags` message carrying the
> account's monitor config **resolved server-side** (defaults applied,
> override-vs-default and registration-disabled already decided). It is sent
> only to monitor admins. `account_flags_badge.html` now compares those
> booleans instead of regex-matching a JSON blob — before this it had never
> rendered, because `mon.account.flags` was never populated. Needs the deployed
> Go API.
>
> Browser coverage creates a fresh account with one paused monitor through
> `api e2e fixture create`; a separately minted monitor admin views it. A
> pending monitor alone isn't enough: `/manage/monitors` sends an account
> without a testing, active or paused monitor to the setup instructions. Do not
> mutate a long-lived devel monitor/account to manufacture these states.

- [x] As a **monitor admin** on `/manage/monitors/admin` (all-accounts view), an account with `monitor_enabled` shows the green **Bypass** badge. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] An account with `monitor_limit = -1` shows the red **Disabled** badge (and *not* "Custom Limit"). (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] An account with a custom `monitor_limit` shows the blue **Custom Limit** badge, tooltip naming the number. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] An account with a custom per-server limit shows the yellow **Per-Server** badge, tooltip naming the number. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] An account on **all defaults** shows **no badges at all** — and no stray empty gap beside the account name. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] Badges appear in **both** the per-account list and the admin all-accounts view. (`e2e/tests/monitor-badges.spec.ts` → "monitor admin sees account flag badges in both monitor lists")
- [x] As a **non-monitor-admin**, no badges render, and the `list_monitors` JSON response contains no `flags` key for the account. (`e2e/tests/monitor-badges.spec.ts` → "non-monitor-admin sees no badges, gets no flags, and can't open the admin list")

## 16. Dual-stack monitor cards

> A monitor with an IPv4 and an IPv6 row sharing one TLS name renders as one
> card. When both rows have the same status the card shows it once; otherwise
> each address shows its own status. Browser coverage uses a dual-stack
> monitor from `api e2e fixture create`.

- [x] A dual-stack monitor whose addresses have **different statuses** shows each address with its own status. (`e2e/tests/monitor-badges.spec.ts` → "dual-stack monitor cards show per-family or combined status")
- [x] A dual-stack monitor whose addresses share a status shows **one combined status**. (`e2e/tests/monitor-badges.spec.ts` → "dual-stack monitor cards show per-family or combined status")
