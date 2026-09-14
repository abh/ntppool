import { spawn } from "node:child_process";
import { once } from "node:events";
import path from "node:path";

const TIMEOUT_MS = 15_000;
const STDERR_TAIL_LINES = 20;

/**
 * The e2e/ directory. Playwright loads this file as CommonJS, where __dirname
 * is defined; `import.meta` breaks there. Under ESM (node --test, the README
 * cleanup snippet) __dirname is undefined, so those callers pass cwd.
 */
function e2eDir(): string {
  if (typeof __dirname !== "string") {
    throw new Error(
      "runApiCli: __dirname is not defined in this module system; pass the e2e/ directory as cwd",
    );
  }
  return path.resolve(__dirname, "..");
}

/**
 * Run an `api e2e` subcommand through the NTP_API_CLI command prefix, send
 * `request` as JSON on stdin and return the JSON object printed on stdout.
 *
 * NTP_API_CLI is split on whitespace and started without a shell, with `args`
 * appended and the working directory set to e2e/, so relative paths in it
 * work wherever Playwright was started. The child inherits process.env, so a
 * local binary can pick up deployment_mode and DATABASE_URI from e2e/.env.
 *
 * `label` names the call in error messages and `subject` adds what it was
 * about (an email or attempt ID).
 */
export async function runApiCli<T = Record<string, unknown>>(
  label: string,
  args: string[],
  request: unknown,
  subject = "",
  cwd = e2eDir(),
): Promise<T> {
  const prefix = (process.env.NTP_API_CLI ?? "").trim();
  if (!prefix) {
    throw new Error("NTP_API_CLI is not set");
  }
  const [command, ...prefixArgs] = prefix.split(/\s+/);
  const context = `${label}${subject && ` for ${subject}`}`;

  const child = spawn(command, [...prefixArgs, ...args], { cwd });

  // Not spawn's own timeout option: it clears its timer only on "exit", which
  // a command that can't start never emits, so the timer would hold the
  // process open for the full 15 s. "close" waits for stdout and stderr, and a
  // process the command started (a kubectl credential plugin, say) can keep
  // them open after the kill, so the timer closes our ends too.
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    child.kill("SIGKILL");
    child.stdout.destroy();
    child.stderr.destroy();
  }, TIMEOUT_MS);

  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => {
    stdout += chunk;
  });
  child.stderr.on("data", (chunk: string) => {
    stderr += chunk;
  });

  // A child that exits before reading stdin makes this write fail (EPIPE).
  // The exit status below is the useful error then; a write failure only
  // matters if the child still exits 0.
  let stdinError: Error | undefined;
  child.stdin.on("error", (err) => {
    stdinError = err;
  });
  child.stdin.end(JSON.stringify(request));

  // once() rejects when the child emits "error" before "close", which is how
  // a command that can't start (ENOENT, EACCES) is reported.
  const [code, signal] = await once(child, "close")
    .catch((err: Error) => {
      throw new Error(`${context}: could not start NTP_API_CLI command "${command}": ${err.message}`);
    })
    .finally(() => clearTimeout(timer));

  if (timedOut) {
    throw new Error(`${context}: NTP_API_CLI timed out after ${TIMEOUT_MS / 1000}s`);
  }
  if (code !== 0) {
    const tail = stderr.trimEnd().split("\n").slice(-STDERR_TAIL_LINES).join("\n");
    throw new Error(`${context} failed: exit ${code ?? `signal ${signal}`}\n${tail}`);
  }
  if (stdinError) {
    throw new Error(`${context}: writing the request to NTP_API_CLI failed: ${stdinError.message}`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw new Error(`${label} returned malformed JSON`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`${label} returned malformed JSON`);
  }
  return parsed as T;
}
