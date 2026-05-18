# Admin deletion of an empty account (keep the user)

Status: deferred until the Postgres / Go rewrite.

## What today's flow does

`/manage/account/delete?u=<token>` deletes a *user*. The blocker logic in
`render_user_delete` (`lib/NTPPool/Control/Manage/Account.pm`) iterates every
account where that user is the sole remaining member; the user is only
deletable if each such account has no active servers, no vendor zones, and no
active monitors. When the scheduled `user_task` (task=`delete`, 7-day delay)
runs, the user is removed and any sole-membership accounts are cleaned up as a
side effect.

There is no separate "delete this account" action. An account with two members
where the admin wants to drop one inactive account cannot be removed without
either deleting the user (which would orphan the user's other memberships) or
manually editing the database.

## Desired capability

Allow staff to delete a single account when:

- the account has no active servers, vendor zones, or monitors, and
- at least one of its members still belongs to another account (so the user
  is not left without any account membership).

The user(s) remain intact and keep their other account memberships. The
deleted account's `account_users` rows go away; the account row itself is
removed (or soft-deleted, see "Open questions").

## Why this needs to wait

The new flow has to live in the api-internal service (Go, Postgres). The
Perl side issues an authenticated call; the Go side enforces eligibility,
performs the cascade, and emits the audit record. Implementing this in the
Perl/Rose::DB layer would duplicate logic we are actively moving server-side
(see recent commit `3cab841b` — account-delete blocker checks are shifting to
the api-internal eligibility endpoint).

## Sketch of the future implementation

API: `POST /int/account/delete` with `{ "a": "<account-token>" }`, returning
`200`/`409` (blockers) / `404`.

Authorization: caller must be staff. The Perl controller passes `user=<cookie>`
and the target account token as today.

Server-side checks (mirror the existing eligibility logic, kept in one place):

- account has no servers with `deletion_on IS NULL`
- account has no vendor zones
- account has no active monitors (`status <> 'deleted'`, `deleted_on IS NULL`,
  `is_current = true`, `type = 'monitor'` — see the soft-deleted-monitor
  handling in `render_user_delete` and the Go-side parity work)
- every `account_users.user` of this account also belongs to at least one
  other account; if not, return a structured blocker so the UI can suggest
  "delete the user instead"

Cascade: remove `account_users` rows for the account, then delete (or
soft-delete) the account. Wrap in a transaction. Emit an `NP::Model::Log`
entry from the Perl side identifying the acting staff member and the
account; the server-side action can also record its own audit row.

UI:

- A staff-only "Delete account" button on `docs/manage/tpl/account/form.html`
  when viewing an empty account.
- Confirmation page (`tpl/account/delete_confirmation.html`) listing the
  remaining team members and the account's lack of resources, with a final
  POST to commit.

## Open questions to settle before building

1. Hard delete vs soft delete (`deleted_on` column on `accounts`). Hard
   delete is simpler; soft delete preserves history for audit but requires
   filtering across queries (cf. monitor soft-delete work).
2. Should the action be available to non-staff for accounts they themselves
   own (e.g., self-service "leave and dissolve an empty account")? That's a
   different threat model; default to staff-only and revisit.
3. What's the right URL/route — `/manage/account/delete?a=<token>` collides
   with the user-deletion route. Use a distinct path like
   `/manage/account/dissolve` or `/manage/account/remove`.

## Quick interim escape hatch (no code change needed)

Until the above ships, staff can:

1. Add another user to the account team, then
2. From that user's perspective, leave the account (the existing "Remove"
   button), or have staff delete the empty account row directly via SQL.

Neither is a great UX; that's the point of doing this properly later.
