This is the website frontend for the NTP Pool Project; the management
system for a global cluster of NTP (time servers) available to internet
users across the world.

The website frontend is written in Perl with Template Toolkit templates.

`CLAUDE.md` in the repository root is the fuller version of this file. Where
the two disagree, `CLAUDE.md` wins.

## Related Codebases

- **ntppool** (this repo) — Perl/Template Toolkit web frontend. It is becoming
  a thin controller layer with no direct database access.
- **Go API** (`../go/ntp/api`) — Go + PostgreSQL backend. All new database
  operations live here, exposed via ConnectRPC and consumed from Perl through
  `lib/NP/CAPI/*.pm`.
- **ntppool-main** (`../ntppool-main`) — the pre-migration Perl/MySQL version,
  kept for reference.

The website is translated to dozens of languages. The HTML translations
are in docs/ntppool/??/ where ?? is the language code. There are PO files
for shorter strings in i18n/??.po.

The system runs in Kubernetes in production and has many dependencies
making it difficult to run partially.

## Development Environment
- Built into Docker containers, executed in Kubernetes
- Uses `Dockerfile.dev` during development
- Uses the most recent released Perl version
- Data lives in PostgreSQL and is reached only through the Go API. This repo
  has no database handle of its own: the Rose::DB layer (`lib/NP/Model*`) was
  removed. MySQL is the old backend and is still what `ntppool-main` uses.

## Project Structure
- `lib/NTPPool/Control.pm` and `lib/NTPPool/Control/*` - Web controllers
- `combust/lib/Combust/` - Internal "Combust" web framework
- `lib/NP/CAPI.pm` and `lib/NP/CAPI/*` - ConnectRPC clients for the Go API.
  The per-service modules are generated from the protos in the Go repo;
  edit the proto and regenerate rather than editing them by hand.
- `docs/ntppool/` - Main website templates
- `docs/manage/` - Management interface templates
- `docs/shared/` - Shared templates and static files (CSS, JS)
- `client/` - Frontend sources (TypeScript, SCSS)
- `i18n/` - PO translation files

## Architecture Guidelines
- **New database functionality**: implement it in the Go API and call it over
  ConnectRPC. There is no direct database access from this repo.
- **API Integration**: use `lib/NP/CAPI/*.pm`. Check what already exists there
  before adding a new integration.
- **Put the logic in Go, not Perl**: one user action is one API call. Perl
  displays what the API returns — it does not filter, sort, recompute, or
  reformat it, and it does not write audit logs for operations the API
  performed. If two pieces of code would have to agree on a derived value,
  that value has one owner, and the owner is the Go API.
- **Never reload after a write**: use the API response data directly. Don't
  re-fetch an object to "refresh" it.
- **Web Framework**: controllers built on the internal "Combust" framework

## Frontend

Content Security Policy is enforced: no inline styles, no inline `<script>`,
no `onclick=` attributes, no dynamic style injection. All CSS belongs in
`client/src/styles/`, all JavaScript in `client/src/`. Inline styles and
scripts are blocked at runtime and the feature breaks silently.

## Code Standards

### Required Before Each Commit
- Run `perltidy` before committing any changes to ensure proper code formatting
- Trim trailing whitespace on all edited lines. End files with a linebreak.

## Testing

Perl unit tests are not used here — the dependencies make them impractical in
this environment. Verify behavior against the dev site instead, and put test
coverage for migrated logic in the Go API, where it belongs with the code.

## Key Guidelines
1. Follow Perl best practices and idiomatic patterns
2. Maintain existing code structure and organization
3. For new database operations, implement via the Go API rather than direct
   database access
4. Follow Combust framework patterns when creating new controllers
5. Return errors rather than falling back to a plan B; don't write code that
   masks a failure
6. The maintainer's email address is ask@develooper.com; this isn't a typo.
