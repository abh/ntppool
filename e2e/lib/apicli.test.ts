import assert from "node:assert/strict";
import { realpathSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import { runApiCli } from "./apicli.ts";

// node --test loads these files as ESM, where runApiCli can't find e2e/ from
// __dirname, so every call passes cwd explicitly.
const E2E_DIR = path.resolve(import.meta.dirname, "..");
const FAKE = "lib/testdata/fake-api-cli.mjs";

async function withCli<T>(value: string | undefined, fn: () => Promise<T>): Promise<T> {
  const saved = process.env.NTP_API_CLI;
  if (value === undefined) {
    delete process.env.NTP_API_CLI;
  } else {
    process.env.NTP_API_CLI = value;
  }
  try {
    return await fn();
  } finally {
    if (saved === undefined) {
      delete process.env.NTP_API_CLI;
    } else {
      process.env.NTP_API_CLI = saved;
    }
  }
}

test("runApiCli appends args, sends the request and parses stdout", async () => {
  const result = await withCli(`node ${FAKE} echo`, () =>
    runApiCli("e2e session", ["e2e", "session"], { email: "a@example.com" }, "a@example.com", E2E_DIR),
  );
  assert.deepEqual(result, { args: ["e2e", "session"], request: { email: "a@example.com" } });
});

test("runApiCli reports a non-zero exit with the stderr tail", async () => {
  await withCli(`node ${FAKE} fail`, () =>
    assert.rejects(
      runApiCli("e2e session", ["e2e", "session"], {}, "a@example.com", E2E_DIR),
      (err: Error) => {
        assert.match(err.message, /^e2e session for a@example\.com failed: exit 3/);
        assert.match(err.message, /user already exists/);
        return true;
      },
    ),
  );
});

test("runApiCli rejects malformed stdout", async () => {
  await withCli(`node ${FAKE} malformed`, () =>
    assert.rejects(
      runApiCli("e2e session", ["e2e", "session"], {}, "", E2E_DIR),
      /e2e session returned malformed JSON/,
    ),
  );
});

test("runApiCli requires NTP_API_CLI", async () => {
  for (const value of [undefined, "", "   "]) {
    await withCli(value, () =>
      assert.rejects(runApiCli("e2e session", ["e2e", "session"], {}, "", E2E_DIR), /NTP_API_CLI is not set/),
    );
  }
});

test("runApiCli names NTP_API_CLI when the command can't start", async () => {
  await withCli("./does-not-exist-api e2e", () =>
    assert.rejects(
      runApiCli("e2e session", ["e2e", "session"], {}, "", E2E_DIR),
      /could not start NTP_API_CLI command "\.\/does-not-exist-api"/,
    ),
  );
});

test("runApiCli runs the command in the given directory", async () => {
  // The script path is relative to testdata/, so it only resolves if the
  // child really starts there (this process runs from e2e/).
  const dir = path.join(E2E_DIR, "lib", "testdata");
  const result = await withCli("node fake-api-cli.mjs cwd", () =>
    runApiCli<{ cwd: string }>("e2e session", ["e2e", "session"], {}, "", dir),
  );
  assert.equal(realpathSync(result.cwd), realpathSync(dir));
});
