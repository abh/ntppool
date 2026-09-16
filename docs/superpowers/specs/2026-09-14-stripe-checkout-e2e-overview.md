# Real Stripe checkout: what an e2e test would exercise

This is an overview of the actual code path a full-checkout Playwright test
would drive, and what would need to exist for that test to be automatable —
written before any test-writing plan, to settle the shape of the problem
first. Covers `MANUAL_TEST_PLAN.md` §7 ("Stripe-gateway service path works
end to end (checkout → subscription recorded)").

The design that came out of this is
[2026-09-15-stripe-checkout-e2e-design.md](2026-09-15-stripe-checkout-e2e-design.md),
and its plan is `docs/superpowers/plans/2026-09-15-stripe-checkout-e2e.md`.
Every "still to do" item below is settled there.

## Three repos are involved, not two

- **`ntppool`** (this repo, Perl) — `lib/NTPPool/Control/Vendor.pm` and
  `lib/NP/Stripe.pm`. Never talks to Stripe directly.
- **`../go/ntp/stripe-gw`** — a separate first-party Go service (Echo +
  `stripe-go/v74`). This is the only thing that holds real Stripe
  credentials (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`) and the only
  thing that calls Stripe's actual API.
- **`../go/ntp/api`** — the main API. `ProcessStripeWebhook`
  (`server/api/subscription/subscription.go:109`) and
  `CreateOrUpdateSubscription` (`:243`) are the two entry points that
  actually write `account_subscriptions` rows. Neither ever talks to Stripe;
  both take already-parsed fields.

Devel runs a `stripe-gw` instance in the `askntp` namespace, deployed from
`../flux-ntp/askntp/stripe-gw/` (`devtools/restart-stripe-gw` bounces the
pod). It has its own TLS-terminated public ingress for `/webhook`, so Stripe's
real servers can reach it for webhook delivery. The older manifests under
`../ntppool-k8s/devel/stripe/` are a superseded, local-only copy of the same
setup (see open question 1).

## Two independent paths write the same data

This is the part worth designing the test around, not just the happy path:

1. **Synchronous, browser-driven.** After Stripe redirects the browser back
   to the merchant site, `render_subscription` in `Vendor.pm:656-660` sees
   `session_id` on the query string and calls `_update_subscription`
   (`Vendor.pm:559-622`), which:
   - calls stripe-gw's `GET checkout/session_data` (`NP::Stripe::get_session`,
     `Stripe.pm:77-81`) to fetch the completed session's customer/subscription,
   - calls the main API's `create_or_update_subscription` CAPI method
     directly with that data (`Vendor.pm:581-591`),
   - calls `update_account_stripe_customer` if the account had no
     `stripe_customer_id` yet (`Vendor.pm:610-619`).
2. **Asynchronous, webhook-driven.** Stripe also POSTs real webhook events to
   stripe-gw's `POST /webhook` (`stripe-gw/webhook.go:41`), which verifies
   the signature (`webhook.ConstructEvent`, `:60`). `customer.subscription.*`
   (`:90`) and `subscription_schedule.*` (`:106`) events call the main API's
   `ProcessStripeWebhook` (`updateSubscription`, `:134`), which looks the
   account up by `stripe_customer_id`. `checkout.session.completed` is
   received but only logged (`:76-88`; the fulfillment call is commented
   out), so for a new checkout the webhook-side write comes from
   `customer.subscription.created`, not from the checkout event.

   Perl saves the Stripe customer id on the account before redirecting to
   Checkout (step 2 below), so the account lookup should succeed by the time
   that event arrives. If it doesn't, the API answers "account not found"
   (`subscription.go:141`) and stripe-gw returns 200 without asking Stripe to
   retry (`webhook.go:211-217`). That case is a silent miss, not a failure
   anyone would see in Stripe's delivery log.

So a checkout completion is reported **twice**, through two different
services, to the same `CreateOrUpdateSubscription`-shaped write path in the
main API, in no guaranteed order. A test that only drives the browser and
checks the resulting page would never notice if the webhook side silently
broke (e.g. the exact TLS failure noted in the team's own history —
`~/src/emails/business/bug-stripe-webhook-tls-failures.md`, or the
content-type failure described under open question 2). A test that only
fires a synthetic webhook would never notice if the real Checkout page or
`create_session` broke. Getting confidence in "the whole thing works" means
checking both converge on the same state, not just that the browser ends up
on the right page.

## The real click-through, step by step

1. Vendor is on `/manage/vendor/plan` for a zone that needs coverage, picks a
   product/price (`Vendor.pm:676-762`, template `tpl/vendor/subscription.html`).
   This list itself comes from stripe-gw's `GET /api/v1/products`
   (`NP::Stripe::product_groups` → `get_products`, `Stripe.pm:105`), which
   lists active recurring prices from Stripe (`stripe_prices.go:43-47`),
   skips inactive products and anything named `myproduct`
   (`api_products.go:49`, the name `stripe trigger` gives its fixtures), and
   caches the result for 5 minutes. The devel test account has products to
   show (see "What has to exist" below).
2. Submitting goes to `/manage/vendor/plan/create_session?product_id=...&price_id=...`.
   If the account has no `stripe_customer_id` yet, Perl first calls
   stripe-gw's `POST customer/create` (`Vendor.pm:711-719`) and persists the
   returned Stripe customer id via the main API.
3. Perl calls stripe-gw's `POST checkout/create_session`
   (`Vendor.pm:750`, `NP::Stripe::create_session`), passing
   `return_url = /manage/vendor/plan?id=<zone>&a=<account>`. stripe-gw builds
   a real Stripe Checkout Session in **subscription** mode
   (`sessions.go:158-171`: `Mode: "subscription"`) and sets **both**
   `SuccessURL` and `CancelURL` to `return_url + "session_id={CHECKOUT_SESSION_ID}"`
   — Stripe substitutes the real session id into that placeholder itself.
4. Perl redirects the browser to the Checkout Session's real, hosted
   `checkout.stripe.com` URL (`Vendor.pm:757`). This is Stripe's own page, a
   normal top-level navigation (not an iframe the way embedded Stripe
   Elements would be), so Playwright can just fill it in like any other page:
   a test card number, expiry, CVC, and the Subscribe button. Stripe
   publishes fixed test-mode card numbers for this
   (e.g. `4242 4242 4242 4242` for a plain success) — no real card or money
   involved as long as stripe-gw's key is a `sk_test_...` key.
5. Stripe redirects the browser back to the `return_url`, now carrying the
   real `session_id`. Whether this lands as "success" or "cancel" in
   Stripe's UI, it's the *same* URL either way (step 3) — the only signal
   that the subscription actually completed is what `get_session` reports
   about it, not which button was clicked.
6. `render_subscription` → `_update_subscription` runs (path 1 above); in
   parallel, whenever Stripe delivers the `customer.subscription.created`
   webhook to stripe-gw's public endpoint, path 2 runs independently.
7. Observable outcome: `/manage/vendor` shows the zone's coverage as
   "Current plan" instead of "Processing"/no subscription
   (`vendor-coverage.spec.ts` already asserts this UI state, just seeded via
   fixture instead of a real subscription), and the main API's
   `GetAccountSubscriptionStatus` / `GetAccountSubscriptions` report a
   `live_subscription` with the **real** Stripe subscription id — not the
   `e2e_<attemptId>` placeholder the existing fixture writes
   (`e2e/lib/fixtures.ts:214-225`).

## What has to exist before this is automatable

Already in place (checked 2026-09-14):

- **A devel Stripe test-mode account wired into devel's `stripe-gw`.** The
  "NTP Pool Project" sandbox (`acct_103Pmy2ZWuSKvxWM`). Devel's
  `/api/v1/products` returns product ids that exist in that sandbox with
  `livemode: false`.
- **Real test-mode products/prices.** `/api/v1/products?zones=1&quantity=0`
  returns four products, each with a `category` metadata value matching the
  plan page's groups: "Personal NTP Pool DNS Zone" (one annual price),
  "Prototyping & Development" (annual and quarterly), "Production" (annual
  and quarterly, volume tiers) and "Enterprise" (annual, graduated tiers).
  The sandbox also holds about a dozen `myproduct` leftovers from
  `stripe trigger` runs and some archived products; stripe-gw filters both
  out.
- **Webhook delivery.** Registered, enabled and verified end to end; see
  open question 2.

Still to do:

- **Identifiable, cleanable test data on the Stripe side.** Every run creates
  a real Stripe customer + subscription. `e2e/README.md`'s existing
  `E2E_RUN_ID` teardown cleans up the database side, but nothing today tags
  or cancels the Stripe-side objects — worth tagging the Stripe customer
  with the run id in metadata at creation (`customer/create` already takes
  `account_id`/`account_url`, so stripe-gw would need a small change to also
  accept and forward a run tag) and, ideally, cancelling the subscription
  through stripe-gw's own customer-portal or a direct Stripe API call in
  teardown so test subscriptions don't accumulate forever in the test
  dashboard.
- **Network reachability and secrets for the CI/test runner.** This test
  needs the Playwright browser to actually reach `checkout.stripe.com`
  (outbound internet, not just Tailscale to devel) — a different reachability
  requirement than every other spec in `e2e/`, which only talks to the dev
  site and devel's internal API.
- **Tolerance for real third-party latency/flakiness.** Every other test in
  `e2e/` is deterministic against fixtures; this one makes real network calls
  to Stripe on every run. Slower and occasionally flaky by nature — probably
  belongs in its own spec file that's easy to skip/quarantine separately from
  the rest of the suite, not mixed into `vendor-coverage.spec.ts`.

## What "seeing it flow back" should mean, concretely

Given the two-path design above, a real test should check more than "the
zone page says Covered" — it should distinguish which path produced that
state:

- Assert the account's `stripe_customer_id` (from `UpdateAccountStripeCustomer`)
  matches the real customer id stripe-gw created.
- Assert `GetAccountSubscriptions` shows a subscription whose
  `stripe_subscription_id` matches the real Stripe subscription id from the
  Checkout Session (not `e2e_...`), confirming the synchronous browser path
  wrote correctly.
- Separately confirm the webhook path also converges. On the initial
  checkout both paths race to write the same row, so the result alone can't
  show which one did it. Instead, poll for the subscription `status` to
  reflect a webhook-driven update after the initial creation (a plan
  upgrade/downgrade or cancellation only ever arrives via webhook, never
  through the checkout redirect, so exercising *that* is the part the
  synchronous-path check alone can't prove).

## Open questions before writing a test plan

1. **Resolved: test mode, confirmed by a live call.**
   Devel's `stripe-gw` sources its Stripe credentials from Vault at
   `kv/data/ntppool/devel/stripe` (`../flux-ntp/askntp/stripe-gw/config-stripe-gw-local.yaml:39-52`,
   injected as `STRIPE_SECRET_KEY`/`STRIPE_PUBLISHABLE_KEY`/`STRIPE_WEBHOOK_SECRET`)
   — a devel-specific Vault path, separate from whatever production uses, and
   the pod's own `API_URL: http://api-internal/int/rpc` (`:35`) confirms it's
   wired to the **current** Go API, not the retired pre-migration Perl
   `/webhook/stripe` handler.

   `GET /api/v1/products` isn't on the public ingress
   (`config-stripe-gw-local.yaml:16-19` exposes only `/webhook`; the public
   host returns 404 for anything else), and the Pomerium debug host
   `stripe-dev-debug.int.ntp.dev` wasn't reachable from the workstation. The
   Kubernetes API server's service proxy works and needs no `exec`:

   ```sh
   kubectl --context dala get --raw \
     '/api/v1/namespaces/askntp/services/stripe-gw:80/proxy/api/v1/products?zones=1&quantity=0'
   ```

   That returned the four products listed above, with ids matching the
   sandbox the Stripe CLI is logged into (`livemode: false`).
   `kubectl logs` on the pod works the same way and is how the webhook
   history in question 2 was found.

   The running image is `harbor.ntppool.org/ntporg/stripe-gw:sha-1741f621`,
   matching the `appVersion` flux-ntp pins. `stripe-gw` HEAD (`174cc3e`) only
   adds a Go/Alpine bump and a `go.ntppool.org/common` update on top of it,
   with no code changes, so the deployed gateway is current.

   **The legacy manifest:** `../ntppool-k8s/devel/stripe/stripe-gw.yaml`
   targets the same `stripe.askntp.grundclock.com` host with a different
   ingress class, and its `upstream: http://ntppool/webhook/stripe` points at
   the retired Perl handler. It has a Stripe test-mode secret key,
   publishable key and webhook secret in plaintext. `../ntppool-k8s` is a
   local repository that isn't pushed anywhere, so those values haven't left
   this machine. The manifest is superseded by the flux-ntp config and can be
   deleted.

   A related stale comment: `../flux-ntp/ntp-base/stripe-gw/config-stripe-gw-common.yaml:21-28`
   says the binary reads the lowercase `upstream` env var. Nothing in
   `stripe-gw` reads `upstream` anymore; webhooks go to the Go API via
   `API_URL`.

   The `../go/ntp/stripe-gw` `resync-tool` branch (unmerged, 2026-08-17) is
   real but **not a quick answer here**: its `--dsn` flag reads "MySQL DSN for
   ntpdb" (`cmd/resync/main.go`) — it was built against the pre-Postgres-migration
   database and would need updating before it says anything reliable about
   current devel state. It also refuses to run without an explicit `--dsn`
   and Stripe key on the command line (deliberately, no environment
   fallback — see the comment at `cmd/resync/main.go:50-56`), which I didn't
   supply.

2. **Resolved: the webhook endpoint is registered and delivery works, as of
   2026-09-14.** The sandbox has one endpoint, `we_1U4tHA2ZWuSKvxWMIRrCtcQZ`
   ("askdev / devel stripe-gw"), enabled, pointed at
   `https://stripe.askntp.grundclock.com/webhook`, subscribed to
   `checkout.session.completed`, `customer.subscription.*` and
   `subscription_schedule.*` (`stripe webhook_endpoints list`).

   **It had never delivered successfully before 2026-09-14.** The only real
   deliveries in the pod's logs were three attempts of one event,
   `evt_1U5Zd02ZWuSKvxWMY0GpPGg3` (`customer.subscription.created`, from a
   `stripe trigger` run), on 2026-08-17 23:07 UTC (twice) and 2026-08-18
   00:07 UTC. All three got HTTP 500:
   `Go API error ... unknown: Unsupported content type: application/proto`.
   The API's input validation middleware
   (`server/middleware/input_validation.go:133`) was rejecting stripe-gw's
   Connect protobuf requests. API commit `a5a58ed` ("skip input validation
   for ConnectRPC endpoints", 2026-08-17 22:58 PDT) fixed that a few hours
   after the last attempt, but Stripe had stopped retrying and sent nothing
   further, so the fix went unverified. The API currently running on devel
   (`api-dev:sha-cefe995a`) includes it.

   Verified on 2026-09-14 by resending that event:

   ```sh
   stripe events resend evt_1U5Zd02ZWuSKvxWMY0GpPGg3 \
     --webhook-endpoint=we_1U4tHA2ZWuSKvxWMIRrCtcQZ
   ```

   stripe-gw logged `Processing subscription: sub_1U5Zcx2ZWuSKvxWMZsJIFCgb`,
   the API call went through (service-key auth and content type both
   accepted), the API answered "account not found" because the customer is
   a Stripe CLI throwaway with no linked account (so nothing was written),
   stripe-gw returned 200, and the event's `pending_webhooks` dropped to 0.
   That covers Stripe → public ingress → signature check → Stripe
   subscription fetch → Go API. A delivery that actually matches an account
   and writes a row still hasn't happened; the e2e checkout would be the
   first.

   Stripe keeps events retrievable for 30 days, so this event ages out
   around 2026-09-16 and won't be available for a repeat check after that.
   `stripe trigger customer.subscription.created` produces a fresh one.
3. **Resolved:** runs in the normal suite, with a way to skip it (e.g. an env
   var or Playwright tag/`--grep-invert`) given the real-network dependency
   and cost/flakiness concerns above.
4. **Resolved:** yes — tag Stripe-side test customers (via a run-tag param on
   stripe-gw's `customer/create`) so they're identifiable and cleanable,
   same spirit as the DB-side `E2E_RUN_ID` teardown.

   This also surfaced a real product gap, now filed as
   [`ntppool/api#22`](https://gitea.develooper.com/ntppool/api/issues/22):
   nothing today blocks scheduling or purging an account that still has a
   live Stripe subscription (the existing `ScheduleAccountDeletion` /
   `DeleteAccount` blockers cover active servers, vendor zones, and active
   monitors, but not subscriptions), so a deleted account can leave Stripe
   still billing a customer that no longer exists. That's separate from this
   e2e effort but should land before (or alongside) it, since writing this
   test means creating real subscriptions against real accounts.

## Investigation findings

Devel runs a dedicated, Vault-sourced Stripe test-mode credential set, wired
to the current Go API. The deployed stripe-gw is current, the test account
has products the plan page can show, and the webhook endpoint is registered
and delivers end to end. The webhook path was broken from at least
2026-08-17 until API `a5a58ed` shipped, and that went unnoticed because
nothing exercised it, which is the argument for the e2e test checking the
webhook path separately from the browser path.

Two things the test design should account for: stripe-gw ignores
`checkout.session.completed` (the webhook write comes from
`customer.subscription.created`), and an "account not found" answer from the
API gets a 200 with no retry, so a webhook that arrives before the account is
linked is dropped without any visible error.
