# e2e remaining failures

After the harness infrastructure was fixed (URL-encoded session cookie, manage-host
targeting via a two-project split, and a real logged-in preflight in `global-setup.ts`),
the suite runs against the correct hosts and the mass "Invalid cookie fields" /
DNS failures are gone.

The failures below are **genuine spec-vs-live-site issues**, not infrastructure.
Some need a product decision, not just a test edit.

Status at time of writing: 19 passing, 24 failing (before the `login.spec` selector
fix below, which recovers 2 of the login tests).

Update: groups 2, 3, and 6 are now resolved. #6 was a test-only fix (already
green). #2 and #3 turned out to be real product/API gaps, not test bugs — both
fixed in the Go api repo (commits `23da38c` and `08cb4b6`) and will pass once the
dev API is redeployed. See each section for details.

Update: group 4 is now FIXED (Go + Perl), pending dev redeploy. The Go create guard
rejected non-admins from setting `device_information`, but that field **is** collected
from everyone (only its visibility is admin-only). Narrowed the guard so only
`contact_information` is `vendor_admin`-only on create, and stopped the Perl from
sending blank `device_information`/`contact_information` (an empty string still
unmarshals to a non-nil field in Go and tripped the guard). No template change.
#5 turned out to be a **real Perl bug** (not a harness artifact): `Login::logout`
called `delete_session` without `auth`, so the Go session-auth middleware rejected it
401 and the session was never deleted — logout left the token valid for ~45 days.
Fixed in `Login.pm` by passing `auth => $session_token`; the test passes as-written
once deployed. See each section for the confirmed cause and proposed fix.

---

## 1. `/manage/server/add` returns 403 for a fresh user — FIXED (test-only)

**Tests**
- `server.spec.ts:52` — add-server form renders clean for a fresh user
- `server.spec.ts:76` — add a server (best-effort, gated by permission + routable IP)
- `server.spec.ts:142` — set up a server to delete (or use env-provided one)
- `regression-smoke.spec.ts:5` — core pages load clean as a logged-in user

**Symptom**

```
Error: unexpected status for /manage/server/add
Expected: 200
Received: 403
```

**Cause (corrected — the earlier `can_add_servers` analysis was wrong)**

The 403 has nothing to do with `can_add_servers` and nothing to do with how
"full" the minted session is. `/manage/server/add` is a **POST-only,
CSRF-protected form action**: `handle_add` (`Server.pm:131`) runs
`return 403 unless $self->check_auth_token` *before* any permission logic, and
`check_auth_token` (`Combust/Control.pm:488`) returns 0 when there is no
`auth_token` request param. A bare GET carries no token, so it 403s for *any*
user. The `can_add_servers` failure path actually returns **200** (the
"verify your existing servers" notice rendered into `add_form.html`), so it
could never produce the observed 403.

The add **form** is rendered on `/manage/servers` (`tpl/manage.html` line 25,
`PROCESS add_form.html`), unconditionally — it is present even for a fresh
account. When `can_add_servers` is false the servers page shows a
"...before adding more" notice alongside the form (`tpl/manage.html` ~line 26).

**Fix (test-only)**

Point the tests at `/manage/servers` (where the form lives) instead of GETing
the POST-only `/manage/server/add`. The add tests detect the permission notice
on the servers page and skip gracefully when gated; `regression-smoke` swaps the
bogus `/manage/server/add` GET for `/manage/account`. No API change or new
`CreateTestSession` grant flag needed.

---

## 2. Invite "Resend" form/button not found

**Tests**
- `invites.spec.ts:72` — pending invite shows a Resend button for an account with edit access
- `invites.spec.ts:87` — clicking Resend shows the success badge and sends a new invite email
- `invites.spec.ts:119` — an immediate second resend is blocked by the 5-minute cooldown
- `invites.spec.ts:189` — a resent invite's expiry moves to ~30 days out
- `invites.spec.ts:278` — a user without access to the account cannot resend

**Symptom**

```
expect(locator).toBeVisible() failed
Locator: locator('form:has(input[name="resend_invite_id"]) button[type="submit"]')
Error: element(s) not found
```

**Cause (confirmed)**

Not a selector issue. A freshly-created invite reported `can_resend=false`, so
`team.html` rendered the *disabled* Resend button and the active resend form never
appeared. The initial invite send sets `sent_count=1` and `last_sent_on=now`,
which started the 5-minute resend cooldown immediately. All 5 tests assumed a
fresh invite is immediately resendable (including the non-member test, which
checks the owner's active button before switching identities).

**Fix (Go API — pending deploy)**

The cooldown now applies only *between* resends: the first resend (sent_count = 1)
is exempt, while the 3-per-24h cap still applies. Changed `evalResend` and the
atomic `ResendAccountInvite` WHERE clause together (commit `23da38c` in the Go
api repo). Tests will go green once the dev API is redeployed.

---

## 3. Staff "Delete user" link not found

**Tests**
- `staff-deletion.spec.ts:155` — staff schedules deletion of another USER, targeting that user (not self)
- `staff-deletion.spec.ts:208` — staff schedules another ACCOUNT's deletion, scoped to that account
- `staff-deletion.spec.ts:266` — non-staff user cannot target another user or account
- `staff-deletion.spec.ts:339` — DB: scheduling a user deletion writes an audit-log row for the target
- `staff-deletion.spec.ts:393` — DB: scheduling an account deletion writes an audit-log row

**Symptom**

```
Error: staff team page should show a Delete user link
expect(locator).toBeVisible() failed
Locator: locator('a[href*="/manage/account/delete"]').filter({ hasText: 'Delete user' }).first()
Error: element(s) not found
```

**Cause (confirmed — deeper than the template)**

Not the template or the selector. The acting user *is* staff (the staff-only
"Admin search" nav link renders), but the team table came back **empty** and the
audit logs showed "unavailable: unauthorized". The real gap was in the Go auth
**middleware**: it resolved the requested account (`?a=` / `X-Account`) via
membership-only `GetAccountByTokenUser`, so a staff user on a foreign account
failed account resolution and the whole request was rejected (401). Only
`ValidateSession` had a staff override, which is why the page *shell* loaded while
`GetAccountUsers`, `GetAccountInvites`, and the audit-log endpoint all returned
empty/unauthorized. (Test 123 "passed" only because the target email appears in
the account-name heading, not in a team row.)

Note: tests 208/393 (account dissolve) were grouped here but actually failed for
the same root cause — the dissolve schedule RPC also needs the foreign account
context resolved.

**Fix (Go API — pending deploy)**

Added the staff override to `getRequestAccount` (falls back to
`GetAccountByIDToken`), fixing all account-scoped endpoints in one place, and
broadened the override (middleware + `ValidateSession`) to any staff privilege
(support, monitor, or vendor). Destructive actions stay gated on `support_staff`
(commit `08cb4b6` in the Go api repo). Tests will go green once the dev API is
redeployed.

---

## 4. Vendor new-zone form submit never navigates

**Tests**
- `vendor.spec.ts:98` — create a New vendor zone request
- `vendor.spec.ts:122` — edit a New/Pending zone and persist a changed field
- `vendor.spec.ts:161` — open-source submit retains justification and edits without error
- `vendor.spec.ts:217` — duplicate zone name surfaces a red error alert with a Trace ID
- `vendor.spec.ts:390` — approve/reject status changes and owner resubmit

**Symptom**

```
Error: page.waitForURL: Test timeout of 30000ms exceeded.
waiting for navigation until "load"
  navigated to "https://manage.askdev.grundclock.com/manage/vendor/zone"
```

(`createNewZone` at `vendor.spec.ts:65` — `page.waitForURL(/\/manage\/vendor\/zone\?/)`)

**Cause (confirmed) — FIXED (Go guard + Perl); device_information stays user-settable**

All five tests funnel through the `createNewZone` helper (`vendor.spec.ts:53-71`),
which POSTs the new-zone form to `/manage/vendor/zone`. The POST hit a
`permission_denied` error, so the controller re-rendered the form (HTTP 200, no
redirect) and the page stayed on `/manage/vendor/zone` with no query string — exactly
the `waitForURL(/\/manage\/vendor\/zone\?/)` timeout reported.

Two things combined to cause it:

1. **The Go create guard was too broad.** `RequestVendorZone`
   (`../go/ntp/api/server/api/vendorzone/request.go`) rejected *any* non-nil
   `device_information` **or** `contact_information` from a non-`vendor_admin` user.
   But `device_information` **is** collected from all users — the form
   (`form.html:82-89`) renders the textarea for everyone, and the test fills it
   (`vendor.spec.ts:47,61`). So a fresh, non-admin user submitting the form was
   rejected. (Note the create guard was also inconsistent with the **update** path,
   `update.go`, which has no such guard — an in-account user can already set both
   fields on update.)
2. **The Perl always sent both fields as `''`.** `_edit_zone`
   (`lib/NTPPool/Control/Vendor.pm`) put `device_information => req_param(...) || ''`
   and `contact_information => req_param(...) || ''` into `%content` unconditionally
   and forwarded them on the create path. `request_vendor_zone`
   (`lib/NP/CAPI/VendorZone.pm:490-491`) forwards each key when present, and these are
   proto3 `optional` fields, so a present JSON key (even `""`) unmarshals to a
   **non-nil** `*string` in Go — tripping the guard even when the user left a field
   blank. `contact_information` is gated in the form (`form.html:93`,
   `[% IF vz.contact_information %]`), so a regular user never sees it, yet Perl still
   sent `contact_information => ''`.

`render_edit` (`Vendor.pm:449-457`) re-renders the form on error instead of
redirecting, hence the missing query string. The edit / open-source / duplicate-name
/ approve-reject tests (`vendor.spec.ts:122,161,217,390`) all call `createNewZone`
first, so they failed at the create POST before reaching their own assertions.

**Fix (applied, two repos)**

1. **Go** (`../go/ntp/api/server/api/vendorzone/request.go`) — narrowed the create
   guard so only `contact_information` is `vendor_admin`-only; `device_information` is
   now accepted from any requester (it is still shown only to admins, but anyone may
   provide it). Persistence (`request.go:90-110`) and read-back
   (`buildVendorZone`, `vendorzone.go:114-118`) already return `device_information`
   whenever set, for the zone owner — no read-side filtering. Go build/vet/tests pass.
2. **Perl** (`lib/NTPPool/Control/Vendor.pm`, `_edit_zone`) — on the create path,
   copy `%content` and drop `device_information`/`contact_information` when blank
   before calling `request_vendor_zone`, so an empty `contact_information` no longer
   reaches the (now contact-only) guard and an empty `device_information` stores unset
   rather than `""`. The update path is unchanged (it sends all fields, which is fine
   — no guard there, and blanking a field to clear it still works).

No template change was needed: `device_information` correctly remains collected from
everyone.

**Verification**

- Go: `go build ./...`, `go vet ./server/api/vendorzone/`, and
  `go test ./server/api/vendorzone/` all pass.
- Pending: run `vendor.spec.ts` against dev once the Go API is redeployed. The
  duplicate-name test (`vendor.spec.ts:217`) will then exercise its intended path
  (it previously failed on the first `createNewZone` permission error, not on the
  duplicate name).

---

## 5. Logout does not end the server-side session — FIXED (real Perl bug)

> **Correction:** the earlier "test/harness artifact" diagnosis was **wrong**.
> Logout was genuinely broken server-side: the session was never deleted. The fix
> is a one-line Perl change in `Login::logout`, not a test edit. The test passes
> as-written once that fix is deployed.

**Test**
- `login.spec.ts:85` — logout then log back in restores the same account

**Symptom**

```
expect(locator).toBeVisible() failed
Locator: getByRole('heading', { name: 'Sign in to the NTP Pool' })
Error: element(s) not found
```

After `GET /manage/logout`, the browser is **still logged in**: it redirects to
`/manage/servers?a=...` and shows "Add my server" rather than the sign-in page.

**Cause (confirmed against live dev) — `DeleteSession` was never authorized**

`DeleteSession` is gated by the Go **session auth middleware**, but
`Login::logout` (`lib/NTPPool/Control/Login.pm`) called `delete_session` with only
`session_token` and `context` — **no `auth`**. With no `Authorization: Bearer`
header, the middleware rejects the RPC with `401 {"message":"unauthorized"}`
*before* `delete_session.go` runs, so the row is never deleted. Perl only `warn`s
"Failed to delete session" and redirects, so the failure was invisible.

The browser cookie clearing works, but is irrelevant here: the Playwright/CDP
store keeps the injected host-only `npuid` across the redirect, so the still-present
cookie is re-sent — and because the session it points to is **still live**,
`validate_session` returns valid and the user lands back on the authenticated
dashboard. (A real browser drops the cookie and *appears* logged out, which is why
this went unnoticed — but the session token stays valid in the DB for ~45 days, a
real logout/security defect: a captured token survives "Logout".)

**Live evidence (dev `manage.askdev.grundclock.com` + internal API):**

- `GET /manage/logout` emits the clearing cookie *and* a 302, but reusing the same
  token on `GET /manage` afterward still 302s to `/manage/servers?a=...` (authed).
- Direct RPC, same token:
  - `DeleteSession` with **no** auth → `{"message":"unauthorized"}`; the session
    still validates.
  - `DeleteSession` with `Authorization: Bearer <token>` → `{"deleted":true}`; a
    follow-up `ValidateSession` then returns `unauthorized` (session gone).
  - Works with the real cookie form too: a `Bearer nps_..._<checksum>;<timestamp>`
    value (suffix included) is accepted — the middleware strips the `;timestamp`.

Both `ValidateSession` and `DeleteSession` look the session up by the same
`token_lookup = strconv.Itoa(checksum)`, so once the authorized delete runs the
session is genuinely gone. The lookup was never the problem — authorization was.

**Fix (Perl — applied)**

`lib/NTPPool/Control/Login.pm`, `logout`: pass the captured session token as
`auth` as well as `session_token`:

```perl
my $result = delete_session(
    auth          => $session_token,
    session_token => $session_token,
    context       => $self->_get_request_context(),
);
```

`connect_rpc` (`lib/NP/CAPI.pm:242`) maps `auth` to `Authorization: Bearer`, which
satisfies the middleware. `$session_token` is captured before the cookie is cleared,
so it is still the live token. No Go change is needed — the guard is correct, and
the only real caller of `delete_session` in Perl is this logout path.

**Why the test now passes as-written**

With the server-side delete actually happening, the lingering harness cookie points
to a dead session: the post-logout `/manage` request sends it, `validate_session`
returns 4xx invalid, `Login::user` clears the cookie and treats the request as
logged out, and `/manage` renders the sign-in page — exactly what
`login.spec.ts:103-106` asserts. No test edit required.

**Verification**

- Done (mechanism, live dev via direct RPC): authorized `DeleteSession` invalidates
  the session; unauthorized does not — see "Live evidence" above.
- Pending deploy: the Perl fix runs in the deployed `manage` app, so the live
  `/manage/logout` end-to-end and `login.spec.ts:85` go green only after the
  `postgres`-branch Perl is redeployed to dev.

---

## 6. Legacy `/scores/graph/<id>-offset.png` redirect

**Test**
- `scores.spec.ts:62` — legacy `/scores/graph/<id>-offset.png` redirects to the PNG

**Symptom**

`waitForURL` / `getAttribute` timeout waiting for
`img[src*="-offset.png"], img[src*="/offset.png"]` on the score page; the legacy
redirect assertion does not resolve.

**Cause (confirmed) — FIXED (test-only)**

The redirect itself works (`Scores.pm` 301s `/scores/graph/<id>-offset.png` →
`/graph/<ip>/offset.png` → PNG). The test failed because the
`<img src="…-offset.png">` lives inside `<noscript>` (`server.html`), so a
JS-enabled browser never exposes it in the DOM. The same legacy URL is carried as
`data-offset-graph-url` on the real `#legacy-graphs` element.

Fixed the test to read that attribute and follow it; passes against live dev. No
API change or deploy needed.

---

## Already fixed in this pass

- **Session cookie URL-encoding** — `lib/auth.ts` installs the `Cookie::Baker`-encoded
  value (raw `;` → `%3B`), so CDP accepts it and it round-trips through `crush_cookie`.
- **Host targeting** — two Playwright projects (`web` / `manage`) with per-project
  `baseURL`; the session cookie is installed on the manage host. New `NTP_MANAGE_URL`.
- **Preflight** — `global-setup.ts` now mints a session, loads the manage dashboard in
  a browser, and asserts the visible Logout link, so auth/host/cookie breakage fails
  once with a clear message.
- **`login.spec.ts` Logout selector** — scoped to `a.nav-link:visible` (the manage
  layout renders the sidebar twice; the `#mobile-nav` copy is hidden). Recovers the
  two passing login tests; the logout test (group 5 above) remains.
