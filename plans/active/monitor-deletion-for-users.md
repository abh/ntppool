# Monitor Deletion Implementation Plan

## Overview

This plan implements user-controlled monitor deletion using the new DELETE API endpoint. The feature allows regular users to delete their own monitors while unifying the admin experience to use delete buttons instead of status dropdown changes.

## Requirements Summary

- **API Endpoint**: `DELETE /int/monitor/manage/monitor` with form parameters `name` and `id`
- **User Access**: Non-admins can delete monitors from accounts they belong to (enforced by API)
- **Admin Changes**: Remove "deleted" status from dropdown, use delete button for all users
- **UX Pattern**: Delete button on detail page only, with HTMX confirmation
- **Error Handling**: Generic user messages with trace IDs, detailed server logging

## Implementation Phases

### Phase 1: Add DELETE Method Support to IntAPI Helper

**File**: `lib/NP/IntAPI.pm`

Add DELETE method support to the `_int_api` function after the existing PATCH handler (around line 98):

```perl
elsif ($method eq 'delete') {
    $res = $ua->$method(
        $url,
        'Authorization' => $auth,
        Content         => $data
    );
}
```

**Key Points**:
- Handle form data like POST method (send as content body)
- Use existing authentication pattern (`Bearer $user`)
- Follow existing error handling and logging patterns

### Phase 2: Add Controller Route and Handler

**File**: `lib/NTPPool/Control/Manage/Monitor.pm`

#### 2.1 Add Route Pattern
In the `manage_dispatch()` method, add route handler after line 93:

```perl
if ($self->request->uri =~ m!^/manage/monitors/monitor/delete$!) {
    return $self->render_delete_monitor();
}
```

#### 2.2 Implement Delete Handler
Add new method after existing methods:

```perl
sub render_delete_monitor {
    my $self = shift;

    return 403 unless $self->check_auth_token;
    return 405 unless $self->request->method eq 'post';

    my $name = $self->req_param('name');
    my $id = $self->req_param('id');

    unless ($name && $id) {
        warn "Missing required parameters for monitor deletion: name=$name, id=$id";
        if ($self->is_htmx) {
            $self->tpl_param('error', 'Unable to delete monitor');
            return OK, $self->evaluate_template('tpl/monitors/delete_error.html');
        }
        return $self->redirect($self->manage_url('/manage/monitors/'));
    }

    my $data = int_api(
        'delete',
        'monitor/manage/monitor',
        {   name => $name,
            id   => $id,
            user => $self->plain_cookie($self->user_cookie_name),
            a    => $self->current_account->id_token,
        },
        $self->_get_request_context()
    );

    # Log exact API response for debugging
    warn "Delete monitor API response for $name: " . Data::Dump::pp($data);

    if ($data->{code} == 204) {
        # Successful deletion - redirect to monitor list
        if ($self->is_htmx) {
            # HTMX redirect header
            $self->header_out('HX-Redirect', $self->manage_url('/manage/monitors/'));
            return OK, '';
        }
        return $self->redirect($self->manage_url('/manage/monitors/'));
    }
    else {
        # Error case - log details, show generic message
        warn "Failed to delete monitor $name: " . ($data->{error} || 'Unknown error');

        if ($self->is_htmx) {
            $self->tpl_param('error', 'Unable to delete monitor');
            $self->tpl_param('trace_id', $data->{trace_id}) if $data->{trace_id};
            return OK, $self->evaluate_template('tpl/monitors/delete_error.html');
        }

        $self->tpl_param('error', 'Unable to delete monitor');
        return $self->redirect($self->manage_url('/manage/monitors/monitor', {name => $name}));
    }
}
```

### Phase 3: Update Monitor Detail Template

**File**: `docs/manage/tpl/monitors/show.html`

#### 3.1 Replace Admin Status Section
Replace the existing admin-only status section (lines 33-64) with a delete section for all users:

```html
<!-- Delete Monitor Section -->
<h3>Monitor Actions</h3>
<div class="mb-3">
    <form hx-post="/manage/monitors/monitor/delete?a=[% combust.current_account.id_token %]"
          hx-confirm="Are you sure you want to delete this monitor? This action cannot be undone."
          hx-target="#delete-result"
          hx-swap="innerHTML">
        <input type="hidden" name="auth_token" value="[% combust.auth_token %]">
        <input type="hidden" name="name" value="[% mon.TLSName | html %]">
        <input type="hidden" name="id" value="[% mon.IDToken | html %]">

        <button type="submit" class="btn btn-outline-danger btn-sm">
            Delete Monitor
        </button>
    </form>

    <div id="delete-result" class="mt-2"></div>
</div>

[% IF error %]
<div class="alert alert-warning">
    [% error | html %]
    [% IF trace_id %]<small>(Trace ID: [% trace_id | html %])</small>[% END %]
</div>
[% END %]
```

#### 3.2 Remove Admin Status Controls
- Remove the `[% IF combust.user.is_monitor_admin %]` block and all status form content
- Remove the `status_form` BLOCK definition at the top
- Keep all other existing functionality (monitor info, metrics, etc.)

### Phase 4: Create Error Template

**File**: `docs/manage/tpl/monitors/delete_error.html`

```html
<div class="alert alert-warning">
    [% error | html %]
    [% IF trace_id %]
        <br><small>Support reference: [% trace_id | html %]</small>
    [% END %]
</div>
```

### Phase 5: Filter Status Options (If Needed)

**Context**: If the `data.StatusOptions` is still used elsewhere for admin operations, ensure "deleted" is filtered out since deletion now uses dedicated buttons.

Check if this data is used in other admin templates and filter accordingly.

## Technical Implementation Notes

### HTMX Integration Details

1. **Confirmation**: Use `hx-confirm` attribute for user confirmation dialog
2. **Target**: Use `hx-target="#delete-result"` for inline error display
3. **Redirect**: Use `HX-Redirect` header for successful deletion navigation
4. **Error Handling**: Return error template for display in target element

### Error Handling Strategy

1. **Server Logging**: Log exact API errors with full context for debugging
2. **User Messages**: Show generic "Unable to delete monitor" message
3. **Trace IDs**: Include trace IDs in user-facing errors for support
4. **Graceful Degradation**: Handle both HTMX and non-HTMX requests

### Security Considerations

1. **CSRF Protection**: Validate `auth_token` using `check_auth_token()`
2. **Method Validation**: Only allow POST requests
3. **Parameter Validation**: Require both `name` and `id` parameters
4. **Authorization**: API enforces user can only delete own monitors

### Code Patterns to Follow

1. **API Calls**: Follow existing patterns in `monitor_metrics()` method
2. **Error Handling**: Follow patterns in `render_admin_status()` method
3. **Template Integration**: Follow patterns in existing monitor templates
4. **HTMX Usage**: Follow patterns in existing HTMX implementations in codebase

## Testing Checklist

### Functional Testing
- [ ] Non-admin users can delete their own monitors
- [ ] Admin users can delete any monitor
- [ ] HTMX confirmation dialog appears
- [ ] Successful deletion redirects to monitor list
- [ ] Deleted monitors disappear from list view
- [ ] Error cases display properly with trace IDs

### Security Testing
- [ ] CSRF token validation prevents unauthorized requests
- [ ] Users cannot delete monitors from other accounts
- [ ] API authorization is properly enforced
- [ ] Method validation rejects non-POST requests

### Error Scenarios
- [ ] Missing parameters handled gracefully
- [ ] API errors logged and displayed appropriately
- [ ] Network failures don't break the interface
- [ ] Invalid monitor IDs return proper errors

### Cross-Browser Testing
- [ ] HTMX functionality works in supported browsers
- [ ] Confirmation dialogs display correctly
- [ ] Fallback works when JavaScript disabled

## Files Modified

1. **`lib/NP/IntAPI.pm`** - Add DELETE method support
2. **`lib/NTPPool/Control/Manage/Monitor.pm`** - Add delete route and handler
3. **`docs/manage/tpl/monitors/show.html`** - Replace admin controls with delete button
4. **`docs/manage/tpl/monitors/delete_error.html`** - New error template (create)

## Deployment Notes

- Feature is additive - no breaking changes to existing functionality
- DELETE API endpoint already exists and supports required functionality
- Delete buttons only appear for users with appropriate access
- Graceful fallback if API is unavailable
- Compatible with existing monitor management workflows

## Future Enhancements

1. **Bulk Deletion**: Add checkbox selection for multiple monitor deletion
2. **Soft Delete Recovery**: Add ability to restore recently deleted monitors
3. **Delete Confirmation Page**: Replace dialog with dedicated confirmation page
4. **Admin Status Management**: Create separate admin interface for status changes

## Support Information

- **API Documentation**: Covered in internal API specification
- **Trace IDs**: Included in error responses for support debugging
- **Logging**: Detailed server-side logging for troubleshooting
- **Rollback**: Feature can be disabled by removing delete buttons from templates
