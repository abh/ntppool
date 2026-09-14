import "dotenv/config";
import { finishRun } from "./lib/run";

// Finish the run global setup started: the API schedules every user the run
// created for deletion and deletes their sessions, so the session cookies in
// trace zips stop working. Playwright registers global teardown ahead of
// global setup, so this also runs after a failed setup and after the first
// Ctrl-C.
export default async function globalTeardown() {
  const id = process.env.E2E_RUN_ID;
  if (!id) {
    // Setup stopped before it generated a run ID, so nothing was minted.
    return;
  }
  const run = await finishRun(id);
  // UI mode and the VS Code extension run teardown and then setup again in
  // the same process; clear the finished ID so that setup starts a new run
  // instead of refusing an "inherited" one.
  delete process.env.E2E_RUN_ID;
  console.log(
    `e2e run ${id} finished: flagged_users=${run.flaggedUsers} ` +
      `already_pending=${run.alreadyPending} deleted_sessions=${run.deletedSessions}`,
  );
}
