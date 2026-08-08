# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The NTP Pool Project is a website frontend for managing a global cluster of NTP time servers. It's written in Perl using Template Toolkit templates and the internal "Combust" web framework. The system runs in Kubernetes in production and has many dependencies.

## Related Codebases

This project spans a few repositories. Paths below assume teammates check them
out as siblings; adjust for your own layout (or note local paths in CLAUDE.local.md).

- **ntppool** (this repo) — Perl/Template Toolkit web frontend. Becoming a thin
  controller layer with no direct database access.
- **Go API** (`../go/ntp/api`) — Go + PostgreSQL backend. All new database
  operations live here, exposed via ConnectRPC (consumed in Perl through
  `lib/NP/CAPI/*.pm`). See its `plans/postgres.md` for migration strategy.
- **ntppool-main** (`../ntppool-main`) — the pre-migration Perl/MySQL version,
  kept for reference and occasional sync of non-migration changes.

## Development Commands

- `perltidy` - Format Perl code (required before committing)

## LLM Coding Agent Guidelines

### Working with Git Submodules
This repository contains submodules (notably `combust/`):
- Check if you're working within a submodule directory by examining file paths
- If changes are in a submodule (e.g., `combust/lib/...`), navigate to the submodule directory before committing
- Use `cd <submodule-name> && git add <files> && git commit` for submodule commits
- Be explicit about whether you're committing to the submodule or parent repository

### Frontend Development Guidelines

#### **Critical: Content Security Policy (CSP) Compliance**
**ABSOLUTE RULE - NO EXCEPTIONS:**
- **NEVER create inline styles** (e.g., `style="background-color: red;"` or `element.style.backgroundColor = 'red'`)
- **NEVER create inline JavaScript** (e.g., `onclick="doSomething()"` or inline `<script>` tags)
- **NEVER use `document.createElement('style')` or dynamic style injection**
- **ALL CSS must be in external .scss files in `client/src/styles/`**
- **ALL JavaScript must be in external .ts/.js files in `client/src/`**

CSP policies WILL block any inline styles or scripts, causing features to break silently. This rule is non-negotiable for security and functionality.

Use playwright to verify site behavior and layout.

`client/CLAUDE.md` covers the rest of the frontend conventions (SCSS
organization, Web Components, HTMX patterns, anti-patterns, refactoring) and
loads automatically when working under `client/`.

### API Integration and Cross-Language Compatibility

**Data Type Handling**:
- When sending JSON to APIs, ensure proper data types:
  - Use `JSON::XS::true`/`JSON::XS::false` for boolean values, not 1/0
  - Force numeric context with `0 + int($value)` to ensure integers aren't encoded as strings
  - Check API documentation/code for expected field names and types

**API Debugging Process**:
1. Add comprehensive logging for data being sent to APIs
2. Log both the Perl data structure and final JSON string
3. Compare expected vs actual API request format
4. Add error handling that extracts and displays trace IDs from response headers

**Cross-Language Integration**:
- Always verify field names match between frontend forms and backend API structs
- Handle checkbox form submission properly (unchecked checkboxes send no value)
- Account for different boolean representations across languages

## Project Architecture

- **API Interface**: `lib/NP/CAPI/*.pm` (ConnectRPC APIs - use for all new code)
- New database functionality should use ConnectRPC API calls via `lib/NP/CAPI/*.pm`; models use Rose::DB but prefer API calls for new features.

## Architecture Guidelines

### Database and API

**CRITICAL - PostgreSQL Migration in Progress:**

Read [../go/ntp/api/plans/postgres.md](../go/ntp/api/plans/postgres.md) for complete migration strategy.

**Architecture Goal**: This Perl codebase is becoming a **thin web controller layer with NO direct database access**. All data operations go through Go APIs.

**During Migration (Current State):**
- **Split-Brain Scenario**: Go API writes to PostgreSQL, Perl ORM (`NP::Model`) reads from MySQL
- **NEVER Use `NP::Model->fetch()` After API Calls**: Data written by Go won't exist in MySQL
- **API Responses Must Be Complete**: Don't rely on database reloads for "fresh" data

**Migration Rules for AI Agents:**
1. ✅ **DO**: Use API response data directly without database access
2. ✅ **DO**: Work with IDs and tokens from API responses
3. ✅ **DO**: Request complete data from APIs (not minimal responses)
4. ❌ **DON'T**: Add `NP::Model->fetch()` calls after API operations
5. ❌ **DON'T**: Reload objects to "refresh" data after API calls
6. ❌ **DON'T**: Query MySQL database for data that was just created/updated in PostgreSQL

### API Design Principles

**The Go API Should Do the Work, Not Perl:**

When migrating Perl code to use APIs, move logic to the Go API layer. Perl should be a thin presentation layer that displays data, not a computation layer.

Three rules follow from that. Worked ❌/✅ code for each is in the
`ntppool-api-patterns` skill:

1. **One user action = one API call.** Don't orchestrate several API calls in
   Perl to complete a single operation.
2. **Perl does not calculate.** Don't filter, sort, or format API data in Perl —
   request it pre-processed and display-ready.
3. **The API writes its own audit logs**, in the same transaction as the change.
   Perl never logs an operation it just asked the API to perform.

**Why This Matters:**
- Audit logs are created atomically with data changes
- Can't forget to log operations (happens automatically)
- Consistent audit messages across all operations
- Perl doesn't need database access for logging
- Works correctly during PostgreSQL migration (logs to PostgreSQL)

**When Migrating Code:**
1. **Identify the User Operation**: What is the user trying to accomplish?
2. **Move All Related Logic to Go**: Don't split logic between Perl and Go (including audit logging)
3. **Return Complete Data**: Include all fields Perl will need for display
4. **Pre-format Display Strings**: Don't make Perl concatenate or calculate
5. **Single API Call**: One user action = one API call (with automatic logging)

**Never Recompute in Perl a Value the API Already Owns:**

If two pieces of code must agree on a value, that value has exactly ONE
source: the side that owns the data (the Go API). Perl reuses what the API
returned — it never computes its own copy and hopes the two match.

The trap is subtle because both computations look identical in the source. The
canonical case: the Go API stores `users.deletion_on = now() + 7 days` from its
own clock, and Perl computes its own "7 days from now" for the purge task's
`execute_on`. Two clocks, two independent `now()`s — if Perl's lags by even a
second the task fires before `deletion_on` and the purge fails permanently
(failed tasks are never retried), silently, after the user was already emailed
"deletion scheduled". The ❌/✅ code is in the `ntppool-api-patterns` skill.

If the operation needs a follow-on record (a queued task, an audit row, a
child object), the API creates it in the same transaction — one user action,
one API call. Don't have Perl issue a second call to stitch on the follow-up.

**Stop-and-rethink signal (this is what wastes the most time):** if you find
yourself reasoning about whether two independently-derived values will stay in
sync — clocks, generated IDs, ordering, rounding, "7 days" written in two
places — the design is wrong, not the details. Don't tune the Perl side to
agree more reliably (pass the value through, add a fudge margin, etc.). Move
the computation to its single owner in Go so there is nothing to keep in sync.
A patch that makes two sources agree "closely enough" is still the wrong layer.

**IMPORTANT - API Integration:**
- Use `NP::CAPI` modules (ConnectRPC) for all API integrations
- Check `lib/NP/CAPI/*.pm` for available ConnectRPC methods before creating new API integrations

- **New database operations**: Implement as API calls to the internal API service, not direct database access
- **API Integration**: `lib/NP/CAPI/*.pm` uses ConnectRPC - use for all new code
- **Database Models**: Built on Rose::DB, but prefer API calls for new features and NEVER reload after API operations

### ConnectRPC API Patterns (NP::CAPI) - USE FOR NEW CODE

**Authentication and Context**:
- ConnectRPC APIs are in `lib/NP/CAPI/*.pm` (e.g., `NP::CAPI::Account`)
- Import specific functions: `use NP::CAPI::Account qw(create_account update_account);`
- Pass authentication and context via named parameters

**Common Parameters**:
- `auth`: User session token via `$self->plain_cookie($self->user_cookie_name)`
- `account`: Account token via `$self->current_account->id_token` (when needed)
- `context`: Request context via `$self->_get_request_context()` (for IP forwarding)

Every method returns a hashref; see `lib/NP/CAPI.pm` for the exact shape.

**Error Handling**:
- Always check `$result->{error}` first
- Log trace IDs for debugging: `$result->{trace_id}`
- Use the API response data directly — never reload from the ORM afterwards
- Return user-friendly error messages from `$result->{error}` or `$result->{data}{message}`

### API-Driven Feature Integration Patterns

For the full controller-method + template integration example (request-scoped
caching, multi-context queries, graceful degradation), load the
`ntppool-api-patterns` skill.

### Code Standards
- We do not normally write Perl unit tests — they don't work well in this
  environment. Verify behavior against the dev site instead (see
  `CLAUDE.local.md`). Test coverage for migrated logic belongs in the Go API.
- Trim trailing whitespace on all edited lines and end files with a linebreak

### Request-Scoped Caching Pattern
- Cache expensive operations (API calls, database queries) using `$self->{_cache_key}` pattern
- Check for existence with `exists $self->{_cache_key}` before making calls
- Example: `monitor_eligibility()` and `account_monitor_count()` methods in `lib/NTPPool/Control/Manage.pm`
- On API failure, degrade the *display* gracefully (hide the feature); never
  swallow the error — log it and surface it upstream

### Translation System
- Website is translated to dozens of languages
- HTML translations: `docs/ntppool/??/` (where ?? is language code)
- PO files for shorter strings: `i18n/??.po`
- Valid languages defined in `i18n/languages.json`

### Template Toolkit Patterns
- Access controller methods via `combust.method_name` (e.g., `combust.monitor_eligibility`)
- Email links: `<a href="mailto:[% "support" | email %]">[% "support" | email %]</a>`

## Development Environment Notes

- System runs in Kubernetes with many dependencies, difficult to run partially
- The maintainer's email is ask@develooper.com (not a typo)

## Git Workflow and Commit Guidelines

### Commit Message Conventions
- **CRITICAL**: never use `git commit --no-verify` unless EXPLICITLY requested. We almost always fail commits because of trailing whitespace left in the files.
