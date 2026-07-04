import { test, expect } from "@playwright/test";

// MANUAL_TEST_PLAN.md §6 — DNS zone generation (Go API), auth-guard portion.
//
// /api/dns-zone (NTPPool::Control::DNSZone->render, apache/sites/ntppool.tmpl)
// is a PUBLIC route on the web host, but requires a service bearer token whose
// who_am_i() resolves to auth_type=service with a "dns"-type service attached
// (see lib/NTPPool/Control/DNSZone.pm). Minting a real "dns" service token
// needs infrastructure-level provisioning that isn't available to this test
// harness (unlike CreateTestSession's dev-only user-session minting), so a
// happy-path zone-JSON check is a manual step — see MANUAL_TEST_PLAN.md §6.
//
// What IS coverable here, and worth covering: the auth guard itself
// (lib/NTPPool/Control/DNSZone.pm:15-37) survived the NP::Model::DnsRoot ->
// NP::DNSZone::Root rename (issue #31, commit c0f15f22) without regressing.
test.describe("DNS zone endpoint auth guard (§6)", () => {
  test("rejects a request with no Authorization header", async ({ page }) => {
    const response = await page.request.get("/api/dns-zone?origin=example.com");
    expect(response.status()).toBe(403);
  });

  test("rejects a request with a malformed Authorization header", async ({
    page,
  }) => {
    const response = await page.request.get(
      "/api/dns-zone?origin=example.com",
      { headers: { Authorization: "not-a-bearer-token" } },
    );
    expect(response.status()).toBe(403);
  });

  test("rejects a request with an invalid bearer token", async ({ page }) => {
    const response = await page.request.get(
      "/api/dns-zone?origin=example.com",
      { headers: { Authorization: "Bearer not-a-real-token" } },
    );
    expect(response.status()).toBe(403);
  });
});
