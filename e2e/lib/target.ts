// The e2e target decides every default that depends on where the suite runs:
// the site URLs, the internal API, the API CLI and browser TLS handling.
// E2E_TARGET picks one; explicit NTP_* variables always win over its defaults.

export type TargetName = "stack" | "askdev";

export interface Target {
  name: TargetName;
  contextOptions: { ignoreHTTPSErrors: boolean };
  launchOptions: { args: string[] };
}

// Every page loads two things from the internet: mapper.js from the
// production mapper (`defer`, so DOMContentLoaded waits on it) and web fonts
// from Google (the load event waits on them). From CI either can hang until
// the 30s navigation timeout. Nothing the suite checks depends on them;
// resolving their hosts to nothing makes them fail at once.
const BROWSER_ARGS = [
  "--host-resolver-rules=" +
    "MAP www.mapper.ntppool.org ~NOTFOUND, MAP fonts.gstatic.com ~NOTFOUND",
];

const TARGETS: Record<
  TargetName,
  { defaults: Record<string, string>; ignoreHTTPSErrors: boolean }
> = {
  // The throwaway compose stack (e2e/stack). Caddy serves its own CA.
  stack: {
    defaults: {
      NTP_BASE_URL: "https://web.ntppool.test",
      NTP_MANAGE_URL: "https://manage.ntppool.test",
      NTP_INTERNAL_API_URL: "http://api:4211/int/rpc",
      NTP_API_CLI: "/apibin/api",
    },
    ignoreHTTPSErrors: true,
  },
  // The shared dev site. It has no safe default for the internal API or the
  // API CLI; e2e/.env supplies them.
  askdev: {
    defaults: {
      NTP_BASE_URL: "https://web.askdev.grundclock.com",
      NTP_MANAGE_URL: "https://manage.askdev.grundclock.com",
    },
    ignoreHTTPSErrors: false,
  },
};

function isTargetName(name: string): name is TargetName {
  return Object.hasOwn(TARGETS, name);
}

/**
 * Fill unset NTP_* variables in `env` from the target's defaults, and return
 * the target. E2E_TARGET is written back, so specs can read the resolved
 * name. On the stack, NTP_SKIP_STRIPE_CHECKOUT is also set unless E2E_STRIPE
 * is set. Safe to call more than once.
 */
export function applyTargetDefaults(env: NodeJS.ProcessEnv): Target {
  const name = env.E2E_TARGET || "stack";
  if (!isTargetName(name)) {
    throw new Error(
      `unknown E2E_TARGET "${name}"; expected one of: ${Object.keys(TARGETS).join(", ")}`,
    );
  }
  const target = TARGETS[name];
  env.E2E_TARGET = name;

  for (const [key, value] of Object.entries(target.defaults)) {
    if (!env[key]) {
      env[key] = value;
    }
  }
  if (name === "stack" && !env.E2E_STRIPE && !env.NTP_SKIP_STRIPE_CHECKOUT) {
    env.NTP_SKIP_STRIPE_CHECKOUT = "1";
  }

  return {
    name,
    contextOptions: { ignoreHTTPSErrors: target.ignoreHTTPSErrors },
    launchOptions: { args: BROWSER_ARGS },
  };
}
