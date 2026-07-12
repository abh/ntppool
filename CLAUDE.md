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

## Technology Stack

- **Language**: Perl (latest released version)
- **Web Framework**: Internal "Combust" framework
- **Templates**: Template Toolkit
- **Database**: MySQL (accessed via internal API service)
- **Database ORM**: Rose::DB
- **Containerization**: Docker/Kubernetes
- **Build System**: ExtUtils::MakeMaker (Makefile.PL)

## Development Commands

### Building and Testing
- `make` - Build the project
- `make test` - Run tests (files in `t/*.t`)
- `make clean` - Clean build artifacts

### Code Formatting (Required Before Commits)
- `perltidy` - Format Perl code (run before committing)

### Docker Development
- Uses `Dockerfile.dev` during development
- Built into Docker containers, executed in Kubernetes

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

#### **CSS and code organization**
- Keep all styling in external SCSS files, never in TypeScript/JavaScript
- Use Bootstrap utility classes where possible (`d-none`, `d-block`, `text-center`, etc.)
- Use SCSS nesting sparingly - prefer flat, specific selectors for maintainability
- Never embed CSS strings in TypeScript files
- Use external event handlers, not inline event attributes
- Web Components should inherit styles from page CSS (not Shadow DOM); use `inherit-styles="true"`
- Keep functions focused and avoid over-engineering with design patterns

#### **Common Anti-Patterns to Avoid**
❌ **Over-Engineering**: Don't create complex class hierarchies, strategy patterns, or factories for simple tasks
❌ **Inline Styles**: Never use `style=""` attributes or `element.style.property = value`
❌ **CSS in JS**: Don't embed CSS template literals in TypeScript files
❌ **Shadow DOM by default**: Use `inherit-styles="true"` for Web Components
❌ Don't use <span>&times;</span> for a "close box".

✅ **Preferred Patterns**: Simple functions, external CSS files, Bootstrap components, inherited styles.
✅ Use playwright to verify site behavior and layout.

#### **HTMX Integration Patterns**
- Use `hx-target` and `hx-swap` for dynamic content updates
- Implement proper error handling with `hx-on` attributes
- Add comprehensive debugging to JavaScript error handlers
- Use Bootstrap classes instead of inline styles for show/hide behavior
- Use compact success indicators (badges) instead of large alerts for HTMX updates
- Implement proper cancel/back flows in forms

#### **Refactoring Guidelines**
When refactoring frontend code:
1. **Start minimal** - make the smallest change that achieves the goal
2. **Preserve working structure** - don't rewrite code that already works well
3. **Measure success by code reduction** - fewer lines is usually better
4. **Avoid architectural complexity** - simple functions over design patterns
5. **CSP compliance first** - move CSS to external files before any other changes

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

- **API Interface (Legacy)**: `lib/NP/IntAPI.pm` (old REST API - being phased out)
- **API Interface (Current)**: `lib/NP/CAPI/*.pm` (new ConnectRPC APIs - use for all new code)
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

**❌ WRONG - Perl Does Multiple API Calls:**
```perl
# DON'T: Orchestrate multiple API calls in Perl
my $server_result = create_server($ip);
my $server_id = $server_result->{data}{server_id};

my $monitors = get_monitors_for_ip_version($ip_version);
for my $monitor (@$monitors) {
    create_server_score($server_id, $monitor->{id});
}

setup_review_schedule($server_id);
```

**✅ RIGHT - Single API Call Does Everything:**
```perl
# DO: Make one API call that handles the complete operation
my $result = add_server(
    auth => $self->plain_cookie($self->user_cookie_name),
    ip => $ip,
    hostname => $hostname,
);
# Server is fully set up with scores and review schedule
my $server = $result->{data}{server};
```

**❌ WRONG - Perl Does Calculations:**
```perl
# DON'T: Process API data in Perl
my $zones_result = list_zones();
my @zones = grep { $_->{dns} } @{$zones_result->{data}{zones}};
@zones = sort { $a->{name} cmp $b->{name} } @zones;
for my $zone (@zones) {
    $zone->{display} = "$zone->{description} ($zone->{server_count} servers)";
}
```

**✅ RIGHT - API Returns Ready-to-Display Data:**
```perl
# DO: Request pre-processed, display-ready data from API
my $result = list_zones(
    dns_only => JSON::XS::true,
    sort_by => 'name',
);
# Zones are filtered, sorted, and have display_name field ready
my $zones = $result->{data}{zones};
# Template uses: [% zone.display_name %]
```

**❌ WRONG - Perl Creates Audit Logs:**
```perl
# DON'T: Make Perl responsible for audit logging
my $result = NP::CAPI::ServerManagement::delete_server(
    ip => $ip,
    deletion_date => $date,
);

# Then separately log the operation (easy to forget!)
NP::Model::Log->log_changes($user, "server-delete", "Deletion scheduled", $server);
```

**✅ RIGHT - API Creates Audit Logs Automatically:**
```perl
# DO: API handles audit logging internally
my $result = NP::CAPI::ServerManagement::delete_server(
    ip => $ip,
    deletion_date => $date,
);
# Audit log created automatically by Go API in same transaction
```

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

**Example Anti-Pattern (WRONG):**
```perl
# API returns minimal data
my $result = create_account(name => "Test");
my $account_id = $result->{data}{account_id};

# This FAILS - trying to reload from MySQL but data is in PostgreSQL
my $account = NP::Model->account->fetch(id => $account_id);  # Returns undef!
```

**Correct Pattern:**
```perl
# API returns complete account data
my $result = create_account(name => "Test");
my $account_data = $result->{data}{account};  # Full account object

# Use data directly from API response
my $account_name = $account_data->{name};
my $account_token = $account_data->{account_token};
```

**Never Recompute in Perl a Value the API Already Owns:**

If two pieces of code must agree on a value, that value has exactly ONE
source: the side that owns the data (the Go API). Perl reuses what the API
returned — it never computes its own copy and hopes the two match.

The trap is subtle because both computations look identical in the source:

**❌ WRONG - Perl recomputes a value the API also computed:**
```perl
# Go API stored users.deletion_on = now() + 7 days  (Go host's clock)
my $result = schedule_user_deletion($self->api_auth_params);

# Perl computes its OWN "7 days from now" for the purge task's execute_on.
# Two clocks, two independent now()s. If Perl's clock lags Go's by even a
# second, the task fires before deletion_on and the purge fails permanently
# (failed tasks are never retried) — silently, after the user was emailed
# "deletion scheduled".
my $task = create_user_task(
    $self->api_auth_params,
    task_type       => 'delete',
    execute_on_unix => DateTime->now->add(days => 7)->epoch,  # <-- drifts from the API's value
);
```

**✅ RIGHT - the API owns the whole operation; Perl makes one call:**
```perl
# schedule_user_deletion() sets deletion_on AND enqueues the purge task in the
# same transaction, both from the single deletionTime it already computed.
# Perl computes no timestamp and cannot drift from the stored value.
my $result = schedule_user_deletion($self->api_auth_params);
```
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

**IMPORTANT - API Migration in Progress:**
- **NEW CODE**: Use `NP::CAPI` modules (ConnectRPC) for all new integrations
- **OLD CODE**: Many existing calls use `int_api()` (REST endpoints) - these are being migrated
- If you find yourself writing `int_api()` calls, you're almost certainly doing it wrong
- Check `lib/NP/CAPI/*.pm` for available ConnectRPC methods before creating new API integrations

- **New database operations**: Implement as API calls to the internal API service, not direct database access
- **API Integration (Legacy)**: `lib/NP/IntAPI.pm` uses old REST endpoints - avoid in new code
- **API Integration (Current)**: `lib/NP/CAPI/*.pm` uses ConnectRPC - use for all new code
- **Database Models**: Built on Rose::DB, but prefer API calls for new features and NEVER reload after API operations

### Legacy REST API Patterns (int_api) - FOR REFERENCE ONLY

**⚠️ DO NOT USE FOR NEW CODE ⚠️** `int_api()` from `NP::IntAPI` is being phased
out in favor of ConnectRPC (`NP::CAPI`). For the legacy parameter conventions
and call-site examples (needed only when reading or migrating old code), load
the `ntppool-api-patterns` skill.

### ConnectRPC API Patterns (NP::CAPI) - USE FOR NEW CODE

**Authentication and Context**:
- ConnectRPC APIs are in `lib/NP/CAPI/*.pm` (e.g., `NP::CAPI::Account`)
- Import specific functions: `use NP::CAPI::Account qw(create_account update_account);`
- Pass authentication and context via named parameters

**Common Parameters**:
- `auth`: User session token via `$self->plain_cookie($self->user_cookie_name)`
- `account`: Account token via `$self->current_account->id_token` (when needed)
- `context`: Request context via `$self->_get_request_context()` (for IP forwarding)

**Response Format**:
All ConnectRPC methods return a hashref:
```perl
{
    code         => 200,                    # HTTP status code
    status_line  => "200 OK",              # HTTP status text
    connect_code => undef,                  # ConnectRPC error code (if error)
    data         => { ... },                # Response data (if success)
    error        => undef,                  # Error message (if error)
    trace_id     => "...",                  # OpenTelemetry trace ID
}
```

**Example - Create Account**:
```perl
use NP::CAPI::Account qw(create_account);

my $result = create_account(
    auth    => $self->plain_cookie($self->user_cookie_name),
    context => $self->_get_request_context(),
    name    => $account_name,
);

if ($result->{error}) {
    warn "Failed to create account: " . $result->{error};
    warn "Trace ID: " . $result->{trace_id};
    return undef;
}

my $account_id = $result->{data}{account_id};
my $account = NP::Model->account->fetch(id => $account_id);
```

**Example - Update Account**:
```perl
use NP::CAPI::Account qw(update_account);

my $result = update_account(
    auth             => $self->plain_cookie($self->user_cookie_name),
    account          => $account->id_token,
    context          => $self->_get_request_context(),
    name             => $new_name,              # Optional fields
    organization_name => $org_name,             # Only send what's changing
    public_profile   => JSON::XS::true,         # Use JSON::XS booleans
);

if ($result->{error}) {
    warn "Update failed: " . $result->{error};
    return $result->{error};
}

# Reload model to get updated values
$account = NP::Model->account->fetch(id => $account->id);
```

**Available APIs**:
- `NP::CAPI::Account` - Account management, user tasks, sessions
- (More to be added as migration continues)

**Error Handling**:
- Always check `$result->{error}` first
- Log trace IDs for debugging: `$result->{trace_id}`
- Reload models after mutations to get fresh data
- Return user-friendly error messages from `$result->{error}` or `$result->{data}{message}`

### API-Driven Feature Integration Patterns

For the full controller-method + template integration example (request-scoped
caching, multi-context queries, graceful degradation), load the
`ntppool-api-patterns` skill.

### Code Standards
- Follow Perl best practices and idiomatic patterns
- Maintain existing code structure and organization
- Write unit tests for new functionality (use table-driven tests when possible)
- Follow Combust framework patterns when creating new controllers
- Trim trailing whitespace on all edited lines and end files with a linebreak

### Request-Scoped Caching Pattern
- Cache expensive operations (API calls, database queries) using `$self->{_cache_key}` pattern
- Check for existence with `exists $self->{_cache_key}` before making calls
- Example: `monitor_eligibility()` and `account_monitor_count()` methods in `lib/NTPPool/Control/Manage.pm`
- Always provide safe defaults when API calls fail to ensure graceful degradation

### Translation System
- Website is translated to dozens of languages
- HTML translations: `docs/ntppool/??/` (where ?? is language code)
- PO files for shorter strings: `i18n/??.po`
- Valid languages defined in `i18n/languages.json`

### Template Toolkit Patterns
- Use conditional logic with `[% IF condition %]...[% ELSIF %]...[% ELSE %]...[% END %]`
- Access controller methods via `combust.method_name` (e.g., `combust.monitor_eligibility`)
- Handle singular/plural text: `[% count == 1 ? "month" : "months" %]`
- Email links: `<a href="mailto:[% "support" | email %]">[% "support" | email %]</a>`
- Alert styling: Use Bootstrap classes like `alert alert-info`, `alert alert-warning`
- Navigation badges: `<span class="badge badge-success">+</span>` for positive indicators

## Development Environment Notes

- System runs in Kubernetes with many dependencies, difficult to run partially
- Uses MySQL database accessed via internal API service
- Development uses Docker containers via `Dockerfile.dev`
- The maintainer's email is ask@develooper.com (not a typo)

## Git Workflow and Commit Guidelines

### Commit Message Conventions
- **CRITICAL**: never use `git commit --no-verify` unless EXPLICITLY requested. We almost always fail commits because of trailing whitespace left in the files.
