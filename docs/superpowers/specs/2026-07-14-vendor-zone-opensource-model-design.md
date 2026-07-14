# Vendor Zone Open-Source Model — Design

**Date:** 2026-07-14
**Issue:** #39 — Vendor zone submission silently forces paid zones into `opensource=true`
**Status:** Approved design, ready for implementation plan

## Problem

`vendor_zones.opensource` is a single boolean asked to encode three different
facts at once:

1. The vendor's **claim** — "I'm applying under the free open-source plan."
2. Staff's **determination** — "we grant the open-source exemption."
3. Implicitly, the funding **track** (open-source grant vs. paid subscription).

The submit form writes this boolean at submit time, inferred from the template
guard `!need_subscription`. That guard is true for *paying* vendors (already
covered by a subscription) and for all Rejected zones — exactly the wrong
population. Commit `edec7946` swapped the plain "Submit for production" button
for `_opensource.html`, whose form hard-codes `opensource_request=1`, so any
submission through that path now persists `opensource=true`. A paying vendor's
zone gets silently reclassified as non-revenue open-source (#39).

The deeper defect surfaced during review: a common rejection reason is "the
project isn't actually open source." A zone rejected for that reason is stored
`opensource=true, status=Rejected` — the database asserts the opposite of the
finding that caused the rejection. And `status.go` (approve/reject) never
touches `opensource` at all, so there is no determination step and no place to
record a rejection reason. The claim is mislabeled as truth.

## Approach

Split the overloaded boolean into the two facts the workflow actually
distinguishes — the vendor's claim and staff's determination — and add the
missing rejection reason. "Paid" is derived from `account_subscriptions` (an
account-level fact), not stored on the zone.

Per-zone comps/sponsorships are a deliberate non-goal: all funding is
account-level today, which has been sufficient. The two-column split leaves
room to add a zone-level funding track later without rework.

## Data model — `vendor_zones`

```sql
opensource_requested  boolean NOT NULL DEFAULT false   -- vendor's claim (set at submit)
opensource_approved   boolean NULL                     -- staff determination (NULL = undecided)
opensource_info       text                             -- justification (unchanged)
rejection_reason      text NULL                         -- why rejected, e.g. "not open source"
-- dropped: opensource
```

`status` (`New → Pending → Approved/Rejected`) is unchanged; it describes the
review lifecycle, not funding.

State meanings:

| Scenario | requested | approved | reason |
|---|---|---|---|
| New/Pending, undecided | claim | `NULL` | `NULL` |
| Approved as open-source | `true` | `true` | `NULL` |
| Approved, paid/covered | `false` | `false` | `NULL` |
| Rejected — not open source | `true` | `false` | text |
| Rejected — other | claim | `false` | text |

## Backfill (from existing `opensource`)

- `opensource_requested` ← old `opensource`
- `opensource_approved` ←
  - `true`  when `status = 'Approved' AND opensource`
  - `false` when `status IN ('Approved','Rejected')` (otherwise)
  - `NULL`  when `status IN ('New','Pending')` (undecided)
- `rejection_reason` ← `NULL` (historically unknown)

Sequencing: this is the pre-cutover postgres branch with no live production
data on PostgreSQL yet, so there is no rolling-deploy constraint. Do it as one
migration: add columns, backfill from `opensource`, drop `opensource`, with the
Go and Perl code updated in the same change.

The MySQL→PostgreSQL import mapping (pgloader) must target the new columns
rather than `opensource`; update it alongside the migration so a re-import
produces the split columns.

## Go API changes (`../go/ntp/api`)

- **Proto** (`ntppool/vendorzone/v1`):
  - `VendorZoneContent.opensource` → `opensource_requested`.
  - `UpdateVendorZoneStatusRequest` gains `opensource_approved` (bool) and
    `rejection_reason` (string).
  - `VendorZone` message gains `opensource_requested`, `opensource_approved`,
    `rejection_reason` so Perl can route on them.
- **`submit.go`**: write `opensource_requested` from content; the
  `zone.Opensource && !OpensourceInfo.Valid` validation becomes
  `opensource_requested && !info`.
- **`status.go`** (approve/reject): write `opensource_approved` and
  `rejection_reason` in the same transaction as the status change, so the
  determination is recorded atomically with the transition.
- **`buildVendorZone`** and the sqlc queries
  (`UpdateVendorZone`, `UpdateVendorZoneStatus`, `contentToUpdateParams`)
  updated for the new columns. Regenerate sqlc; stage all generated files.
- Out of scope: `SubmitVendorZoneResponse.NeedsSubscription` is a stub
  (always `true`) and unused by Perl, which computes `need_subscription` itself
  via `get_account_subscription_status`.

## Perl changes (this repo)

- **`docs/manage/tpl/vendor/show.html`**: the submit control stops keying off
  `!need_subscription`:
  - New/Rejected zone **already covered** by a subscription (paying) → plain
    "Submit for production" / "Resubmit for production" button →
    `opensource_requested = false`, no justification form.
  - New zone **not covered** → the existing products page
    (`_opensource.html` justification + paid products side by side) lets the
    vendor choose their track. Already correct; unchanged.
  - Rejected zone whose stored claim was open-source → the `_opensource.html`
    justification form for resubmission.
- **admin approve/reject form** (`show.html`, vendor_admin block): add an
  open-source-grant control and a rejection-reason field.
- **`lib/NTPPool/Control/Vendor.pm`**:
  - `render_submit` sends `opensource_requested`.
  - the admin status change sends `opensource_approved` + `rejection_reason`.

## Testing

- **Go integration** (`submit_integration_test.go`): a covered/paying vendor
  submits a New zone → assert persisted `opensource_requested = false` and
  `opensource_approved` stays `NULL`. This is the invariant whose absence let
  #39 ship.
- **Go integration** (`status_integration_test.go`): approve as open-source →
  `opensource_approved = true`; reject with a reason →
  `opensource_approved = false`, `rejection_reason` set.
- **Perl/e2e**: a covered vendor's submit page shows the plain button, not the
  justification form; a paid submission does not set `opensource_requested`.

## Non-goals

- Per-zone funding arrangements / comps (account-level is sufficient today).
- Restructuring `account_subscriptions`.
- Fixing the `NeedsSubscription` stub in the Go API.
- A structured rejection-reason enum — free text now; enum can come later
  without a data migration beyond the values themselves.
