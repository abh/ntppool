# Tiered plan device limits: store what was bought

Date: 2026-09-16
Status: design approved, plan pending
Handoff: `docs/superpowers/handoffs/2026-09-16-tiered-plan-device-limits.md`

Repos and branches:

- stripe-gw: `~/src/go/ntp/stripe-gw`, branch `main`
- api: `~/src/go/ntp/api`, branch `main`
- Perl: `~/src/ntppool`, branch `postgres`

stripe-gw's `go.mod` still has `replace go.ntppool.org/api => ../api` until the
api commit is pushed.

## Problem

A vendor who buys a tiered plan is stored with the plan's highest device count,
not the devices they bought. `limitsForPrice` (stripe-gw `plan_limits.go`) calls
`getTiers(plan, price, 0)` and keeps the highest `MaxClients`. Every Production
subscriber gets `max_devices = 1,000,000` and every Enterprise subscriber would
get 100,000,000. That number is the one `AccountCoverage` enforces
(api `server/api/subscription/coverage.go`), summed across the account's live
subscriptions and compared with all approved zones on the account plus the zone
being submitted.

The plan page already promises the right number. `products.html:56` says
"$X per year for up to `CostDevices` devices", and `CostDevices` is what
`getTiers` works out for the quantity. Only the stored limit disagrees.

## Findings

### Prices

Sandbox and live have the same structure; only the IDs differ.

| Plan | Mode | Tier pricing | Price IDs (sandbox / live) |
|---|---|---|---|
| Personal, Prototyping & Development | flat | n/a, `max_clients` metadata | not affected |
| Production (Annual) | volume | a flat amount per tier, no unit price | `price_1K2Yr92ZWuSKvxWM558s0yM4` / `price_1MmrNQ2ZWuSKvxWMlxRDkkti` |
| Production (Quarterly) | volume | same | `price_1MgPVr2ZWuSKvxWMPE796sD1` / `price_1MmrNQ2ZWuSKvxWMMT2PpsXD` |
| Enterprise | graduated | a flat amount plus a unit price per device | `price_1MmQZP2ZWuSKvxWMo4I79PWE` / `price_1Mmskp2ZWuSKvxWMdwBJvKnd` |

Production's tiers top out at 5,000, 10,000, 25,000, 100,000 and 500,000,
followed by an open-ended tier. Enterprise's top out at 1M, 5M, 30M and 50M,
followed by an open-ended tier. Stripe requires the last tier to be `up_to: inf`;
`getTiers` gives it a device count of twice the tier below
(`api_products.go:259` graduated, `:300` volume), so the table shows 1,000,000
for Production and 100,000,000 for Enterprise.

Product metadata: Production has no `quantity_scale`; Enterprise has
`quantity_scale: 1`. No price uses `transform_quantity`.

### Bug in the open-ended tier

`getTiers` matches a quantity to a tier with `quantity <= t.UpTo`
(`api_products.go:266`, `:307`). For the open-ended tier `UpTo` is 0, so a
quantity above the last finite tier matches nothing: `CostDevices` is 0 and the
plan's cost falls back to the lowest tier's. The plan page shows "up to 0
devices" at the wrong price.

### Production data (read-only report, 2026-09-16)

From live Stripe and production MySQL. Production still runs the MySQL
`v0.9.x` stack, where only the checkout path writes `max_devices`.

- 30 live rows: 17 Production (volume), 13 flat, 0 Enterprise.
- No account would go over its limit under this design. Every account has at
  most one approved zone, none open-source, and every Production quantity
  equals the account's approved device count.
- 13 of the 17 Production rows store 1,000,000. The other 4 already store the
  tier's number, which is what this design computes for them.
- 9 accounts would sit exactly at their limit (their quantity is a tier's top:
  5k, 10k, 25k or 500k); any growth brings the upgrade prompt. The other 8 have
  room from rounding up to a tier.
- 5 rows are live in MySQL but `unpaid` (3) or `canceled` (2) in Stripe. All
  five are in stripe-gw `docs/subscription-repair-2026-09-02.md`.

## Decisions

1. **`max_devices` is what the plan page promises for the quantity bought.**
   For a tier with no unit price, that is the tier's number in stripe-gw's table,
   including the open-ended tier's (1,000,000 on Production). For a tier with a
   unit price, it is the quantity.
2. **Checkout buys what the account needs:** approved devices on the account
   plus the zone being submitted, as computed by the API.
3. **Upgrades go through the Stripe billing portal** with a preset quantity
   (`subscription_update_confirm`). A zone-count overage keeps the email path.
4. **No self-service decreases.** The general billing portal doesn't allow
   quantity changes; decreases go through email.
5. **The API stores what was bought** (quantity, and whether the price is
   tiered) and decides whether an upgrade is offered.
6. **Upgrades charge the prorated difference immediately** (`always_invoice`).
7. **Existing rows get no special migration.** One resync at cutover brings
   them in line.

## Design

### 1. What a quantity buys (stripe-gw)

One function answers "what does quantity Q buy on price P". It finds the tier Q
falls in and returns the device count:

- A tier with no unit price: the table's number for that tier, including the
  open-ended tier's computed number.
- A tier with a unit price: Q.
- The rule is per tier, not per tiers mode.
- A Q above the table's top on a tier with no unit price (1,200,000 on
  Production) gets the table's top (1,000,000). The plan page already marks the
  product unavailable at that size, and `upgrade_session` refuses it.

The tier lookup moves out of `getTiers` into this function, and the open-ended
tier matches any quantity above the tier below it. `getTiers` uses the function
for `CostDevices`, which also fixes the plan page's price and "up to 0 devices"
for quantities in the open-ended tier.

Price validation stays in one place that both the product list and the sync
use, so a price the sync would refuse is not sold. It keeps today's checks
(name, `max_zones`, interval) and adds one: a tiered price with
`quantity_scale` other than 1 or with `transform_quantity` is refused, because
what a quantity buys is then ambiguous.

The sync's device count for a subscription item:

- Flat prices ignore the quantity and keep using `max_clients` metadata.
- Tiered prices use the function above with the item's quantity.
- A tiered item with a quantity below 1 is refused.

`buildWebhookRequest` (`webhook.go:236`) passes `sub.Items.Data[0].Quantity`
and adds two fields to the request: `quantity` (the item quantity) and `tiered`
(the price has a `TiersMode`). The refusals above follow the existing path: the
request still carries status, without name or limits, and the error is logged.

The product's range on the plan page ("Plans with support for up to N devices",
"Only for zones with less than N devices") is unchanged.

### 2. What the API stores and returns

**Migration 031** adds two nullable columns to `account_subscriptions`:
`quantity bigint` and `tiered boolean`. NULL means the row hasn't been synced
since this change (rows carried over from MySQL until the cutover resync).

**`ProcessStripeWebhookRequest`** gets `optional int64 quantity` and
`optional bool tiered`. When any of `name`, `max_zones` or `max_devices` is set,
both new fields must be set, or the API refuses the request
(`subscription.go:161` is where the existing check lives).
`UpsertAccountSubscription` writes them; `UpdateAccountSubscriptionStatus`
leaves them alone. The api and stripe-gw deploy together on devel; this stack
isn't in production, so there is no compatibility period.

**`AccountCoverage`** and **`GetAccountSubscriptionStatusResponse`** gain:

- `required_devices`: approved devices on the account plus the requested
  `device_count`, the number the device check already compares against.
  Returned in every state.
- `upgrade { stripe_subscription_id, quantity }`, set only when:
  - the state is `OVER_LIMIT` because of devices (the zone count fits),
  - the account has exactly one live subscription, and
  - that row has `tiered = true` and a non-NULL `quantity`.

  `quantity` is `required_devices`. With one subscription that is always an
  increase: required devices > `max_devices` >= the quantity bought.

Everything else that is over the limit (zone count, several live subscriptions,
a flat plan, a row not yet resynced) gets no `upgrade` block.

`max_devices` stays summed across live subscriptions. The other readers
(`account/sessions.go:256`, `billing.html`) are unchanged.

`sql/e2e_fixtures.sql` subscription seeding gets the new columns, so e2e can
seed a tiered subscription.

### 3. Checkout and upgrade flow

**Checkout (Perl).** `render_zone` (`Vendor.pm:227`, `:274`) and
`render_subscription` (`:660`, `:686`) use the API's `required_devices` for the
plan picker and as the `create_session` quantity for tiered prices; flat prices
keep quantity 1. `render_subscription` fetches the status for the zone's
account to get it. A tiered checkout without a zone is refused; the picker's
forms always send one.

**Zone page, over the limit** (`show.html:136`). With an `upgrade` block:
"Your plan covers {max_devices} devices; this zone brings the account to
{required_devices}." and a POST button "Update plan to {quantity} devices" to
`/manage/vendor/plan/upgrade`. Without one: today's email text.

**`/manage/vendor/plan/upgrade`** (Perl, POST, `can_edit`, CSRF token). Fetches
the zone and the status again and uses that response's `upgrade` block; the
quantity never comes from the form. If the block is gone, redirect to the zone
page. Otherwise call stripe-gw `POST /api/v1/subscription/upgrade_session` with
the account's `stripe_customer_id`, the subscription id, the quantity, the
return URL (`/manage/vendor/plan/upgraded`) and the zone page URL for cancel,
then redirect to the portal. On a refusal, show the email text.

**stripe-gw `POST /api/v1/subscription/upgrade_session`.** Fetches the
subscription (with price and tiers) and refuses unless:

- the subscription's customer is the one sent,
- the status is `active` or `trialing`,
- it has exactly one item, on a tiered price,
- the new quantity is higher than the item's current quantity, and
- the price's table covers the new quantity.

Then it creates a portal session with the upgrade configuration: flow type
`subscription_update_confirm`, the item id and new quantity,
`after_completion: redirect` to the return URL, and `return_url` set to the
zone page for backing out.

**Return: `/manage/vendor/plan/upgraded`** (Perl). Calls stripe-gw
`POST /api/v1/subscription/sync` with the subscription id and the account's
customer id; stripe-gw checks the subscription belongs to that customer and runs
`syncSubscription`, the same code the webhook uses, so the page doesn't wait on
the webhook. Idempotent with the webhook. Perl then redirects to the zone page.

**Stripe setup, sandbox and live.**

- An upgrade portal configuration: `subscription_update` enabled with
  `default_allowed_updates: [quantity]`, the Production and Enterprise prices
  listed, `proration_behavior: always_invoice`, all other features off. Its ID
  is stored in Vault (`kv/ntppool/{devel,prod}/stripe`) and reaches stripe-gw as
  `STRIPE_UPGRADE_PORTAL_CONFIGURATION`. stripe-gw refuses to start without it,
  like `STRIPE_WEBHOOK_SECRET` (`stripe-gw.go:88`).
- The default portal configuration, used by `billing_portal_url`
  (`Vendor.pm:783`), must not allow quantity changes. Check it; its current live
  setting is unknown.

**Prior art.** stripe-gw branch `subscription-upgrade-wip` (2024-06-24) has a
hardcoded `subscription_update_confirm` prototype. This design replaces it.

### 4. Rollout

Devel and sandbox, in order:

1. **Spike (sandbox).** Create the upgrade configuration and confirm:
   - a quantity-only `subscription_update_confirm` session works with it,
   - with `always_invoice`, a failed payment leaves the quantity (and so the
     limits) unchanged,
   - the default configuration does not allow quantity changes.

   If any of these fails, stop and revisit section 3.
2. Sections 1 and 2 together: stripe-gw limits, api migration, proto, coverage.
   Regenerate and commit generated code (sqlc, buf, and Perl `lib/NP/CAPI` via
   the api's `make generate`).
3. Section 3: stripe-gw `upgrade_session` and `sync`, then Perl checkout,
   upgrade, return and templates.
4. Resync the sandbox subscriptions so devel rows get `quantity` and `tiered`.
5. E2E on devel.

**Resync.** A `resync` mode in stripe-gw runs `syncSubscription` for every
subscription in Stripe. Devel uses it in step 4 and production at cutover.

Production, at the PostgreSQL cutover:

- Create the live upgrade configuration, check the live default configuration,
  store the ID in Vault.
- Rerun the read-only report (`run-tiered-report`, kept untracked next to
  `run-resync` in stripe-gw) with current data.
- Run the resync once after rows migrate. It lowers the rows at 1,000,000 to
  their tier's number and fills `quantity` and `tiered`.
- The resync also corrects the five status-drift rows, and those vendors lose
  coverage for new submits. `subscription-repair-2026-09-02.md` treats that as
  customer-visible, so the resync must not run before that repair is decided.
  Add this ordering to `flux-ntp/docs/plans/stripe-gw-postgres-edition.md`.

## Testing

- **stripe-gw, unit:** table-driven tests of the quantity function against a
  volume price shaped like Production and a graduated price shaped like
  Enterprise, both with an open-ended tier: each tier, tier boundaries, the
  open-ended tier, a quantity above the table's top, and the refusals.
  `buildWebhookRequest` sets `max_devices`, `quantity` and `tiered`.
  `upgrade_session`: one test per refusal. `sync`: refuses a customer mismatch.
- **api, integration:** coverage returns an `upgrade` block for a device
  overage on one tiered subscription, and none for a zone overage, two live
  subscriptions, a flat subscription or a NULL quantity. `required_devices` is
  right in each state. `ProcessStripeWebhook` saves `quantity` and `tiered` and
  refuses limits without them.
- **E2E, devel sandbox:** checkout, over-limit zone, upgrade button, portal
  confirm, return, and a covered submit.

## Out of scope

- Raising `max_zones` or switching plans through the portal. Zone overages and
  over-limit flat plans keep the email path.
- Accounts with more than one live subscription.
- Whether open-source zones should count against paid limits
  (`GetApprovedZoneStats` counts every approved zone).
- Edits to an approved zone's device count.
