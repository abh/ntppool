# Zone API Perl Integration Implementation Plan

## Overview

This plan details the integration of the new ConnectRPC Zone API service into the NTP Pool Perl/Combust web application. The Zone API provides zone information, server counts, and historical statistics through a ConnectRPC interface, replacing direct database queries.

**Dependencies:**
- Go Zone API service must be deployed and accessible
- `lib/NP/CAPI/Zone.pm` must be generated (should already exist via `make generate`)
- `lib/NP/CAPI.pm` ConnectRPC client library must be functional

**Repositories:**
- **Go API**: `~/src/go/ntp/api` (already implemented)
- **Perl Frontend**: `~/src/ntppool` (this implementation)

## Prerequisites Verification

Before starting implementation, verify:

```bash
# 1. Check Zone.pm exists
test -f lib/NP/CAPI/Zone.pm && echo "✓ Zone.pm exists" || echo "✗ Missing - run make generate"

# 2. Verify it has required functions
grep -q "sub list_zones" lib/NP/CAPI/Zone.pm && echo "✓ list_zones found"
grep -q "sub get_zone" lib/NP/CAPI/Zone.pm && echo "✓ get_zone found"

# 3. Check Go API is accessible (update URL as needed)
curl -s -X POST https://api.ntppool.dev/ntppool.zone.v1.ZoneService/ListZones \
  -H "Content-Type: application/json" -d '{}' | jq '.zones | length'
```

## Implementation Steps

### Phase 1: Homepage Zone List Integration

#### Step 1.1: Update `lib/NTPPool/Control.pm`

**File**: `lib/NTPPool/Control.pm`

**Goal**: Replace `count_by_continent` method to use Zone API instead of direct database queries.

**Current Implementation** (locate this code):
```perl
sub count_by_continent {
    my $self = shift;
    # ... existing database query code ...
}
```

**Action**: Replace with API integration:

```perl
use NP::CAPI::Zone qw(list_zones);

sub count_by_continent {
    my $self = shift;

    # Call Zone API
    my $result = list_zones(context => {
        x_forwarded_for => $self->request->header_in('X-Forwarded-For'),
    });

    # Handle API errors
    if ($result->{error}) {
        warn "Failed to fetch zones from API: $result->{error} (TraceID: $result->{trace_id})";
        # Fallback to empty array rather than failing hard
        return [];
    }

    # Return zones array from API response
    return $result->{data}->{zones} || [];
}
```

**Testing**:
```bash
# Test homepage loads
curl -s http://localhost:8000/ | grep -q "pool.ntp.org" && echo "✓ Homepage loads"

# Check for JavaScript errors in browser console
# Verify zone list displays with correct server counts
# Check that global (@) and total (.) zones appear at the end
```

**Validation Checklist**:
- [ ] Homepage loads without errors
- [ ] Zone list displays all continental/regional zones
- [ ] Server counts are accurate (compare with old implementation if still available)
- [ ] Global zone (@) appears near the end
- [ ] Total zone (.) appears at the very end
- [ ] No Perl errors in application logs
- [ ] API trace IDs logged on errors

---

### Phase 2: Zone Detail Page Integration

#### Step 2.1: Update `lib/NTPPool/Control/Zone.pm`

**File**: `lib/NTPPool/Control/Zone.pm`

**Goal**: Replace database queries in `render` method with Zone API calls.

**Current Implementation** (locate these patterns):
```perl
sub render {
    my $self = shift;
    my $zone = $self->get_zone;  # or similar database fetch
    # ... database queries for parent, children, server counts, historical stats ...
}
```

**Action**: Add imports at top of file:

```perl
use NP::CAPI::Zone qw(get_zone);
```

**Action**: Replace `render` method (or update sections):

```perl
sub render {
    my $self = shift;
    my $zone_name = $self->zone_name;

    # Call Zone API
    my $result = get_zone($zone_name, context => {
        x_forwarded_for => $self->request->header_in('X-Forwarded-For'),
    });

    # Handle errors
    if ($result->{error}) {
        # Zone not found
        if ($result->{connect_code} eq 'not_found') {
            warn "Zone not found: $zone_name";
            return 404;
        }

        # Other API errors
        warn "Failed to fetch zone $zone_name: $result->{error} (TraceID: $result->{trace_id})";
        return 500;
    }

    my $zone_data = $result->{data}->{zone};

    # Convert API response to template-friendly format
    my $formatted_zone = $self->_format_zone($zone_data);

    $self->tpl_param('zone' => $formatted_zone);

    # Continue with rest of render logic
    # ... existing template param setup ...

    return;
}
```

#### Step 2.2: Add `_format_zone` Adapter Method

**Goal**: Convert Zone API response format to match existing template expectations.

**Action**: Add this new method to `lib/NTPPool/Control/Zone.pm`:

```perl
sub _format_zone {
    my ($self, $zone_data) = @_;

    # Adapter pattern: converts API response to template-compatible structure
    # This allows gradual migration without changing templates immediately

    return {
        # Basic zone information
        id          => $zone_data->{id},
        name        => $zone_data->{name},
        description => $zone_data->{description},
        url         => $zone_data->{url},
        fqdn        => $zone_data->{fqdn},
        dns         => $zone_data->{dns} ? 1 : 0,  # Ensure boolean
        sub_zone_count => $zone_data->{sub_zone_count} || 4,

        # Parent zone (may be undef)
        parent      => $zone_data->{parent},

        # Child zones array
        children    => $zone_data->{children} || [],

        # Server count accessor (called as method or function in templates)
        server_count => sub {
            my $ip_version = shift;

            # No IP version specified: return total
            return $zone_data->{server_counts}->{total} unless $ip_version;

            # IPv4 count
            return $zone_data->{server_counts}->{ipv4} if $ip_version eq 'v4';

            # IPv6 count
            return $zone_data->{server_counts}->{ipv6} if $ip_version eq 'v6';

            # Unknown version
            return 0;
        },

        # Historical stats accessor
        stats_days_ago => sub {
            my ($days, $ip_version) = @_;
            my $version_key = $ip_version || 'v4';  # Default to v4

            # Find stats for requested IP version
            my $version_stats = $zone_data->{historical_stats};
            my ($stats_for_version) = grep { $_->{ip_version} eq $version_key } @$version_stats;
            return unless $stats_for_version;

            # Find stats for requested day
            my ($stat) = grep { $_->{days_ago} == $days } @{$stats_for_version->{stats}};
            return unless $stat;

            # Return formatted stats object
            return {
                count_active     => $stat->{count_active},
                count_registered => $stat->{count_registered},
                netspeed_active  => $stat->{netspeed_active},
                date             => $stat->{date},
                ago              => $days == 1 ? "1 day ago" : "$days days ago",
            };
        },

        # Keep existing helper method reference
        random_subzone_ids => \&NP::Model::Zone::random_subzone_ids,
    };
}
```

**Testing**:
```bash
# Test various zone detail pages
curl -s http://localhost:8000/zone/na | grep -q "North America" && echo "✓ NA zone loads"
curl -s http://localhost:8000/zone/eu | grep -q "Europe" && echo "✓ EU zone loads"
curl -s http://localhost:8000/zone/@ | grep -q "Global" && echo "✓ Global zone loads"

# Test zone not found
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/zone/nonexistent | grep -q 404 && echo "✓ 404 on missing zone"
```

**Validation Checklist**:
- [ ] Zone detail pages load without errors
- [ ] Zone name and description display correctly
- [ ] Parent zone link works (if zone has parent)
- [ ] Child zones list displays correctly
- [ ] Server counts show for IPv4, IPv6, and total
- [ ] Historical statistics display for all time periods (1, 7, 14, 60, 180, 365, 1095, 2190 days)
- [ ] FQDN is correct (e.g., "na.pool.ntp.org" for "na" zone)
- [ ] Special zones (@, .) show correct FQDN ("pool.ntp.org")
- [ ] Zone not found returns 404
- [ ] API errors log with trace IDs

---

### Phase 3: Template Cleanup

#### Step 3.1: Remove Server List from Zone Template

**File**: `docs/ntppool/tpl/zone.html`

**Goal**: Remove the server list feature from zone detail pages (no longer needed as servers are managed through monitor interface).

**Action**: Locate and remove the server list section.

**Current Code** (approximate location, lines 106-148):
```html
[% IF show_servers %]
  <h3>Servers</h3>
  <!-- Server list table -->
  <table class="server-list">
    <!-- ... server rows ... -->
  </table>
[% END %]
```

**Action**: Remove:
1. The entire `[% IF show_servers %]` block
2. Any related template variables like `is_logged_in`, `show_servers`
3. Server list table HTML

**Note**: Keep all other zone display logic:
- Zone information header
- Parent/child zone navigation
- Server count statistics
- Historical statistics graphs
- Random subzone IDs feature

**Testing**:
```bash
# Verify template renders without server list
curl -s http://localhost:8000/zone/us | grep -qv "Servers" && echo "✓ Server list removed"

# Check page still displays zone info
curl -s http://localhost:8000/zone/us | grep -q "United States" && echo "✓ Zone info displays"
```

**Validation Checklist**:
- [ ] Zone detail pages still display correctly
- [ ] No server list appears
- [ ] No broken template references (check logs for template errors)
- [ ] Parent/child navigation still works
- [ ] Statistics still display
- [ ] Page layout is not broken

---

### Phase 4: Code Cleanup

#### Step 4.1: Remove Deprecated Database Methods

**Files**:
- `lib/NTPPool/Control/Zone.pm`
- `lib/NP/Model/Zone.pm` (if applicable)

**Goal**: Remove database query methods that are now redundant.

**Action**: Identify and remove (or mark as deprecated):

```perl
# Methods that are likely now redundant:
# - get_zone_with_counts
# - get_zone_children
# - get_zone_parent
# - get_zone_historical_stats
# - count_servers_by_version
```

**Important**: Only remove methods that are ONLY used by zone display. Check for other uses:

```bash
# Find all uses of a method before removing
grep -r "get_zone_with_counts" lib/ docs/
```

**Action**: Comment out or remove redundant methods. If unsure, add deprecation warnings:

```perl
sub get_zone_with_counts {
    warn "DEPRECATED: get_zone_with_counts is deprecated, use NP::CAPI::Zone::get_zone instead";
    # ... old implementation ...
}
```

#### Step 4.2: Remove Template Parameters

**File**: `lib/NTPPool/Control/Zone.pm`

**Action**: Remove `tpl_param` calls that set now-unused variables:

```perl
# Remove these if they exist:
$self->tpl_param('show_servers' => ...);
$self->tpl_param('is_logged_in' => ...);
```

**Validation**:
- [ ] No template errors in logs
- [ ] No undefined variable warnings
- [ ] Pages still render correctly

---

### Phase 5: Error Handling & Monitoring

#### Step 5.1: Add Comprehensive Error Logging

**Goal**: Ensure all API errors are properly logged with trace IDs for debugging.

**Action**: Update error handling in both controller methods:

```perl
# In count_by_continent
if ($result->{error}) {
    my $trace_id = $result->{trace_id} || 'unknown';
    my $error_msg = $result->{error} || 'unknown error';
    my $error_code = $result->{connect_code} || 'unknown';

    warn "Zone API list_zones failed: code=$error_code, msg=$error_msg, trace_id=$trace_id";

    # Log to application metrics/monitoring if available
    # $self->log_api_error('zone.list_zones', $error_code, $trace_id);

    return [];
}

# In render
if ($result->{error}) {
    my $trace_id = $result->{trace_id} || 'unknown';
    my $error_msg = $result->{error} || 'unknown error';
    my $error_code = $result->{connect_code} || 'unknown';

    warn "Zone API get_zone failed for zone=$zone_name: code=$error_code, msg=$error_msg, trace_id=$trace_id";

    # Return appropriate HTTP status
    return 404 if $error_code eq 'not_found';
    return 503 if $error_code eq 'unavailable';
    return 500;
}
```

#### Step 5.2: Add Health Check

**Goal**: Verify Zone API is accessible during application startup or health checks.

**File**: Create `lib/NP/CAPI/Zone/HealthCheck.pm` (optional)

```perl
package NP::CAPI::Zone::HealthCheck;
use strict;
use warnings;
use NP::CAPI::Zone qw(list_zones);

sub check {
    my $result = list_zones();

    if ($result->{error}) {
        return {
            status => 'unhealthy',
            error => $result->{error},
            trace_id => $result->{trace_id},
        };
    }

    return {
        status => 'healthy',
        zones_count => scalar(@{$result->{data}->{zones} || []}),
    };
}

1;
```

**Validation**:
- [ ] Errors are logged with trace IDs
- [ ] HTTP status codes are appropriate (404 for not found, 500 for internal errors)
- [ ] Can correlate Perl logs with Go API logs via trace ID

---

## Testing Strategy

### Test Cases

#### Homepage Tests
1. **Basic Load**: Homepage displays without errors
2. **Zone List**: All zones display with names and descriptions
3. **Server Counts**: Counts are reasonable (> 0 for major zones)
4. **Zone Order**: Zones sorted by description, with @ and . at end
5. **Links**: Zone links are correct format (`/zone/{name}`)

#### Zone Detail Page Tests
Test each of these zones:
- `na` - Continental zone with children
- `us` - Country zone with parent
- `@` - Global zone (special case)
- `.` - Total zone (special case)
- `nonexistent` - Should return 404

For each zone, verify:
1. **Basic Info**: Name, description, FQDN are correct
2. **Parent Link**: Appears and is correct (if zone has parent)
3. **Children List**: Displays correctly (if zone has children)
4. **Server Counts**: IPv4, IPv6, and total counts display
5. **Historical Stats**: All 8 time periods (1, 7, 14, 60, 180, 365, 1095, 2190 days) show data or zeros
6. **No Server List**: Server list section is gone

#### Error Handling Tests
1. **API Unavailable**:
   ```bash
   # Stop Go API service temporarily
   # Verify Perl app returns 500 or shows graceful error
   # Verify error logged with details
   ```

2. **Slow API Response**:
   ```bash
   # Add delay to API (if possible)
   # Verify request doesn't hang indefinitely
   ```

3. **Malformed Response**:
   - Should not crash Perl app
   - Should log error
   - Should show generic error page

#### Performance Tests
1. **Response Time**: Zone pages should load in < 500ms
2. **API Latency**: Check trace spans show API calls < 100ms
3. **Cache Effectiveness**: Verify API responses are cached if caching is enabled

### Manual Testing Checklist

```bash
# 1. Homepage
curl -s http://localhost:8000/ > /tmp/homepage.html
grep -q "North America" /tmp/homepage.html && echo "✓ NA zone"
grep -q "Europe" /tmp/homepage.html && echo "✓ EU zone"

# 2. Zone detail pages
for zone in na eu us uk @ .; do
    echo "Testing zone: $zone"
    curl -s -o /dev/null -w "%{http_code}" "http://localhost:8000/zone/$zone"
done

# 3. Check logs for errors
tail -f /var/log/ntppool/error.log | grep -i zone

# 4. Check API logs for trace IDs
# (on API server)
tail -f /var/log/ntppool-api/app.log | grep ZoneService
```

---

## Deployment Plan

### Pre-Deployment

1. **Verify Go API is deployed and healthy**:
   ```bash
   curl -s https://api.ntppool.org/ntppool.zone.v1.ZoneService/ListZones \
     -H "Content-Type: application/json" -d '{}' | jq '.zones | length'
   ```

2. **Run full test suite**:
   ```bash
   cd ~/src/ntppool
   make test
   ```

3. **Review code changes**:
   ```bash
   git diff lib/NTPPool/Control.pm
   git diff lib/NTPPool/Control/Zone.pm
   git diff docs/ntppool/tpl/zone.html
   ```

### Deployment Steps

#### Option A: Blue-Green Deployment (Recommended)

1. **Deploy to staging environment first**
   ```bash
   # Deploy Perl changes to staging
   # Run smoke tests
   # Monitor for 1 hour
   ```

2. **Deploy to production**
   ```bash
   # Deploy Perl changes
   # Monitor logs and metrics
   # Keep old version ready for rollback
   ```

#### Option B: Gradual Rollout

1. **Deploy with feature flag** (if infrastructure supports):
   ```perl
   # In controller:
   my $use_zone_api = $ENV{USE_ZONE_API} || 0;

   if ($use_zone_api) {
       # New API implementation
   } else {
       # Old database implementation
   }
   ```

2. **Enable for percentage of traffic**:
   - 10% for 1 hour
   - 50% for 1 hour
   - 100% if metrics look good

### Monitoring

**Metrics to Watch**:
- Zone page response times
- API error rates
- HTTP 500 error rates
- Page load errors in browser monitoring

**Alerts**:
- Zone API error rate > 1%
- Zone page response time > 1s
- HTTP 500 rate increases

**Logs to Monitor**:
```bash
# Perl app logs
tail -f /var/log/ntppool/error.log | grep -E "(Zone API|get_zone|list_zones)"

# Go API logs (on API server)
tail -f /var/log/ntppool-api/app.log | grep ZoneService

# Look for trace IDs to correlate
grep "trace_id=abc123" /var/log/ntppool/*.log
```

---

## Rollback Plan

### If Issues Are Detected

**Symptoms requiring rollback**:
- Zone pages showing 500 errors > 5%
- Zone API errors > 10%
- User reports of broken zone pages
- Missing data on zone pages

### Rollback Steps

1. **Immediate**: Revert Perl code changes
   ```bash
   cd ~/src/ntppool
   git revert HEAD
   # Deploy previous version
   ```

2. **Verify**: Check zone pages work with old code
   ```bash
   curl http://localhost:8000/zone/na
   ```

3. **Investigate**: Check logs for root cause
   ```bash
   # What was the error?
   grep "Zone API" /var/log/ntppool/error.log | tail -50

   # Check API logs
   # On API server:
   grep "ZoneService" /var/log/ntppool-api/app.log | tail -50
   ```

4. **Fix**: Address root cause
   - API connectivity issue?
   - Response format mismatch?
   - Template error?

5. **Re-deploy**: After fix is confirmed in staging

---

## Success Criteria

The integration is successful when:

- [ ] All zone pages load without errors
- [ ] Server counts match previous implementation (±5%)
- [ ] Historical statistics display for all time periods
- [ ] No increase in page load times (< 500ms)
- [ ] API error rate < 0.1%
- [ ] No user-reported issues for 48 hours
- [ ] Old database query code removed
- [ ] Server list removed from zone pages
- [ ] Error logs clean (no Zone API errors under normal operation)

---

## Post-Deployment

### Day 1
- [ ] Monitor error rates closely
- [ ] Check API logs for unusual patterns
- [ ] Verify all major zones load correctly
- [ ] Confirm historical stats are accurate

### Week 1
- [ ] Review performance metrics
- [ ] Check for any user reports
- [ ] Verify cache hit rates (if applicable)
- [ ] Compare server counts with direct DB queries (spot check)

### Week 2
- [ ] Remove old database query code if not used elsewhere
- [ ] Remove deprecated methods
- [ ] Update documentation
- [ ] Consider removing feature flags if used

---

## Troubleshooting Guide

### Issue: "Zone API failed to fetch zones"

**Symptoms**: Homepage shows no zones, error in logs

**Check**:
```bash
# 1. Is API reachable?
curl https://api.ntppool.org/ntppool.zone.v1.ZoneService/ListZones

# 2. Check Perl CAPI configuration
grep -r "zone.v1.ZoneService" lib/NP/CAPI/

# 3. Check DNS resolution
host api.ntppool.org

# 4. Check network connectivity
ping api.ntppool.org
```

**Fix**:
- Verify API endpoint URL is correct
- Check firewall rules
- Verify SSL certificates

### Issue: "Zone not found" for valid zone

**Symptoms**: 404 error for zone that should exist

**Check**:
```bash
# 1. Does zone exist in database?
# On DB server:
SELECT name FROM zones WHERE name = 'na';

# 2. Does API return the zone?
curl -X POST https://api.ntppool.org/ntppool.zone.v1.ZoneService/GetZone \
  -H "Content-Type: application/json" \
  -d '{"name": "na"}' | jq .

# 3. Check case sensitivity
# Zone names should be lowercase
```

**Fix**:
- Verify zone exists in database
- Check API deployment has latest database schema
- Verify zone name is lowercase

### Issue: Historical stats showing all zeros

**Symptoms**: Stats display but all values are 0

**Check**:
```bash
# 1. Does historical data exist in DB?
# On DB server:
SELECT * FROM zone_server_counts WHERE zone_id = 1 AND date > NOW() - INTERVAL '7 days';

# 2. Check API response
curl -X POST https://api.ntppool.org/ntppool.zone.v1.ZoneService/GetZone \
  -H "Content-Type: application/json" \
  -d '{"name": "na"}' | jq '.zone.historical_stats'
```

**Fix**:
- Verify `zone_server_counts` table has recent data
- Check zone statistics background job is running
- Verify API query is correct

### Issue: Template shows "undefined" for zone fields

**Symptoms**: Page displays "undefined" or blank fields

**Check**:
1. API response format matches template expectations
2. `_format_zone` method correctly maps all fields
3. Template uses correct variable names

**Fix**:
- Add missing field mappings in `_format_zone`
- Check API response structure vs template requirements
- Verify spelling of field names

---

## File Checklist

Files that will be modified:

- [ ] `lib/NTPPool/Control.pm` - Update `count_by_continent`
- [ ] `lib/NTPPool/Control/Zone.pm` - Update `render`, add `_format_zone`
- [ ] `docs/ntppool/tpl/zone.html` - Remove server list section

Files to review (may need updates):

- [ ] `lib/NP/CAPI/Zone.pm` - Verify generated correctly
- [ ] `lib/NP/CAPI.pm` - Base ConnectRPC client (should not need changes)
- [ ] `lib/NP/Model/Zone.pm` - Check for deprecated methods to remove

New files (optional):

- [ ] `lib/NP/CAPI/Zone/HealthCheck.pm` - API health checking
- [ ] `docs/testing/zone-api-integration-tests.md` - Test documentation

---

## Contact & Support

**For questions or issues**:
- Check Go API logs for trace IDs
- Review this implementation plan
- Check original requirements: `~/src/go/ntp/api/ntppool/API_REQUIREMENTS_ZONES.md`

**Key trace points**:
- Perl logs: Look for "Zone API" in error logs
- Go API logs: Look for "ZoneService" in application logs
- Correlate using trace_id field from API errors

---

## Appendix: API Response Examples

### ListZones Response
```json
{
  "zones": [
    {
      "name": "eu",
      "description": "Europe",
      "url": "/zone/eu",
      "server_count": 1234,
      "dns": true
    },
    {
      "name": "na",
      "description": "North America",
      "url": "/zone/na",
      "server_count": 2345,
      "dns": true
    },
    {
      "name": "@",
      "description": "Global",
      "url": "/zone/@",
      "server_count": 5000,
      "dns": true
    },
    {
      "name": ".",
      "description": "All Servers",
      "url": "/zone/.",
      "server_count": 6789,
      "dns": false
    }
  ]
}
```

### GetZone Response
```json
{
  "zone": {
    "id": 5,
    "name": "us",
    "description": "United States",
    "url": "/zone/us",
    "fqdn": "us.pool.ntp.org",
    "dns": true,
    "sub_zone_count": 4,
    "parent": {
      "name": "na",
      "description": "North America",
      "url": "/zone/na",
      "fqdn": "na.pool.ntp.org",
      "dns": true,
      "server_count": 2345
    },
    "children": [
      {
        "name": "us-ca",
        "description": "California, United States",
        "url": "/zone/us-ca",
        "fqdn": "us-ca.pool.ntp.org",
        "dns": true,
        "server_count": 123
      }
    ],
    "server_counts": {
      "total": 456,
      "ipv4": 400,
      "ipv6": 56
    },
    "historical_stats": [
      {
        "ip_version": "v4",
        "stats": [
          {
            "days_ago": 1,
            "count_active": 400,
            "count_registered": 450,
            "netspeed_active": 4000000,
            "date": "2025-10-03"
          },
          {
            "days_ago": 7,
            "count_active": 395,
            "count_registered": 445,
            "netspeed_active": 3950000,
            "date": "2025-09-27"
          }
        ]
      },
      {
        "ip_version": "v6",
        "stats": [
          {
            "days_ago": 1,
            "count_active": 56,
            "count_registered": 60,
            "netspeed_active": 560000,
            "date": "2025-10-03"
          }
        ]
      }
    ]
  }
}
```

---

**End of Implementation Plan**

This plan should be executed by an agent with Perl experience. The Go API service is already implemented and ready. Good luck with the integration!
