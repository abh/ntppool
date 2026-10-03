import assert from "node:assert/strict";
import test from "node:test";

import { applyTargetDefaults } from "./target.ts";

test("defaults to stack", () => {
  const env: NodeJS.ProcessEnv = {};
  const target = applyTargetDefaults(env);
  assert.equal(target.name, "stack");
  assert.equal(env.E2E_TARGET, "stack");
  assert.equal(target.contextOptions.ignoreHTTPSErrors, true);
  assert.equal(env.NTP_BASE_URL, "https://web.ntppool.test");
  assert.equal(env.NTP_MANAGE_URL, "https://manage.ntppool.test");
  assert.equal(env.NTP_INTERNAL_API_URL, "http://api:4211/int/rpc");
  assert.equal(env.NTP_API_CLI, "/apibin/api");
  assert.equal(env.NTP_SKIP_STRIPE_CHECKOUT, "1");
});

test("explicit env wins", () => {
  const env: NodeJS.ProcessEnv = {
    NTP_BASE_URL: "https://web.example.org",
    NTP_API_CLI: "/opt/api",
  };
  applyTargetDefaults(env);
  assert.equal(env.NTP_BASE_URL, "https://web.example.org");
  assert.equal(env.NTP_API_CLI, "/opt/api");
  assert.equal(env.NTP_MANAGE_URL, "https://manage.ntppool.test");
});

test("askdev keeps today's values", () => {
  const env: NodeJS.ProcessEnv = { E2E_TARGET: "askdev" };
  const target = applyTargetDefaults(env);
  assert.equal(target.name, "askdev");
  assert.equal(target.contextOptions.ignoreHTTPSErrors, false);
  assert.equal(env.NTP_BASE_URL, "https://web.askdev.grundclock.com");
  assert.equal(env.NTP_MANAGE_URL, "https://manage.askdev.grundclock.com");
  assert.equal(env.NTP_INTERNAL_API_URL, undefined);
  assert.equal(env.NTP_API_CLI, undefined);
  assert.equal(env.NTP_SKIP_STRIPE_CHECKOUT, undefined);
});

test("stripe parameter leaves the checkout spec enabled", () => {
  const env: NodeJS.ProcessEnv = { E2E_STRIPE: "1" };
  applyTargetDefaults(env);
  assert.equal(env.NTP_SKIP_STRIPE_CHECKOUT, undefined);
});

test("unknown target throws naming the allowed values", () => {
  assert.throws(
    () => applyTargetDefaults({ E2E_TARGET: "local" }),
    (err: Error) => /stack/.test(err.message) && /askdev/.test(err.message),
  );
});
