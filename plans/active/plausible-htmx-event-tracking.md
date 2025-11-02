# Plausible Analytics Event Tracking for HTMX Forms and Actions

## Overview

This plan outlines the implementation of event tracking for HTMX-powered forms and actions in the NTP Pool Project using the existing Plausible analytics integration. The goal is to track meaningful user interactions while maintaining privacy and following existing code patterns.

## Current State Analysis

### Existing Analytics Setup
- **Location**: `/client/src/analytics.ts`
- **Package**: `plausible-client` v1.1.0
- **Features**: Auto page views and outbound link tracking enabled
- **Build**: Integrated into main bundle via Vite

### HTMX Implementation
- **Version**: HTMX 2.0.5 (loaded via CDN in templates)
- **Usage**: Extensive use in admin/management interfaces
- **Patterns**: Forms, inline editing, status polling, delete confirmations
- **Backend**: Controllers support `is_htmx()` for fragment responses

### Missing Components
1. Meta tags for Plausible configuration in templates
2. Custom event tracking implementation
3. HTMX event hooks for analytics

## Implementation Plan

### Phase 1: Core Analytics Infrastructure

#### 1.1 Extend analytics.ts
```typescript
// Add to /client/src/analytics.ts

// Export the plausible instance for global access
export { plausible }

// Add custom event tracking helper
export function trackEvent(eventName: string, props?: Record<string, string | number | boolean>) {
  plausible.trackEvent(eventName, { props })
}

// Make trackEvent available globally for inline usage
declare global {
  interface Window {
    plausibleTrackEvent: typeof trackEvent
  }
}

window.plausibleTrackEvent = trackEvent
```

#### 1.2 Add Meta Tags to Base Template
```html
<!-- Add to docs/shared/tpl/tpl.head.html before </head> -->
<meta name="plausible-domain" content="www.ntppool.org">
<meta name="plausible-api-host" content="/analytics">
```

### Phase 2: HTMX Event Integration

#### 2.1 Create HTMX Analytics Module
Create new file: `/client/src/htmx-analytics.ts`

```typescript
import { trackEvent } from './analytics'

// Track HTMX form submissions
document.addEventListener('htmx:beforeRequest', (event: CustomEvent) => {
  const element = event.detail.elt as HTMLElement

  // Track form submissions
  if (element.tagName === 'FORM' || element.closest('form')) {
    const form = element.tagName === 'FORM' ? element : element.closest('form')
    const formName = form?.getAttribute('data-analytics-name') ||
                    form?.getAttribute('id') ||
                    'unknown-form'

    trackEvent('htmx_form_submit', {
      form_name: formName,
      action: event.detail.path,
      method: event.detail.verb
    })
  }

  // Track button/link interactions
  if (element.hasAttribute('data-analytics-action')) {
    trackEvent('htmx_action', {
      action: element.getAttribute('data-analytics-action') || 'unknown',
      target: event.detail.target?.id || 'unknown'
    })
  }
})

// Track successful HTMX responses
document.addEventListener('htmx:afterOnLoad', (event: CustomEvent) => {
  if (event.detail.successful) {
    const element = event.detail.elt as HTMLElement

    // Track successful form submissions
    if (element.tagName === 'FORM' || element.closest('form')) {
      const form = element.tagName === 'FORM' ? element : element.closest('form')
      const formName = form?.getAttribute('data-analytics-name') ||
                      form?.getAttribute('id') ||
                      'unknown-form'

      trackEvent('htmx_form_success', {
        form_name: formName,
        status_code: event.detail.xhr.status
      })
    }
  }
})

// Track HTMX errors
document.addEventListener('htmx:responseError', (event: CustomEvent) => {
  const element = event.detail.elt as HTMLElement
  const formName = element.closest('form')?.getAttribute('data-analytics-name') ||
                  element.getAttribute('data-analytics-action') ||
                  'unknown'

  trackEvent('htmx_error', {
    context: formName,
    status_code: event.detail.xhr.status,
    path: event.detail.path
  })
})
```

#### 2.2 Import in main.ts
```typescript
// Add to /client/src/main.ts after analytics import
import './htmx-analytics'
```

### Phase 3: Enhance Existing JavaScript Event Handlers

#### 3.1 Update ntppool.js Event Tracking
Add tracking to existing functions in `docs/shared/static/js/ntppool.js`:

```javascript
// Track successful auto-redirects
function autoRedirectOnSuccess(event) {
  if (event.detail.successful && event.detail.xhr.status == 200) {
    // Existing redirect logic...

    // Add tracking
    if (window.plausibleTrackEvent) {
      window.plausibleTrackEvent('htmx_auto_redirect', {
        from: window.location.pathname,
        to: redirectUrl
      });
    }
  }
}

// Track monitor configuration errors
function showMonitorConfigError(message, traceId) {
  // Existing error display logic...

  // Add tracking
  if (window.plausibleTrackEvent) {
    window.plausibleTrackEvent('monitor_config_error', {
      error_type: 'configuration',
      has_trace_id: !!traceId
    });
  }
}

// Track monitor deletion confirmations
function setupMonitorDelete() {
  const deleteButtons = document.querySelectorAll('.delete-monitor-btn');
  deleteButtons.forEach(btn => {
    btn.addEventListener('htmx:confirm', function(evt) {
      // Existing confirmation logic...

      // Add tracking for confirmation shown
      if (window.plausibleTrackEvent) {
        window.plausibleTrackEvent('monitor_delete_confirm_shown', {
          monitor_name: btn.getAttribute('data-monitor-name') || 'unknown'
        });
      }
    });
  });
}
```

### Phase 4: Add Analytics Attributes to Templates

#### 4.1 Form Analytics Attributes
Add `data-analytics-name` attributes to key forms:

```html
<!-- Monitor registration form -->
<form data-analytics-name="monitor_registration" ...>

<!-- Server configuration form -->
<form data-analytics-name="server_config" ...>

<!-- Netspeed update form -->
<form data-analytics-name="netspeed_update" ...>

<!-- Account settings forms -->
<form data-analytics-name="account_settings" ...>
```

#### 4.2 Action Analytics Attributes
Add `data-analytics-action` attributes to HTMX actions:

```html
<!-- Delete buttons -->
<button data-analytics-action="delete_monitor" hx-delete="...">

<!-- Toggle buttons -->
<button data-analytics-action="toggle_server_status" hx-post="...">

<!-- Search inputs -->
<input data-analytics-action="admin_search" hx-get="...">
```

### Phase 5: High-Value Event Tracking

#### 5.1 Critical User Actions to Track

1. **Monitor Management**
   - `monitor_registration_start`
   - `monitor_registration_success`
   - `monitor_registration_error`
   - `monitor_delete_confirm`
   - `monitor_delete_success`
   - `monitor_config_update`

2. **Server Management**
   - `server_add`
   - `server_delete`
   - `server_status_toggle`
   - `netspeed_update`
   - `server_config_change`

3. **Account Management**
   - `account_settings_update`
   - `account_profile_change`
   - `notification_preference_change`

4. **Admin Actions**
   - `admin_search_perform`
   - `admin_user_action`
   - `admin_monitor_override`

#### 5.2 Event Properties to Capture

For each event, capture relevant properties:
- Form/action name
- Success/failure status
- Error types (if applicable)
- Response times (for performance tracking)
- User context (regular vs admin)

### Phase 6: Testing and Validation

#### 6.1 Testing Checklist
- [ ] Verify analytics.ts loads and initializes properly
- [ ] Confirm meta tags are present in rendered HTML
- [ ] Test event firing for all HTMX forms
- [ ] Verify error tracking works correctly
- [ ] Test with Plausible blocked (graceful degradation)
- [ ] Validate event names and properties in Plausible dashboard

#### 6.2 Browser Console Testing
```javascript
// Test event tracking manually
window.plausibleTrackEvent('test_event', { test: true })

// Verify HTMX event listeners
htmx.logAll() // Enable HTMX logging to see all events
```

### Phase 7: Documentation

#### 7.1 Developer Documentation
Create `/docs/analytics-events.md` documenting:
- All tracked events and their properties
- How to add tracking to new features
- Testing procedures
- Debugging tips

#### 7.2 Code Comments
Add inline comments explaining:
- Why specific events are tracked
- What properties are important
- Any business logic dependencies

## Implementation Guidelines

### Do's
- ✅ Use semantic event names that describe the action
- ✅ Include relevant context in event properties
- ✅ Track both success and failure states
- ✅ Ensure graceful degradation if analytics fail
- ✅ Follow existing code patterns and conventions
- ✅ Test thoroughly with HTMX logging enabled

### Don'ts
- ❌ Don't track sensitive user data
- ❌ Don't block user actions if analytics fail
- ❌ Don't create overly granular events
- ❌ Don't modify core HTMX behavior
- ❌ Don't assume analytics is always available

## Rollout Strategy

1. **Phase 1**: Implement core infrastructure and test internally
2. **Phase 2**: Add tracking to one critical flow (e.g., monitor registration)
3. **Phase 3**: Monitor data quality and adjust as needed
4. **Phase 4**: Roll out to all forms and actions
5. **Phase 5**: Create dashboards and alerts based on events

## Success Metrics

- All HTMX forms have event tracking
- Error rates are tracked and visible
- User journey funnels can be created
- Performance impact is negligible (<50ms)
- No privacy concerns or data leaks

## Additional Considerations

### Privacy
- Plausible is privacy-focused by design
- No personal data in event properties
- IP addresses are not tracked
- GDPR/CCPA compliant

### Performance
- Event tracking is asynchronous
- Minimal payload size
- Local caching where appropriate
- Batch events if volume is high

### Maintenance
- Regular review of event taxonomy
- Prune unused events quarterly
- Update documentation as events change
- Monitor for tracking failures

## Resources

- [Plausible Custom Events API](https://plausible.io/docs/custom-event-goals)
- [HTMX Events Reference](https://htmx.org/reference/#events)
- [TypeScript Declaration Files](https://www.typescriptlang.org/docs/handbook/declaration-files/templates/global-d-ts.html)

## Questions for Implementation Team

1. **Domain Configuration**: Should we use "www.ntppool.org" or a different domain for analytics?
2. **API Host**: Is "/analytics" the correct path for the Plausible API proxy?
3. **Event Naming**: Do you have preferences for event naming conventions?
4. **Property Limits**: Plausible has limits on custom properties - which are most important?
5. **Admin Tracking**: Should admin actions be tracked separately or filtered?
6. **Rate Limiting**: Do we need to implement client-side rate limiting for events?
7. **A/B Testing**: Should we build in support for A/B test tracking?
