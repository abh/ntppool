import { expect, type Page } from "@playwright/test";

/**
 * Record CSP violations on `page` across navigations: `securitypolicyviolation`
 * events, htmx's `htmx:evalDisallowedError` (allowEval is off, so an hx-on or
 * js: expression is skipped without a CSP event), and page errors and console
 * messages that mention the CSP. Call it before the first `goto`.
 */
export async function watchCspViolations(page: Page): Promise<() => string[]> {
  const violations: string[] = [];

  await page.exposeBinding("__cspViolation", (source, report: string) => {
    violations.push(`${source.page.url()}: ${report}`);
  });
  await page.addInitScript(() => {
    const report = (text: string) =>
      (window as unknown as { __cspViolation: (report: string) => void }).__cspViolation(text);
    document.addEventListener("securitypolicyviolation", (event) => {
      report(
        `${event.violatedDirective} blocked ${event.blockedURI || "(inline)"} ` +
          `at ${event.sourceFile || "(unknown)"}:${event.lineNumber}`,
      );
    });
    document.addEventListener("htmx:evalDisallowedError", (event) => {
      const elt = event.target instanceof Element ? event.target.outerHTML.slice(0, 200) : "(unknown)";
      report(`htmx:evalDisallowedError on ${elt}`);
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

/**
 * Fail when `watchCspViolations` recorded anything. The evaluate round trip
 * comes back after any binding calls the page already sent, so a violation
 * from the last click is counted.
 */
export async function expectNoCspViolations(page: Page, violations: () => string[]): Promise<void> {
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0))));
  expect(violations(), "CSP violations").toEqual([]);
}
