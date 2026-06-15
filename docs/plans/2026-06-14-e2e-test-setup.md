# E2E test harness — first-run setup

How to run the Playwright E2E suite (`e2e/`) against the dev site for the first
time. The suite logs in without Auth0 by minting a real session token from the
Go API's dev-only `CreateTestSession` RPC and setting it as the `npuid` cookie.

**Dev only.** The mint RPC refuses to run unless `deployment_mode=devel`, so the
suite cannot be pointed at staging or production.

Related: `docs/plans/2026-06-14-e2e-test-automation-design.md` (design),
`docs/plans/2026-06-14-e2e-test-automation-plan.md` (implementation plan).

## Prerequisites

- The dev site running as usual (DevSpace against the `askntp` namespace on the
  `dala` cluster, reached over Tailscale).
- The Go API serving that environment must include the `CreateTestSession` RPC
  — i.e. it must be running the `e2e-test-session` branch of `../go/ntp/api`
  (commit `feat(auth): add dev-only CreateTestSession RPC for E2E login`).
  Merge/fast-forward it into `main` and redeploy, or point DevSpace at that
  branch. Without it the mint call returns 404.
- The internal Go API reachable over Tailscale (the same internal API the Perl
  `NP::CAPI` layer talks to).

## 1. Provision the test-session key

The harness authenticates to the mint RPC with a service key carrying the
`test-session-api` capability. Create one against the dev PostgreSQL (make sure
`database.yaml` / `DATABASE_URI` points at the dev database the API reads):

```sh
cd ../go/ntp/api
go run . service create e2e-test-session --test-session
```

The output ends with:

```
  Audiences: service-api, test-session-api
API Key (save this - shown only once!):
  npd_...
```

Copy the `npd_…` value — it goes in `NTP_TEST_SESSION_KEY`. It is shown only
once.

## 2. Install the harness

```sh
cd e2e
npm install
npx playwright install chromium
```

## 3. Configure `.env`

```sh
cp .env.example .env
```

Fill in:

- `NTP_BASE_URL` — the dev site, default `https://web.askdev.grundclock.com`.
- `NTP_INTERNAL_API_URL` — the internal Go API base over Tailscale, **including
  the `/int/rpc` prefix** the ConnectRPC services mount under and **no trailing
  slash**, e.g. `http://api-internal.example.ts.net/int/rpc`. The harness
  appends `/ntppool.auth.v1.AuthService/CreateTestSession` to this value.
- `NTP_TEST_SESSION_KEY` — the `npd_…` key from step 1.
- `NTP_TEST_DB_URL` — leave commented out; the read-only DB verification layer
  is deferred and not used by the current specs.

## 4. Run

```sh
npm test            # headless
npm run test:headed # watch it drive the browser
```

Both specs should pass: a freshly minted user reaches `/manage`, and the smoke
pages load without ORM/500 errors.

## Troubleshooting

Work through these in order:

1. **`npx playwright test --list`** — lists the two specs without a live site or
   key. If this fails, the problem is local (install / TypeScript), not the
   environment.

2. **Mint the session directly** to isolate the RPC from the browser:

   ```sh
   curl -sS -X POST \
     "$NTP_INTERNAL_API_URL/ntppool.auth.v1.AuthService/CreateTestSession" \
     -H "Authorization: Bearer $NTP_TEST_SESSION_KEY" \
     -H 'Content-Type: application/json' \
     -d '{"email":"setup-check@example.com","create_if_missing":true}'
   ```

   Expect `{"sessionToken":"nps_…"}`.

   - `404` → `NTP_INTERNAL_API_URL` is missing the `/int/rpc` prefix (or the API
     doesn't have the RPC deployed yet).
   - `permission_denied` → the environment is not `devel`, or the key lacks the
     `test-session-api` audience (re-run step 1 with `--test-session`).
   - connection refused / timeout → not on Tailscale, or wrong internal host.

3. **Login spec fails on the dashboard assertion** — the spec asserts a
   logged-in marker (the sidebar `Logout (email)` link). If the dev theme
   differs, adjust that selector in `e2e/tests/login.spec.ts`, but keep the
   "not a dead-end" intent (don't weaken it to accept the empty/no-invitations
   page).

4. **Cookie not applied (redirected to login despite a 200 mint)** — the cookie
   domain is derived from the `NTP_BASE_URL` hostname. If the dev site sets a
   broader `cookie_domain` (e.g. a parent domain) the test cookie won't match;
   align the cookie domain in `e2e/lib/auth.ts` with the site's configured
   `cookie_domain`.
