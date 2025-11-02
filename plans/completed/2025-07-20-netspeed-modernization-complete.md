# Netspeed Modernization Project - COMPLETED

**📅 COMPLETED: July 20, 2025**
**✅ STATUS: Successfully modernized netspeed updates**
**🎯 SCOPE: jQuery → HTMX + Internal API integration**
**📦 COMMITS:**
- `51d2142f` - feat(server): modernize netspeed update to use API and HTMX

**🏆 ACHIEVEMENTS:**
- ✅ Replaced jQuery-based system with HTMX
- ✅ Updated backend to use internal API instead of direct database access
- ✅ Improved error handling with trace IDs
- ✅ Maintained backward compatibility with noscript fallbacks
- ✅ Enhanced security with proper CSRF token handling

---

## Original Plan Overview
Replace the legacy jQuery-based netspeed update system with modern HTMX and update the Perl backend to use the internal API instead of direct database access.

## Implementation Plan

### 1. Backend Changes (lib/NTPPool/Control/Manage/Server.pm)

**Update `handle_update_netspeed()` method:**
- Replace direct database operations with internal API call to `POST /int/server/netspeed`
- Convert form data to JSON in Perl backend before sending to API
- Use `int_api()` function with proper authentication:
  ```perl
  my $api_response = int_api('post', 'server/netspeed', {
      data => encode_json({
          server_ip => $server->ip,
          netspeed => $netspeed
      }),
      user => $self->plain_cookie($self->user_cookie_name),
      a => $self->current_account->id_token,
  });
  ```
- Handle API response codes (200 success, 403 verification required, 404 not found)
- Return updated server template fragment on success
- Display inline error messages with trace IDs on failure
- Remove legacy jQuery compatibility code

### 2. Frontend Changes (docs/manage/tpl/manage/server.html)

**Replace jQuery with HTMX:**
- Remove `onchange="NP.update_netspeed(...)"` from select element
- Add HTMX attributes:
  ```html
  <select name="netspeed"
          hx-post="/manage/server/update/netspeed"
          hx-target="#server_[% server.id %]"
          hx-swap="outerHTML"
          hx-trigger="change"
          hx-indicator="#netspeed-loading-[% server.id %]"
          hx-include="[name='auth_token'],[name='server'],[name='a']">
  ```
- Add loading indicator element
- Ensure CSRF token is included via `hx-include`
- Keep existing `noscript` fallback form unchanged

### 3. Error Handling

**Inline error display:**
- Show API errors within the server block
- Include trace ID when available
- Use Bootstrap alert classes for styling
- Don't replace current netspeed display on error - show error separately

**Template structure for errors:**
```html
[% IF error %]
<div class="alert alert-warning">
    [% error | html %]
    [% IF trace_id %]<br><small>Trace ID: [% trace_id | html %]</small>[% END %]
</div>
[% END %]
```

### 4. JavaScript Cleanup (docs/shared/static/js/ntppool.js)

**Remove legacy functions:**
- Delete `NP.update_netspeed()` function
- Delete `NP.netspeed_updated()` function
- Keep existing HTMX configuration and error handlers

### 5. API Integration Notes

**Current API Response Analysis:**
The `POST /int/server/netspeed` API returns:
- `netspeed_human`: Human-readable netspeed format
- `zone_changes`: Array of zone membership changes
- `current_zones`: Current zone memberships after update

**Required for Implementation:**
- API already returns zone information
- Use `zone_changes` to show feedback about automatic zone updates
- Use `current_zones` to update the zones display
- Maintain existing zone display template in `server_zones.html`

### 6. Implementation Steps

1. **Update Perl backend** in `handle_update_netspeed()`:
   - Replace database code with API call
   - Convert form data to JSON
   - Handle API responses and errors
   - Return appropriate template fragments

2. **Update HTML template**:
   - Add HTMX attributes to select element
   - Add loading indicator
   - Ensure proper form field inclusion

3. **Clean up JavaScript**:
   - Remove legacy jQuery functions
   - Test HTMX integration

4. **Test scenarios**:
   - Successful netspeed updates for verified servers
   - Verification requirement errors for unverified servers
   - Automatic zone management (@ zone at 10000 Kbps threshold)
   - API failure handling with trace IDs
   - Graceful degradation via noscript form

### 7. Key Benefits

- **Simplicity**: KISS - minimal JavaScript, standard HTMX patterns
- **Consistency**: Uses same internal API as other features
- **Maintainability**: No jQuery dependency, modern web standards
- **Security**: Maintains CSRF protection via auth tokens
- **Performance**: Reduced client-side complexity
- **Error Handling**: Better error visibility with trace IDs

### 8. Technical Details

**CSRF Protection:**
- Maintain existing `auth_token` validation in backend
- Include token via `hx-include` in HTMX request

**Loading Indicators:**
- Use standard `hx-indicator` with simple spinner/loading text
- Leverage existing CSS fade transitions where applicable

**Response Handling:**
- Return complete server block HTML fragment
- Include updated netspeed display and zones
- Show success/error messages inline within server block
