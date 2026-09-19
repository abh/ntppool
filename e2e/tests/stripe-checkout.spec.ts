import { expect, test, type Page } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { bust, expectCleanPage } from "../lib/helpers";
import {
  createNewZone,
  currentPlanCard,
  expectSubmitted,
  freshZoneData,
  upgradeButtonName,
  upgradeOfferText,
  zonePath,
  zoneUrlParams,
} from "../lib/vendor";
import {
  cancelSubscription,
  getAccountSubscriptions,
  waitForSubscriptionStatus,
} from "../lib/subscriptions";

// A real Stripe Checkout, against the sandbox stripe-gw is configured for.
// MANUAL_TEST_PLAN.md §7. Unlike every other spec this one talks to
// checkout.stripe.com, so it needs outbound internet and is slower.
//
// It checks both halves of the write path. The browser half: Stripe sends the
// vendor back, Perl calls stripe-gw's checkout/complete, and the subscription
// appears with the plan's real name and limits. The webhook half: cancelling
// through `api e2e subscription cancel` writes nothing itself, so the status
// only reaches the database if stripe-gw's webhook works.

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

test.describe("Stripe checkout", () => {
  test.skip(
    !!process.env.NTP_SKIP_STRIPE_CHECKOUT,
    "NTP_SKIP_STRIPE_CHECKOUT is set",
  );

  test("a vendor buys a plan and the webhook reports its cancellation", async ({ page, context }) => {
    // Must exceed the waits this test grants itself — 60s back from Stripe, 15s
    // for the cancel CLI, 60s for the webhook — or the outer timeout fires first
    // and waitForSubscriptionStatus's "check stripe-gw's logs" hint never prints.
    test.setTimeout(180_000);

    const { sessionToken } = await loginAs(context, uniqueTestEmail("stripe-checkout"));

    const zone = freshZoneData("sc"); // 5,000 devices
    const { idToken, accountToken } = zoneUrlParams(await createNewZone(page, zone));

    // 1. Pick a plan that covers 5,000 devices in one zone. The product list
    // is on the zone's show page: show.html PROCESSes products.html when the
    // zone is New and uncovered. /manage/vendor/plan only renders a chosen
    // product (subscription.html is one `[% IF pr %]` block) and is otherwise
    // the checkout return URL.
    await expectCleanPage(page, bust(zonePath(idToken)));
    // products.html renders one <div class="col"> per product, each with a form
    // per available price posting straight to create_session.
    const product = page.locator("div.col").filter({ hasText: "Prototyping & Development" });
    await expect(product, "the sandbox sells a plan for 5,000 devices").toBeVisible();
    const buy = product.locator('form[action*="create_session"] input[type="submit"]').first();
    await Promise.all([page.waitForURL(/checkout\.stripe\.com/), buy.click()]);

    // 2. Stripe's own hosted page.
    await payWithTestCard(page);

    // 3. The browser path wrote the subscription: /manage/vendor's billing block
    // shows what the API stored.
    await expectCleanPage(page, bust("/manage/vendor"));
    const plan = await currentPlanCard(page);
    await expect(plan.locator("b")).toContainText("Prototyping & Development");

    const subs = await getAccountSubscriptions(sessionToken, accountToken);
    expect(subs, "one subscription on the account").toHaveLength(1);
    const sub = subs[0];
    expect(sub.stripeSubscriptionId).toMatch(/^sub_/);
    expect(sub.status).toBe("active");
    expect(sub.live).toBe(true);
    expect(sub.name).toContain("Prototyping & Development");
    expect(sub.maxDevices, "the plan covers the zone's 5,000 devices").toBeGreaterThanOrEqual(5000);

    // The page and the API report the same limits — billing.html reads what the
    // API stored, so this is the one assertion that can catch them disagreeing.
    const limits = plan.locator(".product-details li");
    await expect(limits.nth(0)).toHaveText(`Up to ${sub.maxZones} DNS zones`);
    await expect(limits.nth(1)).toHaveText(
      `Up to ${sub.maxDevices.toLocaleString("en-US")} client devices`,
    );

    // 4. The webhook path: only stripe-gw's webhook can write this.
    const status = await cancelSubscription(sub.stripeSubscriptionId);
    expect(status).toBe("canceled");

    const canceled = await waitForSubscriptionStatus(
      sessionToken,
      accountToken,
      sub.stripeSubscriptionId,
      "canceled",
    );
    expect(canceled.endedOn, "the webhook set ended_on").toBeTruthy();
    expect(canceled.live).toBe(false);
  });

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

    const boughtSubs = await getAccountSubscriptions(sessionToken, accountToken);
    expect(boughtSubs, "one subscription on the account").toHaveLength(1);
    const bought = boughtSubs[0];
    expect(bought.name).toContain("Production");
    expect(bought.maxDevices, "Production's 5,000 tier").toBe(5000);

    // 2. Zone B brings the account to 10,000 devices: a device overage on
    // one tiered subscription, so the page offers the upgrade.
    const second = { ...freshZoneData("sv"), deviceCount: "10000" };
    const { idToken: secondToken } = zoneUrlParams(await createNewZone(page, second));
    await expectCleanPage(page, bust(zonePath(secondToken)));
    await expect(page.getByText(upgradeOfferText(5000, 10000))).toBeVisible();

    // 3. Our offer button opens Stripe's billing portal, preset to 10,000.
    await Promise.all([
      page.waitForURL(/billing\.stripe\.com/),
      page.getByRole("button", { name: upgradeButtonName(10000) }).click(),
    ]);
    // Confirming is on Stripe's page; if it renames that button, this is the
    // line to update.
    await Promise.all([
      page.waitForURL(/\/manage\/vendor\/zone\?/, { timeout: 60_000 }),
      page.getByRole("button", { name: /^Confirm/ }).click(),
    ]);

    // 4. The return synced the subscription, so zone B is covered without
    // waiting for the webhook.
    const upgradedSubs = await getAccountSubscriptions(sessionToken, accountToken);
    expect(upgradedSubs, "still one subscription on the account").toHaveLength(1);
    const upgraded = upgradedSubs[0];
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
});
