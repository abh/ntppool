import { connectRpc } from "./auth";
import { runApiCli } from "./apicli";
import { boolField, idField, record, stringField } from "./json";
import { runId } from "./run";

/**
 * One row of SubscriptionService's subscription list. The limits are proto
 * int64s, so ConnectRPC JSON sends them as decimal strings; they are converted
 * once here so callers compare numbers, like `FixtureSubscription` does.
 */
export interface AccountSubscription {
  stripeSubscriptionId: string;
  status: string;
  name: string;
  maxZones: number;
  maxDevices: number;
  live: boolean;
  endedOn?: string;
}

/**
 * Read an account's subscriptions through
 * SubscriptionService.GetAccountSubscriptions. Auth is the user's session
 * token; the account travels in X-Account, as everywhere else.
 */
export async function getAccountSubscriptions(
  sessionToken: string,
  accountToken: string,
): Promise<AccountSubscription[]> {
  const data = record(
    await connectRpc<unknown>(
      "GetAccountSubscriptions",
      "ntppool.subscription.v1.SubscriptionService/GetAccountSubscriptions",
      { Authorization: `Bearer ${sessionToken}`, "X-Account": accountToken },
      {},
      accountToken,
    ),
    "GetAccountSubscriptions response",
  );

  const rows = data.subscriptions;
  if (rows === undefined) return [];
  if (!Array.isArray(rows)) {
    throw new Error("GetAccountSubscriptions subscriptions is malformed");
  }

  return rows.map((row, i) => {
    const label = `subscription ${i}`;
    const sub = record(row, label);
    return {
      stripeSubscriptionId: stringField(sub.stripe_subscription_id, `${label} stripe_subscription_id`),
      status: stringField(sub.status, `${label} status`),
      name: stringField(sub.name, `${label} name`),
      // idField enforces /^\d+$/, so Number() can't produce NaN.
      maxZones: Number(idField(sub.max_zones, `${label} max_zones`)),
      maxDevices: Number(idField(sub.max_devices, `${label} max_devices`)),
      live: boolField(sub.live_subscription, `${label} live_subscription`),
      // Type-checked only: the caller decides whether an end date is expected.
      endedOn:
        sub.ended_on === undefined
          ? undefined
          : stringField(sub.ended_on, `${label} ended_on`, true),
    };
  });
}

/**
 * Cancel a real Stripe subscription through `api e2e subscription cancel`.
 * The command never writes the database: the row changes when stripe-gw
 * delivers the cancellation webhook, which is what the checkout spec waits for.
 */
export async function cancelSubscription(stripeSubscriptionId: string): Promise<string> {
  const raw = record(
    await runApiCli<unknown>(
      "e2e subscription cancel",
      ["e2e", "subscription", "cancel"],
      { run_id: runId(), stripe_subscription_id: stripeSubscriptionId },
      stripeSubscriptionId,
    ),
    "e2e subscription cancel response",
  );
  if (stringField(raw.stripe_subscription_id, "cancel stripe_subscription_id") !== stripeSubscriptionId) {
    throw new Error("cancel response named a different subscription");
  }
  return stringField(raw.stripe_status, "cancel stripe_status");
}

/** Poll until the subscription reaches `status`, or throw when time runs out. */
export async function waitForSubscriptionStatus(
  sessionToken: string,
  accountToken: string,
  stripeSubscriptionId: string,
  status: string,
  timeoutMs = 60_000,
): Promise<AccountSubscription> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const subs = await getAccountSubscriptions(sessionToken, accountToken);
    const sub = subs.find((s) => s.stripeSubscriptionId === stripeSubscriptionId);
    if (sub?.status === status) return sub;
    if (Date.now() >= deadline) {
      throw new Error(
        `${stripeSubscriptionId} was "${sub?.status ?? "none"}" after ${timeoutMs}ms, expected "${status}". ` +
          `The webhook never arrived: check stripe-gw's logs ` +
          `(kubectl --context dala -n askntp logs deploy/stripe-gw).`,
      );
    }
    await new Promise((resolve) => setTimeout(resolve, 2_000));
  }
}
