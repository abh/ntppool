# Tiered Plan Device Limits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store a tiered subscription's device limit as what its quantity bought, check out for the devices the account needs, and let a vendor raise the quantity through Stripe's billing portal when a zone goes over the limit.

**Architecture:** stripe-gw gets one function that answers "what does quantity Q buy on price P"; the product list and the subscription sync both use it, and the sync sends the item's quantity and whether the price is tiered. The API stores both (migration 031), computes `required_devices` and an `upgrade` offer in `AccountCoverage`, and returns them from `GetAccountSubscriptionStatus`. Perl passes the API's numbers to checkout and to a new upgrade route, which asks stripe-gw for a `subscription_update_confirm` portal session; the return route asks stripe-gw to run the webhook's sync.

**Tech Stack:** Go 1.26/1.27 (Echo v4, stripe-go/v74 v74.30.0, pgx v5, sqlc, mockery, buf, testify, ConnectRPC), PostgreSQL, Perl (Template Toolkit, NP::CAPI), TypeScript + Playwright.

**Spec:** `/Users/ask/src/ntppool/docs/superpowers/specs/2026-09-16-tiered-plan-device-limits-design.md`. Read it first; this plan argues from it. The decisions in its "Decisions" section are settled.

---

## Resolved questions

Answered by the user on 2026-09-16; the tasks below carry the answers.

1. **A failed sync on `/manage/vendor/plan/upgraded` (Task 13).** Handle it as `_update_subscription` handles a failed `complete_checkout` (`Vendor.pm:571`): warn with the error and stripe-gw's request id, and return an error response. The message tells the vendor the payment went through and the plan will update shortly. The webhook still corrects the row later.
2. **Who can upgrade (Task 13, Task 15).** Anyone with `can_edit` on `current_account`, staff included. `ValidateSession` lets staff switch into any account with `a=`, and `manage_url` carries `a=`, so `current_account` is normally the zone's account. Both sides also check that it is: the zone page shows the upgrade button only when the status has an `upgrade` block **and** the zone's `account_token` equals `current_account->{id_token}` (otherwise the email text), and `/manage/vendor/plan/upgrade` returns FORBIDDEN when they differ. The Stripe customer id comes from `current_account`. No API change.
3. **An upgrade that isn't an increase (Task 3).** The API requires an increase too: coverage sets `upgrade` only when `required_devices` is greater than the row's stored `quantity`, on top of the other conditions. A quantity bought above the table's top (stored quantity 1,200,000, `max_devices` 1,000,000) with 1,100,000 required devices is `OVER_LIMIT` with no upgrade. stripe-gw keeps its own "must be an increase" refusal (Task 10).

## Notes on the spec

Found while reading the code. None of them changes a decision.

1. **stripe-gw's `go.mod` no longer has a `replace`.** `main` (`d890222`, pushed) requires `go.ntppool.org/api v0.5.4-0.20260916084511-0cdd72220015`, which is api `0cdd722`, also pushed. Task 6 adds `replace go.ntppool.org/api => ../api` for the new proto fields; Task 8 removes it after the api push. CI fails while it is there.
2. **Nullable `bigint` and `boolean` columns come out as `pgtype.Int8` and `pgtype.Bool`.** `sqlc.yaml` has a `gonull.Nullable[uint64]` override for nullable `bigint`, but it doesn't apply in practice: existing nullable `bigint` columns such as `account_id` and `user_id` are `pgtype.Int8` in `ntpdb/models.go`. Task 2 checks the generated types before writing code against them.
3. **The select queries must list the new columns** or sqlc stops returning `ntpdb.AccountSubscription` from them and generates per-query row types instead. `GetAccountSubscriptions`, `GetAccountSubscriptionByStripeID` and `GetLiveSubscriptionsForAccount` list columns explicitly; Task 2 appends `quantity, tiered` in table order.
4. **The coverage state matrix is tested with the querier mock**, the pattern `coverage_test.go` already uses, and one integration test goes through `GetAccountSubscriptionStatus` against the database to prove the columns are read and mapped. The spec files all of it under "integration".
5. **Vault field name.** The spec names the Vault path and the environment variable but not the field. The plan uses `upgrade_portal_configuration` in `kv/ntppool/{devel,prod}/stripe`, next to `secret_key` and `webhook_secret`.
6. **`askntp/stripe-gw/` in flux-ntp is untracked** (a hand-run Helm release, per `flux-ntp/docs/plans/stripe-gw-postgres-edition.md`). The devel config edit in Task 11 has nothing to commit. Production's config is `ntppool/stripe-gw/config-stripe-gw-local.yaml`, which is tracked.
7. **stripe-gw's refusal codes.** `upgrade_session` answers a refusal with 409 and bad input with 400; `sync` answers a customer mismatch with 403. Perl treats every non-200 the same way, so the codes are for logs.
8. **The resync counts a customer no account owns as expected**, not as a failure: the sandbox holds subscriptions of E2E accounts that have since been deleted. It exits non-zero on any other refusal or error.
9. **The E2E upgrade scenario doesn't depend on Production's `max_zones`.** The first zone stays Pending after checkout, and only Approved zones count, so the second zone's overage is a device overage whatever `max_zones` is.
10. **`render_subscription` gets a plan guard.** It already read `$plan->{TiersMode}` without checking that the price belongs to the product; the tiered branch now depends on it, so an unknown price returns an error.

## Global Constraints

Every task's requirements include this section.

**Prices** (from the spec; sandbox / live):

| Plan | Mode | Price IDs |
| --- | --- | --- |
| Production (Annual) | volume, flat amount per tier, no unit price | `price_1K2Yr92ZWuSKvxWM558s0yM4` / `price_1MmrNQ2ZWuSKvxWMlxRDkkti` |
| Production (Quarterly) | volume, same | `price_1MgPVr2ZWuSKvxWMPE796sD1` / `price_1MmrNQ2ZWuSKvxWMMT2PpsXD` |
| Enterprise | graduated, flat amount plus unit price per tier | `price_1MmQZP2ZWuSKvxWMo4I79PWE` / `price_1Mmskp2ZWuSKvxWMdwBJvKnd` |

Production's tiers top out at 5,000, 10,000, 25,000, 100,000 and 500,000, then an open-ended tier the table shows as 1,000,000. Enterprise's top out at 1M, 5M, 30M and 50M, then an open-ended tier shown as 100,000,000.

**What a quantity buys:** a tier without a unit price buys the tier's number in stripe-gw's table, including the open-ended tier's (twice the tier below). A tier with a unit price buys the quantity. The rule is per tier, not per tiers mode. A quantity above the table's top on a tier without a unit price gets the table's top. A tiered price with `quantity_scale` other than 1, or with `transform_quantity`, is refused. A tiered item with quantity below 1 is refused. Flat prices ignore the quantity and use `max_clients` metadata.

**Migration 031:** `account_subscriptions.quantity bigint` and `account_subscriptions.tiered boolean`, both nullable. NULL means not synced since this change.

**Proto:** `ProcessStripeWebhookRequest` gains `optional int64 quantity = 9` and `optional bool tiered = 10`; when any of `name`, `max_zones`, `max_devices` is set, both must be set or the API refuses with `InvalidArgument`. `GetAccountSubscriptionStatusResponse` gains `int64 required_devices = 9` and `optional SubscriptionUpgrade upgrade = 10`, with `message SubscriptionUpgrade { string stripe_subscription_id = 1; int64 quantity = 2; }`.

**`required_devices`:** approved devices on the account plus the requested `device_count`, in every state. **`upgrade`:** set only when the state is `OVER_LIMIT` because of devices (the zone count fits), the account has exactly one live subscription, that row has `tiered = true` and a non-NULL `quantity`, and `required_devices` is greater than that stored `quantity`; its `quantity` is `required_devices`.

**stripe-gw endpoints (form-encoded POST):**
- `POST /api/v1/subscription/upgrade_session`: `customer_id`, `subscription_id`, `quantity`, `return_url`, `cancel_url`. Answers `{"url": "..."}`. Refuses unless the subscription's customer is `customer_id`, its status is `active` or `trialing`, it has exactly one item on a tiered price, `quantity` is higher than the item's quantity, and the price's table covers `quantity`. The portal session uses configuration `STRIPE_UPGRADE_PORTAL_CONFIGURATION`, flow type `subscription_update_confirm` with the item id and new quantity, `after_completion` type `redirect` to `return_url`, and session `return_url` set to `cancel_url`.
- `POST /api/v1/subscription/sync`: `subscription_id`, `customer_id`. Refuses a subscription the customer doesn't own, then runs the webhook's sync. Answers the same JSON as `checkout/complete`.
- `stripe-gw resync`: a command-line mode that syncs every subscription in Stripe and exits.

**Environment:** stripe-gw refuses to start without `STRIPE_UPGRADE_PORTAL_CONFIGURATION`, like `STRIPE_WEBHOOK_SECRET`. Its value comes from Vault `kv/ntppool/{devel,prod}/stripe`, field `upgrade_portal_configuration`.

**Upgrade portal configuration (sandbox and live):** `subscription_update` enabled, `default_allowed_updates: [quantity]`, the Production and Enterprise prices listed, `proration_behavior: always_invoice`, every other feature off. The default configuration must not allow quantity changes.

**Perl routes:** `POST /manage/vendor/plan/upgrade` (`can_edit` on `current_account`, CSRF `auth_token`, form field `id` only; FORBIDDEN when the zone's `account_token` isn't `current_account->{id_token}`) and `GET /manage/vendor/plan/upgraded` (`id`, `subscription_id`). Staff with `can_edit` on the switched-into account may upgrade like a member. The Stripe customer id comes from `current_account`. The quantity never comes from a form field; Perl never calculates limits or quantities.

**Zone page copy (over the limit, with an `upgrade` block and the zone's account as the current account):** `Your plan covers {max_devices} devices; this zone brings the account to {required_devices}.` and a POST button `Update plan to {quantity} devices →`. Without a block, when the zone's account isn't the current account, or after a refusal, today's text: `The current subscription plan doesn't support adding the new DNS zone.` with the email link.

**Upgrade return failure:** when stripe-gw's sync fails, `/manage/vendor/plan/upgraded` warns with the error (which carries stripe-gw's request id) and returns `500` with `Your payment went through. Your plan will update shortly.`, as `_update_subscription` does for a failed checkout.

**Commands and rules:**
- Go: `gofumpt -w` on every modified `.go` file; `go test ./...` in the repo before each commit.
- API integration tests: `./scripts/test-integration [package] [pattern]` from `/Users/ask/src/go/ntp/api`. Never set `TEST_DATABASE_URL` or any other env var inline.
- If native Go fails at `runtime/cgo` with the Xcode license error, stop and ask the user to run `sudo xcodebuild -license`; `make generate` can't run in the `golang:1.27.1` container (it needs `buf`). Unit tests and `go tool sqlc` can run there: `docker run --rm -v /Users/ask/src/go/ntp/api:/src -w /src -v ntp-api-gomod:/go/pkg/mod -v ntp-api-gobuild:/root/.cache/go-build golang:1.27.1 <command>`.
- Generators: `make generate` in the API repo runs sqlc, builds `protoc-gen-perl-capi`, runs `buf generate` and `go generate ./...`. `api/ntppool` is a symlink to `/Users/ask/src/ntppool`, so it also rewrites `lib/NP/CAPI/*.pm` there. After every run, `git status` in **both** repos and stage every generated file with its source change.
- Perl: `perltidy -b <files>` then `rm -f <files>.bak` (`.perltidyrc` has `-b`). Never tidy or edit `lib/NP/CAPI/*.pm`. No Perl unit tests: verify on `https://manage.askdev.grundclock.com/` with `?x=<random>` after the user restarts the dev site (stop and rerun `devspace dev`).
- Templates: no inline styles or scripts (CSP).
- Harness: from `/Users/ask/src/ntppool/e2e`, `npm run typecheck`; specs run with `npx playwright test <spec> --project manage`. Env vars go in `e2e/.env`, never inline.
- Git: never `git add -A`, `git add .`, `git commit -a` or `--no-verify`. Stage named paths. Run `git status` and `git diff --staged` before each commit and re-check `git status` right before committing; if the staged set isn't what you expect, stop and ask. `git diff --staged --check` must be clean (no trailing whitespace).
- Untracked or unrelated files to leave alone: API `plans/active/perl-model-migration-status.md` (modified) and the untracked files; stripe-gw `.claude/`, `TODO.md`, `docs/`, `plans/`, `forward`, `mon`, `run`, `run-resync`, `run-tiered-report`; the many untracked files in ntppool; flux-ntp's uncommitted `askntp/api/api-config-local.yaml` and `ntp-base/stripe-gw/networkpolicy.yaml`.
- Deploys: the api goes to devel by pushing `main`, setting the CI image tag in `~/src/flux-ntp/askntp/api/api-config-local.yaml` (`x-image-tag: &image-tag sha-<first 8 of the commit>`) and running `./update-api` there. stripe-gw goes by pushing `main`, setting `appVersion: sha-<first 8>` in `~/src/flux-ntp/askntp/stripe-gw/config-stripe-gw-local.yaml` and running `./update` there. Never push flux-ntp for askntp. Pushing is the maintainer's step.
- Prose (comments, commits, docs): Conventional Commits; don't use the words "comprehensive" or "business".

## Who does what

- **Executor**: the agent running this plan. Writes code, runs tests, commits locally.
- **Maintainer**: Ask. Pushes, deploys, runs anything against the dala cluster or production (agents' cluster reads are refused here), and restarts `devspace dev`.
- **User at Stripe**: steps needing the Stripe CLI (the session has expired: `stripe login` first), a browser on Stripe's hosted pages, or Vault writes.

A step marked **[maintainer]** or **[user]** is not the executor's; the executor hands over with the exact commands and waits.

## Task map

| Phase | Task | Repo | Owner |
| --- | --- | --- | --- |
| 1. Spike (gate) | 1. Sandbox spike | Stripe sandbox | user |
| 2. Spec sections 1 and 2 (ship together) | 2. The API stores what was bought | api, ntppool (generated) | executor |
| | 3. Coverage reports required devices and the upgrade | api | executor |
| | 4. E2E fixtures seed quantity and tiered | api | executor |
| | 5. What a quantity buys | stripe-gw | executor |
| | 6. The sync reports what the item bought | stripe-gw | executor |
| | 7. Resync mode | stripe-gw | executor |
| | 8. Deploy sections 1 and 2 to devel | api, stripe-gw | maintainer (executor: `go.mod`) |
| 3. Spec section 3 | 9. `POST /api/v1/subscription/sync` | stripe-gw | executor |
| | 10. `POST /api/v1/subscription/upgrade_session` | stripe-gw | executor |
| | 11. Deploy stripe-gw with the upgrade configuration | stripe-gw, Vault, flux-ntp | maintainer, user (executor: config edit) |
| | 12. Checkout buys the devices the account needs | ntppool | executor (maintainer: restart) |
| | 13. Upgrade offer, upgrade and return routes | ntppool | executor (maintainer: restart) |
| 4. Devel data and E2E | 14. Resync the sandbox subscriptions | devel | maintainer |
| | 15. Harness seeds tiered subscriptions; upgrade offer spec | ntppool `e2e/` | executor |
| | 16. Portal upgrade spec and the full run | ntppool `e2e/` | executor (maintainer: run) |
| 5. Production cutover | 17. Cutover steps | flux-ntp docs; production | executor (doc edit), maintainer (at cutover) |

Phase 1 gates everything after it. Tasks 2-7 are committed before Task 8 deploys them; Tasks 9-10 before Task 11; Task 11 before Tasks 12-13 are verified.

## File structure

**API** (`/Users/ask/src/go/ntp/api`):

| File | Change | Responsibility |
| --- | --- | --- |
| `db/migrations/031_account_subscriptions_quantity_tiered.sql` | Create | The two nullable columns |
| `sql/subscriptions.sql` | Modify | Select lists and upsert carry `quantity`, `tiered` |
| `sql/e2e_fixtures.sql` | Modify | Fixture insert takes and returns them |
| `proto/ntppool/subscription/v1/subscription.proto` | Modify | Request fields, `required_devices`, `SubscriptionUpgrade` |
| `server/api/subscription/subscription.go` | Modify | Webhook refusal and upsert; status response mapping |
| `server/api/subscription/coverage.go` | Modify | `RequiredDevices`, `Upgrade`, `upgradeFor` |
| `server/api/subscription/coverage_test.go` | Modify | State matrix |
| `server/api/subscription/subscription_integration_test.go` | Modify | Webhook and status integration tests |
| `server/api/subscription/write_freeze_integration_test.go` | Modify | Sends the new required fields |
| `e2efixture/fixture.go` | Modify | Spec, validation, insert, response |
| `e2efixture/fixture_integration_test.go`, `cmd/e2e_integration_test.go` | Modify | Fixture tests |
| Generated: `ntpdb/models.go`, `ntpdb/subscriptions.sql.go`, `ntpdb/e2e_fixtures.sql.go`, `gen/ntppool/subscription/v1/subscription.pb.go` (and any other file `make generate` touches) | Regenerate | |

**stripe-gw** (`/Users/ask/src/go/ntp/stripe-gw`, `package main`):

| File | Change | Responsibility |
| --- | --- | --- |
| `plan_limits.go` | Modify | `tierTop`, `tableTop`, `quantityTier`, `devicesForQuantity`, price validation, `limitsForItem` |
| `plan_limits_test.go` | Modify | Production- and Enterprise-shaped prices; quantity and validation tests |
| `api_products.go` | Modify | `getTiers` uses the shared tier lookup |
| `api_products_test.go` | Modify | Plan page numbers for the open-ended tier |
| `webhook.go` | Modify | `buildWebhookRequest` sends quantity and tiered; sync split into fetch and report |
| `webhook_test.go` | Modify | Request fields |
| `resync.go`, `resync_test.go` | Create | `stripe-gw resync` |
| `subscription_sync.go`, `subscription_sync_test.go` | Create | `POST /api/v1/subscription/sync`, `checkCustomer` |
| `checkout_complete.go` | Modify | Shares the response builder |
| `subscription_upgrade.go`, `subscription_upgrade_test.go` | Create | `POST /api/v1/subscription/upgrade_session` |
| `stripe-gw.go` | Modify | Env var, routes, resync mode |
| `go.mod`, `go.sum` | Modify | Temporary `replace`, then the pushed api |
| `README.md`, `CLAUDE.md` | Modify | Env var, endpoints, resync |

**ntppool** (`/Users/ask/src/ntppool`):

| File | Change | Responsibility |
| --- | --- | --- |
| `lib/NP/CAPI/Subscription.pm` | Regenerate | New fields |
| `lib/NP/Stripe.pm` | Modify | `upgrade_session`, `sync_subscription` |
| `lib/NTPPool/Control/Vendor.pm` | Modify | Checkout quantity, upgrade and return routes |
| `docs/manage/tpl/vendor/show.html` | Modify | Upgrade offer |
| `e2e/lib/fixtures.ts`, `e2e/lib/vendor.ts` | Modify | Tiered seeds; offer text helpers |
| `e2e/tests/vendor-coverage.spec.ts`, `e2e/tests/stripe-checkout.spec.ts` | Modify | Upgrade specs |
| `e2e/README.md`, `MANUAL_TEST_PLAN.md` | Modify | Seeds and coverage |

**flux-ntp** (`/Users/ask/src/flux-ntp`): `askntp/stripe-gw/config-stripe-gw-local.yaml` (untracked, Task 11) and `docs/plans/stripe-gw-postgres-edition.md` (Task 17, left uncommitted for the maintainer).

---
## Phase 1: Spike (sandbox)

### Task 1: Sandbox spike

The whole task is the user's (Stripe CLI and a browser). An executor may run the CLI commands once the user has logged in, but the browser confirmations and the Vault write are the user's. **Nothing after this task starts until all three checks pass.** If any fails, stop and revisit spec section 3 with the user.

**Files:** none.

**Interfaces:**
- Produces: the sandbox upgrade portal configuration id (`bpc_...`), used in Task 11; three recorded results.

- [ ] **Step 1 [user]: Log in and confirm the sandbox**

```sh
stripe login
stripe prices retrieve price_1K2Yr92ZWuSKvxWM558s0yM4 | jq '{id, livemode, tiers_mode, product}'
```

Expected: `"livemode": false`, `"tiers_mode": "volume"`. The account must be the "NTP Pool Project" sandbox (`acct_103Pmy2ZWuSKvxWM`).

- [ ] **Step 2: Create the upgrade configuration**

```sh
PRODUCTION_PRODUCT=$(stripe prices retrieve price_1K2Yr92ZWuSKvxWM558s0yM4 | jq -r .product)
stripe prices retrieve price_1MgPVr2ZWuSKvxWMPE796sD1 | jq -r .product   # must print the same id
ENTERPRISE_PRODUCT=$(stripe prices retrieve price_1MmQZP2ZWuSKvxWMo4I79PWE | jq -r .product)

stripe billing_portal configurations create \
  -d "features[subscription_update][enabled]=true" \
  -d "features[subscription_update][default_allowed_updates][0]=quantity" \
  -d "features[subscription_update][proration_behavior]=always_invoice" \
  -d "features[subscription_update][products][0][product]=$PRODUCTION_PRODUCT" \
  -d "features[subscription_update][products][0][prices][0]=price_1K2Yr92ZWuSKvxWM558s0yM4" \
  -d "features[subscription_update][products][0][prices][1]=price_1MgPVr2ZWuSKvxWMPE796sD1" \
  -d "features[subscription_update][products][1][product]=$ENTERPRISE_PRODUCT" \
  -d "features[subscription_update][products][1][prices][0]=price_1MmQZP2ZWuSKvxWMo4I79PWE" \
  -d "features[subscription_cancel][enabled]=false" \
  -d "features[payment_method_update][enabled]=false" \
  -d "features[invoice_history][enabled]=false" \
  -d "features[customer_update][enabled]=false" \
  | tee /dev/stderr | jq -r .id
```

Record the `bpc_...` id as `CONFIG`. If Stripe refuses the configuration without a privacy policy or terms of service URL, stop and ask the user which URLs to use; don't invent them.

- [ ] **Step 3: A test customer on Production at quantity 5,000**

```sh
CONFIG=bpc_...   # from step 2
CUSTOMER=$(stripe customers create -d email=email@example.com -d "description=tiered upgrade spike" | jq -r .id)
PM=$(stripe payment_methods attach pm_card_visa -d customer=$CUSTOMER | jq -r .id)
SUB=$(stripe subscriptions create -d customer=$CUSTOMER \
  -d "items[0][price]=price_1K2Yr92ZWuSKvxWM558s0yM4" -d "items[0][quantity]=5000" \
  -d default_payment_method=$PM | jq -r .id)
ITEM=$(stripe subscriptions retrieve $SUB | jq -r '.items.data[0].id')
echo $CUSTOMER $SUB $ITEM
```

- [ ] **Step 4 (check 1) [user]: A quantity-only confirm session works**

```sh
stripe billing_portal sessions create -d customer=$CUSTOMER -d configuration=$CONFIG \
  -d "flow_data[type]=subscription_update_confirm" \
  -d "flow_data[subscription_update_confirm][subscription]=$SUB" \
  -d "flow_data[subscription_update_confirm][items][0][id]=$ITEM" \
  -d "flow_data[subscription_update_confirm][items][0][quantity]=7000" \
  -d "flow_data[after_completion][type]=redirect" \
  -d "flow_data[after_completion][redirect][return_url]=https://example.com/upgraded" \
  -d "return_url=https://example.com/cancel" | jq -r .url
```

Open the URL. Expected: a confirmation page for quantity 7,000 with an amount due today. Confirm; the browser lands on `https://example.com/upgraded`. Then:

```sh
stripe subscriptions retrieve $SUB | jq '{status, quantity: .items.data[0].quantity}'
stripe invoices list -d subscription=$SUB -d limit=1 | jq '.data[0] | {billing_reason, status, amount_paid}'
```

Pass: quantity 7000, and the newest invoice is `subscription_update`, `paid`. Fail: the session call errors (for example, it wants a `price` on the item) or the quantity didn't change.

- [ ] **Step 5 (check 2) [user]: A failed payment leaves the quantity alone**

```sh
BAD=$(stripe payment_methods attach pm_card_chargeCustomerFail -d customer=$CUSTOMER | jq -r .id)
stripe subscriptions update $SUB -d default_payment_method=$BAD
```

Create a second session exactly as in step 4 but with `items[0][quantity]=12000`, open it and confirm. Expected: the portal reports that the payment failed. Then:

```sh
stripe subscriptions retrieve $SUB | jq '{status, quantity: .items.data[0].quantity, pending_update}'
```

Pass: quantity is still 7000 (a `pending_update` may be present). Fail: quantity is 12000, because the sync would then raise `max_devices` for an unpaid upgrade.

- [ ] **Step 6 (check 3): The default configuration doesn't allow quantity changes**

```sh
stripe billing_portal configurations list -d is_default=true | jq '.data[] | {id, is_default, subscription_update: .features.subscription_update}'
```

Pass: `subscription_update.enabled` is `false`, or `default_allowed_updates` doesn't contain `"quantity"`. Fail: it does. Don't change the default configuration yourself; report it.

- [ ] **Step 7: Clean up and report**

```sh
stripe subscriptions cancel $SUB
```

Keep the configuration. Tell the maintainer the `bpc_...` id and the three results. Continue to Phase 2 only when all three passed.

---

## Phase 2: Spec sections 1 and 2

### Task 2: The API stores what was bought

**Files:**
- Create: `/Users/ask/src/go/ntp/api/db/migrations/031_account_subscriptions_quantity_tiered.sql`
- Modify: `/Users/ask/src/go/ntp/api/sql/subscriptions.sql`
- Modify: `/Users/ask/src/go/ntp/api/proto/ntppool/subscription/v1/subscription.proto`
- Modify: `/Users/ask/src/go/ntp/api/server/api/subscription/subscription.go:161-214`
- Modify: `/Users/ask/src/go/ntp/api/server/api/subscription/subscription_integration_test.go`
- Modify: `/Users/ask/src/go/ntp/api/server/api/subscription/write_freeze_integration_test.go:52-68`
- Regenerate: `ntpdb/models.go`, `ntpdb/subscriptions.sql.go`, `gen/ntppool/subscription/v1/subscription.pb.go`, `/Users/ask/src/ntppool/lib/NP/CAPI/Subscription.pm`

**Interfaces:**
- Produces: `ntpdb.AccountSubscription.Quantity pgtype.Int8` and `.Tiered pgtype.Bool`; `ntpdb.UpsertAccountSubscriptionParams.Quantity`/`.Tiered` (same types); proto Go fields `ProcessStripeWebhookRequest.Quantity *int64`, `.Tiered *bool`, `GetAccountSubscriptionStatusResponse.RequiredDevices int64`, `.Upgrade *SubscriptionUpgrade`, `SubscriptionUpgrade{StripeSubscriptionId string; Quantity int64}`; Perl response keys `required_devices` and `upgrade => {stripe_subscription_id, quantity}`.

- [ ] **Step 1: Write the migration**

`db/migrations/031_account_subscriptions_quantity_tiered.sql`:

```sql
-- +goose Up
-- What a subscription item bought, as stripe-gw reports it: the item's
-- quantity and whether its price is tiered. NULL means the row hasn't been
-- synced since these columns were added; the cutover resync fills them.
ALTER TABLE account_subscriptions
    ADD COLUMN quantity bigint,
    ADD COLUMN tiered boolean;

-- +goose Down
ALTER TABLE account_subscriptions
    DROP COLUMN tiered,
    DROP COLUMN quantity;
```

- [ ] **Step 2: Carry the columns in the queries**

In `sql/subscriptions.sql`, append `quantity, tiered` to the column lists of `GetAccountSubscriptions`, `GetAccountSubscriptionByStripeID` and `GetLiveSubscriptionsForAccount`, after `modified_on` (table order keeps sqlc returning `AccountSubscription`). For example:

```sql
-- name: GetLiveSubscriptionsForAccount :many
SELECT id, account_id, stripe_subscription_id, status, name,
       max_zones, max_devices, created_on, ended_on, modified_on,
       quantity, tiered
FROM account_subscriptions
WHERE account_id = $1
  AND status IN ('active', 'trialing', 'incomplete');
```

Replace `UpsertAccountSubscription` with:

```sql
-- name: UpsertAccountSubscription :one
INSERT INTO account_subscriptions (
    account_id, stripe_subscription_id, status, name,
    max_zones, max_devices, quantity, tiered,
    created_on, ended_on, modified_on
)
VALUES (
    sqlc.arg(account_id),
    sqlc.arg(stripe_subscription_id),
    sqlc.arg(status)::account_subscriptions_status,
    sqlc.arg(name),
    sqlc.arg(max_zones),
    sqlc.arg(max_devices),
    sqlc.arg(quantity),
    sqlc.arg(tiered),
    sqlc.arg(created_on),
    sqlc.narg(ended_on),
    CURRENT_TIMESTAMP
)
ON CONFLICT (stripe_subscription_id)
DO UPDATE SET
    status = EXCLUDED.status,
    name = EXCLUDED.name,
    max_zones = EXCLUDED.max_zones,
    max_devices = EXCLUDED.max_devices,
    quantity = EXCLUDED.quantity,
    tiered = EXCLUDED.tiered,
    ended_on = EXCLUDED.ended_on,
    modified_on = CURRENT_TIMESTAMP
RETURNING *;
```

`UpdateAccountSubscriptionStatus` is unchanged: a status-only report leaves `quantity` and `tiered` alone.

- [ ] **Step 3: Add the proto fields**

In `proto/ntppool/subscription/v1/subscription.proto`, end `ProcessStripeWebhookRequest` with:

```proto
  optional int64 max_devices = 8;
  // quantity is the subscription item's quantity. It and tiered are
  // required whenever name, max_zones or max_devices is sent.
  optional int64 quantity = 9;
  // tiered is whether the item's price has tiers.
  optional bool tiered = 10;
}
```

Add after `enum SubmitState { ... }`:

```proto
// SubscriptionUpgrade is the quantity change on the account's one tiered
// subscription that covers the devices the request needs.
message SubscriptionUpgrade {
  string stripe_subscription_id = 1;
  // quantity is the new quantity: the response's required_devices.
  int64 quantity = 2;
}
```

End `GetAccountSubscriptionStatusResponse` with:

```proto
  SubmitState submit_state = 8;
  // required_devices is the approved devices on the account plus the
  // requested device_count: the number the device limit is checked against.
  // Set in every state.
  int64 required_devices = 9;
  // upgrade is set only when the account is over its device limit (its zone
  // count fits) on exactly one live subscription, and that subscription is
  // tiered with a known quantity.
  optional SubscriptionUpgrade upgrade = 10;
}
```

- [ ] **Step 4: Regenerate and reset the test database**

```sh
cd /Users/ask/src/go/ntp/api
make generate
make test-db-restart
git status --short
git -C /Users/ask/src/ntppool status --short lib/NP/CAPI
grep -n -A 14 "type AccountSubscription struct" ntpdb/models.go
```

Expected: `ntpdb/models.go` shows `Quantity pgtype.Int8` and `Tiered pgtype.Bool`; changed generated files are `ntpdb/models.go`, `ntpdb/subscriptions.sql.go` and `gen/ntppool/subscription/v1/subscription.pb.go` (others only if the generator touched them for this change); in ntppool only `lib/NP/CAPI/Subscription.pm` changed. If other `lib/NP/CAPI/*.pm` files changed, stop and ask: that is drift from another change. If the types aren't `pgtype.Int8`/`pgtype.Bool`, use the generated types in every later step and task.

- [ ] **Step 5: Write the failing integration tests**

In `server/api/subscription/subscription_integration_test.go`, add `"github.com/jackc/pgx/v5"` and `"github.com/jackc/pgx/v5/pgtype"` to the imports.

Every existing request that sends limits must now send `Quantity` and `Tiered`. In `TestProcessStripeWebhookUpserts`, the `req` closure becomes:

```go
	req := func(name string, maxZones int64) *connect.Request[subscriptionv1.ProcessStripeWebhookRequest] {
		maxDevices := int64(5000)
		quantity := int64(1)
		tiered := false
		return connect.NewRequest(&subscriptionv1.ProcessStripeWebhookRequest{
			StripeSubscriptionId: "sub_upsert_test",
			StripeCustomerId:     customerID,
			Status:               "active",
			CreatedOnUnix:        time.Now().Unix(),
			Name:                 &name,
			MaxZones:             &maxZones,
			MaxDevices:           &maxDevices,
			Quantity:             &quantity,
			Tiered:               &tiered,
		})
	}
```

In `TestProcessStripeWebhookStatusOnlyUpdatesExistingRow`, next to `maxDevices := int64(8000)` add `quantity := int64(1)` and `tiered := false`, and add `Quantity: &quantity,` and `Tiered: &tiered,` to the first (`active`) request. In `write_freeze_integration_test.go`, next to `maxDevices := int64(1)` add the same two variables and fields.

Append two tests:

```go
// stripe-gw reports what the item bought with the limits; a later
// status-only report leaves it alone.
func TestProcessStripeWebhookSavesQuantityAndTiered(t *testing.T) {
	ctx, api, customerID, cleanup := setupSubscriptionTest(t)
	defer cleanup()

	name := "Production"
	maxZones := int64(2)
	maxDevices := int64(10000)
	quantity := int64(7000)
	tiered := true
	created, err := api.ProcessStripeWebhook(ctx, connect.NewRequest(&subscriptionv1.ProcessStripeWebhookRequest{
		StripeSubscriptionId: "sub_quantity_test",
		StripeCustomerId:     customerID,
		Status:               "active",
		CreatedOnUnix:        time.Now().Unix(),
		Name:                 &name,
		MaxZones:             &maxZones,
		MaxDevices:           &maxDevices,
		Quantity:             &quantity,
		Tiered:               &tiered,
	}))
	require.NoError(t, err)
	require.True(t, created.Msg.Success)

	stripeID := pgtype.Text{String: "sub_quantity_test", Valid: true}
	row, err := api.Q().GetAccountSubscriptionByStripeID(ctx, stripeID)
	require.NoError(t, err)
	assert.Equal(t, pgtype.Int8{Int64: 7000, Valid: true}, row.Quantity)
	assert.Equal(t, pgtype.Bool{Bool: true, Valid: true}, row.Tiered)

	updated, err := api.ProcessStripeWebhook(ctx, connect.NewRequest(&subscriptionv1.ProcessStripeWebhookRequest{
		StripeSubscriptionId: "sub_quantity_test",
		StripeCustomerId:     customerID,
		Status:               "past_due",
		CreatedOnUnix:        time.Now().Unix(),
	}))
	require.NoError(t, err)
	require.True(t, updated.Msg.Success)

	row, err = api.Q().GetAccountSubscriptionByStripeID(ctx, stripeID)
	require.NoError(t, err)
	assert.Equal(t, "past_due", string(row.Status.AccountSubscriptionsStatus))
	assert.Equal(t, pgtype.Int8{Int64: 7000, Valid: true}, row.Quantity, "a status-only update keeps quantity")
	assert.Equal(t, pgtype.Bool{Bool: true, Valid: true}, row.Tiered, "a status-only update keeps tiered")
}

// Limits without quantity and tiered would store a row the coverage check
// can't offer an upgrade for, so the API refuses them.
func TestProcessStripeWebhookRequiresQuantityWithLimits(t *testing.T) {
	ctx, api, customerID, cleanup := setupSubscriptionTest(t)
	defer cleanup()

	name := "Production"
	maxZones := int64(2)
	maxDevices := int64(10000)
	quantity := int64(7000)
	tiered := true

	for _, tc := range []struct {
		name     string
		quantity *int64
		tiered   *bool
	}{
		{"without quantity", nil, &tiered},
		{"without tiered", &quantity, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := api.ProcessStripeWebhook(ctx, connect.NewRequest(&subscriptionv1.ProcessStripeWebhookRequest{
				StripeSubscriptionId: "sub_no_quantity_test",
				StripeCustomerId:     customerID,
				Status:               "active",
				CreatedOnUnix:        time.Now().Unix(),
				Name:                 &name,
				MaxZones:             &maxZones,
				MaxDevices:           &maxDevices,
				Quantity:             tc.quantity,
				Tiered:               tc.tiered,
			}))
			require.Error(t, err)
			assert.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err))

			_, err = api.Q().GetAccountSubscriptionByStripeID(ctx, pgtype.Text{String: "sub_no_quantity_test", Valid: true})
			assert.ErrorIs(t, err, pgx.ErrNoRows, "nothing was saved")
		})
	}
}
```

- [ ] **Step 6: Run the tests and watch them fail**

Run: `./scripts/test-integration ./server/api/subscription "TestProcessStripeWebhook"`
Expected: `TestProcessStripeWebhookSavesQuantityAndTiered` fails (quantity not saved, `Valid: false`); `TestProcessStripeWebhookRequiresQuantityWithLimits` fails (no error returned).

- [ ] **Step 7: Refuse limits without quantity and tiered, and save them**

In `server/api/subscription/subscription.go`, directly before `if msg.Name == nil || msg.MaxZones == nil || msg.MaxDevices == nil {`, add:

```go
	// What the item bought travels with the limits: the coverage check reads
	// quantity and tiered to offer an upgrade, so limits without them would
	// store a row that silently never gets one.
	if (msg.Name != nil || msg.MaxZones != nil || msg.MaxDevices != nil) &&
		(msg.Quantity == nil || msg.Tiered == nil) {
		return nil, connect.NewError(connect.CodeInvalidArgument,
			fmt.Errorf("quantity and tiered are required with name, max_zones or max_devices"))
	}
```

In the `UpsertAccountSubscription` call, after `MaxDevices: *msg.MaxDevices,` add:

```go
		Quantity:             pgtype.Int8{Int64: *msg.Quantity, Valid: true},
		Tiered:               pgtype.Bool{Bool: *msg.Tiered, Valid: true},
```

- [ ] **Step 8: Run the tests and watch them pass**

```sh
gofumpt -w server/api/subscription/subscription.go server/api/subscription/subscription_integration_test.go server/api/subscription/write_freeze_integration_test.go
go build ./... && go test ./...
./scripts/test-integration ./server/api/subscription
./scripts/test-integration ./db/migrations
./scripts/test-integration ./server/api/vendorzone "TestSubmitVendorZone_CoverageGate"
```

Expected: all pass.

- [ ] **Step 9: Commit the API**

```bash
cd /Users/ask/src/go/ntp/api
git status
git add db/migrations/031_account_subscriptions_quantity_tiered.sql sql/subscriptions.sql \
  proto/ntppool/subscription/v1/subscription.proto \
  server/api/subscription/subscription.go \
  server/api/subscription/subscription_integration_test.go \
  server/api/subscription/write_freeze_integration_test.go \
  ntpdb/models.go ntpdb/subscriptions.sql.go gen/ntppool/subscription/v1/subscription.pb.go
# plus any other file step 4 listed as regenerated for this change
git diff --staged --check
git diff --staged
git status
git commit -m "feat(subscription): store the quantity and tiered flag stripe-gw reports" \
  -m "Migration 031 adds nullable quantity and tiered columns to account_subscriptions. ProcessStripeWebhook saves them with the limits and refuses limits sent without them; a status-only report leaves them alone. GetAccountSubscriptionStatusResponse gains required_devices and upgrade, filled in by the next commit."
```

- [ ] **Step 10: Commit the generated Perl client**

```bash
cd /Users/ask/src/ntppool
git status --short lib/NP/CAPI
git add lib/NP/CAPI/Subscription.pm
git diff --staged --stat
git status
git commit -m "chore(capi): regenerate the subscription client" \
  -m "Picks up quantity and tiered on ProcessStripeWebhook, and required_devices and upgrade on GetAccountSubscriptionStatus."
```

### Task 3: Coverage reports required devices and the upgrade

**Files:**
- Modify: `/Users/ask/src/go/ntp/api/server/api/subscription/coverage.go`
- Modify: `/Users/ask/src/go/ntp/api/server/api/subscription/coverage_test.go`
- Modify: `/Users/ask/src/go/ntp/api/server/api/subscription/subscription.go:299-310` (`GetAccountSubscriptionStatus` response)
- Modify: `/Users/ask/src/go/ntp/api/server/api/subscription/subscription_integration_test.go`

**Interfaces:**
- Consumes: `ntpdb.AccountSubscription.Quantity`, `.Tiered`, proto `RequiredDevices`, `Upgrade`, `SubscriptionUpgrade` (Task 2).
- Produces: `subscription.Coverage.RequiredDevices int64`, `subscription.Coverage.Upgrade *subscription.Upgrade`, `type Upgrade struct { StripeSubscriptionID string; Quantity int64 }`. `vendorzone/submit.go` keeps calling `AccountCoverage` unchanged. Task 4's fixture test and Perl (Tasks 12-13) rely on these.

- [ ] **Step 1: Write the failing unit tests**

Replace `TestAccountCoverage` in `coverage_test.go` with:

```go
func TestAccountCoverage(t *testing.T) {
	const accountID = int64(42)

	// tiered is a synced row on a tiered price whose quantity bought 100
	// devices.
	tiered := func(stripeID string) ntpdb.AccountSubscription {
		return ntpdb.AccountSubscription{
			StripeSubscriptionID: pgtype.Text{String: stripeID, Valid: true},
			MaxZones:             5,
			MaxDevices:           100,
			Quantity:             pgtype.Int8{Int64: 100, Valid: true},
			Tiered:               pgtype.Bool{Bool: true, Valid: true},
		}
	}
	flat := ntpdb.AccountSubscription{
		StripeSubscriptionID: pgtype.Text{String: "sub_flat", Valid: true},
		MaxZones:             5,
		MaxDevices:           100,
		Quantity:             pgtype.Int8{Int64: 1, Valid: true},
		Tiered:               pgtype.Bool{Bool: false, Valid: true},
	}
	noQuantity := tiered("sub_no_quantity")
	noQuantity.Quantity = pgtype.Int8{}
	oneZone := tiered("sub_one_zone")
	oneZone.MaxZones = 1
	// Bought above the table's top on a tier without a unit price: the
	// stored limit is the table's top, below the quantity.
	aboveTop := tiered("sub_above_top")
	aboveTop.MaxDevices = 1000000
	aboveTop.Quantity = pgtype.Int8{Int64: 1200000, Valid: true}

	tests := []struct {
		name              string
		liveSubs          []ntpdb.AccountSubscription
		stats             ntpdb.GetApprovedZoneStatsRow
		additionalDevices int64
		wantState         SubmitState
		wantExceeded      bool
		wantProto         subscriptionv1.SubmitState
		wantRequired      int64
		wantUpgrade       *Upgrade
	}{
		{
			name:              "no live subscription is NeedsSubscription",
			liveSubs:          nil,
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 3000},
			additionalDevices: 5000,
			wantState:         NeedsSubscription,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_NEEDS_SUBSCRIPTION,
			wantRequired:      8000,
		},
		{
			name:              "live subscription within limits is Covered",
			liveSubs:          []ntpdb.AccountSubscription{{MaxZones: 5, MaxDevices: 100}},
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 10},
			additionalDevices: 5,
			wantState:         Covered,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_COVERED,
			wantRequired:      15,
		},
		{
			name:         "at or over zone limit is OverLimit",
			liveSubs:     []ntpdb.AccountSubscription{{MaxZones: 1, MaxDevices: 100}},
			stats:        ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 10},
			wantState:    OverLimit,
			wantExceeded: true,
			wantProto:    subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT,
			wantRequired: 10,
		},
		{
			name:              "additional devices push over device limit is OverLimit",
			liveSubs:          []ntpdb.AccountSubscription{{MaxZones: 5, MaxDevices: 100}},
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 98},
			additionalDevices: 5,
			wantState:         OverLimit,
			wantExceeded:      true,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT,
			wantRequired:      103,
		},
		{
			name:              "within limits on a tiered subscription offers no upgrade",
			liveSubs:          []ntpdb.AccountSubscription{tiered("sub_tiered")},
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 10},
			additionalDevices: 5,
			wantState:         Covered,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_COVERED,
			wantRequired:      15,
		},
		{
			name:              "device overage on one tiered subscription offers the required devices",
			liveSubs:          []ntpdb.AccountSubscription{tiered("sub_tiered")},
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 98},
			additionalDevices: 5,
			wantState:         OverLimit,
			wantExceeded:      true,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT,
			wantRequired:      103,
			wantUpgrade:       &Upgrade{StripeSubscriptionID: "sub_tiered", Quantity: 103},
		},
		{
			name:              "zone overage on a tiered subscription offers no upgrade",
			liveSubs:          []ntpdb.AccountSubscription{oneZone},
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 98},
			additionalDevices: 5,
			wantState:         OverLimit,
			wantExceeded:      true,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT,
			wantRequired:      103,
		},
		{
			name:              "device overage across two live subscriptions offers no upgrade",
			liveSubs:          []ntpdb.AccountSubscription{tiered("sub_a"), tiered("sub_b")},
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 198},
			additionalDevices: 5,
			wantState:         OverLimit,
			wantExceeded:      true,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT,
			wantRequired:      203,
		},
		{
			name:              "device overage on a flat subscription offers no upgrade",
			liveSubs:          []ntpdb.AccountSubscription{flat},
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 98},
			additionalDevices: 5,
			wantState:         OverLimit,
			wantExceeded:      true,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT,
			wantRequired:      103,
		},
		{
			name:              "device overage below the stored quantity offers no upgrade",
			liveSubs:          []ntpdb.AccountSubscription{aboveTop},
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 1000000},
			additionalDevices: 100000,
			wantState:         OverLimit,
			wantExceeded:      true,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT,
			wantRequired:      1100000,
		},
		{
			name:              "device overage on a row without a quantity offers no upgrade",
			liveSubs:          []ntpdb.AccountSubscription{noQuantity},
			stats:             ntpdb.GetApprovedZoneStatsRow{ZoneCount: 1, DeviceCount: 98},
			additionalDevices: 5,
			wantState:         OverLimit,
			wantExceeded:      true,
			wantProto:         subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT,
			wantRequired:      103,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			q := ntpdb.NewMockQuerier(t)
			q.EXPECT().GetLiveSubscriptionsForAccount(mock.Anything, accountID).Return(tt.liveSubs, nil)
			q.EXPECT().GetApprovedZoneStats(mock.Anything, pgtype.Int8{Int64: accountID, Valid: true}).Return(tt.stats, nil)

			cov, err := AccountCoverage(context.Background(), q, accountID, tt.additionalDevices)
			require.NoError(t, err)
			require.Equal(t, tt.wantState, cov.State)
			require.Equal(t, tt.wantExceeded, cov.LimitsExceeded)
			require.Equal(t, tt.wantProto, cov.State.Proto())
			require.Equal(t, tt.wantRequired, cov.RequiredDevices, "required devices")
			require.Equal(t, tt.wantUpgrade, cov.Upgrade, "upgrade")
		})
	}
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `go test ./server/api/subscription -run TestAccountCoverage`
Expected: compile failure, `cov.RequiredDevices undefined` and `undefined: Upgrade`.

- [ ] **Step 3: Implement the coverage fields**

In `coverage.go`, add to `Coverage` after `ExistingDevices int64`:

```go
	// RequiredDevices is ExistingDevices plus the devices being added: the
	// number the device limit is checked against. Set in every state.
	RequiredDevices int64
	// Upgrade is set only for a device overage that one quantity change on
	// the account's single tiered subscription can cover.
	Upgrade *Upgrade
```

Add after the `Coverage` type:

```go
// Upgrade is the quantity change that covers a device overage: the
// subscription to change and the quantity to buy, which is the account's
// RequiredDevices.
type Upgrade struct {
	StripeSubscriptionID string
	Quantity             int64
}
```

In `AccountCoverage`, after `cov.ExistingDevices = stats.DeviceCount`:

```go
	cov.RequiredDevices = stats.DeviceCount + additionalDevices
```

and replace the device branch:

```go
	} else if cov.RequiredDevices > cov.MaxDevices {
		cov.LimitsExceeded = true
		cov.LimitsError = fmt.Sprintf("device limit exceeded: have %d, adding %d, max %d",
			stats.DeviceCount, additionalDevices, cov.MaxDevices)
		cov.Upgrade = upgradeFor(liveSubs, cov.RequiredDevices)
	}
```

Add below `AccountCoverage`:

```go
// upgradeFor returns the quantity change that covers requiredDevices, or nil
// when this flow can't make one: several live subscriptions, a flat price, a
// row not yet synced with its quantity, or a quantity already at or above
// requiredDevices (bought above the table's top, where the stored limit is
// lower than the quantity). The zone count is the caller's check; a zone
// overage never gets here.
func upgradeFor(liveSubs []ntpdb.AccountSubscription, requiredDevices int64) *Upgrade {
	if len(liveSubs) != 1 {
		return nil
	}
	sub := liveSubs[0]
	if !sub.Tiered.Valid || !sub.Tiered.Bool || !sub.Quantity.Valid {
		return nil
	}
	if requiredDevices <= sub.Quantity.Int64 {
		return nil
	}
	if !sub.StripeSubscriptionID.Valid || sub.StripeSubscriptionID.String == "" {
		return nil
	}
	return &Upgrade{
		StripeSubscriptionID: sub.StripeSubscriptionID.String,
		Quantity:             requiredDevices,
	}
}
```

- [ ] **Step 4: Run the unit tests**

Run: `gofumpt -w server/api/subscription/coverage.go server/api/subscription/coverage_test.go && go test ./server/api/subscription -run TestAccountCoverage -v`
Expected: all eleven subtests pass.

- [ ] **Step 5: Write the failing integration test**

Append to `subscription_integration_test.go`:

```go
// The upgrade offer reaches the RPC response from real rows: quantity and
// tiered are read from the database and mapped to the proto.
func TestGetAccountSubscriptionStatusUpgrade(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set, skipping integration tests")
	}

	ctx := context.Background()

	db, err := pgxpool.New(ctx, dbURL)
	require.NoError(t, err)
	defer db.Close()

	subAPI, err := subscription.New(base.BaseAPI{DB: db, Env: depenv.DeployDevel})
	require.NoError(t, err)

	ids := testhelpers.GetSubscriptionTestIDs()
	defer testhelpers.CleanupIntegrationTestData(t, ctx, db, ids)

	accountID := int64(ids.AccountIDs[4])
	_, err = db.Exec(ctx, `
		INSERT INTO accounts (id, id_token, name, created_on, modified_on)
		VALUES ($1, $2, $3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name
	`, accountID, "test-sub-upgrade-token", "Test Upgrade")
	require.NoError(t, err)

	// Production-shaped: quantity 5000 bought the 5,000 tier.
	subID := ids.SubscriptionIDs[3]
	_, err = db.Exec(ctx, `
		INSERT INTO account_subscriptions (id, account_id, stripe_subscription_id, status, name,
			max_zones, max_devices, quantity, tiered, created_on, modified_on)
		VALUES ($1, $2, 'sub_upgrade_test', 'active', 'Production', 2, 5000, 5000, true,
			CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		ON CONFLICT (id) DO UPDATE SET max_devices = EXCLUDED.max_devices,
			quantity = EXCLUDED.quantity, tiered = EXCLUDED.tiered
	`, subID, accountID)
	require.NoError(t, err)

	ctx = sessions.SetTestAccountInContext(ctx, ntpdb.Account{ID: accountID})
	status := func(t *testing.T, devices int64) *subscriptionv1.GetAccountSubscriptionStatusResponse {
		t.Helper()
		resp, err := subAPI.GetAccountSubscriptionStatus(ctx, connect.NewRequest(
			&subscriptionv1.GetAccountSubscriptionStatusRequest{DeviceCount: &devices}))
		require.NoError(t, err)
		return resp.Msg
	}

	over := status(t, 7000)
	assert.Equal(t, subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT, over.SubmitState)
	assert.Equal(t, int64(7000), over.RequiredDevices)
	require.NotNil(t, over.Upgrade, "a device overage on one tiered subscription is offered an upgrade")
	assert.Equal(t, "sub_upgrade_test", over.Upgrade.StripeSubscriptionId)
	assert.Equal(t, int64(7000), over.Upgrade.Quantity)

	within := status(t, 4000)
	assert.Equal(t, subscriptionv1.SubmitState_SUBMIT_STATE_COVERED, within.SubmitState)
	assert.Equal(t, int64(4000), within.RequiredDevices)
	assert.Nil(t, within.Upgrade)

	// A row not resynced since migration 031 has no quantity to raise.
	_, err = db.Exec(ctx, `UPDATE account_subscriptions SET quantity = NULL WHERE id = $1`, subID)
	require.NoError(t, err)
	notSynced := status(t, 7000)
	assert.Equal(t, subscriptionv1.SubmitState_SUBMIT_STATE_OVER_LIMIT, notSynced.SubmitState)
	assert.Equal(t, int64(7000), notSynced.RequiredDevices)
	assert.Nil(t, notSynced.Upgrade)
}
```

- [ ] **Step 6: Run it and watch it fail**

Run: `./scripts/test-integration ./server/api/subscription "TestGetAccountSubscriptionStatusUpgrade"`
Expected: FAIL, `RequiredDevices` is 0 and `Upgrade` is nil.

- [ ] **Step 7: Map the fields in the response**

In `GetAccountSubscriptionStatus`, add `RequiredDevices: cov.RequiredDevices,` to the response literal, and before `return connect.NewResponse(response), nil`:

```go
	if cov.Upgrade != nil {
		response.Upgrade = &subscriptionv1.SubscriptionUpgrade{
			StripeSubscriptionId: cov.Upgrade.StripeSubscriptionID,
			Quantity:             cov.Upgrade.Quantity,
		}
	}
```

- [ ] **Step 8: Run everything**

```sh
gofumpt -w server/api/subscription/subscription.go server/api/subscription/subscription_integration_test.go
go test ./...
./scripts/test-integration ./server/api/subscription
./scripts/test-integration ./server/api/vendorzone
./scripts/test-integration ./server/api/account
```

Expected: all pass.

- [ ] **Step 9: Commit**

```bash
cd /Users/ask/src/go/ntp/api
git status
git add server/api/subscription/coverage.go server/api/subscription/coverage_test.go \
  server/api/subscription/subscription.go server/api/subscription/subscription_integration_test.go
git diff --staged --check
git diff --staged
git status
git commit -m "feat(subscription): report required devices and the upgrade offer" \
  -m "AccountCoverage returns required_devices in every state, and an upgrade to that quantity only for a device overage on the account's one live tiered subscription with a known quantity lower than the devices required. GetAccountSubscriptionStatus returns both."
```

### Task 4: E2E fixtures seed quantity and tiered

**Files:**
- Modify: `/Users/ask/src/go/ntp/api/sql/e2e_fixtures.sql:109-115`
- Modify: `/Users/ask/src/go/ntp/api/e2efixture/fixture.go` (`SubscriptionFixtureSpec`, `FixtureSubscription`, `validateFixtureRequest`, the insert in `CreateFixture`)
- Modify: `/Users/ask/src/go/ntp/api/e2efixture/fixture_integration_test.go`
- Modify: `/Users/ask/src/go/ntp/api/cmd/e2e_integration_test.go`
- Regenerate: `ntpdb/e2e_fixtures.sql.go`

**Interfaces:**
- Consumes: `subscription.AccountCoverage`, `subscription.Upgrade` (Task 3).
- Produces: `api e2e fixture create` accepts `"subscription": {"max_zones", "max_devices", "quantity", "tiered"}` where `quantity` (integer ≥ 1) and `tiered` (bool) are optional and sent together; the response's `subscription` carries `"quantity"` and `"tiered"`, `null` when unset. Task 15's harness relies on this JSON.

- [ ] **Step 1: Write the failing tests**

In `fixture_integration_test.go`, add three entries to the `validation before mutation` list, after the `MaxZones: 1, MaxDevices: -1` entry:

```go
			{RunID: testRunID, AttemptID: attempt(t), Subscription: &subscriptionSpec{MaxZones: 1, MaxDevices: 5000, Quantity: new(int64(5000))}},                  // Quantity without tiered.
			{RunID: testRunID, AttemptID: attempt(t), Subscription: &subscriptionSpec{MaxZones: 1, MaxDevices: 5000, Tiered: new(true)}},                         // Tiered without quantity.
			{RunID: testRunID, AttemptID: attempt(t), Subscription: &subscriptionSpec{MaxZones: 1, MaxDevices: 5000, Quantity: new(int64(0)), Tiered: new(true)}}, // Quantity below 1.
```

In the `subscription only attempt` subtest, after `require.EqualValues(t, 10000, sub.MaxDevices)`:

```go
		require.Nil(t, sub.Quantity, "an untiered seed leaves quantity NULL")
		require.Nil(t, sub.Tiered, "an untiered seed leaves tiered NULL")
```

Add a subtest after `subscription only attempt`:

```go
	t.Run("tiered subscription attempt", func(t *testing.T) {
		id := attempt(t)
		fixture := createRequest(t, e2efixture.CreateFixtureRequest{
			RunID:     testRunID,
			AttemptID: id,
			Subscription: &subscriptionSpec{
				MaxZones: 1, MaxDevices: 5000, Quantity: new(int64(5000)), Tiered: new(true),
			},
		})

		sub := fixture.Subscription
		require.NotNil(t, sub)
		require.NotNil(t, sub.Quantity)
		require.EqualValues(t, 5000, *sub.Quantity)
		require.NotNil(t, sub.Tiered)
		require.True(t, *sub.Tiered)
		require.Equal(t, 1, count(t, `SELECT count(*) FROM account_subscriptions
			WHERE id=$1 AND quantity=5000 AND tiered`, sub.SubscriptionID))

		// The seed is only useful if coverage offers an upgrade for it.
		over, err := subscription.AccountCoverage(ctx, q, fixture.AccountID, 10000)
		require.NoError(t, err)
		require.Equal(t, subscription.OverLimit, over.State)
		require.Equal(t, &subscription.Upgrade{StripeSubscriptionID: "e2e_" + id, Quantity: 10000}, over.Upgrade)

		cleaned, err := e2efixture.CleanupFixture(ctx, q, e2efixture.CleanupFixtureRequest{AttemptID: id})
		require.NoError(t, err)
		require.EqualValues(t, 1, cleaned.DeletedSubscriptions)
	})
```

In `cmd/e2e_integration_test.go`, `fixture create and cleanup` subtest: add to the anonymous `Subscription` struct

```go
				Quantity             *int   `json:"quantity"`
				Tiered               *bool  `json:"tiered"`
```

and after `require.Equal(t, 1, created.Subscription.MaxZones)`:

```go
		require.Nil(t, created.Subscription.Quantity, "an untiered seed sends quantity as null")
		require.Nil(t, created.Subscription.Tiered, "an untiered seed sends tiered as null")
```

- [ ] **Step 2: Run them and watch them fail**

Run: `go vet -tags integration,e2efixtures ./e2efixture ./cmd`
Expected: compile errors, unknown fields `Quantity` and `Tiered` in `SubscriptionFixtureSpec`.

- [ ] **Step 3: Carry the columns in the fixture insert**

Replace `InsertE2EFixtureSubscription` in `sql/e2e_fixtures.sql`:

```sql
-- name: InsertE2EFixtureSubscription :one
INSERT INTO account_subscriptions (account_id, stripe_subscription_id, status, name,
                                   max_zones, max_devices, quantity, tiered, created_on)
VALUES (sqlc.arg(account_id), sqlc.arg(stripe_subscription_id),
        'active'::account_subscriptions_status, sqlc.arg(name),
        sqlc.arg(max_zones), sqlc.arg(max_devices), sqlc.narg(quantity), sqlc.narg(tiered),
        CURRENT_TIMESTAMP)
RETURNING id, status, max_zones, max_devices, quantity, tiered;
```

Run: `make generate`, then `git status --short` in both repos. Expected: `ntpdb/e2e_fixtures.sql.go` changed; nothing in ntppool.

- [ ] **Step 4: Spec, validation, insert and response**

In `e2efixture/fixture.go`:

```go
// SubscriptionFixtureSpec seeds one live subscription on the fixture account.
// A missing limit decodes to 0 and fails validation. Quantity and Tiered are
// what the item bought; set both for a synced row, or neither for a row that
// hasn't been synced since they were added.
type SubscriptionFixtureSpec struct {
	MaxZones   int64  `json:"max_zones"`   // At least 1.
	MaxDevices int64  `json:"max_devices"` // At least 1.
	Quantity   *int64 `json:"quantity"`    // Optional; at least 1; with Tiered.
	Tiered     *bool  `json:"tiered"`      // Optional; with Quantity.
}
```

Add to `FixtureSubscription` after `MaxDevices`:

```go
	Quantity             *int64 `json:"quantity"` // null when the seed left it unset.
	Tiered               *bool  `json:"tiered"`   // null when the seed left it unset.
```

In `validateFixtureRequest`, change the message's subscription clause to `an optional subscription with max_zones and max_devices of at least 1 and, optionally together, a quantity of at least 1 and tiered`, and replace the subscription check:

```go
	if sub := req.Subscription; sub != nil &&
		(sub.MaxZones < 1 || sub.MaxDevices < 1 ||
			(sub.Quantity == nil) != (sub.Tiered == nil) ||
			(sub.Quantity != nil && *sub.Quantity < 1)) {
		return invalid
	}
```

In `CreateFixture`, replace the `if spec := req.Subscription; spec != nil { ... }` block:

```go
		if spec := req.Subscription; spec != nil {
			stripeID := fixtureStripeSubscriptionID(req.AttemptID)
			quantity := pgtype.Int8{}
			if spec.Quantity != nil {
				quantity = pgtype.Int8{Int64: *spec.Quantity, Valid: true}
			}
			tiered := pgtype.Bool{}
			if spec.Tiered != nil {
				tiered = pgtype.Bool{Bool: *spec.Tiered, Valid: true}
			}
			row, err := q.InsertE2EFixtureSubscription(ctx, ntpdb.InsertE2EFixtureSubscriptionParams{
				AccountID:            account.ID,
				StripeSubscriptionID: stripeID,
				Name:                 fixtureSubscriptionName,
				MaxZones:             spec.MaxZones,
				MaxDevices:           spec.MaxDevices,
				Quantity:             quantity,
				Tiered:               tiered,
			})
			if err != nil {
				return err
			}
			if !row.Status.Valid {
				return errSubscriptionStatusNull
			}
			response.Subscription = &FixtureSubscription{
				SubscriptionID:       row.ID,
				StripeSubscriptionID: stripeID.String,
				Status:               string(row.Status.AccountSubscriptionsStatus),
				MaxZones:             row.MaxZones,
				MaxDevices:           row.MaxDevices,
			}
			if row.Quantity.Valid {
				response.Subscription.Quantity = &row.Quantity.Int64
			}
			if row.Tiered.Valid {
				response.Subscription.Tiered = &row.Tiered.Bool
			}
		}
```

Use the parameter and field types `make generate` produced if they differ.

- [ ] **Step 5: Run the tests**

```sh
gofumpt -w e2efixture/fixture.go e2efixture/fixture_integration_test.go cmd/e2e_integration_test.go
go test ./...
./scripts/test-integration ./e2efixture
./scripts/test-integration ./cmd
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/ask/src/go/ntp/api
git status
git add sql/e2e_fixtures.sql ntpdb/e2e_fixtures.sql.go e2efixture/fixture.go \
  e2efixture/fixture_integration_test.go cmd/e2e_integration_test.go
git diff --staged --check
git diff --staged
git status
git commit -m "feat(e2e): seed quantity and tiered on fixture subscriptions" \
  -m "api e2e fixture create takes an optional quantity and tiered, together, so a spec can seed a synced tiered subscription the coverage check offers an upgrade for. Both are null in the response when unset."
```

### Task 5: What a quantity buys

**Files:**
- Modify: `/Users/ask/src/go/ntp/stripe-gw/plan_limits.go`
- Modify: `/Users/ask/src/go/ntp/stripe-gw/plan_limits_test.go`
- Modify: `/Users/ask/src/go/ntp/stripe-gw/api_products.go:194-327` (`getTiers`)
- Modify: `/Users/ask/src/go/ntp/stripe-gw/api_products_test.go`

**Interfaces:**
- Produces (all `package main`):
  - `func tierTop(tiers []*stripe.PriceTier, i int) int64`
  - `func tableTop(tiers []*stripe.PriceTier) int64`
  - `func quantityTier(tiers []*stripe.PriceTier, quantity int64) int`
  - `func devicesForQuantity(price *stripe.Price, quantity int64) (int64, error)`
  - `planLimits` gains `Tiered bool`; `limitsForPrice(price)` keeps its signature and refuses a tiered price with `quantity_scale` ≠ 1 or `transform_quantity`.
  - `func limitsForItem(price *stripe.Price, quantity int64) (planLimits, error)`
  - Test helpers `productionPrice()` and `enterprisePrice()` in `plan_limits_test.go`, used again in Tasks 6 and 10.

- [ ] **Step 1: Write the failing tests**

Append to `plan_limits_test.go`:

```go
// productionPrice is shaped like the Production price: volume tiers, each a
// flat amount with no unit price, ending in an open-ended tier. The amounts
// are made up.
func productionPrice() *stripe.Price {
	return &stripe.Price{
		ID:        "price_production",
		Active:    true,
		TiersMode: stripe.PriceTiersModeVolume,
		Tiers: []*stripe.PriceTier{
			{UpTo: 5000, FlatAmountDecimal: 100000},
			{UpTo: 10000, FlatAmountDecimal: 150000},
			{UpTo: 25000, FlatAmountDecimal: 250000},
			{UpTo: 100000, FlatAmountDecimal: 500000},
			{UpTo: 500000, FlatAmountDecimal: 1000000},
			{UpTo: 0, FlatAmountDecimal: 2000000},
		},
		Recurring: &stripe.PriceRecurring{Interval: "year", IntervalCount: 1},
		Product: &stripe.Product{
			ID:       "prod_production",
			Active:   true,
			Name:     "Production",
			Metadata: map[string]string{"max_zones": "2"},
		},
	}
}

// enterprisePrice is shaped like the Enterprise price: graduated tiers, each
// a flat amount plus a unit price, ending in an open-ended tier, with
// quantity_scale 1 on the product. The amounts are made up.
func enterprisePrice() *stripe.Price {
	return &stripe.Price{
		ID:        "price_enterprise",
		Active:    true,
		TiersMode: stripe.PriceTiersModeGraduated,
		Tiers: []*stripe.PriceTier{
			{UpTo: 1000000, FlatAmountDecimal: 500000, UnitAmountDecimal: 0.5},
			{UpTo: 5000000, FlatAmountDecimal: 100000, UnitAmountDecimal: 0.4},
			{UpTo: 30000000, FlatAmountDecimal: 100000, UnitAmountDecimal: 0.3},
			{UpTo: 50000000, FlatAmountDecimal: 100000, UnitAmountDecimal: 0.2},
			{UpTo: 0, FlatAmountDecimal: 100000, UnitAmountDecimal: 0.1},
		},
		Recurring: &stripe.PriceRecurring{Interval: "year", IntervalCount: 1},
		Product: &stripe.Product{
			ID:       "prod_enterprise",
			Active:   true,
			Name:     "Enterprise",
			Metadata: map[string]string{"max_zones": "10", "quantity_scale": "1"},
		},
	}
}

func TestDevicesForQuantity(t *testing.T) {
	// A volume price whose open-ended tier has a unit price: the rule is per
	// tier, not per tiers mode.
	mixed := productionPrice()
	mixed.Tiers = []*stripe.PriceTier{
		{UpTo: 5000, FlatAmountDecimal: 100000},
		{UpTo: 0, UnitAmountDecimal: 20},
	}

	tests := []struct {
		name     string
		price    *stripe.Price
		quantity int64
		want     int64
	}{
		{"volume: first tier", productionPrice(), 1, 5000},
		{"volume: top of the first tier", productionPrice(), 5000, 5000},
		{"volume: just past a tier boundary", productionPrice(), 5001, 10000},
		{"volume: a middle tier's top", productionPrice(), 25000, 25000},
		{"volume: last finite tier", productionPrice(), 500000, 500000},
		{"volume: open-ended tier", productionPrice(), 500001, 1000000},
		{"volume: the table's top", productionPrice(), 1000000, 1000000},
		{"volume: above the table's top gets the top", productionPrice(), 1200000, 1000000},
		{"graduated: unit price buys the quantity", enterprisePrice(), 1, 1},
		{"graduated: tier boundary", enterprisePrice(), 1000000, 1000000},
		{"graduated: just past a boundary", enterprisePrice(), 1000001, 1000001},
		{"graduated: open-ended tier", enterprisePrice(), 60000000, 60000000},
		{"graduated: above the table's top", enterprisePrice(), 120000000, 120000000},
		{"per tier: a tier without a unit price", mixed, 3000, 5000},
		{"per tier: a tier with a unit price", mixed, 7000, 7000},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := devicesForQuantity(tt.price, tt.quantity)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestDevicesForQuantityRefuses(t *testing.T) {
	noTiers := productionPrice()
	noTiers.Tiers = nil

	tests := []struct {
		name     string
		price    *stripe.Price
		quantity int64
		errText  string
	}{
		{"zero quantity", productionPrice(), 0, "below 1"},
		{"negative quantity", enterprisePrice(), -5, "below 1"},
		{"flat price", flatPrice(map[string]string{"max_zones": "1", "max_clients": "5000"}, nil), 1, "isn't tiered"},
		{"no tiers", noTiers, 10, "no tier"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := devicesForQuantity(tt.price, tt.quantity)
			require.Error(t, err)
			assert.Contains(t, err.Error(), tt.errText)
		})
	}
}

func TestTableTop(t *testing.T) {
	assert.Equal(t, int64(1000000), tableTop(productionPrice().Tiers))
	assert.Equal(t, int64(100000000), tableTop(enterprisePrice().Tiers))
	assert.Zero(t, tableTop(nil))
}

func TestLimitsForPriceTiered(t *testing.T) {
	got, err := limitsForPrice(enterprisePrice())

	require.NoError(t, err, "quantity_scale 1 is allowed")
	assert.True(t, got.Tiered)
	assert.Equal(t, int64(100000000), got.MaxClients, "the plan's highest tier")
}

func TestLimitsForPriceRefusesTieredQuantityScale(t *testing.T) {
	price := productionPrice()
	price.Product.Metadata["quantity_scale"] = "1000"

	_, err := limitsForPrice(price)

	require.Error(t, err)
	assert.Contains(t, err.Error(), "quantity_scale")
}

func TestLimitsForPriceRefusesTieredTransformQuantity(t *testing.T) {
	price := productionPrice()
	price.TransformQuantity = &stripe.PriceTransformQuantity{DivideBy: 10, Round: stripe.PriceTransformQuantityRoundDown}

	_, err := limitsForPrice(price)

	require.Error(t, err)
	assert.Contains(t, err.Error(), "transform_quantity")
}

func TestLimitsForItem(t *testing.T) {
	got, err := limitsForItem(productionPrice(), 7000)
	require.NoError(t, err)
	assert.Equal(t, int64(10000), got.MaxClients, "quantity 7000 buys the 10,000 tier")
	assert.Equal(t, int64(2), got.MaxZones)
	assert.True(t, got.Tiered)

	got, err = limitsForItem(flatPrice(map[string]string{"max_zones": "1", "max_clients": "5000"}, nil), 3)
	require.NoError(t, err)
	assert.Equal(t, int64(5000), got.MaxClients, "a flat price ignores the quantity")
	assert.False(t, got.Tiered)

	_, err = limitsForItem(productionPrice(), 0)
	require.Error(t, err, "a tiered item needs a quantity of at least 1")
	assert.Contains(t, err.Error(), "below 1")
}
```

Append to `api_products_test.go`:

```go
// The plan page's price and "up to N devices" for a quantity in the
// open-ended tier. Before the shared tier lookup no tier matched: CostDevices
// was 0 and the cost fell back to the lowest tier's.
func TestBuildProductDataOpenEndedTier(t *testing.T) {
	products, err := buildProductData([]*stripe.Price{productionPrice()}, 1, 600000)

	require.NoError(t, err)
	require.Len(t, products, 1)
	pr := products[0]
	assert.True(t, pr.Available)
	assert.Equal(t, int64(1000000), pr.CostDevices, "the open-ended tier's number")
	assert.Equal(t, int64(2000000), pr.AnnualCost, "the open-ended tier's flat amount")
}

func TestBuildProductDataGraduatedCostDevices(t *testing.T) {
	products, err := buildProductData([]*stripe.Price{enterprisePrice()}, 1, 60000000)

	require.NoError(t, err)
	require.Len(t, products, 1)
	assert.True(t, products[0].Available)
	assert.Equal(t, int64(60000000), products[0].CostDevices, "a tier with a unit price quotes the quantity")
}

func TestBuildProductDataAboveTableTop(t *testing.T) {
	products, err := buildProductData([]*stripe.Price{productionPrice()}, 1, 1200000)

	require.NoError(t, err)
	require.Len(t, products, 1)
	assert.False(t, products[0].Available, "the table stops at 1,000,000")
	assert.Equal(t, int64(1000000), products[0].MaxClients)
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cd /Users/ask/src/go/ntp/stripe-gw && go test ./...`
Expected: compile errors for `devicesForQuantity`, `tableTop`, `limitsForItem` and `Tiered`.

- [ ] **Step 3: Implement the quantity functions and validation**

In `plan_limits.go`, replace the `planLimits` doc comment and struct:

```go
// planLimits are the plan name, billing interval and limits one Stripe price
// implies. From limitsForPrice, MaxClients is the plan's highest tier, the
// range the plan page shows; from limitsForItem, it is what one subscription
// item's quantity bought.
type planLimits struct {
	Name           string
	MaxZones       int64
	MaxClients     int64
	IntervalMonths int64
	Tiered         bool
}
```

In `limitsForPrice`, after the `max_zones` metadata check, add:

```go
	// What a quantity buys has to be unambiguous on a tiered price, or the
	// product list would sell something the sync then stores differently.
	if price.TiersMode != "" {
		scale, err := getFloat(price, "quantity_scale", 1.0)
		if err != nil {
			return planLimits{}, fmt.Errorf("price %s: %w", price.ID, err)
		}
		if scale != 1.0 {
			return planLimits{}, fmt.Errorf("price %s (product %s) is tiered with quantity_scale %v; only 1 is supported",
				price.ID, price.Product.ID, scale)
		}
		if price.TransformQuantity != nil {
			return planLimits{}, fmt.Errorf("price %s is tiered with transform_quantity, which isn't supported", price.ID)
		}
	}
```

and set the flag where `limits` is built:

```go
	limits := planLimits{Name: name, IntervalMonths: interval, Tiered: price.TiersMode != ""}
```

Append to `plan_limits.go`:

```go
// limitsForItem is what one subscription item buys. A flat price ignores the
// quantity: its device count is the max_clients metadata. A tiered price's
// device count is what the item's quantity buys, not the plan's highest tier.
func limitsForItem(price *stripe.Price, quantity int64) (planLimits, error) {
	limits, err := limitsForPrice(price)
	if err != nil {
		return planLimits{}, err
	}
	if !limits.Tiered {
		return limits, nil
	}
	devices, err := devicesForQuantity(price, quantity)
	if err != nil {
		return planLimits{}, err
	}
	limits.MaxClients = devices
	return limits, nil
}

// tierTop is the device count the plan table shows for tier i of a tiered
// price: the tier's up_to, or for the open-ended last tier (Stripe's
// up_to: inf, which arrives as 0) twice the tier below's.
func tierTop(tiers []*stripe.PriceTier, i int) int64 {
	if tiers[i].UpTo > 0 {
		return tiers[i].UpTo
	}
	if i == 0 {
		return 0
	}
	return 2 * tierTop(tiers, i-1)
}

// tableTop is the highest device count a tiered price's table shows.
func tableTop(tiers []*stripe.PriceTier) int64 {
	if len(tiers) == 0 {
		return 0
	}
	return tierTop(tiers, len(tiers)-1)
}

// quantityTier is the index of the tier a quantity falls in: the first tier
// whose up_to covers it, or the open-ended last tier for any quantity above
// the tier below. It is -1 for a quantity below 1 or a table with no tier
// for it.
func quantityTier(tiers []*stripe.PriceTier, quantity int64) int {
	if quantity < 1 {
		return -1
	}
	for i, t := range tiers {
		if t.UpTo == 0 || quantity <= t.UpTo {
			return i
		}
	}
	return -1
}

// devicesForQuantity is what a quantity buys on a tiered price, in the
// devices the plan page promises for it. The rule is per tier: a tier with a
// unit price buys the quantity itself, and a tier without one buys the
// tier's number in the table, so a quantity above the table's top on such a
// tier gets the table's top.
func devicesForQuantity(price *stripe.Price, quantity int64) (int64, error) {
	if price.TiersMode == "" {
		return 0, fmt.Errorf("price %s isn't tiered", price.ID)
	}
	if quantity < 1 {
		return 0, fmt.Errorf("price %s: quantity %d is below 1", price.ID, quantity)
	}
	i := quantityTier(price.Tiers, quantity)
	if i < 0 {
		return 0, fmt.Errorf("price %s has no tier for quantity %d", price.ID, quantity)
	}
	if price.Tiers[i].UnitAmountDecimal > 0 {
		return quantity, nil
	}
	return tierTop(price.Tiers, i), nil
}
```

- [ ] **Step 4: Move the tier lookup out of `getTiers`**

In `api_products.go`, `getTiers`: after the `spr.Recurring == nil` check and the `newCT` closure, before `switch spr.TiersMode {`, add:

```go
	// match is the tier a requested quantity falls in (-1 for none), and
	// devices what it buys there: the numbers the plan page quotes.
	match := -1
	var devices int64
	if quantity > 0 && spr.TiersMode != "" {
		match = quantityTier(spr.Tiers, quantity)
		if match >= 0 {
			devices, err = devicesForQuantity(spr, quantity)
			if err != nil {
				return nil, err
			}
		}
	}
```

Replace the `case "graduated":` loop:

```go
		for i, t := range spr.Tiers {
			cost = cost + t.FlatAmountDecimal
			max := tierTop(spr.Tiers, i)

			tierUnits := max - units

			// the plan cost is for the tier the quantity falls in
			if plan.Cost == 0 && i == match {
				plan.Cost = int64(cost) // before units
				if t.UnitAmountDecimal > 0 {
					tierQuantity := quantity - units
					plan.Cost = plan.Cost + int64((t.UnitAmountDecimal * float64(tierQuantity)))
				}
				plan.CostDevices = devices
			}

			units = max

			if t.UnitAmountDecimal > 0 {
				cost = cost + (t.UnitAmountDecimal * float64(tierUnits))
			}

			ct := newCT()
			ct.Cost = int64(cost)
			ct.MaxClients = int64(float64(max) * productUnitFactor)
			r = append(r, ct)

			if max == 0 {
				return nil, fmt.Errorf("max == 0 for %s / %s", spr.Product.ID, spr.ID)
			}
		}
```

Replace the `case "volume":` block:

```go
	case "volume":
		units := int64(0)
		for i, t := range spr.Tiers {
			cost := t.FlatAmountDecimal
			max := tierTop(spr.Tiers, i)

			units = max

			// the plan cost is for the tier the quantity falls in
			if plan.Cost == 0 && i == match {
				plan.Cost = int64(cost) // flat amount
				if t.UnitAmountDecimal > 0 {
					// todo: support productUnitFactor?
					plan.Cost = plan.Cost + int64((t.UnitAmountDecimal * float64(quantity)))
				}
				plan.CostDevices = devices
			}

			if t.UnitAmountDecimal > 0 {
				cost = cost + (t.UnitAmountDecimal * float64(units))
			}

			ct := newCT()
			ct.Cost = int64(cost)
			ct.MaxClients = int64(float64(max) * productUnitFactor)
			r = append(r, ct)
		}
```

The flat (`case "":`) branch is unchanged.

- [ ] **Step 5: Run the tests**

Run: `gofumpt -w plan_limits.go plan_limits_test.go api_products.go api_products_test.go && go test ./...`
Expected: all pass, including the existing `TestLimitsForPriceVolumeTiers` (25,000, the plan's highest tier).

- [ ] **Step 6: Commit**

```bash
cd /Users/ask/src/go/ntp/stripe-gw
git status
git add plan_limits.go plan_limits_test.go api_products.go api_products_test.go
git diff --staged --check
git diff --staged
git status
git commit -m "feat(limits): work out what a quantity buys on a tiered price" \
  -m "devicesForQuantity finds the tier a quantity falls in and returns the table's number for a tier without a unit price, or the quantity for a tier with one. getTiers uses the same lookup, so a quantity in the open-ended tier gets that tier's price and device count on the plan page instead of 0 devices at the lowest tier's price. limitsForPrice refuses a tiered price with quantity_scale other than 1 or with transform_quantity."
```

### Task 6: The sync reports what the item bought

**Files:**
- Modify: `/Users/ask/src/go/ntp/stripe-gw/go.mod`, `go.sum`
- Modify: `/Users/ask/src/go/ntp/stripe-gw/webhook.go:158-269` (`syncSubscription`, `buildWebhookRequest`)
- Modify: `/Users/ask/src/go/ntp/stripe-gw/webhook_test.go`

**Interfaces:**
- Consumes: `limitsForItem` (Task 5); proto `ProcessStripeWebhookRequest.Quantity *int64`, `.Tiered *bool` (Task 2, through `replace go.ntppool.org/api => ../api`).
- Produces: every request with limits also carries `Quantity` and `Tiered`; `MaxDevices` is what the item's quantity bought.

- [ ] **Step 1: Point stripe-gw at the local api**

```sh
cd /Users/ask/src/go/ntp/stripe-gw
go mod edit -replace go.ntppool.org/api=../api
go mod tidy
go build ./...
```

Expected: builds. This `replace` is temporary; Task 8 removes it before stripe-gw is pushed.

- [ ] **Step 2: Write the failing tests**

Append to `webhook_test.go`:

```go
// A tiered item stores what its quantity bought, and says so.
func TestBuildWebhookRequestTieredItem(t *testing.T) {
	sub := &stripe.Subscription{
		ID:       "sub_tiered",
		Customer: &stripe.Customer{ID: "cus_1"},
		Status:   stripe.SubscriptionStatusActive,
		Items: &stripe.SubscriptionItemList{
			Data: []*stripe.SubscriptionItem{{ID: "si_1", Price: productionPrice(), Quantity: 7000}},
		},
	}

	req, err := buildWebhookRequest(sub)

	require.NoError(t, err)
	require.NotNil(t, req.MaxDevices)
	assert.Equal(t, int64(10000), *req.MaxDevices, "quantity 7000 buys the 10,000 tier, not the plan's top")
	require.NotNil(t, req.Quantity)
	assert.Equal(t, int64(7000), *req.Quantity)
	require.NotNil(t, req.Tiered)
	assert.True(t, *req.Tiered)
}

func TestBuildWebhookRequestFlatItem(t *testing.T) {
	sub := &stripe.Subscription{
		ID:       "sub_flat",
		Customer: &stripe.Customer{ID: "cus_1"},
		Status:   stripe.SubscriptionStatusActive,
		Items: &stripe.SubscriptionItemList{
			Data: []*stripe.SubscriptionItem{{
				ID:       "si_1",
				Price:    flatPrice(map[string]string{"max_zones": "1", "max_clients": "5000"}, nil),
				Quantity: 1,
			}},
		},
	}

	req, err := buildWebhookRequest(sub)

	require.NoError(t, err)
	require.NotNil(t, req.MaxDevices)
	assert.Equal(t, int64(5000), *req.MaxDevices)
	require.NotNil(t, req.Quantity)
	assert.Equal(t, int64(1), *req.Quantity)
	require.NotNil(t, req.Tiered)
	assert.False(t, *req.Tiered)
}

// A tiered item with no quantity has no limits to derive; the status still
// goes out.
func TestBuildWebhookRequestTieredItemWithoutQuantity(t *testing.T) {
	sub := &stripe.Subscription{
		ID:       "sub_no_quantity",
		Customer: &stripe.Customer{ID: "cus_1"},
		Status:   stripe.SubscriptionStatusActive,
		Items: &stripe.SubscriptionItemList{
			Data: []*stripe.SubscriptionItem{{ID: "si_1", Price: productionPrice(), Quantity: 0}},
		},
	}

	req, err := buildWebhookRequest(sub)

	require.NotNil(t, req)
	assert.Equal(t, "active", req.Status)
	assert.Nil(t, req.MaxDevices)
	assert.Nil(t, req.Quantity)
	assert.Nil(t, req.Tiered)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "below 1")
}
```

In `TestBuildWebhookRequestNoUsableLimitsStillReportsStatus`, after `assert.Nil(t, req.MaxDevices)`, add:

```go
	assert.Nil(t, req.Quantity)
	assert.Nil(t, req.Tiered)
```

- [ ] **Step 3: Run them and watch them fail**

Run: `go test ./... -run TestBuildWebhookRequest`
Expected: `TestBuildWebhookRequestTieredItem` fails (MaxDevices 1000000, Quantity nil); `TestBuildWebhookRequestTieredItemWithoutQuantity` fails (no error).

- [ ] **Step 4: Send what the item bought**

In `buildWebhookRequest`, replace from `limits, err := limitsForPrice(sub.Items.Data[0].Price)` to the end of the function:

```go
	item := sub.Items.Data[0]
	limits, err := limitsForItem(item.Price, item.Quantity)
	if err != nil {
		return req, err
	}

	quantity := item.Quantity
	tiered := limits.Tiered
	req.Name = &limits.Name
	req.MaxZones = &limits.MaxZones
	req.MaxDevices = &limits.MaxClients
	req.Quantity = &quantity
	req.Tiered = &tiered
	return req, nil
}
```

In its doc comment, change "just with Name, MaxZones and MaxDevices left nil" to "just with Name, MaxZones, MaxDevices, Quantity and Tiered left nil", and "an unusual line item count, or a price with no usable metadata" to "an unusual line item count, a price with no usable metadata, or a tiered item with a quantity below 1". Make the same wording change in the comment above `req, err := buildWebhookRequest(sub)` in `syncSubscription`.

In `syncSubscription`, extend the `if req.Name != nil` attributes:

```go
	if req.Name != nil {
		span.SetAttributes(
			attribute.String("plan.name", *req.Name),
			attribute.Int64("plan.max_zones", *req.MaxZones),
			attribute.Int64("plan.max_clients", *req.MaxDevices),
			attribute.Int64("plan.quantity", *req.Quantity),
			attribute.Bool("plan.tiered", *req.Tiered),
		)
	}
```

- [ ] **Step 5: Run the tests**

Run: `gofumpt -w webhook.go webhook_test.go && go test ./...`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/ask/src/go/ntp/stripe-gw
git status
git add go.mod go.sum webhook.go webhook_test.go
git diff --staged --check
git diff --staged
git status
git commit -m "feat(sync): report the devices, quantity and tiered flag an item bought" \
  -m "buildWebhookRequest takes max_devices from the item's quantity on a tiered price instead of the plan's highest tier, and sends the quantity and whether the price is tiered. A tiered item with a quantity below 1 reports its status without limits." \
  -m "go.mod temporarily replaces go.ntppool.org/api with ../api for the new request fields; it is removed once the api is pushed."
```

### Task 7: Resync mode

**Files:**
- Create: `/Users/ask/src/go/ntp/stripe-gw/resync.go`
- Create: `/Users/ask/src/go/ntp/stripe-gw/resync_test.go`
- Modify: `/Users/ask/src/go/ntp/stripe-gw/stripe-gw.go:93` (after `webhook := NewWebhook(...)`)
- Modify: `/Users/ask/src/go/ntp/stripe-gw/README.md`, `/Users/ask/src/go/ntp/stripe-gw/CLAUDE.md`

**Interfaces:**
- Consumes: `(*Webhook).syncSubscription(ctx, subscriptionID, requestID string) (*subscriptionv1.ProcessStripeWebhookResponse, error)`, `accountNotFound`, `errMessage`.
- Produces: `stripe-gw resync` (used in Tasks 14 and 17); `type resyncCounts struct { Synced, Unlinked, Refused, Failed int }` with `add(subscriptionID string, msg *subscriptionv1.ProcessStripeWebhookResponse, err error)` and `err() error`.

- [ ] **Step 1: Write the failing test**

`resync_test.go`:

```go
package main

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	subscriptionv1 "go.ntppool.org/api/gen/ntppool/subscription/v1"
)

func TestResyncCounts(t *testing.T) {
	token := "acc_1"
	notFound := "account not found for stripe_customer_id: cus_gone"
	refused := "invalid subscription status: paused"

	var c resyncCounts
	c.add("sub_ok", &subscriptionv1.ProcessStripeWebhookResponse{
		Success:      true,
		AccountToken: &token,
		Subscription: &subscriptionv1.AccountSubscription{Status: "active", MaxDevices: 10000},
	}, nil)
	c.add("sub_unlinked", &subscriptionv1.ProcessStripeWebhookResponse{Error: &notFound}, nil)
	c.add("sub_refused", &subscriptionv1.ProcessStripeWebhookResponse{Error: &refused}, nil)
	c.add("sub_failed", nil, errors.New("stripe: no such subscription"))

	assert.Equal(t, resyncCounts{Synced: 1, Unlinked: 1, Refused: 1, Failed: 1}, c)
	require.Error(t, c.err(), "a refusal or a failure fails the run")

	// A customer no account owns is expected: the sandbox keeps subscriptions
	// of E2E accounts that have since been deleted.
	assert.NoError(t, resyncCounts{Synced: 3, Unlinked: 2}.err())
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `go test ./... -run TestResyncCounts`
Expected: compile error, `undefined: resyncCounts`.

- [ ] **Step 3: Implement the mode**

`resync.go`:

```go
package main

import (
	"context"
	"fmt"
	"log"

	"github.com/stripe/stripe-go/v74"
	"github.com/stripe/stripe-go/v74/subscription"

	subscriptionv1 "go.ntppool.org/api/gen/ntppool/subscription/v1"
)

// resync reports every subscription in Stripe, of any status, to the API
// through syncSubscription, the webhook's own code, so each row ends up as a
// webhook would leave it. It runs once per environment: devel after the
// quantity columns were added, production at the PostgreSQL cutover.
func (wh *Webhook) resync(ctx context.Context) error {
	params := &stripe.SubscriptionListParams{Status: stripe.String("all")}
	params.Filters.AddFilter("limit", "", "100")

	var counts resyncCounts
	it := subscription.List(params)
	for it.Next() {
		if err := ctx.Err(); err != nil {
			return err
		}
		id := it.Subscription().ID
		msg, err := wh.syncSubscription(ctx, id, "resync")
		counts.add(id, msg, err)
	}
	if err := it.Err(); err != nil {
		return fmt.Errorf("listing subscriptions: %w", err)
	}

	log.Printf("resync: %d synced, %d without an account, %d refused, %d failed",
		counts.Synced, counts.Unlinked, counts.Refused, counts.Failed)
	return counts.err()
}

// resyncCounts tallies one resync run.
type resyncCounts struct {
	Synced   int
	Unlinked int
	Refused  int
	Failed   int
}

// add counts and logs one subscription's outcome.
func (c *resyncCounts) add(subscriptionID string, msg *subscriptionv1.ProcessStripeWebhookResponse, err error) {
	switch {
	case err != nil:
		c.Failed++
		log.Printf("resync: %s failed: %s", subscriptionID, err)
	case accountNotFound(msg):
		c.Unlinked++
		log.Printf("resync: %s has no account", subscriptionID)
	case !msg.Success:
		c.Refused++
		log.Printf("resync: %s refused: %s", subscriptionID, errMessage(msg))
	default:
		c.Synced++
		if s := msg.Subscription; s != nil && msg.AccountToken != nil {
			log.Printf("resync: %s account %s status %s max_zones %d max_devices %d",
				subscriptionID, *msg.AccountToken, s.Status, s.MaxZones, s.MaxDevices)
		}
	}
}

// err fails the run on any refusal or error. A customer no account owns is
// not a failure.
func (c resyncCounts) err() error {
	if c.Refused+c.Failed > 0 {
		return fmt.Errorf("%d refused, %d failed", c.Refused, c.Failed)
	}
	return nil
}
```

In `stripe-gw.go`, directly after `webhook := NewWebhook(ctx, webhookSecret)`:

```go
	// `stripe-gw resync` syncs every Stripe subscription to the API and exits
	// instead of serving.
	if len(os.Args) > 1 && os.Args[1] == "resync" {
		if err := webhook.resync(ctx); err != nil {
			log.Fatalf("resync: %s", err)
		}
		return
	}
```

- [ ] **Step 4: Document it**

In `README.md`, add after the "Webhooks" endpoint list:

```markdown
## Resync

`stripe-gw resync` runs the webhook's sync for every subscription in Stripe,
of any status, and exits. It needs the same environment as the server. A
subscription whose customer no account owns is logged and skipped; any other
refusal or error makes it exit non-zero. In a deployed pod:

    kubectl exec deploy/stripe-gw -c stripe-gw -- sh -c \
      'source /vault/secrets/stripe.env && source /vault/secrets/api.env && /stripe/stripe-gw resync'
```

In `CLAUDE.md`, under "Running the Service", add after `./run  # Uses the run script that sets up environment`:

```markdown
`stripe-gw resync` syncs every Stripe subscription to the API and exits (see README).
```

- [ ] **Step 5: Run the tests**

Run: `gofumpt -w resync.go resync_test.go stripe-gw.go && go test ./... && go build ./...`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/ask/src/go/ntp/stripe-gw
git status
git add resync.go resync_test.go stripe-gw.go README.md CLAUDE.md
git diff --staged --check
git diff --staged
git status
git commit -m "feat: add a resync mode that syncs every Stripe subscription" \
  -m "stripe-gw resync runs syncSubscription for each subscription in Stripe and exits, non-zero on any refusal or error other than a customer no account owns. Devel uses it to fill quantity and tiered, and production at the cutover."
```

### Task 8: Deploy sections 1 and 2 to devel

The API and stripe-gw deploy together: between the two, the new API refuses limits from the old stripe-gw, and Stripe retries those webhooks.

**Files:**
- Modify: `/Users/ask/src/go/ntp/stripe-gw/go.mod`, `go.sum`
- Modify (maintainer): `/Users/ask/src/flux-ntp/askntp/api/api-config-local.yaml`, `/Users/ask/src/flux-ntp/askntp/stripe-gw/config-stripe-gw-local.yaml`

**Interfaces:**
- Consumes: the api commits from Tasks 2-4 and the stripe-gw commits from Tasks 5-7.
- Produces: devel running migration 031, the new coverage fields and the quantity-based sync.

- [ ] **Step 1 [maintainer]: Push the API and deploy it**

```sh
cd /Users/ask/src/go/ntp/api
git log --oneline origin/main..main   # expect only the Task 2-4 commits
git push origin main
```

When CI has built `ntporg/api-dev:sha-<first 8 of HEAD>`, set `x-image-tag: &image-tag sha-<first 8>` in `~/src/flux-ntp/askntp/api/api-config-local.yaml` and run `./update-api` in that directory. Don't push flux-ntp.

Verify:

```sh
kubectl --context dala -n askntp exec deploy/api-internal -c main -- /ko-app/api migrate status
```

Expected: `031_account_subscriptions_quantity_tiered.sql` applied.

- [ ] **Step 2 [executor, after step 1]: Use the pushed api module**

```sh
cd /Users/ask/src/go/ntp/stripe-gw
go mod edit -dropreplace go.ntppool.org/api
go get go.ntppool.org/api@main
go mod tidy
grep -n "replace\|go.ntppool.org/api" go.mod
go test ./...
git status
git add go.mod go.sum
git diff --staged
git status
git commit -m "build: use the pushed api module"
```

Expected: no `replace` line, `go.ntppool.org/api` at a pseudo-version for the pushed HEAD, tests pass.

- [ ] **Step 3 [maintainer]: Push stripe-gw and deploy it**

```sh
cd /Users/ask/src/go/ntp/stripe-gw
git log --oneline origin/main..main   # Tasks 5-7 and step 2
git push origin main
```

When CI has built `ntporg/stripe-gw:sha-<first 8>`, set `appVersion: sha-<first 8>` in `~/src/flux-ntp/askntp/stripe-gw/config-stripe-gw-local.yaml` and run `./update` there.

- [ ] **Step 4 [maintainer]: Verify**

```sh
kubectl --context dala get --raw '/api/v1/namespaces/askntp/services/stripe-gw:80/proxy/api/v1/products?zones=1&quantity=600000' \
  | jq '.Products[] | {Name, Available, CostDevices, AnnualCost}'
kubectl --context dala -n askntp logs deploy/stripe-gw --since 10m | grep -i "skipping price"
```

Expected: Production shows `CostDevices` 1000000 (it was 0 before) and is available; Enterprise and the flat products still listed; no `skipping price` line for Production or Enterprise.

---
## Phase 3: Spec section 3

### Task 9: `POST /api/v1/subscription/sync`

**Files:**
- Modify: `/Users/ask/src/go/ntp/stripe-gw/webhook.go` (split `syncSubscription`)
- Modify: `/Users/ask/src/go/ntp/stripe-gw/checkout_complete.go` (share the response)
- Create: `/Users/ask/src/go/ntp/stripe-gw/subscription_sync.go`
- Create: `/Users/ask/src/go/ntp/stripe-gw/subscription_sync_test.go`
- Modify: `/Users/ask/src/go/ntp/stripe-gw/stripe-gw.go` (route)

**Interfaces:**
- Consumes: `buildWebhookRequest`, `accountNotFound`, `errMessage`, `CheckoutCompleteResponse`.
- Produces:
  - `func getSubscription(subscriptionID string) (*stripe.Subscription, error)` (items' price, product and tiers expanded; used again in Task 10)
  - `func (wh *Webhook) reportSubscription(ctx context.Context, sub *stripe.Subscription, requestID string) (*subscriptionv1.ProcessStripeWebhookResponse, error)`
  - `func checkCustomer(sub *stripe.Subscription, customerID string) error` (used again in Task 10)
  - `func completedResponse(msg *subscriptionv1.ProcessStripeWebhookResponse) CheckoutCompleteResponse`
  - `func (wh *Webhook) CompleteUpgrade(c echo.Context) error` on `POST /api/v1/subscription/sync`, form fields `subscription_id`, `customer_id`; answers `CheckoutCompleteResponse` JSON. Perl's `NP::Stripe::sync_subscription` (Task 13) calls it.

- [ ] **Step 1: Write the failing tests**

`subscription_sync_test.go`:

```go
package main

import (
	"net/http"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stripe/stripe-go/v74"
)

// sync and upgrade_session act for the customer Perl names, so a
// subscription belonging to anyone else is refused.
func TestCheckCustomer(t *testing.T) {
	sub := &stripe.Subscription{ID: "sub_1", Customer: &stripe.Customer{ID: "cus_1"}}

	require.NoError(t, checkCustomer(sub, "cus_1"))

	err := checkCustomer(sub, "cus_2")
	require.Error(t, err, "another customer's subscription")
	assert.Contains(t, err.Error(), "does not belong")

	require.Error(t, checkCustomer(sub, ""), "no customer named")
	require.Error(t, checkCustomer(&stripe.Subscription{ID: "sub_1"}, "cus_1"), "subscription without a customer")
}

func TestCompleteUpgradeRequiresFields(t *testing.T) {
	setupTestEnv(t)
	wh := NewWebhook(t.Context(), "whsec_test")

	for name, body := range map[string]string{
		"nothing":            "",
		"no customer_id":     "subscription_id=sub_1",
		"no subscription_id": "customer_id=cus_1",
	} {
		t.Run(name, func(t *testing.T) {
			c, rec := createTestContext(http.MethodPost, "/api/v1/subscription/sync", body)

			err := wh.CompleteUpgrade(c)

			var httpErr *echo.HTTPError
			require.ErrorAs(t, err, &httpErr)
			assert.Equal(t, http.StatusBadRequest, httpErr.Code)
			assert.Zero(t, rec.Body.Len(), "the handler never reached Stripe")
		})
	}
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `go test ./... -run 'TestCheckCustomer|TestCompleteUpgrade'`
Expected: compile errors, `undefined: checkCustomer` and `wh.CompleteUpgrade undefined`.

- [ ] **Step 3: Split the sync into fetch and report**

In `webhook.go`, replace `syncSubscription` (from its doc comment to its closing brace) with:

```go
// syncSubscription fetches a subscription from Stripe and reports it to the
// API. The webhook, checkout/complete and resync use it, so the row is the
// same whichever arrives first. The API's own answer (including "account not
// found") comes back in the response for the caller to interpret.
func (wh *Webhook) syncSubscription(ctx context.Context, subscriptionID, requestID string) (*subscriptionv1.ProcessStripeWebhookResponse, error) {
	ctx, span := tracing.Tracer().Start(ctx, "webhook.sync_subscription")
	defer span.End()

	span.SetAttributes(attribute.String("subscription.id", subscriptionID))

	sub, err := getSubscription(subscriptionID)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "failed to get subscription from Stripe")
		log.Printf("[%s] Failed to get subscription %s from Stripe: %v", requestID, subscriptionID, err)
		return nil, err
	}

	return wh.reportSubscription(ctx, sub, requestID)
}

// getSubscription fetches a subscription with its items' prices, products
// and tiers expanded: everything buildWebhookRequest and checkUpgrade read.
func getSubscription(subscriptionID string) (*stripe.Subscription, error) {
	params := &stripe.SubscriptionParams{}
	params.AddExpand("items.data.price.product")
	params.AddExpand("items.data.price.tiers")
	return subscription.Get(subscriptionID, params)
}

// reportSubscription sends a subscription already fetched from Stripe to the
// API. The caller interprets the API's answer.
func (wh *Webhook) reportSubscription(ctx context.Context, sub *stripe.Subscription, requestID string) (*subscriptionv1.ProcessStripeWebhookResponse, error) {
	ctx, span := tracing.Tracer().Start(ctx, "webhook.report_subscription")
	defer span.End()

	subscriptionID := sub.ID
	span.SetAttributes(attribute.String("subscription.id", subscriptionID))
```

followed by the old body from the `// buildWebhookRequest's only hard failures ...` comment through `return resp.Msg, nil` and the closing brace, unchanged (it already uses `sub`, `subscriptionID`, `requestID`, `span` and `ctx`).

- [ ] **Step 4: Share the checkout response**

In `checkout_complete.go`, replace the end of `CompleteCheckout` from `resp := CheckoutCompleteResponse{}` with:

```go
	return c.JSON(http.StatusOK, completedResponse(msg))
}

// completedResponse is what Perl needs from a successful sync: the account
// and the subscription as the API saved it.
func completedResponse(msg *subscriptionv1.ProcessStripeWebhookResponse) CheckoutCompleteResponse {
	resp := CheckoutCompleteResponse{}
	if msg.AccountToken != nil {
		resp.AccountToken = *msg.AccountToken
	}
	if s := msg.Subscription; s != nil {
		resp.Subscription = &CompletedSubscription{
			ID:               s.StripeSubscriptionId,
			Name:             s.Name,
			Status:           s.Status,
			MaxZones:         s.MaxZones,
			MaxDevices:       s.MaxDevices,
			LiveSubscription: s.LiveSubscription,
		}
	}
	return resp
}
```

and add `subscriptionv1 "go.ntppool.org/api/gen/ntppool/subscription/v1"` to its imports.

- [ ] **Step 5: The handler**

`subscription_sync.go`:

```go
package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/labstack/echo/v4"
	"github.com/stripe/stripe-go/v74"
)

// CompleteUpgrade is the browser's half of a portal upgrade: Stripe sends the
// vendor back, Perl posts the subscription and the account's customer here,
// and this reports the subscription to the API exactly as the webhook does,
// so the zone page shows the new limits without waiting for the webhook.
func (wh *Webhook) CompleteUpgrade(c echo.Context) error {
	ctx := c.Request().Context()
	requestID := getRequestID(c)

	subscriptionID := c.FormValue("subscription_id")
	customerID := c.FormValue("customer_id")
	if subscriptionID == "" || customerID == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "subscription_id and customer_id are required")
	}

	sub, err := getSubscription(subscriptionID)
	if err != nil {
		log.Printf("[%s] could not get subscription %s: %s", requestID, subscriptionID, err)
		return echo.NewHTTPError(http.StatusInternalServerError, "error id "+requestID)
	}
	if err := checkCustomer(sub, customerID); err != nil {
		log.Printf("[%s] refusing to sync: %s", requestID, err)
		return echo.NewHTTPError(http.StatusForbidden, err.Error()+"; request "+requestID)
	}

	msg, err := wh.reportSubscription(ctx, sub, requestID)
	if err != nil {
		log.Printf("[%s] could not sync subscription %s: %s", requestID, subscriptionID, err)
		return echo.NewHTTPError(http.StatusInternalServerError, "error id "+requestID)
	}
	if !msg.Success {
		log.Printf("[%s] API refused subscription %s: %s", requestID, subscriptionID, errMessage(msg))
		return echo.NewHTTPError(http.StatusInternalServerError, "error id "+requestID)
	}

	return c.JSON(http.StatusOK, completedResponse(msg))
}

// checkCustomer refuses a subscription that doesn't belong to the customer
// the caller named.
func checkCustomer(sub *stripe.Subscription, customerID string) error {
	if customerID == "" || sub.Customer == nil || sub.Customer.ID != customerID {
		return fmt.Errorf("subscription %s does not belong to customer %q", sub.ID, customerID)
	}
	return nil
}
```

In `stripe-gw.go`, after `apiV1.POST("/customer/portal", handleCustomerPortal)`:

```go
	apiV1.POST("/subscription/sync", webhook.CompleteUpgrade)
```

- [ ] **Step 6: Run the tests**

Run: `gofumpt -w webhook.go checkout_complete.go subscription_sync.go subscription_sync_test.go stripe-gw.go && go test ./... && go build ./...`
Expected: all pass, including `TestCompleteCheckoutRequiresSessionID`.

- [ ] **Step 7: Commit**

```bash
cd /Users/ask/src/go/ntp/stripe-gw
git status
git add webhook.go checkout_complete.go subscription_sync.go subscription_sync_test.go stripe-gw.go
git diff --staged --check
git diff --staged
git status
git commit -m "feat(api): sync a subscription on the upgrade return" \
  -m "POST /api/v1/subscription/sync fetches the subscription, refuses it unless it belongs to the customer Perl names, and reports it to the API through the webhook's own code. syncSubscription is split into a fetch and a report so the check needs one Stripe call."
```

### Task 10: `POST /api/v1/subscription/upgrade_session`

**Files:**
- Create: `/Users/ask/src/go/ntp/stripe-gw/subscription_upgrade.go`
- Create: `/Users/ask/src/go/ntp/stripe-gw/subscription_upgrade_test.go`
- Modify: `/Users/ask/src/go/ntp/stripe-gw/stripe-gw.go` (env var, route)
- Modify: `/Users/ask/src/go/ntp/stripe-gw/README.md`, `/Users/ask/src/go/ntp/stripe-gw/CLAUDE.md`

**Interfaces:**
- Consumes: `getSubscription`, `checkCustomer` (Task 9); `validateSubscription` (`webhook.go`); `tableTop` (Task 5); `productionPrice`, `flatPrice` test helpers.
- Produces:
  - `func checkUpgrade(sub *stripe.Subscription, customerID string, quantity int64) (*stripe.SubscriptionItem, error)`
  - `func upgradeSessionParams(configuration, customerID, subscriptionID, itemID string, quantity int64, returnURL, cancelURL string) *stripe.BillingPortalSessionParams`
  - `func handleUpgradeSession(configuration string) echo.HandlerFunc` on `POST /api/v1/subscription/upgrade_session`, form fields `customer_id`, `subscription_id`, `quantity`, `return_url`, `cancel_url`; answers `{"url": "..."}` (`UpgradeSessionResponse`). Perl's `NP::Stripe::upgrade_session` (Task 13) calls it.
  - stripe-gw exits at startup without `STRIPE_UPGRADE_PORTAL_CONFIGURATION`.

- [ ] **Step 1: Write the failing tests**

`subscription_upgrade_test.go`:

```go
package main

import (
	"net/http"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stripe/stripe-go/v74"
)

// upgradable is an active Production subscription at quantity 5000 on
// customer cus_up: every check passes for a quantity from 5001 to 1,000,000.
func upgradable() *stripe.Subscription {
	return &stripe.Subscription{
		ID:       "sub_up",
		Customer: &stripe.Customer{ID: "cus_up"},
		Status:   stripe.SubscriptionStatusActive,
		Items: &stripe.SubscriptionItemList{
			Data: []*stripe.SubscriptionItem{{ID: "si_up", Price: productionPrice(), Quantity: 5000}},
		},
	}
}

func TestCheckUpgradeAllows(t *testing.T) {
	item, err := checkUpgrade(upgradable(), "cus_up", 7000)
	require.NoError(t, err)
	assert.Equal(t, "si_up", item.ID)

	trialing := upgradable()
	trialing.Status = stripe.SubscriptionStatusTrialing
	_, err = checkUpgrade(trialing, "cus_up", 1000000)
	require.NoError(t, err, "trialing is live, and the table's top is covered")
}

func TestCheckUpgradeRefuses(t *testing.T) {
	tests := []struct {
		name     string
		change   func(*stripe.Subscription)
		customer string
		quantity int64
		errText  string
	}{
		{
			name:     "another customer's subscription",
			customer: "cus_other", quantity: 7000, errText: "does not belong",
		},
		{
			name:     "not active or trialing",
			change:   func(s *stripe.Subscription) { s.Status = stripe.SubscriptionStatusPastDue },
			customer: "cus_up", quantity: 7000, errText: "not active or trialing",
		},
		{
			name: "more than one item",
			change: func(s *stripe.Subscription) {
				s.Items.Data = append(s.Items.Data, &stripe.SubscriptionItem{ID: "si_2", Price: productionPrice(), Quantity: 1})
			},
			customer: "cus_up", quantity: 7000, errText: "2 line items",
		},
		{
			name: "a flat price",
			change: func(s *stripe.Subscription) {
				s.Items.Data[0].Price = flatPrice(map[string]string{"max_zones": "1", "max_clients": "5000"}, nil)
				s.Items.Data[0].Quantity = 1
			},
			customer: "cus_up", quantity: 7000, errText: "not on a tiered price",
		},
		{
			name:     "the same quantity",
			customer: "cus_up", quantity: 5000, errText: "not an increase",
		},
		{
			name:     "a lower quantity",
			customer: "cus_up", quantity: 4000, errText: "not an increase",
		},
		{
			name:     "above the table's top",
			customer: "cus_up", quantity: 1200000, errText: "does not cover",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sub := upgradable()
			if tt.change != nil {
				tt.change(sub)
			}

			item, err := checkUpgrade(sub, tt.customer, tt.quantity)

			assert.Nil(t, item)
			require.Error(t, err)
			assert.Contains(t, err.Error(), tt.errText)
		})
	}
}

func TestUpgradeSessionParams(t *testing.T) {
	p := upgradeSessionParams("bpc_up", "cus_up", "sub_up", "si_up", 7000,
		"https://example.com/upgraded", "https://example.com/zone")

	assert.Equal(t, "bpc_up", *p.Configuration)
	assert.Equal(t, "cus_up", *p.Customer)
	assert.Equal(t, "https://example.com/zone", *p.ReturnURL, "backing out returns to the zone page")
	require.NotNil(t, p.FlowData)
	assert.Equal(t, "subscription_update_confirm", *p.FlowData.Type)
	require.NotNil(t, p.FlowData.AfterCompletion)
	assert.Equal(t, "redirect", *p.FlowData.AfterCompletion.Type)
	assert.Equal(t, "https://example.com/upgraded", *p.FlowData.AfterCompletion.Redirect.ReturnURL)
	confirm := p.FlowData.SubscriptionUpdateConfirm
	require.NotNil(t, confirm)
	assert.Equal(t, "sub_up", *confirm.Subscription)
	require.Len(t, confirm.Items, 1)
	assert.Equal(t, "si_up", *confirm.Items[0].ID)
	assert.Equal(t, int64(7000), *confirm.Items[0].Quantity)
	assert.Nil(t, confirm.Items[0].Price, "only the quantity changes")
}

func TestUpgradeSessionRequiresFields(t *testing.T) {
	setupTestEnv(t)
	handler := handleUpgradeSession("bpc_test")
	const rest = "customer_id=cus_up&subscription_id=sub_up&return_url=https%3A%2F%2Fexample.com%2Fr&cancel_url=https%3A%2F%2Fexample.com%2Fc"

	for name, body := range map[string]string{
		"nothing":            "",
		"no quantity":        rest,
		"zero quantity":      rest + "&quantity=0",
		"not a number":       rest + "&quantity=lots",
		"no customer_id":     "subscription_id=sub_up&quantity=7000&return_url=https%3A%2F%2Fexample.com%2Fr&cancel_url=https%3A%2F%2Fexample.com%2Fc",
		"no cancel_url":      "customer_id=cus_up&subscription_id=sub_up&quantity=7000&return_url=https%3A%2F%2Fexample.com%2Fr",
	} {
		t.Run(name, func(t *testing.T) {
			c, rec := createTestContext(http.MethodPost, "/api/v1/subscription/upgrade_session", body)

			err := handler(c)

			var httpErr *echo.HTTPError
			require.ErrorAs(t, err, &httpErr)
			assert.Equal(t, http.StatusBadRequest, httpErr.Code)
			assert.Zero(t, rec.Body.Len(), "the handler never reached Stripe")
		})
	}
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `go test ./... -run 'Upgrade'`
Expected: compile errors, `undefined: checkUpgrade`, `upgradeSessionParams`, `handleUpgradeSession`.

- [ ] **Step 3: Implement the endpoint**

`subscription_upgrade.go`:

```go
package main

import (
	"fmt"
	"log"
	"net/http"
	"strconv"

	"github.com/labstack/echo/v4"
	"github.com/stripe/stripe-go/v74"
	portalsession "github.com/stripe/stripe-go/v74/billingportal/session"
)

// UpgradeSessionResponse answers POST /api/v1/subscription/upgrade_session.
type UpgradeSessionResponse struct {
	URL string `json:"url"`
}

// handleUpgradeSession opens a billing portal session that asks the vendor
// to confirm one change: a higher quantity on their single tiered item. The
// API decided the quantity; this refuses anything the portal shouldn't
// confirm, and the upgrade configuration invoices the difference at once.
func handleUpgradeSession(configuration string) echo.HandlerFunc {
	return func(c echo.Context) error {
		requestID := getRequestID(c)

		customerID := c.FormValue("customer_id")
		subscriptionID := c.FormValue("subscription_id")
		returnURL := c.FormValue("return_url")
		cancelURL := c.FormValue("cancel_url")
		if customerID == "" || subscriptionID == "" || returnURL == "" || cancelURL == "" {
			return echo.NewHTTPError(http.StatusBadRequest,
				"customer_id, subscription_id, quantity, return_url and cancel_url are required")
		}
		quantity, err := strconv.ParseInt(c.FormValue("quantity"), 10, 64)
		if err != nil || quantity < 1 {
			return echo.NewHTTPError(http.StatusBadRequest, "quantity must be a whole number of at least 1")
		}

		sub, err := getSubscription(subscriptionID)
		if err != nil {
			log.Printf("[%s] could not get subscription %s: %s", requestID, subscriptionID, err)
			return echo.NewHTTPError(http.StatusInternalServerError, "error id "+requestID)
		}

		item, err := checkUpgrade(sub, customerID, quantity)
		if err != nil {
			log.Printf("[%s] refusing upgrade: %s", requestID, err)
			return echo.NewHTTPError(http.StatusConflict, err.Error()+"; request "+requestID)
		}

		s, err := portalsession.New(upgradeSessionParams(configuration, customerID, sub.ID, item.ID,
			quantity, returnURL, cancelURL))
		if err != nil {
			log.Printf("[%s] billingportal.session.New for %s: %s", requestID, sub.ID, err)
			return echo.NewHTTPError(http.StatusInternalServerError, "error id "+requestID)
		}

		log.Printf("[%s] upgrade session for %s: quantity %d to %d", requestID, sub.ID, item.Quantity, quantity)
		return c.JSON(http.StatusOK, UpgradeSessionResponse{URL: s.URL})
	}
}

// checkUpgrade is every reason upgrade_session refuses, so the portal only
// ever confirms an increase on the customer's own single tiered item that
// the price's table covers. It returns the item to change.
func checkUpgrade(sub *stripe.Subscription, customerID string, quantity int64) (*stripe.SubscriptionItem, error) {
	if err := checkCustomer(sub, customerID); err != nil {
		return nil, err
	}
	if sub.Status != stripe.SubscriptionStatusActive && sub.Status != stripe.SubscriptionStatusTrialing {
		return nil, fmt.Errorf("subscription %s is %s, not active or trialing", sub.ID, sub.Status)
	}
	if err := validateSubscription(sub); err != nil {
		return nil, err
	}
	item := sub.Items.Data[0]
	if item.Price == nil || item.Price.TiersMode == "" {
		return nil, fmt.Errorf("subscription %s is not on a tiered price", sub.ID)
	}
	if quantity <= item.Quantity {
		return nil, fmt.Errorf("subscription %s has quantity %d; %d is not an increase",
			sub.ID, item.Quantity, quantity)
	}
	if top := tableTop(item.Price.Tiers); quantity > top {
		return nil, fmt.Errorf("price %s's table stops at %d devices and does not cover %d",
			item.Price.ID, top, quantity)
	}
	return item, nil
}

// upgradeSessionParams asks the portal to confirm the item's new quantity.
// Confirming sends the vendor to returnURL; backing out, to cancelURL.
func upgradeSessionParams(configuration, customerID, subscriptionID, itemID string, quantity int64, returnURL, cancelURL string) *stripe.BillingPortalSessionParams {
	return &stripe.BillingPortalSessionParams{
		Configuration: stripe.String(configuration),
		Customer:      stripe.String(customerID),
		ReturnURL:     stripe.String(cancelURL),
		FlowData: &stripe.BillingPortalSessionFlowDataParams{
			Type: stripe.String(string(stripe.BillingPortalSessionFlowTypeSubscriptionUpdateConfirm)),
			AfterCompletion: &stripe.BillingPortalSessionFlowDataAfterCompletionParams{
				Type: stripe.String(string(stripe.BillingPortalSessionFlowAfterCompletionTypeRedirect)),
				Redirect: &stripe.BillingPortalSessionFlowDataAfterCompletionRedirectParams{
					ReturnURL: stripe.String(returnURL),
				},
			},
			SubscriptionUpdateConfirm: &stripe.BillingPortalSessionFlowDataSubscriptionUpdateConfirmParams{
				Subscription: stripe.String(subscriptionID),
				Items: []*stripe.BillingPortalSessionFlowDataSubscriptionUpdateConfirmItemParams{
					{ID: stripe.String(itemID), Quantity: stripe.Int64(quantity)},
				},
			},
		},
	}
}
```

In `stripe-gw.go`, after the `STRIPE_WEBHOOK_SECRET` check:

```go
	// The billing portal configuration upgrade sessions use: quantity
	// changes on the tiered prices only, invoiced at once.
	upgradePortalConfiguration := os.Getenv("STRIPE_UPGRADE_PORTAL_CONFIGURATION")
	if len(upgradePortalConfiguration) == 0 {
		log.Fatalf("STRIPE_UPGRADE_PORTAL_CONFIGURATION not set")
	}
```

and after the `/subscription/sync` route:

```go
	apiV1.POST("/subscription/upgrade_session", handleUpgradeSession(upgradePortalConfiguration))
```

- [ ] **Step 4: Document the variable and endpoints**

`README.md`: in "Quick Start", add `export STRIPE_UPGRADE_PORTAL_CONFIGURATION="bpc_..."` after `STRIPE_WEBHOOK_SECRET`. Add a section after "Customer":

```markdown
**Subscription:**
- `POST /api/v1/subscription/sync` - Sync a subscription for its customer (upgrade return)
- `POST /api/v1/subscription/upgrade_session` - Billing portal session confirming a higher quantity
```

`CLAUDE.md`: under "Required environment variables" add `# STRIPE_UPGRADE_PORTAL_CONFIGURATION - Billing portal configuration for quantity upgrades`; in the endpoint list add the same two routes.

- [ ] **Step 5: Run the tests**

Run: `gofumpt -w subscription_upgrade.go subscription_upgrade_test.go stripe-gw.go && go test ./... && go build ./...`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/ask/src/go/ntp/stripe-gw
git status
git add subscription_upgrade.go subscription_upgrade_test.go stripe-gw.go README.md CLAUDE.md
git diff --staged --check
git diff --staged
git status
git commit -m "feat(api): open a billing portal session for a quantity upgrade" \
  -m "POST /api/v1/subscription/upgrade_session refuses unless the subscription is the customer's, active or trialing, has one item on a tiered price, and the new quantity is an increase the price's table covers. It then opens a subscription_update_confirm session with STRIPE_UPGRADE_PORTAL_CONFIGURATION, which stripe-gw now requires at startup."
```

### Task 11: Deploy stripe-gw with the upgrade configuration

The new binary refuses to start without the variable, so steps 1-2 come before step 3.

**Files:**
- Modify (untracked, nothing to commit): `/Users/ask/src/flux-ntp/askntp/stripe-gw/config-stripe-gw-local.yaml`

**Interfaces:**
- Consumes: the `bpc_...` id from Task 1; stripe-gw commits from Tasks 9-10.
- Produces: devel stripe-gw serving `sync` and `upgrade_session`.

- [ ] **Step 1 [user]: Store the configuration id in Vault**

```sh
vault kv patch kv/ntppool/devel/stripe upgrade_portal_configuration=bpc_...
```

- [ ] **Step 2 [executor]: Render it into the pod's environment**

In `~/src/flux-ntp/askntp/stripe-gw/config-stripe-gw-local.yaml`, in `vault.hashicorp.com/agent-inject-template-stripe`, add after the `STRIPE_WEBHOOK_SECRET` line:

```yaml
    export STRIPE_UPGRADE_PORTAL_CONFIGURATION="{{ .Data.data.upgrade_portal_configuration }}"
```

- [ ] **Step 3 [maintainer]: Push and deploy**

```sh
cd /Users/ask/src/go/ntp/stripe-gw
git log --oneline origin/main..main   # Tasks 9-10
git push origin main
```

When CI has built the image, set `appVersion: sha-<first 8>` in the same config file and run `./update` in `~/src/flux-ntp/askntp/stripe-gw`.

- [ ] **Step 4 [maintainer]: Verify**

```sh
kubectl --context dala -n askntp get pods -l app.kubernetes.io/name=stripe-gw
kubectl --context dala -n askntp logs deploy/stripe-gw --since 10m | grep -i "not set"
```

Expected: the pod is Running and ready; no `not set` line.

### Task 12: Checkout buys the devices the account needs

**Files:**
- Modify: `/Users/ask/src/ntppool/lib/NTPPool/Control/Vendor.pm` (`render_zone` :223-302, `render_subscription` :655-689)

**Interfaces:**
- Consumes: `get_account_subscription_status` response keys `required_devices`, `max_devices`, `upgrade` (Tasks 2-3, deployed in Task 8).
- Produces: template param `coverage` (the status response's `data` hashref) on every `render_zone`; checkout quantity for tiered prices is `required_devices`. Task 13's template reads `coverage`.

- [ ] **Step 1: Give the zone page the API's coverage, and price the picker with it**

In `render_zone`, after `my $sub_data = ($sub_status && !$sub_status->{error}) ? $sub_status->{data} : {};` add:

```perl
    # The over-limit block in show.html reads max_devices, required_devices
    # and the upgrade offer straight from the API's answer.
    $self->tpl_param('coverage', $sub_data);
```

Delete `my $device_count = $zone->{device_count} || 0;` (its only reader is the product list below).

Replace the start of the `if ($zone->{status} eq 'New') {` block, from `# todo: only load if we need to show this` through the closing brace of the `else` that sets `product_group_list`, with:

```perl
        # The plan picker prices what the account needs: its approved devices
        # plus this zone, as the API computed them. Without the API's answer
        # there is nothing to price, so the picker lists no plans; the
        # open-source form below it still renders.
        if (defined $sub_data->{required_devices}) {
            my ($products, $groups, $group_list) =
              NP::Stripe::product_groups(1, $sub_data->{required_devices});
            if ($products->{error}) {
                warn "stripe gw error: ", $products->{error};

                # todo: show error?
            }
            else {
                $self->tpl_param('products_by_group',  $groups);
                $self->tpl_param('product_group_list', $group_list);
            }
        }
        else {
            warn "no required_devices for zone $zone->{id_token}; listing no plans"
              . (
                ($sub_status && $sub_status->{error})
                ? " (API error: $sub_status->{error}, trace: "
                  . ($sub_status->{trace_id} || 'none') . ")"
                : ""
              );
        }
```

The `show_products`, `need_subscription` and `need_upgrade` lines after it are unchanged.

- [ ] **Step 2: Check out for `required_devices`**

In `render_subscription`, replace

```perl
        my $device_count = $zone ? ($zone->{device_count} || 0) : 0;
        my ($products, $groups, $group_list) =
          NP::Stripe::product_groups(1, $device_count);
```

with:

```perl
        # Checkout buys what the account needs: its approved devices plus
        # this zone, as the API computes them. Without a zone there is no
        # such number, and only a flat price can be bought (below).
        my $required_devices = 0;
        if ($zone) {
            my $status = get_account_subscription_status(
                $self->api_auth_params,
                account      => $zone->{account_token},
                device_count => $zone->{device_count},
            );
            if ($status->{error}) {
                warn "API error getting subscription status for checkout: "
                  . $status->{error}
                  . " (trace: "
                  . ($status->{trace_id} || 'none') . ")";
                return OK,
                  $json->encode({error => "Could not start checkout; please try again."});
            }
            $required_devices = $status->{data}{required_devices};
        }

        my ($products, $groups, $group_list) =
          NP::Stripe::product_groups(1, $required_devices);
```

Replace

```perl
            my ($plan) = grep { $_->{ID} eq $price_id } @{$product->{Plans}};
```

with:

```perl
            my ($plan) =
              grep { $_->{ID} eq $price_id } @{$product ? $product->{Plans} : []};
            unless ($plan) {
                warn "price $price_id is not a plan of product $product_id";
                return OK, $json->encode({error => "Unknown plan; please choose again."});
            }
```

Replace

```perl
            my $quantity = $zone ? ($zone->{device_count} || 1) : 1;
            if ($plan->{TiersMode} eq "") {
                $quantity = 1;
            }
```

with:

```perl
            # A flat price is bought once. A tiered price is bought for the
            # devices the account needs, which takes a zone; the plan
            # picker's forms always send one.
            my $quantity = 1;
            if ($plan->{TiersMode} ne "") {
                unless ($zone) {
                    warn "refusing tiered checkout for price $price_id without a zone";
                    return OK,
                      $json->encode({error => "Choose a plan from the zone's page."});
                }
                $quantity = 0 + $required_devices;
            }
```

- [ ] **Step 3: Tidy**

```sh
cd /Users/ask/src/ntppool
perltidy -b lib/NTPPool/Control/Vendor.pm && rm -f lib/NTPPool/Control/Vendor.pm.bak
git diff --stat
```

Expected: only `Vendor.pm` changed, and only around the edited blocks.

- [ ] **Step 4 [maintainer]: Restart the dev site**

Stop `devspace dev` and run it again.

- [ ] **Step 5: Verify on the dev site**

1. As a vendor whose account has no subscription, create a New zone with 5,000 devices at `https://manage.askdev.grundclock.com/manage/vendor/new?x=<random>`.
2. The zone page lists plans; Production reads "per year for up to 5,000 devices".
3. Press Production's annual button. Stripe Checkout shows quantity 5,000. Go back without paying.
4. From `/Users/ask/src/ntppool/e2e`: `npx playwright test tests/vendor.spec.ts tests/vendor-coverage.spec.ts tests/stripe-checkout.spec.ts --project manage`. If the executor's cluster access is refused (the harness reaches the API CLI through `kubectl`), hand this command to the maintainer.

Expected: steps 2-3 as described; the three specs pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/ask/src/ntppool
git status
git add lib/NTPPool/Control/Vendor.pm
git diff --staged --check
git diff --staged
git status
git commit -m "feat(vendor): check out for the devices the account needs" \
  -m "The zone page's plan picker and the create_session quantity for a tiered price use the API's required_devices, the account's approved devices plus the zone, instead of the zone's own device count. A tiered checkout without a zone, or for a price that isn't the product's, is refused."
```

### Task 13: Upgrade offer, upgrade and return routes

**Files:**
- Modify: `/Users/ask/src/ntppool/lib/NP/Stripe.pm` (after `complete_checkout`)
- Modify: `/Users/ask/src/ntppool/lib/NTPPool/Control/Vendor.pm` (`manage_dispatch` :55, new subs after `render_subscription`)
- Modify: `/Users/ask/src/ntppool/docs/manage/tpl/vendor/show.html:136-148`

**Interfaces:**
- Consumes: `coverage` template param (Task 12); stripe-gw `POST /api/v1/subscription/upgrade_session` and `POST /api/v1/subscription/sync` (Tasks 9-11).
- Produces: `NP::Stripe::upgrade_session(%args)`, `NP::Stripe::sync_subscription(%args)` (each returns the decoded JSON hashref, with `error` on a non-200); routes `POST /manage/vendor/plan/upgrade` (FORBIDDEN unless `can_edit` and the zone's `account_token` is `current_account->{id_token}`) and `GET /manage/vendor/plan/upgraded` (`500` with the payment-went-through message when the sync fails); template param `upgrade_refused`; the zone page's button only for the zone's own account. The E2E specs (Tasks 15-16) read the copy in Global Constraints.

- [ ] **Step 1: stripe-gw calls**

In `lib/NP/Stripe.pm`, after `complete_checkout`:

```perl
sub upgrade_session {
    my %args = @_;
    my $r    = _gw_post_api('subscription/upgrade_session', \%args);
    return $r;
}

sub sync_subscription {
    my %args = @_;
    my $r    = _gw_post_api('subscription/sync', \%args);
    return $r;
}
```

- [ ] **Step 2: Routes**

In `manage_dispatch`, directly before `return $self->render_subscription`:

```perl
    return $self->render_plan_upgrade
      if (    $self->request->uri eq '/manage/vendor/plan/upgrade'
          and $self->request->method eq 'post');

    return $self->render_plan_upgraded
      if $self->request->uri eq '/manage/vendor/plan/upgraded';
```

`manage_dispatch` already checks the CSRF `auth_token` on every POST.

After `render_subscription`, add:

```perl
# render_plan_upgrade sends the vendor to Stripe's billing portal to raise
# the quantity on their tiered subscription. The subscription and quantity
# come from the API's upgrade offer, fetched again here; the form only names
# the zone. Anyone who can edit the current account may upgrade, staff who
# switched into it included, but only for a zone of that account: the Stripe
# customer is the current account's.
sub render_plan_upgrade {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->{permissions}{can_edit};

    my $id = $self->_get_id
      or return $self->redirect($self->manage_url('/manage/vendor'));

    my $result = get_vendor_zone(
        auth     => $self->plain_cookie($self->user_cookie_name),
        id_token => $id,
        context  => $self->_get_request_context(),
    );
    if ($result->{error}) {
        warn "API error getting vendor zone for upgrade: "
          . $result->{error}
          . " (trace: "
          . ($result->{trace_id} || 'none') . ")";
        return $self->redirect($self->manage_url('/manage/vendor'));
    }
    my $zone = $result->{data}{zone};

    # The offer describes the zone's account and the portal session uses the
    # current account's Stripe customer, so the two must be the same account.
    unless (($zone->{account_token} // '') eq ($account->{id_token} // '')) {
        warn "refusing upgrade for zone $zone->{id_token} of account "
          . ($zone->{account_token} // 'none')
          . " from account $account->{id_token}";
        return FORBIDDEN;
    }

    my $zone_url = $self->manage_url('/manage/vendor/zone', {id => $zone->{id_token}});

    my $status = get_account_subscription_status(
        $self->api_auth_params,
        account      => $zone->{account_token},
        device_count => $zone->{device_count},
    );
    if ($status->{error}) {
        warn "API error getting subscription status for upgrade: "
          . $status->{error}
          . " (trace: "
          . ($status->{trace_id} || 'none') . ")";
        return $self->redirect($zone_url);
    }

    # No offer any more (the zone changed, or the plan already covers it):
    # the zone page shows what applies now.
    my $upgrade = $status->{data}{upgrade}
      or return $self->redirect($zone_url);

    my $session = NP::Stripe::upgrade_session(
        customer_id     => $account->{stripe_customer_id} // '',
        subscription_id => $upgrade->{stripe_subscription_id},
        quantity        => $upgrade->{quantity},
        return_url      => $self->manage_url(
            '/manage/vendor/plan/upgraded',
            {   id              => $zone->{id_token},
                subscription_id => $upgrade->{stripe_subscription_id},
            }
        ),
        cancel_url => $zone_url,
    );
    unless ($session->{url} && !$session->{error}) {
        warn "stripe-gw refused the upgrade for zone $zone->{id_token}: "
          . ($session->{error} || 'no url returned');
        $self->tpl_param('upgrade_refused' => 1);
        return $self->render_zone($zone->{id_token});
    }

    return $self->redirect($session->{url});
}

# render_plan_upgraded is where the billing portal sends the vendor after a
# confirmed upgrade. stripe-gw syncs the subscription with the webhook's own
# code, so the zone page shows the new limits without waiting for the
# webhook. A failed sync is an error response, as a failed checkout is in
# _update_subscription; the payment has gone through and the webhook writes
# the same row when it arrives.
sub render_plan_upgraded {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->{permissions}{can_edit};

    my $id = $self->_get_id
      or return $self->redirect($self->manage_url('/manage/vendor'));

    my $subscription_id = $self->req_param('subscription_id') // '';
    unless ($subscription_id =~ m/^sub_\w+$/) {
        warn "upgrade return for zone $id without a valid subscription_id";
        return 400, "Invalid upgrade return link";
    }

    # NP::Stripe's error carries stripe-gw's request id.
    my $r = NP::Stripe::sync_subscription(
        subscription_id => $subscription_id,
        customer_id     => $account->{stripe_customer_id} // '',
    );
    if ($r->{error}) {
        warn "Failed to sync upgraded subscription $subscription_id: $r->{error}";
        return 500, "Your payment went through. Your plan will update shortly.";
    }

    return $self->redirect($self->manage_url('/manage/vendor/zone', {id => $id}));
}
```

- [ ] **Step 3: The offer on the zone page**

In `docs/manage/tpl/vendor/show.html`, replace the `[% IF need_upgrade %]` branch (from `[% IF need_upgrade %]` up to, not including, `[% ELSE %]` / `[% PROCESS tpl/vendor/products.html %]`) with:

```html
      [% IF need_upgrade %]
        <div>
        [% IF coverage.upgrade && vz.account_token == combust.current_account.id_token && !upgrade_refused %]
        <p>
            <br>
            Your plan covers [% coverage.max_devices | format_number %] devices; this zone brings the account to [% coverage.required_devices | format_number %].
        </p>
        <form method="post" class="form-inline btn-inline" action="/manage/vendor/plan/upgrade">
            <input type="hidden" name="id" value="[% vz.id_token %]" />
            <input type="hidden" name="auth_token" value="[% combust.auth_token %]" />
            <input type="hidden" name="a" value="[% combust.current_account.id_token %]">
            <input type="submit" class="btn btn-primary"
                value="Update plan to [% coverage.upgrade.quantity | format_number %] devices &rarr;" />
        </form>
        [% ELSE %]
        <p>
            <br>
            The current subscription plan doesn't support adding the new DNS zone.
        </p>
        <p>
            <a href="mailto:[% "vendors" | email %]?subject=NTP Pool DNS zone [% vz.zone_name | html %] - subscription change"
                >Email to change the plan or with other questions</a>.
        </p>
        [% END %]
        </div>
```

The button shows only for the zone's own account; a vendor admin looking at another account's zone gets the email text, as `/manage/vendor/plan/upgrade` would refuse them. Staff who switched into the zone's account with `a=` get the button. The stale `<!-- waiting for subscription_update_confirm ... -->` comment goes away with the old branch. No inline styles or scripts.

- [ ] **Step 4: Tidy**

```sh
cd /Users/ask/src/ntppool
perltidy -b lib/NP/Stripe.pm lib/NTPPool/Control/Vendor.pm && rm -f lib/NP/Stripe.pm.bak lib/NTPPool/Control/Vendor.pm.bak
```

- [ ] **Step 5 [maintainer]: Restart the dev site**

Stop `devspace dev` and run it again.

- [ ] **Step 6: Verify on the dev site**

Use a fresh vendor account with no subscription (sandbox card 4242 4242 4242 4242, any future expiry and CVC):

1. Create zone A with 5,000 devices and buy Production annual from its page. Back on the site, zone A is submitted (Pending).
2. Create zone B with 10,000 devices. Its page says "Your plan covers 5,000 devices; this zone brings the account to 10,000." with the button "Update plan to 10,000 devices →" and no submit button.
3. As a vendor admin in another browser session, open zone B at `/manage/vendor/admin?show=1&id=<zone B>&x=<random>` (the admin's own account is current): the page has the email text and no upgrade button. Then open `/manage/vendor/zone?id=<zone B>&a=<the vendor's account token>&x=<random>` (switched into the vendor's account): the button shows. Don't press it as the admin.
4. As the vendor, press the button. Stripe's billing portal asks to confirm quantity 10,000 with an amount due today. Back out: you return to zone B's page, unchanged.
5. Press the button again and confirm. You land on zone B's page, which now has "Submit for production".
6. `/manage/vendor` "Current plan" shows up to 10,000 client devices.
7. `kubectl --context dala -n askntp logs deploy/stripe-gw --since 15m | grep -E "upgrade session|subscription/sync"` [maintainer] shows the session and the sync with no refusal.
8. Cancel the subscription afterwards in the Stripe sandbox dashboard [user].

Expected: each as described.

- [ ] **Step 7: Commit**

```bash
cd /Users/ask/src/ntppool
git status
git add lib/NP/Stripe.pm lib/NTPPool/Control/Vendor.pm docs/manage/tpl/vendor/show.html
git diff --staged --check
git diff --staged
git status
git commit -m "feat(vendor): offer a plan upgrade through the Stripe billing portal" \
  -m "An over-limit zone whose account the API offers an upgrade shows what the plan covers, what the zone brings the account to, and a button to update the plan. /manage/vendor/plan/upgrade fetches the offer again and opens stripe-gw's portal session; /manage/vendor/plan/upgraded has stripe-gw sync the subscription before returning to the zone, and answers a failed sync with an error saying the payment went through. The button and the upgrade route are only for the zone's own account, which staff reach by switching into it. Without an offer, or when stripe-gw refuses, the page keeps the email text."
```

---
## Phase 4: Devel data and E2E

### Task 14: Resync the sandbox subscriptions

**Files:** none.

**Interfaces:**
- Consumes: `stripe-gw resync` (Task 7), deployed in Task 8.
- Produces: devel rows with `quantity` and `tiered` filled and `max_devices` computed from the quantity.

- [ ] **Step 1 [maintainer]: Run the resync in the devel pod**

```sh
kubectl --context dala -n askntp exec deploy/stripe-gw -c stripe-gw -- sh -c \
  'source /vault/secrets/stripe.env && source /vault/secrets/api.env && /stripe/stripe-gw resync'
```

Expected: a line per subscription and a final `resync: N synced, M without an account, 0 refused, 0 failed`, exit status 0. If the container isn't named `stripe-gw`, drop `-c stripe-gw`.

- [ ] **Step 2 [maintainer]: Check any refusal**

A refused subscription is logged as `resync: sub_... refused: <reason>`. Refusals mean a status the API doesn't accept (such as `paused`) or a price whose limits can't be derived; each needs a look before the E2E run, not a rerun.

### Task 15: Harness seeds tiered subscriptions; upgrade offer spec

**Files:**
- Modify: `/Users/ask/src/ntppool/e2e/lib/fixtures.ts` (`SubscriptionSeed`, `FixtureSubscription`, `normalizeSubscription`, `parseSubscription`, the request in `createFixture`)
- Modify: `/Users/ask/src/ntppool/e2e/lib/vendor.ts`
- Modify: `/Users/ask/src/ntppool/e2e/tests/vendor-coverage.spec.ts`
- Modify: `/Users/ask/src/ntppool/e2e/README.md:181-189`
- Modify: `/Users/ask/src/ntppool/MANUAL_TEST_PLAN.md` (§5e)

**Interfaces:**
- Consumes: `api e2e fixture create` subscription `quantity`/`tiered` (Task 4, deployed in Task 8); the zone page copy and the zone-account guard on the button and on `/manage/vendor/plan/upgrade` (Task 13); `loginAsVendorAdmin`, `isVendorAdmin`, `adminOpenZone` (`lib/vendor.ts`).
- Produces: `SubscriptionSeed.quantity?: number`, `SubscriptionSeed.tiered?: boolean`; `FixtureSubscription.quantity: number | null`, `.tiered: boolean | null`; `upgradeOfferText(maxDevices: number, requiredDevices: number): string` and `upgradeButtonName(quantity: number): string` in `lib/vendor.ts`, used again in Task 16.

- [ ] **Step 1: Seed quantity and tiered**

In `e2e/lib/fixtures.ts`:

```ts
/**
 * One live subscription on the fixture account (status active). quantity and
 * tiered are what the item bought: set both for a synced row, or neither for
 * a row not synced since they were added.
 */
export interface SubscriptionSeed {
  maxZones: number;
  maxDevices: number;
  quantity?: number;
  tiered?: boolean;
}
```

Add to `FixtureSubscription` after `maxDevices: number;`:

```ts
  /** null when the seed left it unset. */
  quantity: number | null;
  /** null when the seed left it unset. */
  tiered: boolean | null;
```

Replace `normalizeSubscription`:

```ts
function normalizeSubscription(seed: SubscriptionSeed | undefined): SubscriptionSeed | undefined {
  if (seed === undefined) return undefined;
  for (const [name, value] of [["maxZones", seed.maxZones], ["maxDevices", seed.maxDevices]] as const) {
    if (!Number.isInteger(value) || value < 1) {
      throw new Error(`subscription seed ${name} must be an integer of at least 1`);
    }
  }
  if ((seed.quantity === undefined) !== (seed.tiered === undefined)) {
    throw new Error("subscription seed quantity and tiered go together");
  }
  if (seed.quantity !== undefined && (!Number.isInteger(seed.quantity) || seed.quantity < 1)) {
    throw new Error("subscription seed quantity must be an integer of at least 1");
  }
  return { maxZones: seed.maxZones, maxDevices: seed.maxDevices, quantity: seed.quantity, tiered: seed.tiered };
}
```

In `parseSubscription`, after the `limits mismatched` check:

```ts
  // An api-dev image from before the tiered seed omits both; treat that as null.
  const quantity = item.quantity == null ? null : intField(item.quantity, `${label} quantity`);
  const tiered = item.tiered == null ? null : boolField(item.tiered, `${label} tiered`);
  if (quantity !== (want.quantity ?? null) || tiered !== (want.tiered ?? null)) {
    throw new Error(`${label} quantity or tiered mismatched`);
  }
```

and add `quantity,` and `tiered,` to the returned object after `maxDevices,`.

In `createFixture`, replace the subscription request block:

```ts
  // Only a seed with a subscription sends the key, and only a tiered seed
  // sends quantity and tiered. The CLI rejects unknown fields, so specs
  // without them keep working against an older api-dev image.
  if (subscription) {
    const seeded: Record<string, unknown> = {
      max_zones: subscription.maxZones,
      max_devices: subscription.maxDevices,
    };
    if (subscription.quantity !== undefined) {
      seeded.quantity = subscription.quantity;
      seeded.tiered = subscription.tiered;
    }
    request.subscription = seeded;
  }
```

- [ ] **Step 2: Offer text helpers**

In `e2e/lib/vendor.ts`, after `UPGRADE_MESSAGE`:

```ts
/**
 * show.html's upgrade offer: a device overage on the account's one tiered
 * subscription. format_number renders thousands separators.
 */
export function upgradeOfferText(maxDevices: number, requiredDevices: number): string {
  return (
    `Your plan covers ${maxDevices.toLocaleString("en-US")} devices; ` +
    `this zone brings the account to ${requiredDevices.toLocaleString("en-US")}.`
  );
}

/** The upgrade offer's button, which posts to /manage/vendor/plan/upgrade. */
export function upgradeButtonName(quantity: number): string {
  return `Update plan to ${quantity.toLocaleString("en-US")} devices`;
}

/** Any upgrade offer button, for asserting there is none. */
export const UPGRADE_BUTTON = /Update plan to/;
```

- [ ] **Step 3: The spec**

In `e2e/tests/vendor-coverage.spec.ts`, add `adminOpenZone`, `UPGRADE_BUTTON`, `upgradeButtonName` and `upgradeOfferText` to the `../lib/vendor` import. In the header comment, change "and an over-limit New zone the upgrade message with no submit control (:132-148)" to "and an over-limit New zone either the upgrade offer (a device overage on one tiered subscription) or the upgrade message, with no submit control (:132-160)".

In `expectOverLimitRefusal`, after `await expect(page.getByText(UPGRADE_MESSAGE)).toBeVisible();`:

```ts
  await expect(page.getByRole("button", { name: UPGRADE_BUTTON }), "no upgrade offer").toHaveCount(0);
```

This makes the existing flat-seed device-limit and zone-limit tests check that no offer appears.

After the `a covered vendor over the device limit is refused by the site and by the API` test, add:

```ts
// §5e over-limit, device limit, on a tiered plan: the upgrade offer. The
// fixture's e2e_ subscription doesn't exist in Stripe, so stripe-gw can't
// open a portal session for it and the page falls back to the email text.
// The real portal is stripe-checkout.spec.ts. The offer is for the zone's own
// account: a vendor admin on their own account gets the email text and a 403
// from the upgrade route, and gets the button after switching into the
// zone's account with a=.
test("a covered vendor on a tiered plan over the device limit is offered an upgrade", async ({
  page,
  context,
  browser,
  fixtures,
}) => {
  const fixture = await fixtures.create({
    subscription: { maxZones: 1, maxDevices: 5000, quantity: 5000, tiered: true },
  });
  await installSession(context, fixture.sessionToken);
  const { idToken } = zoneUrlParams(await createNewZone(page, { ...freshZoneData("ou"), deviceCount: "10000" }));

  await expectCleanPage(page, bust(zonePath(idToken)));
  await expect(page.getByText(upgradeOfferText(5000, 10000))).toBeVisible();
  await expect(page.getByText(UPGRADE_MESSAGE), "the offer replaces the email text").toHaveCount(0);
  await expect(page.getByRole("button", { name: SUBMIT_CONTROL })).toHaveCount(0);

  const admin = await loginAsVendorAdmin(browser, uniqueTestEmail("vendor-coverage-admin"));
  try {
    expect(await isVendorAdmin(admin.page), VENDOR_ADMIN_REQUIRED).toBe(true);

    // The admin route renders the zone with the admin's own account current.
    await adminOpenZone(admin.page, idToken);
    await expect(admin.page.getByText(UPGRADE_MESSAGE), "another account's zone gets the email text").toBeVisible();
    await expect(admin.page.getByRole("button", { name: UPGRADE_BUTTON })).toHaveCount(0);

    // show.html's admin form carries the admin's own a= and auth_token.
    const adminForm = admin.page.locator('form[action="/manage/vendor/admin"]');
    const refused = await admin.page.request.post("/manage/vendor/plan/upgrade", {
      form: {
        id: idToken,
        a: await adminForm.locator('input[name="a"]').inputValue(),
        auth_token: await adminForm.locator('input[name="auth_token"]').inputValue(),
      },
      maxRedirects: 0,
    });
    expect(refused.status(), "the upgrade route refuses a zone of another account").toBe(403);

    // Staff who switch into the zone's account may upgrade like a member.
    await expectCleanPage(admin.page, bust(`${zonePath(idToken)}&a=${encodeURIComponent(fixture.accountToken)}`));
    await expect(admin.page.getByRole("button", { name: upgradeButtonName(10000) })).toBeVisible();
  } finally {
    await admin.context.close();
  }

  await Promise.all([
    page.waitForNavigation({ waitUntil: "load" }),
    page.getByRole("button", { name: upgradeButtonName(10000) }).click(),
  ]);
  await expectNoErrorBleed(page, page.url());
  await expect(page.getByText(UPGRADE_MESSAGE), "a refused portal session shows the email text").toBeVisible();
  await expect(page.getByRole("button", { name: UPGRADE_BUTTON })).toHaveCount(0);
  await expect(page.getByRole("button", { name: SUBMIT_CONTROL })).toHaveCount(0);

  await expectSubmitRefused(fixture.sessionToken, fixture.accountToken, idToken, "the owner");
  expect((await getVendorZone(fixture.sessionToken, idToken)).status).toBe("New");
});
```

- [ ] **Step 4: Docs**

In `e2e/README.md`, in the paragraph starting "A subscription seed adds one `account_subscriptions` row", change "the requested `max_zones` and `max_devices`" to "the requested `max_zones` and `max_devices`, optionally `quantity` and `tiered` (both or neither; the harness sends them only when set)".

In `MANUAL_TEST_PLAN.md` §5e, after the **Over-limit** item:

```markdown
- [x] **Over-limit on a tiered plan** (device overage, one live tiered subscription with a known quantity): the zone page offers "Update plan to N devices" for the devices the account needs instead of the email text, and a refused portal session falls back to the email text. The offer is only for the zone's own account: a vendor admin on their own account gets the email text and a 403 from `/manage/vendor/plan/upgrade`, and gets the button after switching into the zone's account with `a=`. A flat plan or a zone overage gets no offer. (`e2e/tests/vendor-coverage.spec.ts` → "a covered vendor on a tiered plan over the device limit is offered an upgrade"; the no-offer cases in the two over-limit tests above)
```

- [ ] **Step 5: Typecheck and run**

```sh
cd /Users/ask/src/ntppool/e2e
npm run typecheck
npm run test:unit
npx playwright test tests/vendor-coverage.spec.ts --project manage
```

Expected: typecheck and unit tests pass; the coverage spec passes against devel with Tasks 8, 11 and 13 deployed and the dev site restarted. Hand the Playwright command to the maintainer if cluster access is refused.

- [ ] **Step 6: Commit**

```bash
cd /Users/ask/src/ntppool
git status
git add e2e/lib/fixtures.ts e2e/lib/vendor.ts e2e/tests/vendor-coverage.spec.ts e2e/README.md MANUAL_TEST_PLAN.md
git diff --staged --check
git diff --staged
git status
git commit -m "test(e2e): seed tiered subscriptions and cover the upgrade offer" \
  -m "Fixture subscription seeds take quantity and tiered. The coverage spec checks that a device overage on a tiered seed gets the upgrade offer, that a refused portal session falls back to the email text, that the offer and the upgrade route are only for the zone's own account (staff get them after switching in), and that flat seeds and zone overages get no offer."
```

### Task 16: Portal upgrade spec and the full run

**Files:**
- Modify: `/Users/ask/src/ntppool/e2e/tests/stripe-checkout.spec.ts`
- Modify: `/Users/ask/src/ntppool/MANUAL_TEST_PLAN.md` (§7)

**Interfaces:**
- Consumes: `upgradeOfferText`, `upgradeButtonName` (Task 15); `expectSubmitted`, `createNewZone`, `freshZoneData`, `zonePath`, `zoneUrlParams` (`lib/vendor.ts`); `getAccountSubscriptions`, `cancelSubscription` (`lib/subscriptions.ts`).
- Produces: a spec that buys Production for 5,000 devices, upgrades to 10,000 through the portal and submits a covered zone.

- [ ] **Step 1: Share the card payment**

In `stripe-checkout.spec.ts`, change the Playwright import to `import { expect, test, type Page } from "@playwright/test";` and add `expectSubmitted`, `upgradeButtonName` and `upgradeOfferText` to the `../lib/vendor` import. Add above `test.describe`:

```ts
/**
 * Pay on Stripe's hosted Checkout page with the always-approved test card
 * and wait to land back on /manage/vendor/plan. These are Stripe's stable
 * field ids; if it changes them, this is the block to update.
 */
async function payWithTestCard(page: Page): Promise<void> {
  await page.fill("#cardNumber", "4242424242424242");
  await page.fill("#cardExpiry", "12/34");
  await page.fill("#cardCvc", "123");
  await page.fill("#billingName", "E2E Test");
  const postalCode = page.locator("#billingPostalCode");
  if (await postalCode.isVisible()) {
    await postalCode.fill("94107");
  }
  await Promise.all([
    page.waitForURL(/\/manage\/vendor\/plan/, { timeout: 60_000 }),
    page.locator(".SubmitButton").click(),
  ]);
}
```

In the existing test, replace its step 2 block (from `// 2. Stripe's own hosted page.` through the `Promise.all` that clicks `.SubmitButton`) with:

```ts
    // 2. Stripe's own hosted page.
    await payWithTestCard(page);
```

- [ ] **Step 2: The upgrade test**

Inside `test.describe("Stripe checkout", ...)`, after the existing test:

```ts
  test("a vendor upgrades a tiered plan through the billing portal", async ({ page, context }) => {
    // Two Stripe round trips (Checkout, then the portal) and many page loads.
    test.setTimeout(240_000);

    const { sessionToken } = await loginAs(context, uniqueTestEmail("stripe-upgrade"));

    // 1. Buy Production for zone A's 5,000 devices. Its first tier tops out
    // at 5,000, so the stored limit is exactly 5,000. The return submits
    // zone A, which stays Pending; only Approved zones count toward limits.
    const first = freshZoneData("su"); // 5,000 devices
    const { idToken: firstToken, accountToken } = zoneUrlParams(await createNewZone(page, first));
    await expectCleanPage(page, bust(zonePath(firstToken)));
    const production = page
      .locator("div.col")
      .filter({ has: page.locator("b", { hasText: /^\s*Production\s*$/ }) });
    await expect(production, "the sandbox sells Production for 5,000 devices").toBeVisible();
    const buy = production.locator('form[action*="create_session"] input[type="submit"][value*="per year"]');
    await Promise.all([page.waitForURL(/checkout\.stripe\.com/), buy.click()]);
    await payWithTestCard(page);

    const [bought, ...others] = await getAccountSubscriptions(sessionToken, accountToken);
    expect(others, "one subscription on the account").toHaveLength(0);
    expect(bought.name).toContain("Production");
    expect(bought.maxDevices, "Production's 5,000 tier").toBe(5000);

    // 2. Zone B brings the account to 10,000 devices: a device overage on
    // one tiered subscription, so the page offers the upgrade.
    const second = { ...freshZoneData("sv"), deviceCount: "10000" };
    const { idToken: secondToken } = zoneUrlParams(await createNewZone(page, second));
    await expectCleanPage(page, bust(zonePath(secondToken)));
    await expect(page.getByText(upgradeOfferText(5000, 10000))).toBeVisible();

    // 3. Stripe's billing portal, preset to 10,000. This is Stripe's page; if
    // it renames its confirm button, this is the line to update.
    await Promise.all([
      page.waitForURL(/billing\.stripe\.com/),
      page.getByRole("button", { name: upgradeButtonName(10000) }).click(),
    ]);
    await Promise.all([
      page.waitForURL(/\/manage\/vendor\/zone\?/, { timeout: 60_000 }),
      page.getByRole("button", { name: /^Confirm/ }).click(),
    ]);

    // 4. The return synced the subscription, so zone B is covered without
    // waiting for the webhook.
    const [upgraded] = await getAccountSubscriptions(sessionToken, accountToken);
    expect(upgraded.stripeSubscriptionId).toBe(bought.stripeSubscriptionId);
    expect(upgraded.maxDevices, "Production's 10,000 tier").toBe(10000);

    await expectCleanPage(page, bust(zonePath(secondToken)));
    await Promise.all([
      page.waitForNavigation({ waitUntil: "load" }),
      page.getByRole("button", { name: /^Submit for production/ }).click(),
    ]);
    await expectSubmitted(page, second.zoneName);

    // 5. Leave nothing live in the sandbox.
    expect(await cancelSubscription(bought.stripeSubscriptionId)).toBe("canceled");
  });
```

- [ ] **Step 3: Docs**

In `MANUAL_TEST_PLAN.md` §7, after the Stripe-gateway item:

```markdown
- [x] A tiered plan is bought for the devices the account needs and upgraded
  through the billing portal: Production for 5,000 devices stores 5,000, a
  zone that brings the account to 10,000 gets the upgrade offer, the portal
  confirms it, and the return syncs the subscription so the zone submits as
  covered (`e2e/tests/stripe-checkout.spec.ts` → "a vendor upgrades a tiered
  plan through the billing portal").
```

- [ ] **Step 4: Typecheck and run the full suite**

```sh
cd /Users/ask/src/ntppool/e2e
npm run typecheck
npx playwright test tests/stripe-checkout.spec.ts --project manage
npm test
```

Expected: typecheck passes; both checkout specs pass; the whole suite passes and teardown reports `canceled_subscriptions=0`. The maintainer runs these if cluster access is refused. If the portal step times out, look at the page Stripe rendered (Playwright trace) for the confirm button's name and fix that one line.

- [ ] **Step 5: Commit**

```bash
cd /Users/ask/src/ntppool
git status
git add e2e/tests/stripe-checkout.spec.ts MANUAL_TEST_PLAN.md
git diff --staged --check
git diff --staged
git status
git commit -m "test(e2e): upgrade a tiered plan through the billing portal" \
  -m "Buys Production for 5,000 devices, checks the stored limit, confirms an upgrade to 10,000 in Stripe's billing portal and submits the zone that needed it without waiting for the webhook."
```

---
## Phase 5: Production cutover

### Task 17: Cutover steps

The executor writes the steps into flux-ntp's cutover plan and leaves the file uncommitted (flux-ntp has other uncommitted edits the maintainer owns). Every step in the section runs at the PostgreSQL cutover, by the maintainer; none is an agent task, because production reads need Vault credentials agents can't fetch here.

**Files:**
- Modify: `/Users/ask/src/flux-ntp/docs/plans/stripe-gw-postgres-edition.md`

**Interfaces:**
- Consumes: everything above, released to production with the Postgres-edition stripe-gw and api.
- Produces: the ordering the spec requires, where the cutover is planned.

- [ ] **Step 1 [executor]: Add the environment variable to the comparison table**

In the table under "The two lines", change the `main` cell of the "Env it reads" row to:

```markdown
`NAMESPACE`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_UPGRADE_PORTAL_CONFIGURATION`, `API_URL`, `API_KEY`
```

- [ ] **Step 2 [executor]: Add the section**

Insert before `## What becomes dead — and must not be removed early`:

````markdown
## Tiered plan device limits

`main` stores a tiered subscription's `max_devices` as what its quantity
bought instead of the plan's highest tier, and offers upgrades through a
billing portal configuration of its own. Design:
`~/src/ntppool/docs/superpowers/specs/2026-09-16-tiered-plan-device-limits-design.md`.

The binary exits at startup without `STRIPE_UPGRADE_PORTAL_CONFIGURATION`, so
steps 1 and 2 come before the new image. Do the steps in order.

1. **Live upgrade configuration.** In live mode, create a billing portal
   configuration with `subscription_update` enabled,
   `default_allowed_updates: [quantity]`, `proration_behavior: always_invoice`,
   the Production prices `price_1MmrNQ2ZWuSKvxWMlxRDkkti` and
   `price_1MmrNQ2ZWuSKvxWMMT2PpsXD` and the Enterprise price
   `price_1Mmskp2ZWuSKvxWMdwBJvKnd` listed under their products, and every
   other feature off. The sandbox one was made with
   `stripe billing_portal configurations create` (the tiered plan device
   limits implementation plan, Task 1, step 2); the live one takes the same
   parameters with the live price and product ids.
2. **Check the live default configuration.** `features.subscription_update`
   must be disabled or must not list `quantity` in `default_allowed_updates`.
   Its current setting is unknown. Don't go on while it allows quantity
   changes: vendors could lower their own quantity.
3. **Vault and config.** Store the configuration id at
   `kv/ntppool/prod/stripe`, field `upgrade_portal_configuration`. In
   `ntppool/stripe-gw/config-stripe-gw-local.yaml`, add to the
   `agent-inject-template-stripe` template, after `STRIPE_WEBHOOK_SECRET`:

   ```yaml
       export STRIPE_UPGRADE_PORTAL_CONFIGURATION="{{ .Data.data.upgrade_portal_configuration }}"
   ```

4. **Rerun the read-only report** with current data:
   `~/src/go/ntp/stripe-gw/run-tiered-report` (untracked, next to
   `run-resync`). The 2026-09-16 run found no account that would go over its
   limit; stop if that has changed.
5. **Decide the status repair first.** The resync corrects the five
   status-drift rows in
   `~/src/go/ntp/stripe-gw/docs/subscription-repair-2026-09-02.md` as well,
   and those vendors lose coverage for new submits, which that document
   treats as customer-visible. Don't run step 6 until that repair is decided.
6. **Resync once, after the rows have migrated to PostgreSQL and the new
   stripe-gw and api are running:**

   ```sh
   kubectl --context dala -n ntppool exec deploy/stripe-gw -c stripe-gw -- sh -c \
     'source /vault/secrets/stripe.env && source /vault/secrets/api.env && /stripe/stripe-gw resync'
   ```

   It lowers the rows stored at 1,000,000 to their tier's number and fills
   `quantity` and `tiered`. Expect `0 refused, 0 failed`; look at each
   refusal it logs.
````

- [ ] **Step 3 [executor]: Check and hand over**

```sh
cd /Users/ask/src/flux-ntp
git diff --check docs/plans/stripe-gw-postgres-edition.md
git status --short
```

Expected: no whitespace errors; the doc shows as modified alongside the maintainer's existing uncommitted edits. Don't stage or commit. Tell the maintainer the doc is ready to review and commit.

---

## Self-review

**Spec coverage.**
- Decision 1 and section 1 (what a quantity buys, per-tier rule, open-ended tier, above the table's top, `getTiers` using the function, one validation place with the `quantity_scale`/`transform_quantity` refusal, flat prices unchanged, quantity below 1 refused): Task 5; the sync side, `buildWebhookRequest` sending `quantity` and `tiered` with the existing refusal path: Task 6.
- Decisions 2 and 5 and section 2 (migration 031, request fields and refusal, `UpsertAccountSubscription` writes them, `UpdateAccountSubscriptionStatus` leaves them, `required_devices` in every state, `upgrade` conditions, `max_devices` still summed, `e2e_fixtures.sql`): Tasks 2, 3, 4.
- Decision 2 in Perl (checkout quantity and plan picker from `required_devices`, tiered checkout without a zone refused): Task 12.
- Decisions 3 and 6 and section 3 (zone page offer, `/manage/vendor/plan/upgrade`, `upgrade_session` refusals and session parameters, `/manage/vendor/plan/upgraded` and `sync`, `STRIPE_UPGRADE_PORTAL_CONFIGURATION` required at startup): Tasks 9, 10, 11, 13. Resolved questions: the error response for a failed sync and the zone-account guard on the button and the upgrade route (Task 13, E2E in Task 15); the API's increase condition (Task 3).
- Decision 4 and the Stripe setup (upgrade configuration with `always_invoice`, default configuration without quantity changes): Task 1 (sandbox), Task 17 (live).
- Decision 7 and the rollout: spike first (Task 1); sections 1 and 2 together with generated code committed (Tasks 2-8); section 3, stripe-gw before Perl (Tasks 9-13); sandbox resync (Tasks 7, 14); E2E on devel (Tasks 15-16); production ordering in flux-ntp (Task 17).
- Testing: stripe-gw unit tests of the quantity function against Production- and Enterprise-shaped prices with open-ended tiers, boundaries, above the top and refusals (Task 5), `buildWebhookRequest` fields (Task 6), one `upgrade_session` test per refusal (Task 10), `sync` customer mismatch (Task 9); api coverage states and `required_devices`, including no upgrade when the stored quantity already covers the required devices (Task 3), `ProcessStripeWebhook` saves and refuses (Task 2); E2E checkout, over-limit zone, upgrade button, portal confirm, return and covered submit (Task 16).
- Out of scope items are untouched: no `max_zones` or plan switching, one-subscription accounts only, `GetApprovedZoneStats` unchanged, no approved-zone edits.

**Placeholder scan.** Runtime values the executor can't know in advance are named for where they come from: the `bpc_...` id (Task 1 step 2), `sha-<first 8>` image tags (CI), and the Stripe portal's confirm button name (checked in Task 16 step 4). Generated types are checked in Task 2 step 4 before code uses them.

**Type consistency.** `devicesForQuantity(price *stripe.Price, quantity int64) (int64, error)`, `tableTop([]*stripe.PriceTier) int64` and `limitsForItem(price, quantity) (planLimits, error)` are defined in Task 5 and used in Tasks 6 and 10. `getSubscription(id) (*stripe.Subscription, error)` and `checkCustomer(sub, customerID) error` are defined in Task 9 and used in Task 10. `subscription.Upgrade{StripeSubscriptionID, Quantity}` and `Coverage.RequiredDevices`/`.Upgrade` are defined in Task 3 and used in Task 4. Proto `SubscriptionUpgrade{StripeSubscriptionId, Quantity}`, `RequiredDevices`, `ProcessStripeWebhookRequest.Quantity`/`.Tiered` are defined in Task 2 and used in Tasks 3 and 6. Perl keys `required_devices`, `max_devices`, `upgrade.stripe_subscription_id`, `upgrade.quantity` come from the proto's snake_case JSON. `upgradeOfferText`, `upgradeButtonName` and `UPGRADE_BUTTON` are defined in Task 15 and used in Task 16.
