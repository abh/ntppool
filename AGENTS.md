# AGENTS.md

Shared agent entrypoint for tools that support `AGENTS.md`. In this repository,
the canonical instructions live in `CLAUDE.md` files; this file points agents to
them and highlights the rules that matter most when working here.

## What this repo is

`ntppool` is the NTP Pool Project's web frontend: Perl controllers, Template
Toolkit templates, the Combust web framework, and a TypeScript/Vite frontend
using HTMX and SCSS. Data operations belong in the Go API (`../go/ntp/api`),
accessed through the Perl ConnectRPC clients in `lib/NP/CAPI/`. This repository
has no database handle of its own.

## Instruction loading

1. Read the root `CLAUDE.md` first. It is the authoritative source for the
   project's architecture, conventions, development commands, and repository-wide
   rules.
2. Read `CLAUDE.local.md`, when present, for local checkout paths and development
   environment settings, including the dev site URL and cache-busting guidance.
3. For work in a subtree, read every `CLAUDE.md` on the path from the repository
   root through the target directory, in order from general to specific.
4. More specific `CLAUDE.md` files add to and override rules from their parent
   directories. Do not apply a subtree's instructions to its siblings.
5. For multi-file work, load the applicable instruction stack for each file's
   directory. When exploring before a target is known, start with the root file
   and check for a more specific file as the work narrows.

Current subtree guides cover the frontend (`client/CLAUDE.md`) and ConnectRPC
account-token handling (`lib/NP/CAPI/CLAUDE.md`).

## Rules that matter most here

- **Keep Perl a thin presentation layer.** Use `NP::CAPI` for data operations.
  Business logic, calculations, related writes, and transactional audit logging
  belong in the Go API. One user action should use one API call; use its response
  directly instead of reloading objects or recomputing values the API owns.
- **Preserve CSP compliance.** Put CSS in external SCSS files under
  `client/src/styles/` and JavaScript in external TypeScript/JavaScript files
  under `client/src/`. Never add inline styles, inline scripts, inline event
  handlers, or dynamic style injection, including in templates.
- **Regenerate generated clients.** Do not edit or run `perltidy` on files
  marked `GENERATED CODE - DO NOT EDIT` in `lib/NP/CAPI/`. Change the source or
  generator in the Go API repository and regenerate them.
- **Verify in the appropriate environment.** Use Playwright against the dev
  site to check behavior and layout. Follow `client/CLAUDE.md` for frontend
  checks. We do not normally write Perl unit tests here; coverage for migrated
  logic belongs in the Go API.
- **Respect submodule boundaries.** `combust/` and `docs/shared/static/cdn/`
  are separate repositories. Make their commits within the submodule and be
  explicit about submodule changes and parent pointer updates.
- **Keep formatting and hooks intact.** Follow the root `CLAUDE.md` rules for
  `perltidy`, remove trailing whitespace, and end files with a newline. Never
  use `git commit --no-verify` unless explicitly requested.
- **Use canonical instruction files.** Read files named exactly `CLAUDE.md`
  and the local settings file described above. Ignore backups and conflict
  copies unless explicitly asked to inspect them.

## Other agent files

If a tool also supports another agent file such as `GEMINI.md`, that file should
either repeat these rules or defer to `AGENTS.md`. `CLAUDE.md` remains the
canonical source of project instructions.
