import { expect, test } from "@playwright/test";
import { loginAs, uniqueTestEmail } from "../lib/auth";
import { bust, expectCleanPage } from "../lib/helpers";
import { createNewZone, currentPlanCard, freshZoneData, zonePath, zoneUrlParams } from "../lib/vendor";
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

    // 2. Stripe's own hosted page. These are Stripe's stable field ids; if it
    // changes them, this is the block to update.
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
});
