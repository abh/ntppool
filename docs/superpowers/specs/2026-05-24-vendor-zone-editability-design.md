# Vendor Zone Editability and Error Surfacing

Date: 2026-05-24
Status: Approved (design)

## Problem

Editing a vendor zone that is already submitted ("Processing") leads to a dead
end: the user clicks "Continue" on the edit form, the save silently fails, and a
blank form is shown with no error message.

Two distinct causes:

1. **Editability rule mismatch (root cause).** During the Perl→Go migration the
   UI editability gate became `status ne 'Approved'`, which matches neither the
   old Perl rule nor the Go API. The Go API only permits edits when
   `status == 'New'` (`UpdateVendorZone`, enforced in `update.go` and the SQL
   `WHERE status='New'`). So the UI offers an edit form the API rejects with
   `zone cannot be edited after submission`.

   The Go API's `status='New'`-only restriction was introduced during migration,
   not as a deliberate product decision. The original Perl `can_edit` allowed:
   - `vendor_admin`: edit any status
   - account member: edit only when `status == 'New'`

2. **Errors are swallowed by the UI.** When the API rejects the edit:
   - `_edit_zone` returns the error as an arrayref `[msg]`, but `form.html` only
     reads field-keyed errors (`errors.zone_name`, …) — so nothing renders.
   - On error `$result->{data}` is undef, so `_edit_zone` returns an undef zone;
     `render_form(undef)` takes the "new zone" branch → blank form.
   - `show.html` renders no errors at all, so `render_submit`'s
     `{general => ...}` error (Vendor.pm:402) is also silently lost.

## Goals

- Restore sensible editability: let users fix and resubmit rejected zones, and
  let staff edit zones in any status (with name locked once live).
- Guarantee that API errors are always shown in the UI, with the trace_id when
  available.

## Editability Matrix

Editable content fields: `zone_name`, `organization_name`,
`request_information`, `device_count`, `device_information`,
`contact_information`, `client_type`, `opensource_info`.

Never editable via the edit endpoint: `id`, `id_token`, `status`, `account_id`,
`user_id`, `dns_root_id`, `approved_on`, `rt_ticket`, `created_on`,
`modified_on`.

| Status   | Regular account user            | vendor_admin                       |
|----------|---------------------------------|------------------------------------|
| New      | edit all content fields         | edit all content fields            |
| Pending  | edit all content fields         | edit all content fields            |
| Rejected | edit all content fields + resubmit | edit all content fields         |
| Approved | read-only                       | edit all content fields **except `zone_name`** |

Derived rules:

- **Approval status is never changed by the edit endpoint.** Status transitions
  go through the separate admin-only `UpdateVendorZoneStatus` RPC, so protecting
  approval status requires no special handling in the edit path.
- **`zone_name` is locked only on Approved** (the DNS origin is live). On
  New/Pending/Rejected the name is still editable since nothing is provisioned.

## Resubmit Flow

`SubmitVendorZone` accepts `New → Pending` **and** `Rejected → Pending`. A
rejected zone the user has corrected is resubmitted with the same submit action
(button relabeled for the Rejected case). Re-approving a Rejected zone already
works on the admin side (`UpdateVendorZoneStatus` allows `status IN
('Pending','Rejected')`).

## Go API Changes (`~/src/go/ntp/api`)

### `UpdateVendorZone` (`server/api/vendorzone/update.go` + `sql/vendor_zones.sql`)

- Remove the blanket `status='New'` gate.
- After the existing authorization check (vendor_admin OR user-in-account):
  - If `status == 'Approved'` and **not** vendor_admin → `FailedPrecondition`
    ("approved zones can only be edited by staff").
  - If `status == 'Approved'` (admin) → reject any `zone_name` change with
    `InvalidArgument` ("zone name cannot be changed after approval"); other
    content fields update normally.
- SQL `UpdateVendorZone`: drop `AND status='New'`. Status/role enforcement lives
  in Go (zone already fetched). Keep the zone-name uniqueness check.

### `SubmitVendorZone` (`server/api/vendorzone/submit.go` + SQL)

- Change the Go status check and SQL `WHERE` clause from `status='New'` to
  `status IN ('New','Rejected')`. Update the rejection message accordingly.

### Codegen + tests

- Regenerate sqlc (`go tool sqlc generate`); stage all generated files.
- Update integration tests that assert "updates blocked after submission"
  (e.g. `workflow_integration_test.go`, `update_integration_test.go`) to match
  the new matrix; add cases for: user editing Pending, user editing + resubmit
  from Rejected, admin editing Approved (name change rejected, other fields ok),
  non-admin blocked on Approved.

## Perl UI Changes (`lib/NTPPool/Control/Vendor.pm` + templates)

### Editability gate

- `can_edit_zone`:
  - vendor_admin → true for any status
  - regular user → `status ne 'Approved'`
- `render_zone` edit-mode gate (currently Vendor.pm:229-230): same rule. When
  not editable, fall through to the read-only show page.
- Edit form: when `status == 'Approved'`, render `zone_name` read-only/disabled
  (CSP-compliant — no inline styles/handlers).

### Resubmit

- `show.html`: show the submit button for `Rejected` zones as well as `New`
  (relabel to "Resubmit for production" when Rejected). Keep existing
  subscription gating.

### Error surfacing (always show errors, with trace_id)

- New shared partial `docs/manage/tpl/vendor/_errors.html`: renders a Bootstrap
  `alert alert-danger` when `errors.general` is set, with a small
  "Trace ID: …" line when `errors.trace_id` is present. Included at the top of
  both `form.html` and `show.html`. Field-keyed errors continue to render inline.
- Every CAPI error path in `Vendor.pm` sets
  `errors => { general => $result->{error}, trace_id => $result->{trace_id} }`
  (merging any field-specific errors the API returns). Covers `_edit_zone`,
  `render_submit`, `render_zone`, and the admin/subscription paths.
- `_edit_zone`: on error, return the errors hashref and re-fetch the current
  zone (via `get_vendor_zone`) so `render_form` keeps the user's context instead
  of rendering a blank "new zone" form.
- `render_edit_json`: error shape becomes the hashref (general + trace_id);
  acceptable for JSON consumers.

## Error Handling

- API/transport failures surface as `errors.general` + `errors.trace_id` on the
  relevant page; the page still renders (no blank pages, no bare 500s where a
  zone context exists).
- Validation errors returned by the API keep their field mapping where provided;
  otherwise they fall back to `errors.general`.

## Testing

- Go: integration tests per the matrix above (statuses × roles, resubmit,
  name-lock on Approved).
- Perl: manual verification on the dev site (web.askdev.grundclock.com) of:
  user edit of Pending, edit + resubmit of Rejected, admin edit of Approved with
  name locked, and that an induced API error renders the alert with a trace_id.

## Out of Scope

- Changing the admin approve/reject workflow or `UpdateVendorZoneStatus`.
- Subscription/billing logic changes beyond passing their errors through the new
  error partial.
