import assert from "node:assert/strict";
import test from "node:test";

import {
  requireDevelEnvironmentHeader,
  requireDevelSettings,
} from "./deployment.ts";

test("requireDevelSettings accepts the devel system setting", () => {
  assert.doesNotThrow(() =>
    requireDevelSettings({
      settings: [
        { key: "unrelated", value: "true" },
        { key: "environment", value: '"devel"' },
      ],
    }),
  );
});

for (const environment of ["test", "prod"]) {
  test(`requireDevelSettings rejects ${environment}`, () => {
    assert.throws(
      () =>
        requireDevelSettings({
          settings: [{ key: "environment", value: JSON.stringify(environment) }],
        }),
      /expected devel/,
    );
  });
}

test("requireDevelSettings rejects missing and malformed settings", () => {
  assert.throws(() => requireDevelSettings({ settings: [] }), /missing environment/);
  assert.throws(
    () =>
      requireDevelSettings({
        settings: [{ key: "environment", value: "devel" }],
      }),
    /valid JSON string/,
  );
});

test("requireDevelEnvironmentHeader accepts devel", () => {
  assert.doesNotThrow(() =>
    requireDevelEnvironmentHeader("public web", "https://example.invalid/", "devel"),
  );
});

test("requireDevelEnvironmentHeader rejects missing and non-devel values", () => {
  assert.throws(
    () => requireDevelEnvironmentHeader("public web", "https://example.invalid/", null),
    /missing X-NTPPool-Environment/,
  );
  assert.throws(
    () =>
      requireDevelEnvironmentHeader(
        "manage web",
        "https://example.invalid/manage",
        "prod",
      ),
    /expected devel/,
  );
});
