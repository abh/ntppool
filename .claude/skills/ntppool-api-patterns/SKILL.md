---
name: ntppool-api-patterns
description: Reference for NTP Pool internal API integration patterns. Load when wiring an API-backed controller method + template (request-scoped caching, multi-context queries, graceful degradation). Current-code ConnectRPC (NP::CAPI) conventions live in CLAUDE.md; this skill holds the longer examples.
---

# NTP Pool API integration patterns

Longer examples that don't need to be in every session's context. The
always-loaded architecture rules and the ConnectRPC (`NP::CAPI`) conventions
for **new** code stay in the root `CLAUDE.md` — read that first. Use this skill
when you need the full controller+template integration example.

## API design principles — worked examples

The rules themselves live in `CLAUDE.md` under "API Design Principles" and are
always loaded. These are the code examples behind each rule.

### The Go API should do the work, not Perl

**❌ WRONG - Perl orchestrates multiple API calls:**
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

**✅ RIGHT - a single API call does everything:**
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

### Perl does not calculate

**❌ WRONG - Perl processes API data:**
```perl
# DON'T: Process API data in Perl
my $zones_result = list_zones();
my @zones = grep { $_->{dns} } @{$zones_result->{data}{zones}};
@zones = sort { $a->{name} cmp $b->{name} } @zones;
for my $zone (@zones) {
    $zone->{display} = "$zone->{description} ($zone->{server_count} servers)";
}
```

**✅ RIGHT - the API returns ready-to-display data:**
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

### Audit logging belongs to the API

**❌ WRONG - Perl creates audit logs:**
```perl
# DON'T: Make Perl responsible for audit logging
my $result = NP::CAPI::ServerManagement::delete_server(
    ip => $ip,
    deletion_date => $date,
);

# Then separately log the operation (easy to forget!)
NP::Model::Log->log_changes($user, "server-delete", "Deletion scheduled", $server);
```

**✅ RIGHT - the API creates audit logs automatically:**
```perl
# DO: API handles audit logging internally
my $result = NP::CAPI::ServerManagement::delete_server(
    ip => $ip,
    deletion_date => $date,
);
# Audit log created automatically by Go API in same transaction
```

### Never reload from the ORM after an API call

**❌ WRONG:**
```perl
# API returns minimal data
my $result = create_account(name => "Test");
my $account_id = $result->{data}{account_id};

# This FAILS - trying to reload from MySQL but data is in PostgreSQL
my $account = NP::Model->account->fetch(id => $account_id);  # Returns undef!
```

**✅ RIGHT:**
```perl
# API returns complete account data
my $result = create_account(name => "Test");
my $account_data = $result->{data}{account};  # Full account object

# Use data directly from API response
my $account_name = $account_data->{name};
my $account_token = $account_data->{account_token};
```

### Never recompute a value the API already owns

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

### ConnectRPC call examples

```perl
use NP::CAPI::Account qw(create_account update_account);

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

# Use $result->{data}{account} directly — do NOT reload via NP::Model.

my $update = update_account(
    auth             => $self->plain_cookie($self->user_cookie_name),
    account          => $account->id_token,
    context          => $self->_get_request_context(),
    name             => $new_name,              # Optional fields
    organization_name => $org_name,             # Only send what's changing
    public_profile   => JSON::XS::true,         # Use JSON::XS booleans
);
```

## API-Driven Feature Integration Patterns

When implementing features that integrate with internal APIs (like monitor
metrics, account management, etc.), follow this pattern.

**1. Controller Method Implementation**:
- Create method with request-scoped caching using `$self->{_cache_key}` pattern
- Support multiple query modes (account-specific, item-specific, admin-wide)
- Handle graceful degradation when API is unavailable
- Return structured data with success/error indicators

Example structure:
```perl
use NP::CAPI::Feature qw(get_feature_data);

sub feature_data {
    my $self = shift;
    my %params = @_;

    # Determine actual parameters and build cache key
    my $actual_param1 = $params{param1} || $self->default_value;
    my $cache_key = "_feature_data_" . $actual_param1;
    return $self->{$cache_key} if exists $self->{$cache_key};

    # API call with proper authentication
    my $result = get_feature_data(
        $self->api_auth_params,
        account => $self->current_account->{id_token},
        param1  => $actual_param1,
    );

    # Handle response with graceful degradation
    if ($result->{error}) {
        return $self->{$cache_key} = {
            success  => 0,
            error    => $result->{error} || 'Service temporarily unavailable',
            trace_id => $result->{trace_id},
        };
    }

    return $self->{$cache_key} = {success => 1, data => $result->{data}};
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
