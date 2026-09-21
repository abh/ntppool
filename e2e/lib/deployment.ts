interface SystemSetting {
  key: unknown;
  value: unknown;
}

function systemSettings(value: unknown): SystemSetting[] {
  if (typeof value !== "object" || value === null) {
    throw new Error("GetSettings returned a malformed response");
  }
  const settings = (value as { settings?: unknown }).settings;
  if (!Array.isArray(settings)) {
    throw new Error("GetSettings returned a malformed settings list");
  }
  return settings.filter(
    (setting): setting is SystemSetting => typeof setting === "object" && setting !== null,
  );
}

export function requireDevelSettings(response: unknown): void {
  const setting = systemSettings(response).find(({ key }) => key === "environment");
  if (!setting) {
    throw new Error("GetSettings is missing environment");
  }
  if (typeof setting.value !== "string") {
    throw new Error("GetSettings environment must be a valid JSON string");
  }

  let environment: unknown;
  try {
    environment = JSON.parse(setting.value);
  } catch {
    throw new Error("GetSettings environment must be a valid JSON string");
  }
  if (typeof environment !== "string") {
    throw new Error("GetSettings environment must be a valid JSON string");
  }
  if (environment !== "devel") {
    throw new Error(`GetSettings environment=${environment}; expected devel`);
  }
}

export function requireDevelEnvironmentHeader(
  label: string,
  url: string,
  header: string | null,
): void {
  if (!header) {
    throw new Error(`${label} ${url} is missing X-NTPPool-Environment`);
  }
  if (header !== "devel") {
    throw new Error(
      `${label} ${url} has X-NTPPool-Environment=${JSON.stringify(header)}; expected devel`,
    );
  }
}
