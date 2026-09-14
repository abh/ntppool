# Vendor zone E2E coverage and a subscription fixture seed

**Date:** 2026-09-14
**Status:** Design agreed in conversation on 2026-09-14. Re-checked against
the code on 2026-09-14 (API `main` at `bf777fe`, this repo at `456b9f2c`).
Updated the same day with a zone-limit test (Decision 8) and the placement of
the new admin tests. Implemented on 2026-09-14 (API `c9635c4`, deployed to
devel as `sha-c9635c47`). Passed two devel runs.
**Spans:** the Go API (`../go/ntp/api`: `e2efixture`, `sql/e2e_fixtures.sql`,
`cmd/e2e.go`, one doc fix) and this repo's `e2e/` harness and
`MANUAL_TEST_PLAN.md`. No Perl or template changes.
**Builds on:** `docs/superpowers/specs/2026-09-13-e2e-fixtures-cli-design.md`
(test-only setup lives in `api e2e` subcommands, never in network-reachable
handlers) and `docs/superpowers/specs/2026-09-13-monitor-badge-fixture-design.md`
(`api e2e fixture create|cleanup`).

## Goal

Automate the unchecked `MANUAL_TEST_PLAN.md` §5 rows (vendor zones) that don't
need a test hook in a network handler:

1. Finish the §5a editability matrix and the §5b claim and grant rows with the
   existing harness.
2. Add a live-subscription seed to `api e2e fixture create`, so tests can
   reach a covered vendor and an over-limit vendor (§5, §5b, §5e).
3. Check the §5e coverage gate in both layers: the Perl submit gate in the
   browser, and the Go `SubmitVendorZone` gate through an authenticated
   ConnectRPC call.

This is also the first step toward E2E tests that go through Stripe and
stripe-gw. The seed exercises neither. It gives coverage-routing tests a
fast starting state that doesn't depend on Stripe, and later Stripe tests can
prove that a checkout ends in the same kind of row.

## Decisions

1. The subscription seed goes into `api e2e fixture create`. Not a separate
   command, and not the `CreateOrUpdateSubscription` RPC: that RPC trusts the
   status and limits its caller sends (`subscription.go:244-325`), which the
   Stripe work is likely to tighten.
2. No registry table or migration for subscriptions. The seeded row's
   `stripe_subscription_id` is `e2e_<attempt_id>`, which is unique and
   derivable from the attempt, so it is the durable record.
3. Tests still create zones and move them between statuses through the UI.
   Removing those zones is out of scope.
4. The §5e gate rows are tested in both layers (Perl in the browser, Go
   through `SubmitVendorZone`), so each row gets ticked as a whole.
5. The reject/resubmit/approve walk test is extended with one `test.step` per
   phase. "Grant unchecked" stays its own test, which approves one more zone
   per run.
6. The whitespace-only justification test pins the API's message.
7. The covered-submit test asserts that the claim is false and the grant is
   undecided. It doesn't pin `opensource_info` (see Findings).
8. The over-limit gate is tested for both limits, each in its own test: the
   device limit (test 9) and the zone limit (test 10). Only Approved zones
   count toward `max_zones`, so the zone-limit test has a vendor admin
   approve a zone first. Keeping it separate means the device-limit test
   doesn't depend on an admin session.

## Findings that shaped the design (re-checked 2026-09-14 at API `bf777fe`)

Go paths are relative to `../go/ntp/api`; `server/api/vendorzone/` and
`server/api/subscription/` files are named without their directory.
`Vendor.pm` is `lib/NTPPool/Control/Vendor.pm`, and templates are in
`docs/manage/tpl/vendor/` unless a path is given.

### Coverage and the submit gates

- `AccountCoverage` (`coverage.go:43-83`) counts `active`, `trialing` and
  `incomplete` subscriptions as live (`GetLiveSubscriptionsForAccount`,
  `sql/subscriptions.sql:67-72`) and sums their limits. An account with a live
  subscription is over the limit when its Approved zone count reaches
  `max_zones`, or when its Approved device count plus the new zone's
  `device_count` exceeds `max_devices`. So a fresh account with `max_devices`
  5000 and a 10,000-device zone is over the limit without any Approved zone.
- Only Approved zones count (`GetApprovedZoneStats`,
  `sql/subscriptions.sql:84-90`), so a Pending zone doesn't use up
  `max_zones`. The zone check runs before the device check. Neither
  `RequestVendorZone` nor `UpdateVendorZoneStatus` reads coverage, so an
  account at its zone limit can still create a New zone, and approving a zone
  isn't gated.
- Perl's gate in `render_submit` (`Vendor.pm:375-414`) matches Go's
  (`submit.go:107-124`): a live subscription within limits, or an open-source
  claim with a justification. Both read the zone's account: Perl passes the
  zone's `account_token` to `get_account_subscription_status`. Perl refuses
  before calling the API, so the Go message "a subscription is required, or
  apply as open source" never reaches the browser. Checking the API gate takes
  a direct `SubmitVendorZone` call.
- An uncovered refusal sets `need_subscription` and renders `missing_plan`
  ("Please choose a subscription plan or choose open source below") as a
  `.text-danger` div at the top of `products.html` (`:12-14`), not as an
  alert, whether or not stripe-gw returned products. The open-source form
  renders again below it.
- An over-limit account gets `need_upgrade` instead (`Vendor.pm:283-289`):
  "The current subscription plan doesn't support adding the new DNS zone"
  (`show.html:136-148`), with no submit control and no open-source form. The
  page still has a form carrying `auth_token`: the sidebar's "New account"
  form (`docs/manage/tpl/navigation_sidebar.html:38-43`), whose `a` is `new`.
- The Go gate reads the zone's account and has no admin bypass. `IsStaff()`
  includes vendor-zone staff (`ntpdb/user.go:8-10`, `:41-43`), so the session
  middleware resolves another account's token for a vendor admin
  (`getRequestAccount`, `server/api/sessions/auth.go:466-476`). Perl's
  `get_account_subscriptions` call for the zone's account relies on that.

### Claim and grant

- The UI never shows `opensource_approved`. `GetVendorZone` returns it and
  needs only a logged-in user (`get.go:23`); `X-Account` is optional there.
  The API's JSON uses proto field names and `EmitDefaultValues`
  (`server/base/connect_options.go`). That emits `opensource_requested: false`,
  but omits unset `optional` fields such as `opensource_approved` and
  `opensource_info` (`proto/ntppool/vendorzone/v1/vendor.proto:88,98`) rather
  than sending `null`. An undecided grant is an absent key. `device_count` is
  an `int64`, so it arrives as a JSON string.
- Reject always sends `opensource_approved=false` (`render_admin`,
  `Vendor.pm:833-840`). A resubmit resets it to NULL and clears
  `rejection_reason` (`SubmitVendorZone`, `sql/vendor_zones.sql:113-125`). The
  Grant checkbox (`#opensource_grant`) on the admin form is pre-checked when
  the zone carries a claim (`show.html:111-118`).
- A covered plain submit sends `opensource_requested=false` and
  `opensource_info=""` (`Vendor.pm:417-427`), and `UpdateVendorZone`'s
  `COALESCE` stores both (`sql/vendor_zones.sql:101-102`). A Rejected
  open-source zone whose vendor later resubmits with a subscription therefore
  loses its claim and its stored justification. Nobody has decided whether
  that's intended, so the tests don't pin `opensource_info` there.
- A whitespace-only justification reaches the API:
  `Combust::Request::Plack::req_param` returns the raw parameter
  (`combust/lib/Combust/Request/Plack.pm:45-49`), and Perl's check is a
  truthiness test (`Vendor.pm:388-397`). Go's `validateOpensourceInfo` rejects
  it with "opensource_info must contain non-whitespace characters"
  (`validation.go:164-167`) before any write. `render_submit` shows the Connect
  `message` (`lib/NP/CAPI.pm:441-447`) in the `_errors.html` alert with a
  Trace ID. The "known gap" note in §5b is out of date.

### Editing

- `UpdateVendorZone` (`update.go:224-234`) only restricts Approved zones:
  non-admins can't edit them, and nobody can change their `zone_name` ("zone
  name cannot be changed after approval", `invalid_argument`). That check runs
  before field validation. Owners can edit New, Pending and Rejected zones.
  `server/api/vendorzone/CLAUDE.md` still says updates are allowed only while
  a zone is New.
- On an edit error, `render_edit` re-renders the form with the alert instead
  of redirecting (`Vendor.pm:463-471`). `_edit_zone` refetches the zone first
  (`:544-553`), so the form shows the stored values, not the submitted ones.
- `_edit_zone` sends `contact_information` on every edit (`Vendor.pm:502-509`).
  `RequestVendorZone` refuses it from non-admins (`request.go:48-51`).
  `UpdateVendorZone` doesn't check it, but `form.html` renders the field only
  when the zone already has a value (`form.html:93-103`), so a regular user
  never sees it.

### Pages

- `/manage/vendor/plan` without a `product_id` renders `subscription.html`,
  whose whole body sits inside `IF pr`, so the page content is blank. The
  route is dispatched before the "no zones" redirect and needs `can_edit`
  (`Vendor.pm:56-57`, `:624-628`). The visible subscription effects are on
  `/manage/vendor`: a Pending zone reads "Processing" (`vendor.html:20-23`),
  and `billing.html` renders "Current plan" with the plan name, "Up to N DNS
  zones" and "Up to N client devices". `max_devices` goes through
  `format_number`; `max_zones` doesn't, so the text is "Up to 1 DNS zones".
- `submitted.html` shows the "You'll get an email shortly with a ticket
  number" paragraph only when the vendor isn't covered. `have_subscription`
  is set before the open-source branch (`Vendor.pm:380-384`), so an uncovered
  open-source submit still shows it.

### Subscription rows

- `account_subscriptions` (`schema.sql:264-275`): `account_id`, `name`,
  `max_zones`, `max_devices` and `created_on` are NOT NULL. `status` is a
  nullable `account_subscriptions_status` enum (`incomplete`,
  `incomplete_expired`, `trialing`, `active`, `past_due`, `canceled`,
  `unpaid`, `ended`), and `modified_on` has a default.
  `stripe_subscription_id` is a nullable `varchar(255)` with a unique index
  (`schema.sql:2117`).
- The `account_id` foreign key to `accounts` doesn't cascade
  (`schema.sql:2792-2793`), and neither deletion task removes subscription
  rows. Both already skip an account that has vendor zones
  (`tasks/accountdelete/accountdelete.go:108-114`,
  `tasks/userdelete/userdelete.go:175-182`), and every account in
  `vendor-coverage.spec.ts` gets one. Only a seeded account without zones
  would reach `DeleteAccountByID` and fail on the foreign key.
- Nothing else moves a seeded row. `ProcessStripeWebhook` finds the account
  by `stripe_customer_id` and updates by `stripe_subscription_id`, and
  `UpdateAccountSubscription` and `UpsertAccountSubscription` never set
  `account_id` (`sql/subscriptions.sql:31-66`). Stripe's IDs start with
  `sub_`, so an `e2e_` ID can't collide with one.
- The fixture CLI rejects unknown JSON fields (`cmd/e2e.go:111`). A harness
  that always sent a `subscription` key would break every fixture spec against
  an api-dev image from before this change. The harness also refuses a seed
  with no server and no monitor on its own (`e2e/lib/fixtures.ts:178-180`).

### Devel side effects (not addressed here)

- Tests never remove the zones they create. `GetDnsZoneData` publishes
  Approved zones (`ListActiveVendorZonesByDnsRoot`, `sql/zones.sql:194-200`),
  and the admin block approves five per run today (six after this change).
  `vendor-coverage.spec.ts` approves one more, so a run adds seven.
  Pending zones pile up in the admin list, which has no limit
  (`ListVendorZonesAdmin`, `sql/vendor_zones.sql:171-196`).
- While a seed exists, the admin list sorts that account's zones first: it
  orders by the account's newest unended subscription.
- Vendor emails aren't sent in devel mode (`lib/NP/Email.pm:52-55`).

## Go API

### Request

```json
{
  "attempt_id": "<canonical lowercase UUID v4>",
  "servers": [],
  "monitors": [],
  "subscription": {"max_zones": 1, "max_devices": 10000}
}
```

- `subscription` is optional; absent or `null` means none.
- `max_zones` and `max_devices` are required and at least 1. A missing field
  decodes to 0 and fails that check.
- "At least one server or monitor" becomes "at least one server, monitor or
  subscription", in `validateFixtureRequest` and its message
  (`e2efixture/fixture.go:158-187`).
- Go types: `SubscriptionFixtureSpec` with `MaxZones int64
  json:"max_zones"` and `MaxDevices int64 json:"max_devices"`, and
  `CreateFixtureRequest.Subscription *SubscriptionFixtureSpec
  json:"subscription"`.

### Create

In the existing create transaction, after the account exists, insert one
`account_subscriptions` row (new query `InsertE2EFixtureSubscription` in
`sql/e2e_fixtures.sql`, `RETURNING id`):

| Column | Value |
| --- | --- |
| `account_id` | the fixture account |
| `stripe_subscription_id` | `e2e_<attempt_id>` |
| `status` | `active` (cast to `account_subscriptions_status`) |
| `name` | `E2E fixture` |
| `max_zones`, `max_devices` | from the request |
| `created_on` | `CURRENT_TIMESTAMP` |
| `ended_on` | NULL |
| `modified_on` | column default |

`accounts.stripe_customer_id` stays NULL, which is where a real checkout
starts.

### Response

```json
"subscription": {
  "subscription_id": "123",
  "stripe_subscription_id": "e2e_<attempt_id>",
  "status": "active",
  "max_zones": 1,
  "max_devices": 10000
}
```

`subscription` is `null` when none was requested
(`CreateFixtureResponse.Subscription *FixtureSubscription
json:"subscription"`, no `omitempty`). The ID is a string
(`json:"subscription_id,string"`), like the other IDs in the response; the
limits are JSON numbers.

### Cleanup

Inside the existing attempt lock and transaction, next to the server and
monitor ownership checks (`e2efixture/fixture.go:431-451`):

1. `LockE2EFixtureSubscription` (`:many`; the unique index allows 0 or 1
   rows) selects `id` and `account_id` of the row whose
   `stripe_subscription_id` is `e2e_<attempt_id>`, `FOR UPDATE`.
2. If that row belongs to another account, return `ErrOwnershipChanged`. Its
   message names subscriptions along with servers and monitors.
   `fixtureError` already passes it through (`fixture.go:502`).
3. After the monitor delete and before the tombstone,
   `DeleteE2EFixtureSubscription` (`:execrows`) deletes by that stripe ID and
   the fixture account. The deleted count must equal the locked count.

`CleanupFixtureResponse` gains `DeletedSubscriptions int64
json:"deleted_subscriptions"`: 0 or 1, and 0 on a repeat cleanup or for an
attempt without a seed. Cleanup never deletes by account alone. Users,
accounts and tombstones behave as they do today.

### CLI help

`cmd/e2e.go:31,35-36` describe the fixture commands as servers and monitors.
Name the subscription too.

### Tests

`e2efixture/fixture_integration_test.go` has one `TestFixtureIntegration`
with subtests. Add subtests for:

- a subscription-only attempt creates the row, and cleanup removes it
- a subscription plus a server
- validation: a missing or zero `max_zones` or `max_devices`, and an attempt
  with no server, monitor or subscription
- a repeat cleanup returns 0
- cleanup refuses when the row has moved to another account (the test moves
  it with a direct `UPDATE`), and leaves the attempt uncleaned

### Doc fix

`server/api/vendorzone/CLAUDE.md`: replace "Updates allowed ONLY when
status=New" and "Once submitted (Pending), users cannot edit" (lines 51-52),
the `UpdateVendorZone` summary and authorization lines (80, 83), and "update
(when New)" under Regular Users (139) with the rule `update.go` enforces.

## Harness

### `lib/fixtures.ts`

- `SubscriptionSeed { maxZones: number; maxDevices: number }` and an optional
  `FixtureSeed.subscription`. Normalization rejects limits that aren't
  integers of at least 1 before calling the CLI.
- The local "at least one server or monitor" check (`fixtures.ts:178-180`) and
  the header comment accept a subscription-only seed.
- Send the `subscription` key only when the seed has one, so specs without a
  seed keep working against an older api-dev image.
- Parse `subscription`: when seeded, check status `active`, the stripe ID
  `e2e_<attemptId>`, the requested limits (`intField`) and the ID
  (`idField`); when not seeded, accept an absent or `null` value only.
- Cleanup requires `deleted_subscriptions` only for attempts that seeded a
  subscription, so it needs to know whether the attempt had one. The cleanup
  attachment and failure diagnostics include the subscription ID.

### `lib/auth.ts`

`RpcError` gains `connectMessage`: the Connect error JSON's `message` when it
is a string. `connectRpc` reads only `code` today (`auth.ts:93-110`). The
message stays out of the thrown error's text, so it only appears in a report
when a test asserts on it.

### `lib/vendor.ts` (new)

Moved from `tests/vendor.spec.ts`: `NewZoneData`, `freshZoneData`,
`createNewZone`, `loginAsVendorAdmin` (which now also returns the session
token), `isVendorAdmin`, `createAndSubmitPendingZone` and `adminOpenZone`.

New:

- `getVendorZone(sessionToken, idToken)` calls
  `ntppool.vendorzone.v1.VendorZoneService/GetVendorZone` and returns
  `status`, `zone_name`, `device_count` (a string), `opensource_requested`,
  `opensource_info` (optional) and `opensource_approved` (optional; absent
  means undecided), after checking their types. The API omits unset optional
  fields, so a `null` fails the check.
- `submitVendorZoneApi(sessionToken, accountToken, idToken)` calls
  `SubmitVendorZone` with `X-Account` and a body of only `id_token`, because
  the gate reads the stored claim.
- `approveZone(page, idToken, { grant })` sets `#opensource_grant` to `grant`
  and clicks Approve on the admin zone page; `rejectZone(page, idToken)` clicks
  Reject.
- `editZone(page, idToken, fields)` opens the edit form, changes the given
  fields, saves and waits for the show page.

Account tokens for `X-Account`:

- Owner: `fixture.accountToken`, or the `a` parameter of the show-page URL
  that `createNewZone` returns (`Vendor.pm:475-481`).
- Vendor admin's own account: the `a` input of
  `form[action="/manage/vendor/admin"]` on the admin zone page
  (`show.html:110`). Don't take the first `input[name="a"]` on the page: the
  sidebar's "New account" form comes first and holds `new`.

## Tests

`MANUAL_TEST_PLAN.md` marks new and changed tests "implemented;
live-unverified" until they pass on devel.

### `tests/vendor.spec.ts`, regular user

1. **every writable field saves on a New zone** (new). Change `zone_name`,
   `request_information`, `device_count` and `device_information`, then check
   the show page and the reopened form. The show page renders `device_count`
   through `format_number`, so check it on the form as the select's value.
   `organization_name` already has a test, and a regular user never sees
   `contact_information` (see Editing). (§5a New)
2. **every writable field saves on a Pending zone** (new). The same after an
   open-source submit. (§5a Pending)
3. **a whitespace-only justification is refused by the API and the zone stays
   New** (new). The `_errors.html` alert at the top of the show page shows
   "opensource_info must contain non-whitespace characters" with a Trace ID,
   and the list still shows New. (§5b)

### `tests/vendor.spec.ts`, admin block

New tests in the `test.describe.serial` block follow its pattern: probe
`isVendorAdmin` and skip when the admin session can't reach the admin route.
Tests 4, 5 and 7 go in that existing block, next to the tests they extend or
replace, not in a new describe block.

4. **an uncovered plain submit is refused by the site and by the API** (new),
   all on one uncovered zone:
   - Remove the hidden `opensource_request` input with `locator.evaluate`
     (CDP, so the page CSP doesn't apply), fill in a justification and
     submit. "Please choose a subscription plan or choose open source below"
     renders in `.text-danger`, and the zone stays New.
   - `SubmitVendorZone` as the owner fails with `failed_precondition` and "a
     subscription is required, or apply as open source".
   - The same call as a vendor admin, with the admin's own account in
     `X-Account`, fails the same way.
   - `GetVendorZone` still reports New.

   (§5e uncovered without a claim)
5. **renaming an Approved zone shows the API's refusal** (replaces "vendor
   admin cannot rename an Approved zone via the API"). Remove `readonly` from
   `zone_name` in the browser, change the name, submit the real form and wait
   for the alert, not a redirect: "zone name cannot be changed after approval"
   with a Trace ID. The re-rendered form shows the stored name, read-only
   again. `GetVendorZone` still returns the old name. (§5a staff, Approved)
6. **approve/reject status changes and owner resubmit** (extended, one
   `test.step` per phase):
   - after the open-source submit, `opensource_requested` is true and the
     grant is undecided
   - after Reject, the grant is false
   - the owner edits `organization_name` and `request_information` on the
     Rejected zone; the save works, no "opensource_info" error appears, and
     the justification still shows
   - the owner resubmits with a new justification: Pending, the claim is
     true, `opensource_info` is the new text, and the grant is undecided
   - Approve with the Grant box left checked (assert that it's pre-checked),
     and the grant is true

   (§5a Rejected; §5b grant undecided, claim kept after resubmit, Rejected
   edit, and the checked half of the Grant row)
7. **approving with Grant unchecked leaves the zone on the paid path** (new).
   Uncheck Grant and approve: `opensource_approved` is false and
   `opensource_requested` is still true. (§5b, the unchecked half of the Grant
   row)

### `tests/vendor-coverage.spec.ts` (new)

Uses the `fixtures` test from `lib/fixtures.ts`. Each test creates its own
subscription-only fixture and installs its session for the owner with
`installSession(context, fixture.sessionToken)`. The fixture user has exactly
one account (`CreateDefaultAccount`, `e2efixture/fixture.go:224`), like a
`loginAs` user, so pages without `a=` use it. `test.use({ trace: "off" })`,
because traces would hold session cookies (as in `monitor-badges.spec.ts`).
The admin session comes from `loginAsVendorAdmin(browser, …)`, which works
with the `fixtures` test because it extends Playwright's base test. The
`vendor.spec.ts` preflight doesn't run for this file, so the admin steps in
tests 10 and 11 fail, rather than skip, when the minted session can't reach
`/manage/vendor/admin`.

8. **a covered vendor gets a plain submit and stays off the open-source path**.
   Seed 1 zone and 10,000 devices; the zone has 5,000 devices.
   - The show page has "Submit for production", no `opensource_info` textarea
     and no `opensource_request` input.
   - After submitting, the page names the zone and has no ticket-number
     paragraph.
   - `/manage/vendor` shows "Processing" and "Current plan" with "E2E
     fixture", "Up to 1 DNS zones" and "Up to 10,000 client devices".
   - `/manage/vendor/plan` loads cleanly.
   - The zone page has no "Open Source information".
   - `GetVendorZone` reports Pending, `opensource_requested` false and an
     undecided grant.

   (§5 subscription row, §5b covered rows, §5e covered)
9. **a covered vendor over the device limit is refused by the site and by the
   API**. Seed 1 zone and 5,000 devices; the zone has 10,000 devices.
   - The show page shows the upgrade message, with no submit button and no
     open-source form.
   - A POST to `/manage/vendor/submit` through `page.request`, with `id`,
     `auth_token` and `a` taken from the edit form (`form.html:15-17`),
     returns a body with the upgrade message again.
   - `SubmitVendorZone` as the owner fails with `failed_precondition` and "a
     subscription is required, or apply as open source".
   - `GetVendorZone` still reports New.

   (§5e over-limit, device limit)
10. **a covered vendor at the zone limit is refused by the site and by the
    API**. Seed 1 zone and 100,000 devices. Both zones have 5,000 devices, so
    only the zone count can refuse.
    - The owner creates zone A and submits it with the plain submit, so it's
      Pending. A vendor admin approves it with Grant unchecked.
    - The owner creates zone B. Its show page shows the upgrade message, with
      no submit button and no open-source form.
    - A POST to `/manage/vendor/submit` for B, built as in test 9, returns a
      body with the upgrade message again.
    - `SubmitVendorZone` for B as the owner fails with `failed_precondition`
      and "a subscription is required, or apply as open source".
    - `GetVendorZone` reports B New and A Approved.

    (§5e over-limit, zone limit)
11. **a vendor admin submits for a covered account, and the owner resubmits
    after a rejection**. Seed 1 zone and 10,000 devices.
    - The owner creates a zone. A vendor admin, whose own account has no
      subscription, opens it at `/manage/vendor/zone?id=`, sees "Submit for
      production" and submits. That form posts the admin's own account as
      `a` (`show.html:96`). `GetVendorZone` reports Pending with no claim.
      That can only happen if both layers read coverage from the zone's
      account.
    - The admin rejects the zone. The owner's zone page shows "Resubmit for
      production" and no open-source form (`need_subscription` is only set
      for New zones, `Vendor.pm:268-290`), and resubmitting returns the zone
      to Pending.

    (§5e vendor admin, §5b covered resubmit of a Rejected zone)

## Documentation

### `MANUAL_TEST_PLAN.md`

- Add spec and test references to every row listed above, and update the §5
  intro, which says §5a, §5c, §5d and §5e aren't covered, to say what
  `vendor.spec.ts` and `vendor-coverage.spec.ts` cover.
- §5: the plan row says the plan page is blank until a product is chosen, and
  that the subscription shows on `/manage/vendor`.
- §5b: remove the "known gap" paragraph. The covered row says the claim is
  false and the grant undecided after a covered submit. Add a note that a
  covered submit clears a stored justification, as current behavior still to
  be decided.
- §5e: tick "uncovered with a claim" with a reference to "open-source submit
  retains justification and edits without error". The intro adds that E2E
  checks both the Perl and the Go gate. The over-limit row names test 9
  (device limit) and test 10 (zone limit), and is ticked only when both pass.
- §5c admin failure and the §5d rows stay unchecked, with a line saying they
  need a failure-injection hook, which the fixtures CLI rule forbids.

### `e2e/README.md`

- Fixture section: the subscription seed, the `e2e_<attempt_id>` ID, and how
  cleanup finds and removes the row. Update "needs at least one server or
  monitor" (line 96) and have the manual cleanup script print
  `deleted_subscriptions`.
- Add `vendor-coverage` to the list of fixture specs (lines 74-77) and to the
  acceptance commands. Deploy the api-dev image with the seed before running
  `vendor-coverage.spec.ts`.
- Neither deletion task removes subscription rows, so don't combine the seed
  with account or user deletion flows.
- Coverage list: `vendor-coverage` (§5, §5b, §5e).

## Verification

- Go: `go tool sqlc generate` and `go generate ./ntpdb/`, then stage every
  generated file (`ntpdb/e2e_fixtures.sql.go`, `ntpdb/querier.go`,
  `ntpdb/otel.go`, `ntpdb/mocks.go`). `gofumpt -w` on changed files,
  `go test ./...`, `go test -tags e2efixtures ./cmd/`, and
  `./scripts/test-integration ./e2efixture`. `go test ./...` doesn't run
  the `e2efixture` integration tests: they have the `integration` build tag.
- Harness: `npm run typecheck`, `npm run test:unit` and
  `npx playwright test --list`.
- Deploy the API to devel: push to CI, bump the askntp tag, run
  `./update-api`. There's no Perl change, so no devspace restart.
- Run `tests/vendor.spec.ts` and `tests/vendor-coverage.spec.ts` with
  `--project=manage --retries=0` twice, then tick the rows that passed.
- The thousands separator in "Up to 10,000 client devices" comes from
  Template Toolkit's `Number.Format` plugin and wasn't checked outside devel.
  Confirm it on the first devel run.

## Out of scope

- Removing the zones tests create, and pruning devel's existing E2E zones.
- Tests that go through Stripe or stripe-gw. If they need cleanup for real
  `sub_` rows, a registry table comes back then.
- `CreateOrUpdateSubscription` accepting any account session with
  caller-supplied status and limits.
- Repopulating the entered `zone_name` after a duplicate-name create error
  (§5c).
- §5c admin approve/reject failure, and all of §5d.
- The vendor-facing wording of the whitespace justification error.
- Whether a covered submit should keep an earlier open-source justification.
- Perl reading `submit_state` (the §5e Phase 2).
