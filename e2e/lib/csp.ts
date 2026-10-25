import { expect, type Page } from "@playwright/test";

/**
 * Record Content Security Policy violations on `page` from three sources:
 *
 * - a `securitypolicyviolation` listener on `document`, installed by an init
 *   script and reported back through an exposed binding;
 * - page errors that mention `EvalError` or `Content Security Policy`;
 * - console messages that mention `Content Security Policy`, as a backup.
 *
 * Call it before the first `goto`. The records survive navigations. The
 * returned function gives a snapshot of everything recorded so far.
 */
export async function watchCspViolations(page: Page): Promise<() => string[]> {
  const violations: string[] = [];

  await page.exposeBinding("__cspViolation", (source, report: string) => {
    violations.push(`${source.page.url()}: ${report}`);
  });
  await page.addInitScript(() => {
    document.addEventListener("securitypolicyviolation", (event) => {
      const report = (window as unknown as { __cspViolation: (report: string) => void }).__cspViolation;
      report(
        `${event.violatedDirective} blocked ${event.blockedURI || "(inline)"} ` +
          `at ${event.sourceFile || "(unknown)"}:${event.lineNumber}`,
      );
    });
  });

  page.on("pageerror", (err) => {
    if (err.message.includes("EvalError") || err.message.includes("Content Security Policy")) {
      violations.push(`${page.url()}: pageerror: ${err.message}`);
    }
  });
  page.on("console", (msg) => {
    if (msg.text().includes("Content Security Policy")) {
      violations.push(`${page.url()}: console ${msg.type()}: ${msg.text()}`);
    }
  });

  return () => [...violations];
}

/** Fail the test when `watchCspViolations` recorded anything. */
export function expectNoCspViolations(violations: () => string[]): void {
  expect(violations(), "CSP violations").toEqual([]);
}
