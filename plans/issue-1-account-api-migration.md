# Implementation Plan: Migrate Account Database Operations to Internal API (Issue #1)

## Context
Currently, account management in Perl uses direct Rose::DB database calls. We need to migrate these write operations to use the internal ConnectRPC API (Go service), following the pattern established for monitor eligibility and Auth0 login.

**Related Context from Issue #10**: The broader strategy is to incrementally migrate all Rose::DB ORM calls to the internal API. This task focuses specifically on account write operations as a high-priority subset.

## Scope

**Included in this phase**:
- Account creation
- Account field updates (name, organization_name, organization_url, url_slug, public_profile)
- User removal from accounts
- User task creation (download, delete)

**Excluded from this phase** (separate follow-up):
- Account invitations (create, send, accept, reject)
- User identity creation
- User creation

## Operations to Migrate

### In `lib/NTPPool/Control/Manage/Account.pm`:

1. **Account creation** (lines 45, 58, 362)
   - `NP::Model->account->create(users => [$self->user])`
   - Used when creating new accounts or default accounts

2. **Account updates** (lines 393, 61)
   - `$account->save(changes_only => 1)` after field modifications
   - Fields: name, organization_name, organization_url, url_slug, public_profile

3. **User removal from account** (lines 128-130)
   - Modifies `$account->users()` array
   - Calls `$account->save()`

4. **User task creation** (lines 449, 521)
   - `NP::Model->user_task->create(user => $user->id, task => 'download'|'delete', ...)`

## Implementation Steps

### 1. Define Protocol Buffer Messages (Go API)

Add to `/Users/ask/src/go/ntp/api/proto/ntppool/account/v1/account.proto`:

```protobuf
// CreateAccount creates a new account for the authenticated user.
// Authentication: Required via session middleware (sessions.GetUser).
// Authorization: None required for own account creation.
rpc CreateAccount(CreateAccountRequest) returns (CreateAccountResponse) {}

// UpdateAccount updates account fields.
// Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).
// Authorization: User must have edit access (see permission model below).
rpc UpdateAccount(UpdateAccountRequest) returns (UpdateAccountResponse) {}

// RemoveUserFromAccount removes a user from an account.
// Authentication: Required via session middleware (sessions.GetUser + sessions.GetAccount).
// Authorization: User must have edit access and cannot remove themselves.
rpc RemoveUserFromAccount(RemoveUserFromAccountRequest) returns (RemoveUserFromAccountResponse) {}

// CreateUserTask creates a user task (download, delete, etc.).
// Authentication: Required via session middleware (sessions.GetUser).
// Authorization: User can only create tasks for themselves.
rpc CreateUserTask(CreateUserTaskRequest) returns (CreateUserTaskResponse) {}
```

**Message definitions**:

```protobuf
message CreateAccountRequest {
  // name is the account name (required, 1-255 chars, trimmed)
  string name = 1;
  // initial_user_ids are user IDs to add to the account (optional)
  // If empty, the authenticated user is added automatically
  repeated int64 initial_user_ids = 2;
}

message CreateAccountResponse {
  // account_id is the numeric ID of the created account
  int64 account_id = 1;
  // account_token is the id_token for the account
  string account_token = 2;
}

message UpdateAccountRequest {
  // Fields to update (only provided fields are updated)
  // If a field is not set in the request, it remains unchanged
  optional string name = 1;
  optional string organization_name = 2;
  optional string organization_url = 3;
  optional string url_slug = 4;
  optional bool public_profile = 5;
}

message UpdateAccountResponse {
  // success indicates if the update was successful
  bool success = 1;
}

message RemoveUserFromAccountRequest {
  // user_token is the id_token of the user to remove (NOT numeric user_id)
  string user_token = 1;
}

message RemoveUserFromAccountResponse {
  // success indicates if the removal was successful
  bool success = 1;
}

message CreateUserTaskRequest {
  // task_type is the type of task (e.g., "download", "delete")
  string task_type = 1;
  // status is the initial status (usually empty string for pending)
  string status = 2;
  // execute_on_unix is when the task should be executed (optional, Unix timestamp)
  optional int64 execute_on_unix = 3;
}

message CreateUserTaskResponse {
  // task_id is the ID of the created task
  int64 task_id = 1;
  // traceid links this task to trace logs for async processing
  // Used by background workers to correlate task execution with original request
  string traceid = 2;
}
```

### 2. Create SQL Queries (Go API)

Add to `/Users/ask/src/go/ntp/api/sql/account_mutations.sql`:

```sql
-- name: CreateAccount :one
INSERT INTO accounts (id_token, name, created_on)
VALUES ($1, $2, CURRENT_TIMESTAMP)
RETURNING id, id_token;

-- name: AddUserToAccount :exec
INSERT INTO account_users (account_id, user_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING;

-- name: UpdateAccountName :exec
UPDATE accounts
SET name = $2, modified_on = CURRENT_TIMESTAMP
WHERE id = $1;

-- name: UpdateAccountOrganizationName :exec
UPDATE accounts
SET organization_name = $2, modified_on = CURRENT_TIMESTAMP
WHERE id = $1;

-- name: UpdateAccountOrganizationURL :exec
UPDATE accounts
SET organization_url = $2, modified_on = CURRENT_TIMESTAMP
WHERE id = $1;

-- name: UpdateAccountURLSlug :exec
UPDATE accounts
SET url_slug = $2, modified_on = CURRENT_TIMESTAMP
WHERE id = $1;

-- name: UpdateAccountPublicProfile :exec
UPDATE accounts
SET public_profile = $2, modified_on = CURRENT_TIMESTAMP
WHERE id = $1;

-- name: RemoveUserFromAccount :execresult
DELETE FROM account_users
WHERE account_id = $1 AND user_id = $2;

-- name: GetAccountUsers :many
SELECT u.id, u.email, u.name, u.username, u.id_token
FROM users u
INNER JOIN account_users au ON u.id = au.user_id
WHERE au.account_id = $1;

-- name: CheckUserInAccount :one
SELECT EXISTS(
  SELECT 1 FROM account_users
  WHERE account_id = $1 AND user_id = $2
) AS is_member;

-- name: CreateUserTask :one
INSERT INTO user_tasks (user_id, task, status, traceid, execute_on, created_on)
VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)
RETURNING id, traceid;

-- name: CheckURLSlugAvailable :one
SELECT COUNT(*) as count
FROM accounts
WHERE url_slug = $1 AND id != $2;

-- name: GetUserByIDToken :one
SELECT id, email, username, id_token
FROM users
WHERE id_token = $1;
```

**Note on SQL design**: Instead of COALESCE pattern which makes NULL indistinguishable from "no change", we use separate UPDATE queries per field. This allows explicit NULL setting and clearer intent. The Go handler determines which fields to update based on proto optional field presence.

### 3. Implement Go API Handlers

**Reference implementations**:
- Authentication pattern: `server/api/account/account_status.go:16-35` (sessions.GetUser, sessions.GetAccount)
- Transaction pattern: `server/api/monitorreg/monitor_registration.go:364` (database.WithTransaction)
- Error handling: Return connect.NewError with appropriate codes

Create new file `server/api/account/mutations.go`:

#### Permission Model (from lib/NP/Model/Account.pm:78-84)

```go
// canEditAccount checks if user has permission to edit account
// Permission is granted if:
// - User is support staff (user.privileges.support_staff), OR
// - User is a member of the account (exists in account_users table)
func (api *AccountServiceServer) canEditAccount(ctx context.Context, q ntpdb.Querier, accountID int64, userID int64) (bool, error) {
    log := logger.FromContext(ctx)

    // Check staff privileges (TODO: implement is_staff check on user model)
    // For now, check account membership

    isMember, err := q.CheckUserInAccount(ctx, ntpdb.CheckUserInAccountParams{
        AccountID: accountID,
        UserID: userID,
    })
    if err != nil {
        log.ErrorContext(ctx, "failed to check account membership", "err", err)
        return false, err
    }

    return isMember, nil
}
```

#### Field Validation Rules

```go
// Validation rules to implement in each handler:
// - name: required, 1-255 chars, trimmed
// - organization_name: optional, max 255 chars, trimmed
// - organization_url: optional, valid URL format, max 512 chars
// - url_slug: optional, 3-32 chars, pattern ^[a-z0-9][a-z0-9-]*[a-z0-9]$
//   * Normalize to lowercase before validation
//   * Prohibited values: "admin", "api", "new", "www", "manage", "pool", "test"
//   * Leave existing slugs unchanged if not explicitly updated
// - public_profile: boolean only

func validateURLSlug(slug string) error {
    if slug == "" {
        return nil // Optional field
    }

    // Normalize to lowercase
    slug = strings.ToLower(slug)

    // Length check
    if len(slug) < 3 || len(slug) > 32 {
        return fmt.Errorf("URL slug must be between 3 and 32 characters")
    }

    // Pattern check
    matched, _ := regexp.MatchString("^[a-z0-9][a-z0-9-]*[a-z0-9]$", slug)
    if !matched {
        return fmt.Errorf("URL slug must start and end with a letter or number, and contain only letters, numbers, and hyphens")
    }

    // Reserved words
    prohibited := []string{"admin", "api", "new", "www", "manage", "pool", "test"}
    for _, word := range prohibited {
        if slug == word {
            return fmt.Errorf("URL slug '%s' is reserved and cannot be used", slug)
        }
    }

    return nil
}
```

#### CreateAccount Handler

```go
func (api *AccountServiceServer) CreateAccount(
    ctx context.Context,
    req *connect.Request[accountv1.CreateAccountRequest],
) (*connect.Response[accountv1.CreateAccountResponse], error) {
    log := logger.FromContext(ctx)

    // Get authenticated user from session middleware
    user := sessions.GetUser(ctx)
    if user.ID == 0 {
        return nil, connect.NewError(connect.CodeUnauthenticated, fmt.Errorf("authentication required"))
    }

    // Validate name
    name := strings.TrimSpace(req.Msg.Name)
    if name == "" || len(name) > 255 {
        return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("account name is required and must be 1-255 characters"))
    }

    // Determine initial users (authenticated user + any additional specified)
    userIDs := req.Msg.InitialUserIds
    if len(userIDs) == 0 {
        userIDs = []int64{user.ID}
    }

    // Use transaction to ensure account + users are created atomically
    var accountID int64
    var accountToken string

    err := database.WithTransaction(ctx, api.Q(), func(ctx context.Context, q ntpdb.QuerierTx) error {
        // Generate unique id_token for account
        token := generateAccountToken() // TODO: implement token generation

        // Create account
        account, err := q.CreateAccount(ctx, ntpdb.CreateAccountParams{
            IDToken: pgtype.Text{String: token, Valid: true},
            Name: name,
        })
        if err != nil {
            log.ErrorContext(ctx, "failed to create account", "err", err)
            return fmt.Errorf("failed to create account: %w", err)
        }

        accountID = account.ID
        accountToken = account.IDToken.String

        // Add initial users
        for _, userID := range userIDs {
            err = q.AddUserToAccount(ctx, ntpdb.AddUserToAccountParams{
                AccountID: accountID,
                UserID: userID,
            })
            if err != nil {
                log.ErrorContext(ctx, "failed to add user to account", "user_id", userID, "err", err)
                return fmt.Errorf("failed to add user %d to account: %w", userID, err)
            }
        }

        return nil
    })

    if err != nil {
        // Error already logged in transaction
        // DO NOT gloss over errors - bubble up with context
        return nil, connect.NewError(connect.CodeInternal, err)
    }

    log.InfoContext(ctx, "created account", "account_id", accountID, "user_id", user.ID)

    return connect.NewResponse(&accountv1.CreateAccountResponse{
        AccountId: accountID,
        AccountToken: accountToken,
    }), nil
}
```

#### UpdateAccount Handler

```go
func (api *AccountServiceServer) UpdateAccount(
    ctx context.Context,
    req *connect.Request[accountv1.UpdateAccountRequest],
) (*connect.Response[accountv1.UpdateAccountResponse], error) {
    log := logger.FromContext(ctx)

    // Get authenticated user and account from session middleware
    user := sessions.GetUser(ctx)
    account := sessions.GetAccount(ctx)

    if user.ID == 0 || account.ID == 0 {
        return nil, connect.NewError(connect.CodeUnauthenticated, fmt.Errorf("authentication required"))
    }

    // Check edit permission
    canEdit, err := api.canEditAccount(ctx, api.Q(), account.ID, user.ID)
    if err != nil {
        return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("permission check failed"))
    }
    if !canEdit {
        return nil, connect.NewError(connect.CodePermissionDenied, fmt.Errorf("you don't have permission to edit this account"))
    }

    q := api.Q()

    // Update each field that was provided in the request
    // Proto3 uses field presence detection for optional fields

    if req.Msg.Name != nil {
        name := strings.TrimSpace(*req.Msg.Name)
        if name == "" || len(name) > 255 {
            return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("account name must be 1-255 characters"))
        }
        err := q.UpdateAccountName(ctx, ntpdb.UpdateAccountNameParams{
            ID: account.ID,
            Name: name,
        })
        if err != nil {
            log.ErrorContext(ctx, "failed to update account name", "err", err)
            return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to update account name"))
        }
    }

    if req.Msg.OrganizationName != nil {
        orgName := strings.TrimSpace(*req.Msg.OrganizationName)
        if len(orgName) > 255 {
            return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("organization name must be at most 255 characters"))
        }
        err := q.UpdateAccountOrganizationName(ctx, ntpdb.UpdateAccountOrganizationNameParams{
            ID: account.ID,
            OrganizationName: pgtype.Text{String: orgName, Valid: orgName != ""},
        })
        if err != nil {
            log.ErrorContext(ctx, "failed to update organization name", "err", err)
            return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to update organization name"))
        }
    }

    if req.Msg.OrganizationUrl != nil {
        orgURL := strings.TrimSpace(*req.Msg.OrganizationUrl)
        if orgURL != "" {
            if len(orgURL) > 512 {
                return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("organization URL must be at most 512 characters"))
            }
            // TODO: Add URL format validation
        }
        err := q.UpdateAccountOrganizationURL(ctx, ntpdb.UpdateAccountOrganizationURLParams{
            ID: account.ID,
            OrganizationURL: pgtype.Text{String: orgURL, Valid: orgURL != ""},
        })
        if err != nil {
            log.ErrorContext(ctx, "failed to update organization URL", "err", err)
            return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to update organization URL"))
        }
    }

    if req.Msg.UrlSlug != nil {
        slug := strings.ToLower(strings.TrimSpace(*req.Msg.UrlSlug))

        // Validate slug format
        if err := validateURLSlug(slug); err != nil {
            return nil, connect.NewError(connect.CodeInvalidArgument, err)
        }

        // Check uniqueness
        if slug != "" {
            count, err := q.CheckURLSlugAvailable(ctx, ntpdb.CheckURLSlugAvailableParams{
                URLSlug: pgtype.Text{String: slug, Valid: true},
                ID: account.ID,
            })
            if err != nil {
                log.ErrorContext(ctx, "failed to check URL slug availability", "err", err)
                return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to validate URL slug"))
            }
            if count > 0 {
                return nil, connect.NewError(connect.CodeAlreadyExists, fmt.Errorf("this URL slug is already in use"))
            }
        }

        err := q.UpdateAccountURLSlug(ctx, ntpdb.UpdateAccountURLSlugParams{
            ID: account.ID,
            URLSlug: pgtype.Text{String: slug, Valid: slug != ""},
        })
        if err != nil {
            log.ErrorContext(ctx, "failed to update URL slug", "err", err)
            return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to update URL slug"))
        }
    }

    if req.Msg.PublicProfile != nil {
        err := q.UpdateAccountPublicProfile(ctx, ntpdb.UpdateAccountPublicProfileParams{
            ID: account.ID,
            PublicProfile: *req.Msg.PublicProfile,
        })
        if err != nil {
            log.ErrorContext(ctx, "failed to update public profile setting", "err", err)
            return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to update public profile setting"))
        }
    }

    log.InfoContext(ctx, "updated account", "account_id", account.ID, "user_id", user.ID)

    return connect.NewResponse(&accountv1.UpdateAccountResponse{
        Success: true,
    }), nil
}
```

#### Error Message Standards

User-facing error messages returned in connect.NewError:

```go
// InvalidArgument errors (400-level)
"Account name is required and must be 1-255 characters"
"Organization name must be at most 255 characters"
"Organization URL must be at most 512 characters"
"URL slug must be between 3 and 32 characters"
"URL slug must start and end with a letter or number, and contain only letters, numbers, and hyphens"
"URL slug 'admin' is reserved and cannot be used"
"User token is required"

// AlreadyExists errors
"This URL slug is already in use"

// PermissionDenied errors (403)
"You don't have permission to edit this account"
"You cannot remove yourself from an account"

// Unauthenticated errors (401)
"Authentication required"
"Invalid account"

// Internal errors (500)
"Failed to create account"
"Failed to update account name"
"Permission check failed"
```

### 4. Update Perl Controllers

**Reference implementations for int_api pattern**:
- GET with auth: `lib/NTPPool/Control/Manage/Monitor.pm:126-134` (fetch monitor details)
- GET with account scope: `lib/NTPPool/Control/Manage/Monitor.pm:273-281` (list monitors for account)
- POST with data: `lib/NTPPool/Control/Manage/Server.pm:439-447` (update server netspeed)
- GET with query params: `lib/NTPPool/Control/Manage.pm:394-400` (admin search)

**Standard pattern**:
```perl
my $data = int_api(
    'METHOD',                # 'get', 'post', 'patch', 'delete'
    'endpoint/path',
    {
        user => $self->plain_cookie($self->user_cookie_name),
        a    => $self->current_account->id_token,  # For account-scoped operations
        # ... endpoint-specific params (query params, data, etc.)
    },
    $self->_get_request_context()  # Adds X-Forwarded-For
);
```

In `/Users/ask/src/ntppool/lib/NTPPool/Control/Manage/Account.pm`:

#### Account Creation (lines 45, 58, 362)

```perl
# Replace:
$account = NP::Model->account->create(users => [$self->user]);

# With:
my $data = int_api(
    'post',
    'account/create',
    {
        user => $self->plain_cookie($self->user_cookie_name),
        data => $json->encode({
            name => $self->user->name || 'My Account',
            initial_user_ids => [0 + $self->user->id],
        }),
    },
    $self->_get_request_context()
);

if ($data->{code} != 200) {
    # DO NOT gloss over errors - log and bubble up
    warn "Failed to create account via API: " . ($data->{error} || 'unknown error');
    warn "Trace ID: " . ($data->{trace_id} || 'none') if $data->{trace_id};
    $self->tpl_param('error', 'Failed to create account. Please try again.');
    return $self->render_error_page();
}

# Reload account from database with new ID
$account = NP::Model->account->fetch(id => $data->{data}{account_id});
if (!$account) {
    # This should never happen, but handle gracefully
    warn "Failed to reload account after creation, id=" . $data->{data}{account_id};
    warn "Trace ID: " . ($data->{trace_id} || 'none');
    die "Account creation failed - could not reload account";
}
```

#### Account Updates (line 393)

```perl
# Replace:
$account->save(changes_only => 1);

# With:
my %update_data = ();
for my $f (qw(name organization_name organization_url url_slug)) {
    my $v = $args{$f} // $self->req_param($f);
    $v //= '';
    $v =~ s/^\s+//;
    $v =~ s/\s+$//;
    $v = undef if ($f eq 'url_slug' and $v eq '');
    if (defined($v) && $v ne ($account->$f() // '')) {
        $update_data{$f} = $v;
    }
}

# Handle boolean separately
my $public_profile = $self->req_param('public_profile') ? JSON::XS::true : JSON::XS::false;
if ($public_profile != ($account->public_profile ? JSON::XS::true : JSON::XS::false)) {
    $update_data{public_profile} = $public_profile;
}

if (%update_data) {
    my $data = int_api(
        'patch',
        'account/update',
        {
            user => $self->plain_cookie($self->user_cookie_name),
            a    => $account->id_token,
            data => $json->encode(\%update_data),
        },
        $self->_get_request_context()
    );

    if ($data->{code} != 200) {
        warn "Failed to update account via API: " . ($data->{error} || 'unknown error');
        warn "Trace ID: " . ($data->{trace_id} || 'none') if $data->{trace_id};

        # Extract user-friendly error message if available
        my $error_msg = $data->{message} || 'Failed to update account. Please try again.';
        $self->tpl_param('error', $error_msg);
        return $self->render_account_form($account);
    }

    # Reload account to get updated values
    $account = NP::Model->account->fetch(id => $account->id);
    if (!$account) {
        warn "Failed to reload account after update, id=" . $account->id;
        die "Account update failed - could not reload account";
    }
}
```

#### User Removal (lines 128-130)

```perl
# Replace:
@$users = grep { $_->id != $user_id } @$users;
$account->users($users);
$account->save();

# With:
my $data = int_api(
    'delete',
    'account/remove-user',
    {
        user       => $self->plain_cookie($self->user_cookie_name),
        a          => $account->id_token,
        user_token => $user->id_token,  # Use id_token, not numeric ID
    },
    $self->_get_request_context()
);

if ($data->{code} != 200) {
    warn "Failed to remove user from account via API: " . ($data->{error} || 'unknown error');
    warn "Trace ID: " . ($data->{trace_id} || 'none') if $data->{trace_id};
    $self->tpl_param('error', 'Failed to remove user. Please try again.');
    return $self->render_users($account);
}

# Reload account after successful removal
$account = NP::Model->account->fetch(id => $account->id);
```

#### User Task Creation (lines 449, 521)

```perl
# Replace:
my $task = NP::Model->user_task->create(
    user   => $user->id,
    task   => 'download',
    status => '',
);
$task->save;

# With:
my $data = int_api(
    'post',
    'user/task/create',
    {
        user => $self->plain_cookie($self->user_cookie_name),
        data => $json->encode({
            task_type => 'download',
            status    => '',
        }),
    },
    $self->_get_request_context()
);

if ($data->{code} != 200) {
    warn "Failed to create user task via API: " . ($data->{error} || 'unknown error');
    warn "Trace ID: " . ($data->{trace_id} || 'none') if $data->{trace_id};
    $self->tpl_param('error', 'Failed to create download request. Please try again.');
    return $self->render_download($user);
}

# Note: We don't need to fetch the task - the API returns task_id and traceid
# The traceid links this request to async processing in background workers
```

### 5. Testing Strategy

#### Go Integration Tests

Create `server/api/account/mutations_test.go`:

**Test Setup**:
- Use test fixtures with known account/user data
- Create helper function to set up authenticated context
- Implement cleanup between tests (rollback transactions or DELETE in teardown)

**Test Cases**:

```go
func TestCreateAccount(t *testing.T) {
    tests := []struct {
        name           string
        request        *accountv1.CreateAccountRequest
        setupAuth      func(ctx context.Context) context.Context
        expectedError  bool
        expectedCode   connect.Code
        validateResult func(t *testing.T, resp *accountv1.CreateAccountResponse)
    }{
        {
            name: "create account with name only",
            request: &accountv1.CreateAccountRequest{
                Name: "Test Account",
            },
            setupAuth: func(ctx context.Context) context.Context {
                return sessions.WithUser(ctx, sessions.User{ID: 123, Email: "test@example.com"})
            },
            expectedError: false,
            validateResult: func(t *testing.T, resp *accountv1.CreateAccountResponse) {
                assert.NotZero(t, resp.AccountId)
                assert.NotEmpty(t, resp.AccountToken)
            },
        },
        {
            name: "create account with initial users",
            request: &accountv1.CreateAccountRequest{
                Name: "Team Account",
                InitialUserIds: []int64{123, 456},
            },
            // ... additional test cases
        },
        {
            name: "reject empty name",
            request: &accountv1.CreateAccountRequest{
                Name: "",
            },
            expectedError: true,
            expectedCode: connect.CodeInvalidArgument,
        },
        {
            name: "reject unauthenticated request",
            request: &accountv1.CreateAccountRequest{
                Name: "Test",
            },
            setupAuth: func(ctx context.Context) context.Context {
                return ctx // No auth
            },
            expectedError: true,
            expectedCode: connect.CodeUnauthenticated,
        },
    }
    // ... test implementation
}

func TestUpdateAccount(t *testing.T) {
    // Test cases:
    // - Update name only
    // - Update multiple fields
    // - Update URL slug (valid format)
    // - Reject invalid URL slug (too short)
    // - Reject invalid URL slug (invalid chars)
    // - Reject invalid URL slug (reserved word "admin")
    // - Reject duplicate URL slug
    // - Reject unauthorized user (not in account_users)
    // - Handle concurrent updates (optimistic locking if needed)
}

func TestRemoveUserFromAccount(t *testing.T) {
    // Test cases:
    // - Remove user successfully
    // - Reject self-removal
    // - Reject unauthorized removal
    // - Reject removing last user (if business rule)
    // - Handle non-existent user gracefully
}

func TestCreateUserTask(t *testing.T) {
    // Test cases:
    // - Create download task
    // - Create delete task with execute_on
    // - Verify traceid generation
    // - Reject unauthenticated request
}
```

**Permission Boundary Tests**:
```go
func TestUpdateAccountPermissions(t *testing.T) {
    // Setup: Account A (users: 100, 200), Account B (users: 300)
    // Test: User 100 can edit Account A
    // Test: User 300 cannot edit Account A
    // Test: Staff user can edit any account
}
```

**Concurrency Tests**:
```go
func TestConcurrentAccountUpdates(t *testing.T) {
    // Two goroutines updating different fields of same account
    // Should both succeed without data loss
}
```

#### Perl Manual Testing Checklist

1. **Account Creation Flow**:
   - [ ] New user signup creates default account
   - [ ] Explicit "New Account" button creates account
   - [ ] Account name defaults to user name
   - [ ] User is automatically added to new account

2. **Account Updates**:
   - [ ] Update account name saves correctly
   - [ ] Update organization fields saves correctly
   - [ ] Set URL slug (valid format) saves correctly
   - [ ] Invalid URL slug shows error message
   - [ ] Reserved URL slug ("admin") shows error
   - [ ] Duplicate URL slug shows error
   - [ ] Enable public profile sets flag correctly
   - [ ] Validation errors display in form

3. **User Management**:
   - [ ] Remove user from team page works
   - [ ] Cannot remove self from account
   - [ ] Email notification sent to removed user
   - [ ] Account reloads with updated user list

4. **Download Requests**:
   - [ ] Create download request succeeds
   - [ ] Cannot create duplicate pending requests
   - [ ] Task appears in request list
   - [ ] Trace ID is logged for debugging

## Technical Considerations

### Authentication and Authorization

**Pattern** (reference: `server/api/account/account_status.go:16-35`):
```go
user := sessions.GetUser(ctx)  // From session middleware
account := sessions.GetAccount(ctx)  // From X-Account header or request param
```

**Permission Model** (from `lib/NP/Model/Account.pm:78-84`):
- User can edit account if they are a member (account_users table)
- OR if they have support_staff privilege
- Staff users can view any account (including monitor_admin role)

### Data Encoding

**Perl → Go**:
- Booleans: `JSON::XS::true`/`JSON::XS::false` (NOT 1/0)
- Integers: `0 + $value` to force numeric context
- Strings: Use `$json->encode()` for request bodies

**Go → Database**:
- Use pgtype for nullable fields: `pgtype.Text{String: val, Valid: val != ""}`
- Timestamps: PostgreSQL `CURRENT_TIMESTAMP`

### Caching Strategy

**Per-Request Caches**:
- `$self->{_current_account}` is request-scoped
- Perl request lifecycle: init → dispatch → render → cleanup
- **No need to explicitly clear caches** - they're destroyed at request end
- Only reload from database after mutations to get fresh data

**Why reload after mutation**:
- Rose::DB objects become stale after external changes
- API mutations bypass Perl ORM layer
- Reloading ensures template gets updated values

### Error Handling

**Principle**: Never gloss over errors - log and bubble up

**Pattern**:
```perl
if ($data->{code} != 200) {
    warn "Operation failed: " . ($data->{error} || 'unknown');
    warn "Trace ID: $data->{trace_id}" if $data->{trace_id};
    # Show user-friendly message
    # Return error state
}
```

**Trace Propagation**:
- Framework automatically propagates trace context from Perl → Go → Database
- No manual trace ID passing needed in standard int_api calls
- Use `$self->_get_request_context()` to include X-Forwarded-For

### Transaction Support

**Pattern** (reference: `server/api/monitorreg/monitor_registration.go:364`):
```go
err := database.WithTransaction(ctx, api.Q(), func(ctx context.Context, q ntpdb.QuerierTx) error {
    // Multiple database operations
    // Return error to rollback, nil to commit
    return nil
})
```

**Use Cases**:
- Account creation with initial users (atomic)
- Any multi-step operation that must succeed/fail together

### Idempotency Considerations

**CreateAccount**:
- Risk: User clicks "Create Account" button multiple times
- Mitigation: Use POST-Redirect-GET pattern in Perl controller
- Alternative: Check for existing account before creation
- Decision: Accept duplicate accounts for now (user can delete extras)

**UpdateAccount**:
- Naturally idempotent (same update applied twice = same result)
- Last write wins (no optimistic locking initially)

**RemoveUserFromAccount**:
- Naturally idempotent (DELETE WHERE ... returns 0 rows if already removed)

**CreateUserTask**:
- Not idempotent (each request creates new task)
- Mitigation: Check for pending tasks before creating new one (current behavior)

### Observability

**Logging Levels**:
- `log.InfoContext`: Successful operations (created account, updated account)
- `log.WarnContext`: Invalid input, permission denied
- `log.ErrorContext`: Database errors, unexpected failures

**Metrics**:
- Track account creation rate
- Track update failures
- Track permission denials

**Tracing**:
- Automatic trace propagation via framework
- No manual trace ID injection needed
- Use trace IDs in error responses for debugging

## Migration Order (Revised)

**Rationale**: Start with simpler operations to validate infrastructure before tackling complex flows.

1. **Phase 1: Account Field Updates** (Lowest risk, well-defined)
   - Implement UpdateAccount RPC
   - Test with existing accounts
   - Validate auth/permission infrastructure
   - Add comprehensive tests

2. **Phase 2: User Removal** (Moderate risk, requires permission checks)
   - Implement RemoveUserFromAccount RPC
   - Test permission boundaries
   - Validate transaction handling

3. **Phase 3: User Task Creation** (Independent subsystem)
   - Implement CreateUserTask RPC
   - Test download/delete task flows
   - Validate traceid generation for async processing

4. **Phase 4: Account Creation** (Highest risk, affects new user flow)
   - Implement CreateAccount RPC with transactions
   - Test new user signup flow
   - Test multi-user account creation
   - Validate rollback on failure

## Success Criteria

- All in-scope operations use API calls instead of direct database access
- Existing functionality works identically to current behavior
- Proper error handling with trace IDs and user-friendly messages
- All Go integration tests pass
- Manual Perl testing checklist completed
- No performance degradation (< 50ms p95 latency increase)
- Code follows DRY principles using existing patterns
- No errors glossed over - all failures logged and bubbled up
- Permission model correctly enforced (staff + account membership)
- URL slug validation prevents reserved words and invalid formats
