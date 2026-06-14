import { Page, expect } from "@playwright/test";

/**
 * Visit a page and assert it loaded cleanly: HTTP 200, no Perl/ORM error bleed,
 * no obvious server error. Returns the navigation response for further checks.
 *
 * A fresh account has no servers/zones, so callers should tolerate
 * empty-but-valid pages rather than requiring data.
 */
export async function expectCleanPage(page: Page, path: string) {
  const response = await page.goto(path);
  expect(response, `no response from ${path}`).not.toBeNull();
  expect(response!.status(), `unexpected status for ${path}`).toBe(200);
  await expectNoErrorBleed(page, path);
  return response!;
}

/**
 * Assert the current page body shows no Perl/ORM error leakage. Use after a
 * navigation when you've already checked (or deliberately don't care about) the
 * HTTP status.
 */
export async function expectNoErrorBleed(page: Page, label = page.url()) {
  const body = await page.content();
  expect(body, `Rose::DB / ORM error leaked on ${label}`).not.toContain(
    "NP::Model::",
  );
  expect(body, `Perl 'Can't locate' error on ${label}`).not.toContain(
    "Can't locate",
  );
  // Unrendered Template Toolkit directives indicate a broken template render.
  expect(body, `unrendered template directive on ${label}`).not.toContain(
    "[% ",
  );
}

/**
 * Extract a rendered "Trace ID: <hex>" value from an error alert, if present.
 * Error pages surface the OpenTelemetry trace id alongside the message
 * (see CLAUDE.md error-surfacing patterns). Returns null when none is shown.
 */
export async function getTraceId(page: Page): Promise<string | null> {
  const body = await page.content();
  const match = body.match(/Trace ID:\s*([0-9a-f]+)/i);
  return match ? match[1] : null;
}

/**
 * Assert an error alert is visible. When `requireTraceId` is true, also assert a
 * Trace ID is rendered with it (the project convention for surfaced API errors).
 */
export async function expectErrorAlert(
  page: Page,
  opts: { requireTraceId?: boolean } = {},
) {
  const alert = page.locator(".alert-danger, .alert-warning").first();
  await expect(alert, "expected a visible error alert").toBeVisible();
  if (opts.requireTraceId) {
    const traceId = await getTraceId(page);
    expect(traceId, "error alert should include a Trace ID").not.toBeNull();
  }
}
