// Validators for JSON the harness reads from the API and the `api e2e`
// commands. Each throws with `label` when a field is missing or has the wrong
// type, so a response shape change fails where it is read.

export type JsonRecord = Record<string, unknown>;

export function record(value: unknown, label: string): JsonRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value as JsonRecord;
}

export function stringField(value: unknown, label: string, allowEmpty = false): string {
  if (typeof value !== "string" || (!allowEmpty && value.length === 0)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value;
}

export function idField(value: unknown, label: string): string {
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value;
}

export function intField(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new Error(`${label} is missing or malformed`);
  }
  return value;
}

export function boolField(value: unknown, label: string, omittedDefault = false): boolean {
  if (value === undefined) return omittedDefault;
  if (typeof value !== "boolean") throw new Error(`${label} is malformed`);
  return value;
}
