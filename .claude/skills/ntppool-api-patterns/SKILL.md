---
name: ntppool-api-patterns
description: Reference for NTP Pool internal API integration patterns. Load when reading or migrating legacy `int_api()` (NP::IntAPI) REST call sites, or when wiring an API-backed controller method + template (request-scoped caching, multi-context queries, graceful degradation). Current-code ConnectRPC (NP::CAPI) conventions live in CLAUDE.md; this skill holds the longer examples and the legacy reference.
---

# NTP Pool API integration patterns

Longer examples that don't need to be in every session's context. The
always-loaded architecture rules and the ConnectRPC (`NP::CAPI`) conventions
for **new** code stay in the root `CLAUDE.md` — read that first. Use this skill
when you hit legacy `int_api()` code or need the full controller+template
integration example.

## Legacy REST API Patterns (int_api) — FOR REFERENCE ONLY

**⚠️ DO NOT USE FOR NEW CODE ⚠️**

This documents the old REST approach using `int_api()` from `NP::IntAPI`. These
patterns are being phased out in favor of ConnectRPC APIs in `NP::CAPI/*.pm`.
Retained only for understanding existing un-migrated code and identifying call
sites that need updating to ConnectRPC.

**Authentication and Account Context**:
- Use `int_api()` function from `NP::IntAPI` for internal API calls (LEGACY)
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

## API-Driven Feature Integration Patterns

When implementing features that integrate with internal APIs (like monitor
metrics, account management, etc.), follow this pattern. (The example below
shows the legacy `int_api()` call; for new code substitute the appropriate
`NP::CAPI` method — the caching, multi-context, and graceful-degradation shape
is the reusable part.)

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
