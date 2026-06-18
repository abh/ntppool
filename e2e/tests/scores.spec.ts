import { test, expect } from "@playwright/test";
import { expectCleanPage, expectNoErrorBleed } from "../lib/helpers";

// MANUAL_TEST_PLAN.md §9 — score graphs / PNG endpoints. These are PUBLIC
// pages: no login / session cookie needed, so this spec does not use loginAs.
//
// Server IP under test. The public scores/graph pages do a CAPI get_server
// lookup and 404 for an unknown IP, so this MUST be a real server that exists
// on the dev site (an RFC 5737 documentation address would just 404). Default
// is Google's public NTP server, which the dev site uses in its own
// cache-busting example (CLAUDE.local.md). The human should set
// NTP_SCORES_TEST_IP to a known-good dev server IP if the default is removed.
const SCORES_IP = process.env.NTP_SCORES_TEST_IP || "216.239.35.4";

test.describe("score graphs / PNG endpoints (§9)", () => {
  test("/scores/<ip> renders the public score page", async ({ page }) => {
    // 200 + no Perl/ORM error bleed. A real server renders its score page.
    await expectCleanPage(page, `/scores/${SCORES_IP}`);
  });

  test("offset.png returns a PNG image", async ({ page }) => {
    // The graph image rendered on /scores/<ip> is served by Graph.pm at
    // /graph/<ip>/offset.png (NP::Data::Server->graph_uri), which returns the
    // bytes directly as image/png. NOTE: the literal path /scores/<ip>/offset.png
    // does NOT serve a PNG — Scores.pm's route captures the mode as "offset"
    // (\w+ stops at the dot) and redirects to /scores/<ip> (the HTML page). The
    // canonical PNG endpoint is /graph/<ip>/offset.png, so that's what we assert.
    const response = await page.request.get(`/graph/${SCORES_IP}/offset.png`);
    expect(
      response.status(),
      `unexpected status for /graph/${SCORES_IP}/offset.png`,
    ).toBe(200);
    expect(
      response.headers()["content-type"],
      "offset.png should be served as image/png",
    ).toContain("image/png");
  });

  test("score.png is normalized away (only offset.png is canonical)", async ({
    page,
  }) => {
    // §9 "score.png requests normalize to offset.png". The only canonical graph
    // PNG is offset.png (NP::Data::Server->graph_uri always emits offset.png);
    // there is no /graph/<ip>/score.png endpoint (it 404s). The "score" form is
    // normalized on the /scores/ path: Scores.pm captures mode "score" and
    // 301-redirects /scores/<ip>/score.png to the canonical /scores/<ip> score
    // page (the legacy numeric /scores/graph/<id>-score.png form likewise
    // redirects to the offset graph). So assert score.png is *handled* — a
    // followed redirect to a clean 200, not a 404 — rather than served as a PNG.
    const response = await page.request.get(`/scores/${SCORES_IP}/score.png`);
    expect(
      response.status(),
      `score.png should be normalized (redirected), not 404`,
    ).toBe(200);
    // It resolves to the HTML score page, not an image.
    expect(
      response.headers()["content-type"] || "",
      "normalized score.png should land on the score page, not an image",
    ).not.toContain("image/png");
  });

  test("legacy /scores/graph/<id>-offset.png redirects to the PNG", async ({
    page,
  }) => {
    // The score page links the legacy graph as /scores/graph/<id>-offset.png;
    // Scores.pm 301-redirects that to /graph/<ip>/offset.png. We can't know the
    // numeric server id from the IP without an API call, so drive it the way the
    // page does. The <img src="...-offset.png"> lives inside <noscript>, so a
    // JS-enabled browser never exposes it in the DOM; the same legacy URL is
    // carried as a data attribute on the real #legacy-graphs element, so read it
    // from there.
    await page.goto(`/scores/${SCORES_IP}`);
    const graphSrc = await page
      .locator("#legacy-graphs")
      .getAttribute("data-offset-graph-url");
    expect(
      graphSrc,
      "score page should expose a legacy offset graph url",
    ).toBeTruthy();
    expect(graphSrc, "legacy graph url should be the -offset.png form").toContain(
      "-offset.png",
    );

    // request.get follows the 301 to /graph/<ip>/offset.png by default.
    const response = await page.request.get(graphSrc!);
    expect(response.status(), `unexpected status for ${graphSrc}`).toBe(200);
    expect(
      response.headers()["content-type"],
      "the linked graph should resolve to image/png",
    ).toContain("image/png");
  });

  test("unmatched / invalid graph path returns 404", async ({ page }) => {
    // §9: an unmatched/legacy graph path must return 404, not a blank/200
    // image. Graph.pm only matches /graph/<ip>/(offset|score).png and returns
    // 404 for any other type. A bogus type is the clearest invalid path.
    const response = await page.request.get(`/graph/${SCORES_IP}/bogus.png`, {
      maxRedirects: 0,
    });
    expect(
      response.status(),
      "an invalid graph type should 404, not serve an image",
    ).toBe(404);
    expect(
      response.headers()["content-type"] || "",
      "a 404 must not return an image body",
    ).not.toContain("image/png");
  });

  test("missing record on the scores page returns a clean 404", async ({
    page,
  }) => {
    // §12a: a public read page that uses capi_error_status should return a
    // clean 404 for a genuinely missing record (an RFC 5737 documentation IP
    // that is not a real server), with no ORM/template error bleed.
    const response = await page.goto("/scores/192.0.2.1", {
      waitUntil: "domcontentloaded",
    });
    expect(response, "no response from /scores/192.0.2.1").not.toBeNull();
    expect(
      response!.status(),
      "a non-existent server should yield 404",
    ).toBe(404);
    await expectNoErrorBleed(page, "/scores/192.0.2.1");
  });
});
