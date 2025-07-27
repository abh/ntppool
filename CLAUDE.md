# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The NTP Pool Project is a website frontend for managing a global cluster of NTP time servers. It's written in Perl using Template Toolkit templates and the internal "Combust" web framework. The system runs in Kubernetes in production and has many dependencies.

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

### CRITICAL: Content Security Policy (CSP) Compliance
**ABSOLUTE RULE - NO EXCEPTIONS:**
- **NEVER create inline styles** (e.g., `style="background-color: red;"` or `element.style.backgroundColor = 'red'`)
- **NEVER create inline JavaScript** (e.g., `onclick="doSomething()"` or inline `<script>` tags)
- **NEVER use `document.createElement('style')` or dynamic style injection**
- **ALL CSS must be in external .scss files in `src/styles/`**
- **ALL JavaScript must be in external .ts/.js files**

CSP policies WILL block any inline styles or scripts, causing features to break silently. This rule is non-negotiable for security and functionality.

### Project-Specific Context Usage
When working with this codebase:
- Actively reference the technology stack, patterns, and conventions defined above
- Use project-defined development commands (make, perltidy) before generic alternatives
- Follow architectural guidelines (prefer API calls via `lib/NP/IntAPI.pm` over direct DB access)
- Prioritize project documentation over general assumptions about frameworks or tools

### Working with Git Submodules
This repository contains submodules (notably `combust/`):
- Check if you're working within a submodule directory by examining file paths
- If changes are in a submodule (e.g., `combust/lib/...`), navigate to the submodule directory before committing
- Use `cd <submodule-name> && git add <files> && git commit` for submodule commits
- Be explicit about whether you're committing to the submodule or parent repository

### Enhanced Git Commit Workflow
Before creating commits:
1. **Parallel Information Gathering**: ALWAYS run the following bash commands in parallel using multiple tool calls in a single message:
   - `git status` to see all untracked files and modifications
   - `git diff` to see both staged and unstaged changes
   - `git log --oneline -5` to see recent commit messages for style consistency
2. **Comprehensive Analysis**: Analyze all staged changes (both previously staged and newly added) and draft a commit message that:
   - Accurately reflects the nature of changes (add/update/fix/refactor)
   - Focuses on the "why" rather than the "what"
   - Follows the project's commit message style
3. **Parallel Commit Execution**: Run the following commands in parallel:
   - Add relevant untracked files to staging
   - Create the commit with message using HEREDOC format
   - Run git status to confirm success
4. If the commit fails due to pre-commit hook changes, retry the commit ONCE to include these automated changes. If it fails again, it usually means a pre-commit hook is preventing the commit. If the commit succeeds but you notice that files were modified by the pre-commit hook, you MUST amend your commit to include them.

Important notes:
- NEVER update the git config
- NEVER run additional commands to read or explore code, besides git bash commands
- NEVER use the TodoWrite or Task tools during git operations
- DO NOT push to the remote repository unless the user explicitly asks you to do so
- IMPORTANT: Never use git commands with the -i flag (like git rebase -i or git add -i) since they require interactive input which is not supported.
- If there are no changes to commit (i.e., no untracked files and no modifications), do not create an empty commit
- In order to ensure good formatting, ALWAYS pass the commit message via a HEREDOC, a la this example:
```bash
git commit -m "$(cat <<'EOF'
   Commit message here.
   EOF
   )"
```

### Proactive Todo Management
Use TodoWrite/TodoRead tools extensively for:

**When to Use (REQUIRED)**:
- Multi-step tasks requiring 3+ distinct operations
- Complex features with multiple components
- When user provides multiple tasks (numbered or comma-separated)
- Immediately after receiving new instructions to capture requirements
- Before starting work on any task (mark as in_progress)
- Immediately after completing each task (mark as completed)

**Best Practices**:
- Break complex tasks into specific, actionable items
- Only mark ONE task as in_progress at a time
- Mark tasks completed IMMEDIATELY when finished (don't batch)
- Create new tasks when discovering additional work during implementation
- Use clear, descriptive task names that indicate specific outcomes
- Remove tasks that become irrelevant rather than leaving them pending

**Task States**:
- pending: Not yet started
- in_progress: Currently working (limit to ONE)
- completed: Fully accomplished with no errors or blockers

### Parallel Tool Execution Best Practices

**When to Use Parallel Tool Calls (REQUIRED)**:
- Git operations: Always run `git status`, `git diff`, `git log` concurrently
- Information gathering: Batch multiple Read, Grep, or Glob operations
- API analysis: Run concurrent searches when exploring codebases
- Code exploration: Use multiple search operations simultaneously rather than sequentially

**Performance Optimization**:
- Batch independent information requests in single messages
- Use concurrent Read calls when examining multiple related files
- Combine Grep/Glob searches when looking for patterns across the codebase
- Execute parallel Bash commands for independent operations

**Implementation Pattern**:
Send single messages with multiple tool invocations rather than sequential requests

### Frontend Development Guidelines

#### **Critical: Content Security Policy (CSP) Compliance**
**ABSOLUTE RULE - NO EXCEPTIONS:**
- **NEVER create inline styles** (e.g., `style="background-color: red;"` or `element.style.backgroundColor = 'red'`)
- **NEVER create inline JavaScript** (e.g., `onclick="doSomething()"` or inline `<script>` tags)
- **NEVER use `document.createElement('style')` or dynamic style injection**
- **ALL CSS must be in external .scss files in `client/src/styles/`**
- **ALL JavaScript must be in external .ts/.js files in `client/src/`**

CSP policies WILL block any inline styles or scripts, causing features to break silently. This rule is non-negotiable for security and functionality.

#### **CSS and SCSS Architecture**
- **Main stylesheet**: `client/src/styles/_components.scss` - contains all custom component styles
- **Bootstrap integration**: `client/src/styles/bootstrap.scss` - imports and configures Bootstrap
- **Variables**: `client/src/styles/_variables.scss` - CSS custom properties and SCSS variables
- **Build process**: Vite processes SCSS files and outputs to `docs/shared/static/build/`

**CSS Organization Rules**:
- Keep all styling in external SCSS files, never in TypeScript/JavaScript
- Use Bootstrap utility classes where possible (`d-none`, `d-block`, `text-center`, etc.)
- Group related styles together with clear section comments
- Use SCSS nesting sparingly - prefer flat, specific selectors for maintainability

#### **TypeScript/JavaScript Architecture**
- **Main entry**: `client/src/main.ts` - application initialization and Bootstrap imports
- **Components**: `client/src/components/` - Web Components for charts and interactive elements
- **Charts**: `client/src/charts/` - D3.js chart implementations
- **Utils**: `client/src/utils/` - shared utility functions
- **Types**: `client/src/types/` - TypeScript type definitions

**Code Organization Rules**:
- Never embed CSS strings in TypeScript files
- Use external event handlers, not inline event attributes
- Web Components should inherit styles from page CSS (not Shadow DOM)
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

### Error Handling and Debugging Patterns

**Systematic Debugging Approach**:
1. **Add Comprehensive Logging**: Use warn statements to track data flow through the system
2. **Data Structure Inspection**: Use `Data::Dump::pp()` to examine complex data structures
3. **API Communication**: Log both request data and response details including headers
4. **Type Verification**: Check data types (ref(), typeof) when debugging serialization issues

**Common Debugging Techniques**:
- Add console.log debugging to JavaScript for client-side troubleshooting
- Log all HTTP headers when debugging API responses (especially TraceID extraction)
- Use template debugging with `[% USE Dumper; Dumper.dump_html(data) %]` sparingly
- Add form parameter logging to understand what data is being submitted

**Error Resolution Process**:
1. Identify the exact error message and trace ID
2. Add logging at each step of the data flow
3. Compare expected vs actual data formats
4. Check API documentation for correct field names and types
5. Verify data type encoding (strings vs numbers vs booleans)

## Project Architecture

### Core Structure
- **Web Controllers**: `lib/NTPPool/Control.pm` and `lib/NTPPool/Control/*`
- **Web Framework**: `combust/lib/Combust/` (internal framework)
- **API Interface**: `lib/NP/IntAPI.pm` (for internal API calls)
- **Database Models**: `lib/NP/Model.pm` and `lib/NP/Model/*` (Rose::DB based)
- **Main Templates**: `docs/ntppool/` (website templates)
- **Management Interface**: `docs/manage/` (admin interface templates)
- **Shared Resources**: `docs/shared/` (templates, CSS, JS)
- **Translations**: `i18n/` (PO files), `docs/ntppool/??/` (HTML translations)

### Key Components
- Controllers are built on Combust framework patterns
- New database functionality should use API calls via `lib/NP/IntAPI.pm`
- Database models use Rose::DB but prefer API calls for new features
- Supports dozens of languages with translations in `i18n/` and `docs/ntppool/`

## Architecture Guidelines

### Database and API
- **New database operations**: Implement as API calls to the internal API service, not direct database access
- **API Integration**: Use `lib/NP/IntAPI.pm` for communication with the separate API service
- **Database Models**: Built on Rose::DB, but prefer API calls for new features

### Internal API Integration Patterns

**Authentication and Account Context**:
- Use `int_api()` function from `NP::IntAPI` for internal API calls
- **ALWAYS use `user` parameter**: Pass user cookie via `$self->plain_cookie($self->user_cookie_name)`
- **Account context via `a` parameter**: Pass account token via `$self->current_account->id_token`

**Parameter Naming Conventions (CRITICAL)**:
- **`a`**: Account token (e.g., "21wase0") - used for authentication AND account scoping
- **`user`**: User cookie for authentication
- **`names`**: Monitor TLS names (comma-separated) - NOT "monitor_ids"
- **`account_id`**: AVOID - use `a` parameter with account token instead
- **`all_accounts`**: Boolean flag for admin queries across all accounts

**Common Parameter Patterns**:
```perl
# Account-scoped query (most common)
my $data = int_api('get', 'endpoint', {
    user => $self->plain_cookie($self->user_cookie_name),
    a    => $self->current_account->id_token,  # Account token
});

# Specific items by name
my $data = int_api('get', 'endpoint', {
    user => $self->plain_cookie($self->user_cookie_name),
    a    => $self->current_account->id_token,
    names => "item1,item2,item3",  # Comma-separated names
});

# Admin cross-account query
my $data = int_api('get', 'endpoint', {
    user => $self->plain_cookie($self->user_cookie_name),
    a    => $self->current_account->id_token,
    all_accounts => 'true',
});

# Different account context (when permitted)
my $data = int_api('get', 'endpoint', {
    user => $self->plain_cookie($self->user_cookie_name),
    a    => $target_account_token,  # Different account's token
});
```

**Error Handling**:
- Handle error responses gracefully: 404 (not found), 500+ (server errors)
- Extract and display trace IDs from response headers for debugging
- Always provide fallback behavior when API is unavailable
- Use structured error responses with success flags

### API-Driven Feature Integration Patterns

When implementing features that integrate with internal APIs (like monitor metrics, account management, etc.), follow this comprehensive pattern:

**1. Controller Method Implementation**:
- Create method with request-scoped caching using `$self->{_cache_key}` pattern
- Support multiple query modes (account-specific, item-specific, admin-wide)
- Handle graceful degradation when API is unavailable
- Return structured data with success/error indicators

Example structure:
```perl
sub feature_data {
    my $self = shift;
    my %params = @_;

    # Determine actual parameters and build cache key
    my $actual_param1 = $params{param1} || $self->default_value;
    my $cache_key = "_feature_data_" . $actual_param1;
    return $self->{$cache_key} if exists $self->{$cache_key};

    # API call with proper authentication
    my $data = int_api('get', 'endpoint', {
        user => $self->plain_cookie($self->user_cookie_name),
        a    => $self->current_account->id_token,
        param1 => $actual_param1,
    });

    # Handle response codes with graceful degradation
    if ($data->{code} == 200) {
        return $self->{$cache_key} = { success => 1, data => $data->{data} };
    } else {
        return $self->{$cache_key} = {
            success => 0,
            error => $data->{error} || 'Service temporarily unavailable',
            trace_id => $data->{trace_id}
        };
    }
}
```

**2. Template Integration**:
- Use conditional logic to check for successful data retrieval
- Implement different detail levels for list vs detail views
- Show error messages with trace IDs when API fails
- Ensure page remains functional even when feature data unavailable

Example template patterns:
```html
[% IF feature_data && feature_data.success && feature_data.data.items %]
    [% IF show_details %]
        <!-- Detailed breakdown for individual item pages -->
    [% ELSE %]
        <!-- Summary display for list pages -->
    [% END %]
[% END %]

[% IF feature_data && !feature_data.success %]
    <div class="alert alert-warning">
        <small>
            Feature data: [% feature_data.error | html %]
            [% IF feature_data.trace_id %](Trace ID: [% feature_data.trace_id | html %])[% END %]
        </small>
    </div>
[% END %]
```

**3. Multi-Context Support**:
- Regular users: scope to their account/items
- Admin users: support cross-account queries with `all_accounts` parameter
- Individual items: support specific item queries by name/ID

**4. Integration Points**:
- Add method calls to existing render methods
- Pass data to templates via `$self->tpl_param`
- Ensure admin lists inherit same functionality through template reuse

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

## Test Files

Located in `t/` directory:
- `t/Alert.t`
- `t/LogScore.t`
- `t/Zone.t`
