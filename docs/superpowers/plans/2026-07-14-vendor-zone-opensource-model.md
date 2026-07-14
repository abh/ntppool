# Vendor Zone Open-Source Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the overloaded `vendor_zones.opensource` boolean into a vendor *claim* (`opensource_requested`) and a staff *determination* (`opensource_approved`), add a `rejection_reason`, and route the submit UI on subscription coverage + stored claim instead of the `!need_subscription` guard — fixing #39 (paying vendors silently reclassified as open-source).

**Architecture:** Cross-repo change. The Go API (`../go/ntp/api`) owns the schema, ConnectRPC contract, and handlers; the Perl frontend (this repo) owns the template routing and controller. The Perl CAPI client (`lib/NP/CAPI/VendorZone.pm`) is **generated** from the proto via `protoc-gen-perl-capi` (the go repo's `ntppool/` output dir is a symlink to this repo), so it is regenerated, never hand-edited. The change is additive first (new columns/fields alongside `opensource`), then the old column/field is dropped in a final cleanup task, so every task leaves both repos compiling and green.

**Tech Stack:** Go, PostgreSQL, goose migrations, sqlc (`pgx/v5`), buf/ConnectRPC, Perl (Combust/Template Toolkit), Playwright (e2e).

## Global Constraints

- Two repos: Go API at `/Users/ask/src/go/ntp/api`, Perl frontend at `/Users/ask/src/ntppool`. Commit in the repo the file lives in.
- Regenerate after schema/proto edits: `make sqlc` (schema/queries) and `make generate` (proto → Go `gen/` **and** Perl `lib/NP/CAPI/VendorZone.pm`). After any generator run, `git status` and stage ALL generated files in both repos.
- sqlc reads its schema from `db/migrations/`, not `schema.sql`. `schema.sql` is a pg_dump artifact refreshed separately via `make test-db-schema`.
- All `GetVendorZoneByTokenRow`-family query result structs must keep an identical column set and order — `buildVendorZone` does direct `GetVendorZoneByTokenRow(v)` conversions. New columns go into every SELECT/RETURNING list in `sql/vendor_zones.sql` at the same position.
- "Paid" is derived from `account_subscriptions`; it is NOT a `vendor_zones` column. Per-zone comps are out of scope.
- `rejection_reason` is free text (no enum). `opensource_approved` is nullable (`NULL` = undecided).
- Perl: run `perltidy` on modified `.pm` files, trim trailing whitespace, before committing. Never `git add -A`/`.`; stage explicit paths. Never `git commit --no-verify`.
- CSP: no inline styles or scripts in templates — Bootstrap classes only.
- Backfill semantics: `opensource_requested ← opensource`; `opensource_approved ← true` when `status='Approved' AND opensource`, `false` when `status IN ('Approved','Rejected')`, else `NULL`; `rejection_reason ← NULL`.

---

### Task 1: Schema migration + sqlc queries (Go API, additive)

**Files:**
- Create: `/Users/ask/src/go/ntp/api/db/migrations/025_vendor_zones_opensource_claim.sql`
- Modify: `/Users/ask/src/go/ntp/api/sql/vendor_zones.sql`
- Generated (stage after `make sqlc`): `/Users/ask/src/go/ntp/api/ntpdb/*.sql.go`, `ntpdb/models.go`, `ntpdb/querier.go`

**Interfaces:**
- Produces (via sqlc regen): `ntpdb.GetVendorZoneByTokenRow` gains `OpensourceRequested bool`, `OpensourceApproved pgtype.Bool`, `RejectionReason pgtype.Text`; `ntpdb.UpdateVendorZoneParams` gains `OpensourceRequested pgtype.Bool`; `ntpdb.UpdateVendorZoneStatusParams` gains `OpensourceApproved pgtype.Bool`, `RejectionReason pgtype.Text`. The old `Opensource bool` / `Opensource pgtype.Bool` fields remain (additive phase).

- [ ] **Step 1: Write the migration**

Create `db/migrations/025_vendor_zones_opensource_claim.sql`:

```sql
-- +goose Up
-- Split the overloaded `opensource` boolean into the vendor's claim
-- (opensource_requested, set at submit) and staff's determination
-- (opensource_approved, set at approve/reject; NULL = undecided), and add a
-- free-text rejection_reason. `opensource` is kept for now and dropped in a
-- later migration once all code reads the new columns.
ALTER TABLE vendor_zones ADD COLUMN opensource_requested boolean NOT NULL DEFAULT false;
ALTER TABLE vendor_zones ADD COLUMN opensource_approved boolean;
ALTER TABLE vendor_zones ADD COLUMN rejection_reason text;

UPDATE vendor_zones SET opensource_requested = opensource;
UPDATE vendor_zones SET opensource_approved = CASE
    WHEN status = 'Approved' AND opensource THEN true
    WHEN status IN ('Approved', 'Rejected')  THEN false
    ELSE NULL
END;

-- +goose Down
ALTER TABLE vendor_zones DROP COLUMN rejection_reason;
ALTER TABLE vendor_zones DROP COLUMN opensource_approved;
ALTER TABLE vendor_zones DROP COLUMN opensource_requested;
```

- [ ] **Step 2: Add the new columns to every SELECT/RETURNING list in `sql/vendor_zones.sql`**

In each of `GetVendorZonesByAccount`, `GetVendorZoneByID`, `GetVendorZoneByToken`, `GetVendorZoneByTokenForUpdate`, `CreateVendorZone` (RETURNING), `UpdateVendorZone` (RETURNING), and `ListVendorZonesAdmin` (as `vz.`-prefixed), replace the `client_type, opensource, opensource_info,` fragment so it reads (use `vz.` prefixes only in `ListVendorZonesAdmin`):

```sql
       client_type, opensource, opensource_info,
       opensource_requested, opensource_approved, rejection_reason,
       rt_ticket,
```

- [ ] **Step 3: Extend the `UpdateVendorZone` SET clause**

In `UpdateVendorZone`, add `opensource_requested` next to the existing opensource lines:

```sql
  opensource = COALESCE(sqlc.narg(opensource), opensource),
  opensource_requested = COALESCE(sqlc.narg(opensource_requested), opensource_requested),
  opensource_info = COALESCE(sqlc.narg(opensource_info), opensource_info),
```

- [ ] **Step 4: Extend the `UpdateVendorZoneStatus` SET clause**

In `UpdateVendorZoneStatus`, add the determination fields after the `rt_ticket` line:

```sql
  rt_ticket = COALESCE(sqlc.arg(rt_ticket), rt_ticket),
  opensource_approved = COALESCE(sqlc.narg(opensource_approved), opensource_approved),
  rejection_reason = COALESCE(sqlc.narg(rejection_reason), rejection_reason),
```

- [ ] **Step 5: Regenerate sqlc and verify it compiles**

Run: `cd /Users/ask/src/go/ntp/api && make sqlc && go build ./...`
Expected: sqlc compiles and generates without error; `go build` succeeds (existing handlers still reference the retained `Opensource` field, so nothing breaks).

- [ ] **Step 6: Apply the migration to the test DB and confirm columns exist**

Run:
```bash
cd /Users/ask/src/go/ntp/api
make test-db-start
go run . migrate   # applies goose migrations
make test-db-shell <<'SQL'
\d vendor_zones
SQL
```
Expected: `vendor_zones` shows `opensource_requested`, `opensource_approved`, `rejection_reason`.

- [ ] **Step 7: Commit (in the Go repo)**

```bash
cd /Users/ask/src/go/ntp/api
git add db/migrations/025_vendor_zones_opensource_claim.sql sql/vendor_zones.sql ntpdb/
git status
git commit -m "$(cat <<'EOF'
feat(vendorzone): add opensource_requested/approved + rejection_reason columns

Additive migration splitting the overloaded opensource boolean into the
vendor's claim and staff's determination, with a free-text rejection reason.
The old opensource column is retained until code cutover. Refs #39.
EOF
)"
```

---

### Task 2: Proto contract + regenerate Go and Perl clients (Go API)

**Files:**
- Modify: `/Users/ask/src/go/ntp/api/proto/ntppool/vendorzone/v1/vendor.proto`
- Generated (stage after `make generate`): `/Users/ask/src/go/ntp/api/gen/ntppool/vendorzone/v1/*.go`, and in this repo `/Users/ask/src/ntppool/lib/NP/CAPI/VendorZone.pm`

**Interfaces:**
- Consumes: nothing.
- Produces: `vendorzonev1.VendorZoneContent.OpensourceRequested *bool`; `vendorzonev1.VendorZone.OpensourceRequested bool`, `.OpensourceApproved *bool`, `.RejectionReason *string`; `vendorzonev1.UpdateVendorZoneStatusRequest.OpensourceApproved *bool`, `.RejectionReason *string`. Generated Perl `update_vendor_zone_status` accepts `opensource_approved` and `rejection_reason` keys.

- [ ] **Step 1: Add `opensource_requested` to `VendorZoneContent`**

After the `optional bool opensource = 8;` line in `message VendorZoneContent`:

```proto
  optional bool   opensource = 8;
  optional string opensource_info = 9;
  // opensource_requested is the vendor's claim (replaces opensource).
  optional bool   opensource_requested = 10;
```

- [ ] **Step 2: Add the three fields to `message VendorZone`**

After `optional string opensource_info = 14;` … keep existing fields, and append at the end of the message (next free field numbers):

```proto
  // opensource_requested is the vendor's claim ("applying as open source").
  bool opensource_requested = 18;
  // opensource_approved is staff's determination (unset = undecided).
  optional bool opensource_approved = 19;
  // rejection_reason is free-text why a zone was rejected (e.g. "not open source").
  optional string rejection_reason = 20;
```

- [ ] **Step 3: Add determination inputs to `UpdateVendorZoneStatusRequest`**

After `optional int32 rt_ticket = 3;`:

```proto
  // opensource_approved records whether the open-source exemption was granted.
  optional bool opensource_approved = 4;
  // rejection_reason is free-text shown to the vendor on rejection.
  optional string rejection_reason = 5;
```

- [ ] **Step 4: Lint, regenerate both clients, verify compile**

Run:
```bash
cd /Users/ask/src/go/ntp/api
make buf-lint
make generate
go build ./...
```
Expected: lint passes; `gen/` and `../ntppool/lib/NP/CAPI/VendorZone.pm` regenerate; `go build` succeeds.

- [ ] **Step 5: Confirm the generated Perl client picked up the new status fields**

Run: `grep -n "opensource_approved\|rejection_reason\|opensource_requested" /Users/ask/src/ntppool/lib/NP/CAPI/VendorZone.pm`
Expected: `update_vendor_zone_status` extracts `opensource_approved` and `rejection_reason` into `%request`; content docs mention `opensource_requested`.

- [ ] **Step 6: Commit the Go-repo generated files**

```bash
cd /Users/ask/src/go/ntp/api
git add proto/ntppool/vendorzone/v1/vendor.proto gen/
git status
git commit -m "$(cat <<'EOF'
feat(vendorzone): proto for opensource claim/determination + rejection reason

Adds opensource_requested to VendorZoneContent/VendorZone and
opensource_approved + rejection_reason to VendorZone and the status-update
request. Refs #39.
EOF
)"
```

- [ ] **Step 7: Commit the regenerated Perl client (in the ntppool repo)**

```bash
cd /Users/ask/src/ntppool
git add lib/NP/CAPI/VendorZone.pm
git status
git commit -m "$(cat <<'EOF'
chore(capi): regenerate VendorZone client for opensource claim/determination

Generated from vendorzone/v1 proto. Refs #39.
EOF
)"
```

---

### Task 3: Handler logic + Go integration tests (Go API)

**Files:**
- Modify: `/Users/ask/src/go/ntp/api/server/api/vendorzone/update.go` (`contentToUpdateParams`, `hasContentChanges`)
- Modify: `/Users/ask/src/go/ntp/api/server/api/vendorzone/submit.go` (validation)
- Modify: `/Users/ask/src/go/ntp/api/server/api/vendorzone/status.go` (write determination)
- Modify: `/Users/ask/src/go/ntp/api/server/api/vendorzone/vendorzone.go` (`buildVendorZone`)
- Test: `/Users/ask/src/go/ntp/api/server/api/vendorzone/submit_integration_test.go`, `status_integration_test.go`

**Interfaces:**
- Consumes: Task 1 params/rows, Task 2 proto fields.
- Produces: submit persists `opensource_requested` from content; approve/reject persist `opensource_approved` + `rejection_reason`; `buildVendorZone` fills the three new proto fields.

- [ ] **Step 1: Write the failing submit invariant test**

Append to `submit_integration_test.go` (reuses the setup pattern already in the file — a fresh zone with `opensource=false`, `status='New'`):

```go
func TestSubmitVendorZone_DoesNotForceOpensource(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set, skipping integration tests")
	}
	ctx := context.Background()
	db, err := pgxpool.New(ctx, dbURL)
	require.NoError(t, err)
	defer db.Close()

	vzAPI, err := vendorzone.New(base.BaseAPI{DB: db})
	require.NoError(t, err)
	ids := testhelpers.GetVendorZoneTestIDs()
	defer testhelpers.CleanupIntegrationTestData(t, ctx, db, ids)

	seedVendorZoneForSubmit(t, ctx, db, ids, "vz_osclaim1") // helper below

	testUser := ntpdb.UserX{User: ntpdb.User{ID: int64(ids.UserIDs[0]), Email: fmt.Sprintf("vzsub%d@example.com", ids.UserIDs[0])}}
	ctx = sessions.SetTestUserInContext(ctx, testUser)
	ctx = sessions.SetTestAccountInContext(ctx, ntpdb.Account{ID: int64(ids.AccountIDs[0])})

	// Submit with NO opensource fields in content (a plain "submit for production").
	resp, err := vzAPI.SubmitVendorZone(ctx, connect.NewRequest(&vendorzonev1.SubmitVendorZoneRequest{
		IdToken: "vz_osclaim1",
	}))
	require.NoError(t, err)
	require.True(t, resp.Msg.Success)

	q := ntpdb.New(db)
	zone, err := q.GetVendorZoneByToken(ctx, pgtype.Text{String: "vz_osclaim1", Valid: true})
	require.NoError(t, err)
	assert.False(t, zone.OpensourceRequested, "plain submit must not set opensource_requested")
	assert.False(t, zone.OpensourceApproved.Valid, "submit must not touch the determination")
}
```

Add a small seed helper near the top of the test file (extract from the existing `TestSubmitVendorZone` INSERT so the DRY rule holds):

```go
func seedVendorZoneForSubmit(t *testing.T, ctx context.Context, db *pgxpool.Pool, ids testhelpers.VendorZoneTestIDs, token string) {
	t.Helper()
	// accounts/users/dns_root setup identical to TestSubmitVendorZone; call the
	// existing setup or inline the same INSERTs, then:
	_, err := db.Exec(ctx, `
		INSERT INTO vendor_zones (
			id, id_token, account_id, user_id, dns_root_id, zone_name,
			organization_name, request_information, device_count, client_type,
			opensource, opensource_requested, status, created_on, modified_on
		) VALUES ($1, $2, $3, $4, $5, $6, 'Org', 'usage', 5000, 'ntp', false, false, 'New', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		ON CONFLICT (id) DO NOTHING
	`, ids.VendorZoneIDs[0], token, int64(ids.AccountIDs[0]), int64(ids.UserIDs[0]), 1, fmt.Sprintf("t%d", ids.VendorZoneIDs[0]))
	require.NoError(t, err)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/ask/src/go/ntp/api && make test-integration ARGS="./server/api/vendorzone -run TestSubmitVendorZone_DoesNotForceOpensource"`
Expected: FAIL — compile error `zone.OpensourceRequested undefined` is expected only if Task 1 didn't regen; if it compiles, it fails at the assertions once handlers still read the old field. (If the DB isn't available it will `t.Skip`; start it with `make test-db-start` first.)

- [ ] **Step 3: Map the new content field in `update.go`**

In `contentToUpdateParams`, after the `content.Opensource` block:

```go
	if content.Opensource != nil {
		params.Opensource = pgtype.Bool{Bool: *content.Opensource, Valid: true}
	}
	if content.OpensourceRequested != nil {
		params.OpensourceRequested = pgtype.Bool{Bool: *content.OpensourceRequested, Valid: true}
	}
```

In `hasContentChanges`, add the new field to the OR chain:

```go
		content.Opensource != nil ||
		content.OpensourceRequested != nil ||
		content.OpensourceInfo != nil
```

- [ ] **Step 4: Update the submit validation in `submit.go`**

Replace the opensource_info requirement check so it reads the claim field:

```go
	// Validate opensource_info requirement using the post-update values
	if zone.OpensourceRequested && !zone.OpensourceInfo.Valid {
		return nil, connect.NewError(connect.CodeInvalidArgument,
			fmt.Errorf("opensource_info is required for open source projects"))
	}
```

- [ ] **Step 5: Write the determination in `status.go`**

In `UpdateVendorZoneStatus`, extend the params built before the `UpdateVendorZoneStatus` call:

```go
	params := ntpdb.UpdateVendorZoneStatusParams{
		ID:       zone.ID,
		Status:   newStatus,
		RtTicket: pgtype.Int4{Valid: false},
	}
	if req.Msg.RtTicket != nil {
		params.RtTicket = pgtype.Int4{Int32: *req.Msg.RtTicket, Valid: true}
	}
	if req.Msg.OpensourceApproved != nil {
		params.OpensourceApproved = pgtype.Bool{Bool: *req.Msg.OpensourceApproved, Valid: true}
	}
	if req.Msg.RejectionReason != nil {
		params.RejectionReason = pgtype.Text{String: *req.Msg.RejectionReason, Valid: true}
	}
```

- [ ] **Step 6: Expose the fields in `buildVendorZone` (`vendorzone.go`)**

In the `ListVendorZonesAdminRow` case of the type switch, add the three fields to the struct literal (alongside `Opensource`/`OpensourceInfo`):

```go
			Opensource:          v.Opensource,
			OpensourceInfo:      v.OpensourceInfo,
			OpensourceRequested: v.OpensourceRequested,
			OpensourceApproved:  v.OpensourceApproved,
			RejectionReason:     v.RejectionReason,
```

In the `vz := &vendorzonev1.VendorZone{...}` literal, add:

```go
		Opensource:          zone.Opensource,
		OpensourceRequested: zone.OpensourceRequested,
```

After the existing optional-field blocks, add:

```go
	if zone.OpensourceApproved.Valid {
		approved := zone.OpensourceApproved.Bool
		vz.OpensourceApproved = &approved
	}
	if zone.RejectionReason.Valid {
		vz.RejectionReason = &zone.RejectionReason.String
	}
```

- [ ] **Step 7: Add the approve/reject determination test**

Append to `status_integration_test.go` (follow the file's existing setup for a `Pending` zone and a vendor_admin user):

```go
func TestUpdateVendorZoneStatus_RecordsDetermination(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set, skipping integration tests")
	}
	ctx := context.Background()
	db, err := pgxpool.New(ctx, dbURL)
	require.NoError(t, err)
	defer db.Close()

	vzAPI, err := vendorzone.New(base.BaseAPI{DB: db})
	require.NoError(t, err)
	ids := testhelpers.GetVendorZoneTestIDs()
	defer testhelpers.CleanupIntegrationTestData(t, ctx, db, ids)

	seedPendingVendorZone(t, ctx, db, ids, "vz_det1")   // status='Pending', follows file's pattern
	ctx = sessions.SetTestUserInContext(ctx, vendorAdminUser(ids)) // helper already in file or inline privilege

	// Reject with a reason.
	falseVal := false
	reason := "not open source"
	_, err = vzAPI.UpdateVendorZoneStatus(ctx, connect.NewRequest(&vendorzonev1.UpdateVendorZoneStatusRequest{
		IdToken:            "vz_det1",
		Status:             "Rejected",
		OpensourceApproved: &falseVal,
		RejectionReason:    &reason,
	}))
	require.NoError(t, err)

	q := ntpdb.New(db)
	zone, err := q.GetVendorZoneByToken(ctx, pgtype.Text{String: "vz_det1", Valid: true})
	require.NoError(t, err)
	require.True(t, zone.OpensourceApproved.Valid)
	assert.False(t, zone.OpensourceApproved.Bool)
	assert.Equal(t, "not open source", zone.RejectionReason.String)
}
```

(Reuse existing seed/admin helpers in the file; if none exist, inline the same INSERT/privilege setup used by the other tests in `status_integration_test.go` — do not duplicate production logic.)

- [ ] **Step 8: Run both tests to verify they pass**

Run: `cd /Users/ask/src/go/ntp/api && make test-integration ARGS="./server/api/vendorzone -run 'TestSubmitVendorZone_DoesNotForceOpensource|TestUpdateVendorZoneStatus_RecordsDetermination'"`
Expected: PASS (2 tests).

- [ ] **Step 9: Run the full vendorzone suite + build**

Run: `cd /Users/ask/src/go/ntp/api && go build ./... && make test-integration ARGS="./server/api/vendorzone"`
Expected: build succeeds; all vendorzone tests pass (no regressions in existing submit/status tests).

- [ ] **Step 10: Commit (Go repo)**

```bash
cd /Users/ask/src/go/ntp/api
git add server/api/vendorzone/
git status
git commit -m "$(cat <<'EOF'
feat(vendorzone): write opensource claim on submit, determination on review

Submit persists opensource_requested (never forcing it); approve/reject
persist opensource_approved + rejection_reason in the status transaction.
buildVendorZone exposes all three. Adds integration tests for both
invariants. Refs #39.
EOF
)"
```

---

### Task 4: Perl controller — send claim on submit, determination on review

**Files:**
- Modify: `/Users/ask/src/ntppool/lib/NTPPool/Control/Vendor.pm` (`render_submit` ~400-413, `render_admin` reject ~811 and approve ~839)

**Interfaces:**
- Consumes: generated CAPI `submit_vendor_zone` (content passthrough) and `update_vendor_zone_status` (accepts `opensource_approved`, `rejection_reason`) from Task 2.
- Produces: `vz.opensource_requested` / `vz.opensource_approved` / `vz.rejection_reason` available to templates via the API response (already exposed by Task 3).

- [ ] **Step 1: Send `opensource_requested` from `render_submit`**

Replace the submit block (currently sends `opensource`):

```perl
    # Submit zone via API
    my $opensource_requested =
      $self->req_param('opensource_request') ? JSON::XS::true : JSON::XS::false;
    my $submit_result = submit_vendor_zone(
        $self->api_auth_params,
        account  => $self->current_account->{id_token},
        id_token => $id,
        content  => {
            opensource_requested => $opensource_requested,
            opensource_info      => $opensource_info,
        },
    );
```

- [ ] **Step 2: Send the determination on reject (`render_admin`)**

In the reject branch, extend the `update_vendor_zone_status` call:

```perl
                my $update_result = update_vendor_zone_status(
                    auth              => $self->plain_cookie($self->user_cookie_name),
                    context           => $self->_get_request_context(),
                    id_token          => $id,
                    status            => 'Rejected',
                    opensource_approved => JSON::XS::false,
                    rejection_reason  => scalar($self->req_param('rejection_reason') // ''),
                );
```

- [ ] **Step 3: Send the determination on approve (`render_admin`)**

In the approve branch, extend the `update_vendor_zone_status` call:

```perl
                my $update_result = update_vendor_zone_status(
                    auth              => $self->plain_cookie($self->user_cookie_name),
                    context           => $self->_get_request_context(),
                    id_token          => $id,
                    status            => 'Approved',
                    opensource_approved =>
                      $self->req_param('opensource_grant') ? JSON::XS::true : JSON::XS::false,
                );
```

- [ ] **Step 4: Format and syntax-check**

Run:
```bash
cd /Users/ask/src/ntppool
perltidy -b lib/NTPPool/Control/Vendor.pm && rm -f lib/NTPPool/Control/Vendor.pm.bak
perl -c -Ilib -Icombust/lib lib/NTPPool/Control/Vendor.pm
```
Expected: perltidy reformats cleanly; `perl -c` prints `syntax OK` (dependency warnings acceptable if it still reports OK).

- [ ] **Step 5: Commit**

```bash
cd /Users/ask/src/ntppool
git add lib/NTPPool/Control/Vendor.pm
git status
git commit -m "$(cat <<'EOF'
feat(vendor): send opensource_requested on submit, determination on review

render_submit sends the vendor's claim (never forcing opensource);
render_admin sends opensource_approved (+ rejection_reason on reject) so
the determination is recorded with the status transition. Refs #39.
EOF
)"
```

---

### Task 5: Perl template — route submit control on coverage + claim, add admin controls

**Files:**
- Modify: `/Users/ask/src/ntppool/docs/manage/tpl/vendor/show.html` (submit block ~86-90; vendor_admin block ~93-108)

**Interfaces:**
- Consumes: `have_subscription` and `need_subscription` tpl params (set in `render_show`/`render_submit`), and `vz.opensource_requested` from the API response (Task 3).

- [ ] **Step 1: Replace the submit-control block**

Replace the current comment + `[% IF (vz.status == 'New' || vz.status == 'Rejected') && !need_subscription %] [% PROCESS tpl/vendor/_opensource.html %] [% END %]` with:

```tt
    [% # Submit control for a New/Rejected zone. The paid-subscription products
       # page (below, when need_subscription) handles the "not yet covered"
       # case. Here: show the open-source justification form only when the
       # vendor's stored claim was open source AND they are not covered by a
       # subscription; otherwise a plain production submit that does NOT mark
       # the zone open source.
    %]
    [% IF (vz.status == 'New' || vz.status == 'Rejected') && !need_subscription %]
      [% IF vz.opensource_requested && !have_subscription %]
        [% PROCESS tpl/vendor/_opensource.html %]
      [% ELSE %]
        <form method="post" class="form-inline btn-inline" action="/manage/vendor/submit">
            <input type="hidden" name="id" value="[% vz.id_token %]" />
            <input type="hidden" name="auth_token" value="[% combust.auth_token %]" />
            <input type="hidden" name="a" value="[% combust.current_account.id_token %]">
            <input type="submit" class="btn btn-primary"
                value="[% vz.status == 'Rejected' ? 'Resubmit for production &rarr;' : 'Submit for production &rarr;' %]" />
        </form>
      [% END %]
    [% END %]
```

- [ ] **Step 2: Add admin determination controls to the vendor_admin block**

In the `[% IF combust.user.privileges.vendor_admin %]` form, replace the Approve/Reject buttons with controls that carry the determination (Bootstrap classes only — no inline styles):

```tt
        [% IF vz.status == 'Pending' or vz.status == 'Rejected' %]
        <div class="form-check mb-2">
          <input class="form-check-input" type="checkbox" name="opensource_grant" value="1"
                 id="opensource_grant"[% IF vz.opensource_requested %] checked[% END %]>
          <label class="form-check-label" for="opensource_grant">Grant open-source (non-revenue) plan</label>
        </div>
        <input class="btn btn-success" type="submit" name="status_change" value="Approve" />
        [% END %]
        [% IF vz.status == 'Pending' %]
        <div class="mt-3">
          <textarea class="form-control mb-2" name="rejection_reason" rows="2"
                    placeholder="Reason for rejection (e.g. not open source)"></textarea>
          <input class="btn btn-info btn-sm" type="submit" name="status_change" value="Reject" />
        </div>
        [% END %]
```

- [ ] **Step 3: Verify the rendered pages on the dev site**

Prereq: the Go API from Tasks 1-3 must be built and deployed to the dev environment, and this branch's templates live-reload on `web.askdev.grundclock.com`. Then, with a browser (Playwright or manual):

Run (manual check): open `https://web.askdev.grundclock.com/manage/vendor/zone?id=<covered_zone>&mode=show&x=1`
Expected: a **covered** vendor's New/Rejected zone shows the plain "Submit for production" button, NOT the open-source justification textarea. An admin viewing a Pending zone sees the "Grant open-source" checkbox and a rejection-reason textarea.

- [ ] **Step 4: Commit**

```bash
cd /Users/ask/src/ntppool
git add docs/manage/tpl/vendor/show.html
git status
git commit -m "$(cat <<'EOF'
fix(vendor): stop forcing paid zones through the open-source form (#39)

Route the New/Rejected submit control on subscription coverage and the
vendor's stored claim instead of !need_subscription: covered vendors get a
plain production submit (no opensource marking); the justification form
shows only for an uncovered open-source applicant. Adds admin controls to
grant the open-source plan and record a rejection reason.
EOF
)"
```

---

### Task 6: e2e regression test (Perl frontend)

**Files:**
- Modify: `/Users/ask/src/ntppool/e2e/tests/vendor.spec.ts`

**Interfaces:**
- Consumes: the deployed dev site with Tasks 1-5 in effect.

- [ ] **Step 1: Add the failing e2e case**

Following the existing patterns in `vendor.spec.ts` (auth/session setup, navigation to a vendor zone), add a test asserting a subscription-covered vendor's New/Rejected zone submit page shows the plain button and not the open-source justification textarea:

```ts
test('covered vendor submit page shows plain button, not the open-source form', async ({ page }) => {
  // Navigate to a vendor zone whose account has an active subscription (covered).
  // Reuse the spec's existing helper for logging in and opening a vendor zone.
  await openVendorZone(page, COVERED_ZONE_TOKEN); // existing helper / fixture in this spec

  // The open-source justification textarea must NOT be present for a covered vendor.
  await expect(page.locator('textarea[name="opensource_info"]')).toHaveCount(0);
  // A plain production submit button must be present.
  await expect(page.getByRole('button', { name: /Submit for production|Resubmit for production/ })).toBeVisible();
});
```

If the spec has no covered-zone fixture, add one following the existing fixture/setup convention in `e2e/tests/vendor.spec.ts` and `e2e/global-setup.ts` (do not invent a new harness).

- [ ] **Step 2: Run the e2e test**

Run: `cd /Users/ask/src/ntppool/e2e && npx playwright test tests/vendor.spec.ts -g "covered vendor submit page"`
Expected: PASS against the dev site with the fix deployed. (Before the Task 5 template change is deployed, this test fails because the textarea is present — that is the regression it guards.)

- [ ] **Step 3: Commit**

```bash
cd /Users/ask/src/ntppool
git add e2e/tests/vendor.spec.ts
git status
git commit -m "$(cat <<'EOF'
test(e2e): guard that covered vendors are not shown the open-source form (#39)
EOF
)"
```

---

### Task 7: Cleanup — drop the old `opensource` column and proto field

**Files:**
- Create: `/Users/ask/src/go/ntp/api/db/migrations/026_vendor_zones_drop_opensource.sql`
- Modify: `/Users/ask/src/go/ntp/api/sql/vendor_zones.sql` (remove `opensource` from lists + `UpdateVendorZone` SET)
- Modify: `/Users/ask/src/go/ntp/api/proto/ntppool/vendorzone/v1/vendor.proto` (remove `opensource` fields)
- Modify: `/Users/ask/src/go/ntp/api/server/api/vendorzone/{update.go,vendorzone.go}` (remove remaining `Opensource` reads)
- Generated (stage): `ntpdb/*`, `gen/*`, `/Users/ask/src/ntppool/lib/NP/CAPI/VendorZone.pm`

**Interfaces:**
- Consumes: everything above already reads the new columns/fields.
- Produces: `opensource` fully removed; `opensource_requested`/`opensource_approved`/`rejection_reason` are the sole representation.

- [ ] **Step 1: Find every remaining consumer of the old field**

Run:
```bash
cd /Users/ask/src/go/ntp/api && grep -rn "Opensource\b\|opensource\b" sql/ server/api/vendorzone/ proto/ --include='*.go' --include='*.sql' --include='*.proto' | grep -iv "opensource_requested\|opensource_approved\|opensource_info\|OpensourceRequested\|OpensourceApproved\|OpensourceInfo"
cd /Users/ask/src/ntppool && grep -rn "vz.opensource\b\|\bopensource\b" docs/manage/tpl/vendor/ lib/NTPPool/Control/Vendor.pm | grep -iv "opensource_requested\|opensource_approved\|opensource_info\|opensource_request\b\|_opensource.html\|opensource_grant"
```
Expected: a short list — `sql/vendor_zones.sql` column lists + `UpdateVendorZone` SET, `proto` fields 8/13, `update.go` `content.Opensource` block, `vendorzone.go` `Opensource:` assignments. Address each below; if the Perl grep surfaces a template still reading `vz.opensource`, switch it to `vz.opensource_requested`/`vz.opensource_approved` as appropriate.

- [ ] **Step 2: Write the drop migration**

Create `db/migrations/026_vendor_zones_drop_opensource.sql`:

```sql
-- +goose Up
-- opensource_requested / opensource_approved now carry the claim and the
-- determination; the old conflated column is no longer read.
ALTER TABLE vendor_zones DROP COLUMN opensource;

-- +goose Down
ALTER TABLE vendor_zones ADD COLUMN opensource boolean NOT NULL DEFAULT false;
UPDATE vendor_zones SET opensource = opensource_requested;
```

- [ ] **Step 3: Remove `opensource` from the queries**

In `sql/vendor_zones.sql`, delete `opensource,` from every SELECT/RETURNING list (leaving `opensource_info` and the three new columns) and delete the `opensource = COALESCE(sqlc.narg(opensource), opensource),` line from `UpdateVendorZone`.

- [ ] **Step 4: Remove the `opensource` proto fields**

In `vendor.proto`, delete `optional bool opensource = 8;` from `VendorZoneContent` and `bool opensource = 13;` from `VendorZone`. (Pre-cutover: the `buf breaking` check is expected to flag these; that is acceptable for this branch. Do not renumber other fields.)

- [ ] **Step 5: Remove remaining Go reads**

In `update.go`, delete the `if content.Opensource != nil { ... }` block and its `content.Opensource != nil ||` line in `hasContentChanges`. In `vendorzone.go`, delete the `Opensource: v.Opensource,` line in the admin-row case and `Opensource: zone.Opensource,` in the `vz` literal.

- [ ] **Step 6: Regenerate, rebuild, re-run tests**

Run:
```bash
cd /Users/ask/src/go/ntp/api
make sqlc && make generate && go build ./...
make test-db-reset && go run . migrate
make test-integration ARGS="./server/api/vendorzone"
```
Expected: generation and build succeed; migrations apply through 026; vendorzone tests pass.

- [ ] **Step 7: Refresh the schema dump**

Run: `cd /Users/ask/src/go/ntp/api && make test-db-schema`
Expected: `schema.sql` no longer lists `opensource` on `vendor_zones` and includes the three new columns.

- [ ] **Step 8: Commit (Go repo, then regenerated Perl client)**

```bash
cd /Users/ask/src/go/ntp/api
git add db/migrations/026_vendor_zones_drop_opensource.sql sql/vendor_zones.sql proto/ server/api/vendorzone/ ntpdb/ gen/ schema.sql
git status
git commit -m "$(cat <<'EOF'
refactor(vendorzone): drop the legacy opensource column and proto field

All code now reads opensource_requested / opensource_approved. Closes #39.
EOF
)"

cd /Users/ask/src/ntppool
git add lib/NP/CAPI/VendorZone.pm
git status
git commit -m "chore(capi): regenerate VendorZone client after dropping opensource field"
```

---

## Self-Review

**Spec coverage:**
- Schema split (`opensource_requested`/`opensource_approved`/`rejection_reason`, drop `opensource`) → Tasks 1, 7. ✓
- Backfill semantics → Task 1 Step 1 (matches spec table). ✓
- "Paid derived, not a column" → honored; no funding column added. ✓
- Go: proto rename/additions, submit validation, status determination, buildVendorZone, sqlc → Tasks 2, 3. ✓
- Perl: template routing on coverage + claim, admin controls, controller sends claim/determination, regenerated CAPI → Tasks 2 (regen), 4, 5. ✓
- Testing: Go submit invariant, Go approve/reject determination, e2e covered-vendor guard → Tasks 3, 6. ✓
- Non-goals (per-zone comps, subscription restructuring, NeedsSubscription stub, enum reason) → not implemented. ✓

**Placeholder scan:** Every code step contains concrete code/SQL/commands. Test helpers (`seedVendorZoneForSubmit`, `seedPendingVendorZone`, `vendorAdminUser`, `openVendorZone`) explicitly instruct reuse of existing per-file setup rather than inventing new harnesses, to satisfy DRY without duplicating production logic.

**Type consistency:** `opensource_requested` is `pgtype.Bool` in update params (nullable narg) but `bool` on the row (NOT NULL column) — consistent with the schema. `opensource_approved` is nullable everywhere (`pgtype.Bool` / `*bool` / `optional bool`). `rejection_reason` is `pgtype.Text` / `*string` / `optional string`. Proto field names map to Go `OpensourceRequested`/`OpensourceApproved`/`RejectionReason` and Perl keys `opensource_requested`/`opensource_approved`/`rejection_reason` throughout.

**Ordering:** Additive Tasks 1-6 each leave both repos compiling and green; the destructive drop is isolated to Task 7 after all consumers read the new fields.
