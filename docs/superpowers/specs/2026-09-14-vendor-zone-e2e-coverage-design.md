# Vendor zone E2E coverage and a subscription fixture seed

**Date:** 2026-09-14
**Status:** Design agreed in conversation on 2026-09-14 and checked against
the code by a review agent. No code written.
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
   status and limits its caller sends, which the Stripe work is likely to
   tighten.
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

## Findings that shaped the design (verified 2026-09-14)

### Coverage and the submit gates

- `AccountCoverage` (`server/api/subscription/coverage.go`) counts `active`,
  `trialing` and `incomplete` subscriptions as live. An account with a live
  subscription is over the limit when its Approved zone count reaches
  `max_zones`, or when its Approved device count plus the new zone's
  `device_count` exceeds `max_devices`. So a fresh account with
  `max_devices` 5000 and a 10,000-device zone is over the limit without any
  Approved zone.
- Perl's gate in `render_submit` (`Vendor.pm`) matches Go's: a live
  subscription within limits, or an open-source claim with a justification.
  Perl refuses before calling the API, so the Go message "a subscription is
  required, or apply as open source" (`server/api/vendorzone/submit.go`)
  never reaches the browser. Checking the API gate takes a direct
  `SubmitVendorZone` call.
- An uncovered refusal renders `missing_plan` ("Please choose a subscription
  plan or choose open source below") at the top of `products.html`, whether or
  not stripe-gw returned products. An over-limit account gets `need_upgrade`
  instead ("The current subscription plan doesn't support adding the new DNS
  zone", `show.html`), with no submit control and no form carrying
  `auth_token`.
- The Go gate reads the zone's account and has no admin bypass. `IsStaff()`
  includes vendor-zone staff (`ntpdb/user.go:8-10`), so the session middleware
  resolves another account's token for a vendor admin.

### Claim and grant

- The UI never shows `opensource_approved`. `GetVendorZone` returns it (an
  optional field: absent means undecided) and needs only a logged-in user;
  `X-Account` is optional there. The API's JSON uses proto field names and
  emits default values (`server/base/connect_options.go`), so
  `opensource_requested: false` is present in responses.
- Reject always sends `opensource_approved=false` (`render_admin`). A resubmit
  resets it to NULL and clears `rejection_reason` (`SubmitVendorZone` in
  `sql/vendor_zones.sql`). The Grant checkbox on the admin form is pre-checked
  when the zone carries a claim (`show.html`).
- A covered plain submit sends `opensource_requested=false` and
  `opensource_info=""` (`render_submit`). A Rejected open-source zone whose
  vendor later resubmits with a subscription therefore loses its claim and its
  stored justification. Nobody has decided whether that's intended, so the
  tests don't pin `opensource_info` there.
- A whitespace-only justification reaches the API:
  `Combust::Request::Plack::req_param` doesn't trim, and Perl's check is a
  truthiness test. Go's `validateOpensourceInfo` rejects it with
  "opensource_info must contain non-whitespace characters", and
  `render_submit` shows that with a Trace ID. The "known gap" note in §5b is
  out of date.

### Editing

- `UpdateVendorZone` (`update.go`) only restricts Approved zones: non-admins
  can't edit them, and nobody can change their `zone_name` ("zone name cannot
  be changed after approval"). Owners can edit New, Pending and Rejected
  zones. `server/api/vendorzone/CLAUDE.md` still says updates are allowed only
  while a zone is New.
- On an edit error, `render_edit` re-renders the form with the alert instead
  of redirecting.

### Pages

- `/manage/vendor/plan` without a `product_id` renders `subscription.html`,
  whose whole body sits inside `IF pr`, so the page is blank. The visible
  subscription effects are on `/manage/vendor`: a Pending zone reads
  "Processing", and `billing.html` renders "Current plan" with "Up to N DNS
  zones" and "Up to N client devices".
- `submitted.html` shows the "You'll get an email shortly with a ticket
  number" paragraph only when the vendor isn't covered.

### Subscription rows

- `account_subscriptions.stripe_subscription_id` has a unique index
  (`schema.sql`). The `account_id` foreign key to `accounts` doesn't cascade,
  and the account-deletion task doesn't remove subscription rows, so an
  account can't be deleted while a seeded row exists.
- Nothing else moves a seeded row. The webhook and checkout paths match on
  `stripe_subscription_id` and never change `account_id`. Stripe's IDs start
  with `sub_`, so an `e2e_` ID can't collide with one.
- The fixture CLI rejects unknown JSON fields (`cmd/e2e.go:111`). A harness
  that always sent a `subscription` key would break every fixture spec against
  an api-dev image from before this change.

### Devel side effects (not addressed here)

- Tests never remove the zones they create. `GetDnsZoneData` publishes
  Approved zones (`ListActiveVendorZonesByDnsRoot`), and the admin block
  approves five per run today (six after this change). Pending zones pile up
  in the admin list, which has no limit.
- Vendor emails aren't sent in devel mode (`NP/Email.pm`).

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
  subscription".
- Go types: `SubscriptionFixtureSpec` with `MaxZones int64
  json:"max_zones"` and `MaxDevices int64 json:"max_devices"`, and
  `CreateFixtureRequest.Subscription *SubscriptionFixtureSpec
  json:"subscription"`.

### Create

In the existing create transaction, after the account exists, insert one
`account_subscriptions` row (new query `InsertE2EFixtureSubscription` in
`sql/e2e_fixtures.sql`):

| Column | Value |
| --- | --- |
| `account_id` | the fixture account |
| `stripe_subscription_id` | `e2e_<attempt_id>` |
| `status` | `active` |
| `name` | `E2E fixture` |
| `max_zones`, `max_devices` | from the request |
| `created_on` | now |
| `ended_on` | NULL |

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

`subscription` is `null` when none was requested. The ID is a string, like the
other IDs in the response.

### Cleanup

Inside the existing attempt lock and transaction, next to the server and
monitor ownership checks:

1. `LockE2EFixtureSubscription` selects the row whose `stripe_subscription_id`
   is `e2e_<attempt_id>`, `FOR UPDATE`.
2. If that row belongs to another account, return `ErrOwnershipChanged`. Its
   message names subscriptions along with servers and monitors.
3. `DeleteE2EFixtureSubscription` (`:execrows`) deletes by that stripe ID and
   the fixture account. The deleted count must equal the locked count.

The response gains `deleted_subscriptions`: 0 or 1, and 0 on a repeat cleanup
or for an attempt without a seed. Cleanup never deletes by account alone.
Users, accounts and tombstones behave as they do today.

### Tests

`e2efixture` integration tests:

- a subscription-only attempt creates the row, and cleanup removes it
- a subscription plus a server
- validation: a missing or zero `max_zones` or `max_devices`, and an attempt
  with no server, monitor or subscription
- a repeat cleanup returns 0
- cleanup refuses when the row has moved to another account, and leaves the
  attempt uncleaned

### Doc fix

`server/api/vendorzone/CLAUDE.md`: replace "Updates allowed ONLY when
status=New" and "Once submitted (Pending), users cannot edit" with the rule
`update.go` enforces.

## Harness

### `lib/fixtures.ts`

- `SubscriptionSeed { maxZones: number; maxDevices: number }` and an optional
  `FixtureSeed.subscription`. Normalization rejects limits that aren't
  integers of at least 1 before calling the CLI.
- Send the `subscription` key only when the seed has one, so specs without a
  seed keep working against an older api-dev image.
- Parse `subscription`: when seeded, check status `active`, the stripe ID
  `e2e_<attemptId>` and the requested limits; when not seeded, accept an
  absent or `null` value only.
- Cleanup requires `deleted_subscriptions` only for attempts that seeded a
  subscription. The cleanup attachment and failure diagnostics include the
  subscription ID.

### `lib/auth.ts`

`RpcError` gains `connectMessage`: the Connect error JSON's `message` when it
is a string. It stays out of the thrown error's text, so it only appears in a
report when a test asserts on it.

### `lib/vendor.ts` (new)

Moved from `tests/vendor.spec.ts`: `NewZoneData`, `freshZoneData`,
`createNewZone`, `loginAsVendorAdmin` (which now also returns the session
token), `isVendorAdmin`, `createAndSubmitPendingZone` and `adminOpenZone`.

New:

- `getVendorZone(sessionToken, idToken)` calls
  `ntppool.vendorzone.v1.VendorZoneService/GetVendorZone` and returns
  `status`, `zone_name`, `device_count`, `opensource_requested`,
  `opensource_info` (optional) and `opensource_approved` (optional; absent or
  `null` means undecided), after checking their types.
- `submitVendorZoneApi(sessionToken, accountToken, idToken)` calls
  `SubmitVendorZone` with `X-Account` and no content, because the gate reads
  the stored claim.
- `approveZone(page, idToken, { grant })` and `rejectZone(page, idToken)` act
  on the admin zone page.
- `editZone(page, idToken, fields)` opens the edit form, changes the given
  fields, saves and waits for the show page.

## Tests

`MANUAL_TEST_PLAN.md` marks new and changed tests "implemented;
live-unverified" until they pass on devel.

### `tests/vendor.spec.ts`, regular user

1. **every writable field saves on a New zone** (new). Change `zone_name`,
   `request_information`, `device_count` and `device_information`, then check
   the show page and the reopened form. `organization_name` already has a
   test, and only vendor admins can set `contact_information`. (§5a New)
2. **every writable field saves on a Pending zone** (new). The same after an
   open-source submit. (§5a Pending)
3. **a whitespace-only justification is refused by the API and the zone stays
   New** (new). The alert shows "opensource_info must contain non-whitespace
   characters" with a Trace ID, and the list still shows New. (§5b)

### `tests/vendor.spec.ts`, admin block

4. **an uncovered plain submit is refused by the site and by the API** (new),
   all on one uncovered zone:
   - Remove the hidden `opensource_request` input in the browser, fill in a
     justification and submit. "Please choose a subscription plan or choose
     open source below" renders, and the zone stays New.
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
   with a Trace ID. `GetVendorZone` still returns the old name. (§5a staff,
   Approved)
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

Uses the `fixtures` test and installs the fixture's session for the owner.
`test.use({ trace: "off" })`, because traces would hold session cookies. The
`vendor.spec.ts` preflight doesn't run for this file, so the admin steps in
test 10 fail, rather than skip, when the minted session can't reach
`/manage/vendor/admin`.

8. **a covered vendor gets a plain submit and stays off the open-source path**.
   Seed 1 zone and 10,000 devices; the zone has 5,000 devices.
   - The show page has "Submit for production", no `opensource_info` textarea
     and no `opensource_request` input.
   - After submitting, the page names the zone and has no ticket-number
     paragraph.
   - `/manage/vendor` shows "Processing" and "Current plan" with "Up to 1 DNS
     zones" and "Up to 10,000 client devices".
   - `/manage/vendor/plan` loads cleanly.
   - The zone page has no "Open Source information".
   - `GetVendorZone` reports Pending, `opensource_requested` false and an
     undecided grant.

   (§5 subscription row, §5b covered rows, §5e covered)
9. **a covered vendor over the device limit is refused by the site and by the
   API**. Seed 1 zone and 5,000 devices; the zone has 10,000 devices.
   - The show page shows the upgrade message, with no submit button and no
     open-source form.
   - A POST to `/manage/vendor/submit`, with `auth_token` and `a` taken from
     the edit form, shows the upgrade message again.
   - `SubmitVendorZone` as the owner fails with `failed_precondition` and "a
     subscription is required, or apply as open source".
   - `GetVendorZone` still reports New.

   (§5e over-limit)
10. **a vendor admin submits for a covered account, and the owner resubmits
    after a rejection**. Seed 1 zone and 10,000 devices.
    - The owner creates a zone. A vendor admin, whose own account has no
      subscription, opens it at `/manage/vendor/zone?id=`, sees "Submit for
      production" and submits. `GetVendorZone` reports Pending with no claim.
      That can only happen if coverage is read from the zone's account.
    - The admin rejects the zone. The owner's zone page shows "Resubmit for
      production" and no open-source form, and resubmitting returns the zone
      to Pending.

    (§5e vendor admin, §5b covered resubmit of a Rejected zone)

## Documentation

### `MANUAL_TEST_PLAN.md`

- Add spec and test references to every row listed above, and update the §5
  intro to say what `vendor.spec.ts` and `vendor-coverage.spec.ts` cover.
- §5: the plan row says the plan page is blank until a product is chosen, and
  that the subscription shows on `/manage/vendor`.
- §5b: remove the "known gap" paragraph. The covered row says the claim is
  false and the grant undecided after a covered submit. Add a note that a
  covered submit clears a stored justification, as current behavior still to
  be decided.
- §5e: tick "uncovered with a claim" with a reference to "open-source submit
  retains justification and edits without error". The intro adds that E2E
  checks both the Perl and the Go gate.
- §5c admin failure and the §5d rows stay unchecked, with a line saying they
  need a failure-injection hook, which the fixtures CLI rule forbids.

### `e2e/README.md`

- Fixture section: the subscription seed, the `e2e_<attempt_id>` ID, and how
  cleanup finds and removes the row.
- Deploy the api-dev image with the seed before running
  `vendor-coverage.spec.ts`.
- An account with a seeded subscription can't be deleted before cleanup, so
  don't combine the seed with deletion flows.
- Coverage list: `vendor-coverage` (§5, §5b, §5e).

## Verification

- Go: `go tool sqlc generate` and stage every generated file, `gofumpt -w` on
  changed files, `go test ./...` including the `e2efixture` integration tests.
- Harness: `npm run typecheck`, `npm run test:unit` and
  `npx playwright test --list`.
- Deploy the API to devel: push to CI, bump the askntp tag, run
  `./update-api`. There's no Perl change, so no devspace restart.
- Run `tests/vendor.spec.ts` and `tests/vendor-coverage.spec.ts` with
  `--project=manage --retries=0` twice, then tick the rows that passed.

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
