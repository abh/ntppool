import { runApiCli } from "./apicli";
import { intField, record, stringField } from "./json";

// Every user the harness creates is tagged with the run ID global setup
// generates (E2E_RUN_ID). Global teardown finishes the run: the API schedules
// those users for deletion and deletes their sessions.

/** The current run's ID. Throws unless global setup started the run. */
export function runId(): string {
  const id = process.env.E2E_RUN_ID;
  if (!id) {
    throw new Error(
      "E2E_RUN_ID is not set; global setup generates it, so start tests with `npx playwright test`",
    );
  }
  return id;
}

export interface FinishedRun {
  flaggedUsers: number;
  alreadyPending: number;
  deletedSessions: number;
}

/** Run `api e2e run finish` for a run and return its counts. */
export async function finishRun(id: string): Promise<FinishedRun> {
  const raw = record(
    await runApiCli<unknown>("e2e run finish", ["e2e", "run", "finish"], { run_id: id }, id),
    "e2e run finish response",
  );
  if (stringField(raw.run_id, "run finish run_id") !== id) {
    throw new Error("run finish response run_id did not match request");
  }
  return {
    flaggedUsers: intField(raw.flagged_users, "run finish flagged_users"),
    alreadyPending: intField(raw.already_pending, "run finish already_pending"),
    deletedSessions: intField(raw.deleted_sessions, "run finish deleted_sessions"),
  };
}
