# CAPI Requirements for DNS Zone Generation

## Executive Summary

This document specifies the minimal CAPI (ConnectRPC) API requirements to migrate DNS zone generation from direct PostgreSQL database access to API-based data retrieval. The goal is to eliminate database queries in `lib/NP/Model/DnsRoot.pm` and `lib/NTPPool/Control/DNSZone.pm` while keeping DNS zone generation logic in Perl.

**Risk Minimization Strategy:** Use the minimum number of API calls with batched responses to reduce latency and complexity.

## Current Database Dependencies

### Files Requiring Migration
1. `lib/NP/Model/DnsRoot.pm` - Zone data population logic
2. `lib/NTPPool/Control/DNSZone.pm` - HTTP endpoint with API key authentication

### Current Database Queries

```perl
# DNSZone.pm - Authentication
my $api_key = NP::Model->api_key->fetch("api_key" => $token);
my $root = NP::Model->dns_root->fetch(origin => $origin);

# DnsRoot.pm - Data fetching
my $zones = NP::Model->zone->get_zones_iterator(query => [dns => 1]);
my $vendor_zones = NP::Model->vendor_zone->get_vendor_zones(
    query => [status => 'Approved', dns_root_id => $root->id],
    sort_by => 'approved_on',
);
my $settings = NP::Settings->get_setting('dns_settings');
```

## Proposed API Design

### Design Principle: Batch Related Data

Instead of 5 separate API calls, use **2 API calls**:
1. **ValidateApiKey** - Authentication (separate concern)
2. **GetDnsZoneData** - Single batched response with all zone data

This minimizes:
- Network round trips (1 data call instead of 4)
- Latency accumulation
- Error handling complexity
- Risk of inconsistent data

---

## Required CAPI Methods

### 1. System Service: Validate API Key

**Service:** `ntppool.system.v1.SystemService`
**Method:** `ValidateApiKey` (new method)

**Purpose:** Replace `NP::Model->api_key->fetch("api_key" => $token)` using new API key system

**Request:**
```protobuf
message ValidateApiKeyRequest {
  string api_key = 1;  // The Bearer token from Authorization header
}
```

**Response:**
```protobuf
message ValidateApiKeyResponse {
  bool valid = 1;      // true if token is valid and not expired
  string user_id = 2;  // User ID (for logging, optional)
}
```

**Authentication:** None (this IS the authentication check)

**Perl Usage:**
```perl
use NP::CAPI::System qw(validate_api_key);

my $result = validate_api_key(api_key => $token);

# Fail hard on API errors
if ($result->{error}) {
    warn "API key validation failed: " . $result->{error} .
         " [trace: " . $result->{trace_id} . "]";
    return 500;
}

# Check if key is valid
unless ($result->{data}{valid}) {
    return 403;  # Forbidden
}

# Continue with DNS zone generation
```

**Notes:**
- Will use new API key system in the API
- Returns 200 with `valid=false` for invalid keys (not 401/403)
- Must implement rate limiting to prevent brute force
- No grants checking initially (commented out in current code)

---

### 2. Zone Service: Get DNS Zone Data (Batched)

**Service:** `ntppool.zone.v1.ZoneService`
**Method:** `GetDnsZoneData` (new method)

**Purpose:** Replace ALL data fetching in DnsRoot.pm with a single API call

**Request:**
```protobuf
message GetDnsZoneDataRequest {
  string origin = 1;  // Required: DNS root origin (e.g., "pool.ntp.org")
}
```

**Response:**
```protobuf
message GetDnsZoneDataResponse {
  DnsRootInfo dns_root = 1;
  repeated DnsZone zones = 2;
  repeated ActiveVendorZone vendor_zones = 3;
  DnsSettings settings = 4;
}

message DnsRootInfo {
  int32 id = 1;
  string origin = 2;        // e.g., "pool.ntp.org"
  string ns_list = 3;       // Space or comma-separated NS records
}

message DnsZone {
  int32 id = 1;
  string name = 2;          // Zone identifier (e.g., "na", "us", "@", ".")
  string description = 3;   // Human-readable name (not used in generation)
}

message ActiveVendorZone {
  int32 id = 1;
  string zone_name = 2;     // e.g., "linksys", "cisco"
  string client_type = 3;   // "ntp", "sntp", or "legacy"
}

message DnsSettings {
  int32 ttl = 1;            // TTL in seconds (0 = use default)
  string stathat_api = 2;   // StatHat API key (empty string if not configured)
}
```

**Authentication:** None required (public data)

**HTTP Headers:**
- `Cache-Control: public, max-age=45` - Cache for 45 seconds (zone data changes every few minutes)

**Perl Usage:**
```perl
use NP::CAPI::Zone qw(get_dns_zone_data);

my $result = get_dns_zone_data(origin => $origin);

# Fail hard on errors - no silent fallbacks
if ($result->{error}) {
    croak "DNS zone data failed: " . $result->{error} .
          " [trace: " . $result->{trace_id} . "]";
}

if ($result->{code} == 404) {
    return 404;  # DNS root not found
}

# Extract all data from single response
my $data = $result->{data};
my $root = $data->{dns_root};
my $zones = $data->{zones};              # arrayref
my $vendor_zones = $data->{vendor_zones}; # arrayref
my $settings = $data->{settings};

# Use root info for DNS generation
my $root_id = $root->{id};
my $ns_list = $root->{ns_list};

# Iterate zones (replaces get_zones_iterator)
for my $zone (@$zones) {
    my $name = $zone->{name};
    # ... populate_country_zones logic
}

# Iterate vendor zones (replaces get_vendor_zones)
for my $vendor (@$vendor_zones) {
    my $name = $vendor->{zone_name};
    my $client_type = $vendor->{client_type};
    # ... populate_vendor_zones logic
}

# Get TTL (replaces get_setting)
my $ttl = $settings->{ttl} || default_ttl;
$ttl = 30 if $ttl > 0 && $ttl < 30;  # Enforce minimum
```

**Backend Implementation:**
```go
// Pseudocode for Go implementation
func (s *ZoneService) GetDnsZoneData(ctx context.Context, req *GetDnsZoneDataRequest) (*GetDnsZoneDataResponse, error) {
    // 1. Fetch DNS root
    root, err := s.db.GetDnsRootByOrigin(ctx, req.Origin)
    if err != nil {
        return nil, connect.NewError(connect.CodeNotFound, err)
    }

    // 2. Fetch all DNS zones (dns = true) - can parallelize
    zones, err := s.db.ListDnsZones(ctx)
    if err != nil {
        return nil, connect.NewError(connect.CodeInternal, err)
    }

    // 3. Fetch active vendor zones for this root - can parallelize
    vendorZones, err := s.db.ListActiveVendorZonesByRoot(ctx, root.ID)
    if err != nil {
        return nil, connect.NewError(connect.CodeInternal, err)
    }

    // 4. Fetch DNS settings (with default fallback)
    settings, _ := s.db.GetDnsSettings(ctx)  // Non-critical, can fail

    return &GetDnsZoneDataResponse{
        DnsRoot: root,
        Zones: zones,
        VendorZones: vendorZones,
        Settings: settings,
    }, nil
}
```

**Notes:**
- Single API call returns everything needed for DNS generation
- Reduces latency (1 round trip instead of 4)
- Atomic snapshot of data (consistency)
- Backend can parallelize database queries
- Returns 404 if DNS root origin not found
- `zones` includes ALL zones where `dns = true` (no root filtering)
- `vendor_zones` filtered by `dns_root_id` and status='Approved'
- `vendor_zones` sorted by `approved_on` ascending
- `settings.ttl = 0` means "use default" (Perl has fallback logic)
- Response cached for 45 seconds (zone data changes every few minutes)

---

## Migration Plan

### Phase 1: Implement Go API Methods

**Priority:** HIGH (blocking PostgreSQL migration)

```bash
cd /Users/ask/src/go/ntp

# 1. Add proto definitions
edit api/proto/ntppool/zone/v1/zone.proto
# Add GetDnsZoneData RPC and messages

edit api/proto/ntppool/system/v1/system.proto
# Add ValidateApiKey RPC and messages

# 2. Generate code
make generate

# 3. Implement service methods
edit pkg/zone/service.go
# Add GetDnsZoneData implementation
# Set Cache-Control header: w.Header().Set("Cache-Control", "public, max-age=45")

edit pkg/system/service.go
# Add ValidateApiKey implementation using new API key system

# 4. Add database queries
edit pkg/zone/db.go
# - GetDnsRootByOrigin(ctx, origin)
# - ListDnsZones(ctx) // where dns = true
# - ListActiveVendorZonesByRoot(ctx, rootID)
# - GetDnsSettings(ctx)

edit pkg/system/db.go
# - ValidateApiKey(ctx, apiKey) // using new API key tables

# 5. Test
go test ./pkg/zone/...
go test ./pkg/system/...
```

### Phase 2: Generate Perl CAPI Client

```bash
cd /Users/ask/src/ntppool

# Regenerate Perl CAPI modules from updated protos
make generate-capi

# This creates/updates:
# - lib/NP/CAPI/Zone.pm (adds get_dns_zone_data)
# - lib/NP/CAPI/System.pm (adds validate_api_key)
```

### Phase 3: Update Perl Code

**File:** `lib/NTPPool/Control/DNSZone.pm`

```perl
package NTPPool::Control::DNSZone;
use strict;
use parent qw(NTPPool::Control);
use Combust::Constant qw(OK);
use NP::CAPI::System qw(validate_api_key);
use NP::CAPI::Zone qw(get_dns_zone_data);
use NP::Model::DnsRoot;
use Carp qw(croak);

sub render {
    my $self = shift;

    $self->cache_control('private, no-cache');

    # Extract Bearer token
    my $token = $1
      if ($self->request->header_in("Authorization") || '') =~ /^\s*Bearer\s+(.+)/i;
    return 403 unless $token;

    # Validate API key via CAPI (new API key system)
    my $auth_result = validate_api_key(api_key => $token);
    if ($auth_result->{error}) {
        warn "API key validation error: " . $auth_result->{error} .
             " [trace: " . $auth_result->{trace_id} . "]";
        return 500;
    }
    return 403 unless $auth_result->{data}{valid};

    # Get origin parameter
    my $origin = $self->req_param('origin');

    # Fetch all DNS zone data via CAPI
    my $result = get_dns_zone_data(origin => $origin);

    # Fail hard on errors - clients will keep old data
    if ($result->{error}) {
        croak "DNS zone data error: " . $result->{error} .
              " [trace: " . $result->{trace_id} . "]";
    }

    return 404 if $result->{code} == 404;

    # Create DnsRoot object and populate with CAPI data
    my $root = NP::Model::DnsRoot->new();
    $root->populate_from_api_data($result->{data});

    my $json = JSON::XS->new->pretty->utf8->convert_blessed;
    my $js = $json->encode($root);

    return OK, $js;
}

1;
```

**File:** `lib/NP/Model/DnsRoot.pm`

```perl
package NP::Model::DnsRoot;
use strict;
use warnings;
use Combust::Config;
use List::Util qw(shuffle);
use NP::CAPI::Zone qw(get_zone_active_servers);
use Carp qw(croak);

# Remove: use NP::Settings;
# Remove: use NP::Model;

my $config     = Combust::Config->new;
my $config_ntp = $config->site->{ntppool};

use constant default_ttl => 150;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub populate_from_api_data {
    my ($self, $api_data) = @_;

    # Validate required data
    croak "Missing dns_root in API response" unless $api_data->{dns_root};
    croak "Missing zones in API response" unless $api_data->{zones};
    croak "Missing vendor_zones in API response" unless $api_data->{vendor_zones};

    # Store root info
    $self->{_root_id} = $api_data->{dns_root}{id};
    $self->{_origin} = $api_data->{dns_root}{origin};
    $self->{_ns_list} = $api_data->{dns_root}{ns_list};

    # Store zones, vendor_zones, settings for use by populate methods
    $self->{_api_zones} = $api_data->{zones};
    $self->{_api_vendor_zones} = $api_data->{vendor_zones};
    $self->{_api_settings} = $api_data->{settings};

    # Call existing populate logic
    $self->populate();

    return $self;
}

sub populate {
    my $self = shift;
    $self->populate_vendor_zones;
    $self->populate_country_zones;
}

sub populate_country_zones {
    my $self = shift;

    # Use data from API instead of database query
    my $zones = $self->{_api_zones};
    croak "No zones data from API" unless $zones && ref($zones) eq 'ARRAY';

    my $data = $self->data;

    for my $zone (@$zones) {
        my $name = $zone->{name};

        my $ttl;

        #if ($name eq 'br' or $name eq 'au') {
        #    $ttl = 55;
        #}

        $name = ''       if $name eq '@';
        $name = "$name." if $name;

        if (my $entries = _get_zone_servers($zone, 'v4')) {

            my $min_non_duplicate_size = 2;
            my $response_records       = 3;
            my @zones                  = ("0.", "1.", "2.", "3.");
            my $zone_count             = scalar @zones;

            # add all servers to the non-numbered "NTP" zone
            (my $pgeodns_group = "${name}") =~ s/\.$//;
            push @{$data->{$pgeodns_group}->{a}}, $_ for @$entries;
            if ($ttl) {
                $data->{$pgeodns_group}->{ttl} = $ttl;
            }
            $data->{$pgeodns_group}->{mx} = [{mx => ".", preference => 0}];

            $min_non_duplicate_size = int(@$entries / $zone_count)
              if (@$entries / $zone_count > $min_non_duplicate_size);

           # print $fh "# " . scalar @$entries . " active servers in ", $zone->name, "\n";

            if ($#$entries < ($min_non_duplicate_size * $zone_count - 1)) {

                # possible duplicates, not enough servers
                foreach my $z (@zones) {
                    (my $pgeodns_group = "$z${name}") =~ s/\.$//;

                    # already has an alias, so don't add more data
                    if ($data->{$pgeodns_group}->{alias}) {
                        next;
                    }

                    $data->{$pgeodns_group}->{mx} = [{mx => ".", preference => 0}];

                    $data->{$pgeodns_group}->{a} = [];
                    if ($ttl) {
                        $data->{$pgeodns_group}->{ttl} = $ttl;
                    }
                    @$entries = shuffle(@$entries);
                    foreach my $e (@$entries) {
                        push @{$data->{$pgeodns_group}->{a}}, $e;
                    }
                }
            }
            else {

                # 'big' zone without duplicates
                @$entries = shuffle(@$entries);
                foreach my $z (@zones) {
                    (my $pgeodns_group = "$z${name}") =~ s/\.$//;
                    if ($ttl) {
                        $data->{$pgeodns_group}->{ttl} = $ttl;
                    }
                    $data->{$pgeodns_group}->{a} = [];
                    for (my $i = 0; $i < $min_non_duplicate_size; $i++) {
                        my $e = shift @$entries;
                        push @{$data->{$pgeodns_group}->{a}}, $e;
                    }

                    $data->{$pgeodns_group}->{mx} = [{mx => ".", preference => 0}];
                }
            }
        }

        if (my $entries = _get_zone_servers($zone, 'v6')) {
            @$entries = shuffle(@$entries);

            # for now just put all IPv6 servers in the '2' zone
            (my $pgeodns_group = "2.${name}") =~ s/\.$//;
            push @{$data->{$pgeodns_group}->{aaaa}}, $_ for @$entries;
        }

    }
}

sub populate_vendor_zones {
    my $self = shift;

    # Use data from API instead of database query
    my $vendor_zones = $self->{_api_vendor_zones};
    croak "No vendor zones from API" unless defined $vendor_zones && ref($vendor_zones) eq 'ARRAY';

    my %vendors;

    for my $vendor (@$vendor_zones) {
        my $name = $vendor->{zone_name};
        $vendors{$name} = {
            type   => $vendor->{client_type},
            vendor => $vendor
        };
    }

    # File system vendor zones (legacy, pool.ntp.org only)
    # TODO: Migrate to database, but keep file system for now
    if ($self->origin eq 'pool.ntp.org') {
        my $vendordir = "vendordns";
        if (-d $vendordir) {
            opendir my $dir, $vendordir or warn "could not open '$vendordir' dir: $!";
            if ($dir) {
                my @vendor_files =
                  grep { $_ !~ /\~$/ and -f $_ } map {"$vendordir/$_"} readdir($dir);
                closedir $dir;
                for my $vendor (@vendor_files) {
                    $vendor =~ s!.*/!!;
                    $vendors{$vendor} = {type => 'ntp'};
                }
            }
        }
    }

    for my $name (sort keys %vendors) {
        next unless $name;    # vendor_name="" on separate dns root
        my $client_type = $vendors{$name}->{type};
        my $sntp        = ($client_type eq 'sntp' or $client_type eq 'legacy');
        my $ntp         = ($client_type eq 'ntp'  or $client_type eq 'legacy');
        unless ($sntp or $ntp) {
            $sntp = 1;
            $ntp  = 1;
        }
        if ($sntp) {
            $self->data->{"$name"}->{alias} = "";
        }
        if ($ntp) {
            for my $i (0 .. 3) {
                $self->data->{"$i.$name"}->{alias} = $i;
            }
        }
    }
}

sub ttl {
    my $self = shift;

    # Use API settings if available
    if ($self->{_api_settings}) {
        my $ttl = $self->{_api_settings}{ttl};
        if ($ttl && $ttl > 0) {
            $ttl = 30 if $ttl < 30;  # Enforce minimum
            return $ttl;
        }
    }

    # Fallback to default
    return default_ttl;
}

sub serial {
    return shift->{_dns_serial} ||= time;
}

sub stathat_api {
    my $self = shift;
    return $self->{_api_settings}{stathat_api} || $config_ntp->{stathat_api} || '';
}

sub data {
    my $self = shift;

    # return a singleton for the root so other methods can add to the data
    return $self->{_dns_data} ||= do {

        my $www_record = {
            cname => $config_ntp->{www_cname} || 'www-lb.ntppool.org.',
            ttl   => 7200,
        };

        my $data = {};
        $data->{www} = $www_record;
        $data->{web} = $www_record;
        $data->{gb}  = {alias => 'uk'};
        for my $i (0 .. 3) {
            $data->{"$i.gb"} = {alias => "$i.uk"};
        }

        $data->{""}->{ns} = {map { $_ => undef } split /[\s+,]/, $self->ns_list};

        $data->{""}->{txt} = [

            # Fastly TLS verification
            {   txt =>
                  "_globalsign-domain-verification=mVYWxIl-2ab_B1yPPFxEmDCLrBcl6ucouXJOU_P0_C"
            },
        ];

        # null MX records by default, rfc7505
        $data->{""}->{mx} = [{mx => ".", preference => 0},];

        if ($self->origin eq "pool.ntp.org") {

            # google domain verification
            $data->{"v4zgfk4oagsu"}->{cname} = "gv-35off4weczdcxg.dv.googlehosted.com.";
            push @{$data->{""}->{txt}},
              {txt => "v=spf1 -all"},
              {txt => "facebook-domain-verification=sfjgxys7hmryn50lszk658gi7amidt"},
              {txt =>
                  "google-site-verification=PRDJb3cjUxA4K-Abx2wItCnGwTkkNTRqJVjCkmAk54Q"};

            $data->{"_dmarc"}->{txt} =
              'v=DMARC1; p=reject; pct=100; rua=mailto:4649a710@in.mailhardener.com; sp=reject; adkim=s; aspf=r; ruf=mailto:4649a710@in.mailhardener.com';

        }
        elsif ($self->origin eq "beta.grundclock.com") {
            $data->{"fchof3xzaiyl"}->{cname} = "gv-fveibxaoathoje.dv.googlehosted.com.";
            push @{$data->{""}->{txt}},
              {txt => "facebook-domain-verification=9gahpfmem9gwjmxypka1o3v3fgnb4k"};
        }

        $data;
    };
}

sub TO_JSON {
    my $self = shift;
    return {
        serial    => $self->serial,
        ttl       => $self->ttl,
        data      => $self->data,
        max_hosts => 4,
        logging   => {stathat_api => $self->stathat_api},
    };
}

sub origin {
    my $self = shift;
    return $self->{_origin} || '';
}

sub ns_list {
    my $self = shift;
    return $self->{_ns_list} || '';
}

sub id {
    my $self = shift;
    return $self->{_root_id};
}

# _get_zone_servers is unchanged - already uses CAPI
sub _get_zone_servers {
    my ($zone, $ip_version) = @_;

    my $result = get_zone_active_servers(
        zone_name  => $zone->{name},
        ip_version => $ip_version,
    );

    # Fail hard on API errors
    if ($result->{error}) {
        my $msg = "Failed to get active servers for zone " . $zone->{name} . " ($ip_version): ";
        $msg .= $result->{error} // 'unknown error';
        $msg .= " [code: " . $result->{connect_code} . "]" if $result->{connect_code};
        $msg .= " [trace: " . $result->{trace_id} . "]" if $result->{trace_id};
        croak $msg;
    }

    unless (defined $result->{data}) {
        croak "No data returned for zone "
            . $zone->{name} . " ($ip_version)";
    }

    my $servers = $result->{data}{servers};
    unless (defined $servers && ref($servers) eq 'ARRAY') {
        croak "Invalid servers response for zone "
            . $zone->{name} . " ($ip_version)";
    }

    # Convert from CAPI format [{ip => ..., netspeed => ...}, ...]
    # to legacy format [[ip, netspeed], ...]
    my @entries;
    for my $srv (@$servers) {
        unless (ref($srv) eq 'HASH') {
            croak "Invalid server entry (not a hash) for zone "
                . $zone->{name};
        }

        my $ip = $srv->{ip};
        unless (defined $ip && length($ip) > 0) {
            croak "Missing or empty IP in server entry for zone "
                . $zone->{name};
        }

        my $netspeed = $srv->{netspeed};
        unless (defined $netspeed && $netspeed =~ /^\d+$/ && $netspeed > 0) {
            croak "Invalid netspeed '$netspeed' for server $ip in zone "
                . $zone->{name};
        }

        push @entries, [$ip, $netspeed];
    }

    return \@entries;
}

1;
```

### Phase 4: Testing Strategy

**1. Unit Tests (Go)**
```go
func TestGetDnsZoneData(t *testing.T) {
    // Test valid origin
    // Test invalid origin (404)
    // Test data completeness
    // Test vendor zone filtering by root
    // Test vendor zone sorting
    // Test Cache-Control header
}

func TestValidateApiKey(t *testing.T) {
    // Test valid API key
    // Test invalid API key
    // Test expired API key
    // Test response format
}
```

**2. Integration Tests (Perl)**
```perl
# Test full DNS zone generation with CAPI
# Compare output with baseline
# Test error handling (API down, invalid origin)
# Test fail-hard behavior (croak on errors)
```

**3. Comparison Testing**
```bash
# Generate with old code (before migration)
OLD_OUTPUT=$(curl -H "Authorization: Bearer $OLD_TOKEN" \
  "https://api/dnszone?origin=pool.ntp.org")

# Generate with new code (after migration)
NEW_OUTPUT=$(curl -H "Authorization: Bearer $NEW_TOKEN" \
  "https://api/dnszone?origin=pool.ntp.org")

# Compare (ignoring serial timestamp)
diff <(echo "$OLD_OUTPUT" | jq -S 'del(.serial)') \
     <(echo "$NEW_OUTPUT" | jq -S 'del(.serial)')

# Should be identical
```

**4. Performance Testing**
```bash
# Measure latency before/after
# Target: < 100ms additional latency
# Test under load (multiple GeoDNS servers polling)

# Check Cache-Control header
curl -I -H "Authorization: Bearer $TOKEN" \
  "https://api/dnszone?origin=pool.ntp.org" | grep -i cache-control
# Should show: Cache-Control: public, max-age=45
```

---

## Error Handling Strategy

### Fail-Hard Approach

**Critical:** DNS zone generation must fail hard if ANY error occurs. Clients (GeoDNS servers) will keep old data available when requests fail.

**Implementation:**
```perl
# Use croak for all API errors (not warn)
use Carp qw(croak);

# Example:
if ($result->{error}) {
    croak "DNS zone data failed: " . $result->{error} .
          " [trace: " . $result->{trace_id} . "]";
}

# NOT this (silent fallback):
if ($result->{error}) {
    warn "Error, using cached data...";  # WRONG
    return $cached_data;
}
```

**Why Fail Hard:**
- GeoDNS clients expect failures occasionally
- They keep the last successful zone data
- Silent fallbacks hide problems
- Better to surface issues immediately
- Trace IDs enable debugging

**Error Scenarios:**
1. **API unavailable** → croak with trace ID
2. **Invalid origin** → return 404
3. **Invalid API key** → return 403
4. **Missing required data** → croak with details
5. **Invalid data format** → croak with validation error

---

## Caching Strategy

### API Response Caching

**Cache-Control Header:** `public, max-age=45`

**Rationale:**
- Zone data changes every few minutes
- 45-second cache reduces API load
- Multiple GeoDNS servers polling concurrently
- CDN/proxy can cache responses

**Implementation (Go):**
```go
func (s *ZoneService) GetDnsZoneData(ctx context.Context, req *pb.GetDnsZoneDataRequest) (*connect.Response[pb.GetDnsZoneDataResponse], error) {
    // ... fetch data ...

    resp := connect.NewResponse(&pb.GetDnsZoneDataResponse{
        DnsRoot: root,
        Zones: zones,
        VendorZones: vendorZones,
        Settings: settings,
    })

    // Add cache header
    resp.Header().Set("Cache-Control", "public, max-age=45")

    return resp, nil
}
```

**Client Behavior:**
- GeoDNS servers poll every ~60 seconds
- Cache hit rate should be high during stable periods
- Cache misses trigger fresh data fetch
- No stale data risk (45s max age is short)

---

## Vendor Zone File System Migration

### Current State
- File system vendor zones only for `pool.ntp.org`
- Located in `vendordns/` directory
- Format: One file per vendor

### Migration Plan
- **Phase 1 (this migration):** Keep file system reading in Perl
- **Phase 2 (future):** Migrate vendor zone files to database
  - Create migration script to import files
  - Update vendor zone management UI
  - Remove file system dependency

### Implementation (Now)
```perl
# Keep this code in populate_vendor_zones()
if ($self->origin eq 'pool.ntp.org') {
    my $vendordir = "vendordns";
    if (-d $vendordir) {
        opendir my $dir, $vendordir or warn "could not open '$vendordir' dir: $!";
        # ... read vendor files ...
    }
}
```

**Notes:**
- Low risk to keep file system for now
- File system vendor zones rarely change
- Can migrate to database in separate project
- Perl code handles missing directory gracefully

---

## Risk Analysis and Mitigation

### Risk 1: Increased Latency
**Impact:** DNS zone generation slower
**Likelihood:** Medium
**Mitigation:**
- Batch all data in single API call (reduces round trips)
- Backend parallelizes database queries
- Keep API service on same network
- HTTP keep-alive connection pooling
- 45-second response caching
- Monitor latency with OpenTelemetry

### Risk 2: API Availability
**Impact:** DNS zone generation fails if API down
**Likelihood:** Low (same K8s cluster)
**Mitigation:**
- API runs in same cluster (high availability)
- GeoDNS clients keep old data on failure
- Health checks and circuit breakers
- Monitor API uptime
- Alerting on DNS generation failures

### Risk 3: Data Inconsistency
**Impact:** Zone data doesn't match expectations
**Likelihood:** Medium
**Mitigation:**
- Thorough comparison testing before production
- Validate response data in Perl (required fields)
- Atomic batched response (all from same transaction)
- Fail-hard on validation errors
- Comprehensive error messages with trace IDs

### Risk 4: Migration Errors
**Impact:** Bugs introduced during code changes
**Likelihood:** Medium
**Mitigation:**
- Keep zone generation logic unchanged (only data source)
- Extensive testing in development
- Staged rollout (beta.grundclock.com first)
- Easy rollback plan
- Side-by-side comparison testing

---

## Rollback Plan

If production issues occur after deployment:

### Immediate Rollback (< 5 minutes)
1. Revert Perl code to use `NP::Model` database queries
2. Deploy reverted code
3. GeoDNS continues working with database access

### Files to Revert
- `lib/NTPPool/Control/DNSZone.pm`
- `lib/NP/Model/DnsRoot.pm`

### Temporary Mitigation
- Keep PostgreSQL read replica for DNS zone tables
- Allows rollback without MySQL dependency
- Debug API issues in development

### Re-deployment
- Fix API issues based on production errors
- Re-test extensively
- Attempt migration again

---

## Deployment Strategy

### Stage 1: Development Testing
1. Deploy Go API with new methods
2. Update Perl code
3. Test with beta.grundclock.com DNS root
4. Verify JSON output matches baseline
5. Performance testing

### Stage 2: Staging Deployment
1. Deploy to staging environment
2. Run comparison tests
3. Load testing with multiple concurrent clients
4. Verify caching behavior
5. Test failure scenarios

### Stage 3: Production Deployment
1. Create new API keys for GeoDNS servers
2. Deploy Go API to production
3. Deploy Perl code to production
4. Monitor error rates
5. Check GeoDNS zone file updates
6. Verify no service degradation

### Stage 4: Validation
1. Monitor for 24 hours
2. Check API latency metrics
3. Verify cache hit rates
4. Confirm no error spikes
5. GeoDNS servers functioning normally

---

## Success Criteria

- [ ] `GetDnsZoneData` API method implemented and tested
- [ ] `ValidateApiKey` API method implemented with new API key system
- [ ] Cache-Control header set to `public, max-age=45`
- [ ] Perl CAPI modules generated
- [ ] `lib/NP/Model/DnsRoot.pm` updated to use CAPI
- [ ] `lib/NTPPool/Control/DNSZone.pm` updated to use CAPI
- [ ] All database queries removed from both files
- [ ] Fail-hard error handling implemented (croak on errors)
- [ ] Comparison tests show identical JSON output
- [ ] Performance tests show < 100ms additional latency
- [ ] Integration tests passing
- [ ] Successfully deployed to beta.grundclock.com
- [ ] Successfully deployed to pool.ntp.org
- [ ] No increase in error rates
- [ ] GeoDNS servers functioning normally
- [ ] Cache hit rate > 50% during stable periods

---

## Summary

This migration eliminates all direct database access from DNS zone generation while:

- **Minimizing risk** with batched API calls (2 calls, not 5)
- **Preserving logic** - only data source changes
- **Failing hard** - no silent fallbacks, clients handle failures
- **Adding caching** - 45-second response cache reduces load
- **Using new API keys** - modern API key system
- **Keeping vendor files** - file system migration deferred to Phase 2
- **Comprehensive testing** - comparison and performance tests
- **Easy rollback** - clear revert path if issues occur

The batched API design reduces latency while the fail-hard approach ensures issues are surfaced immediately rather than hidden with fallback behavior.
