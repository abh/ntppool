# NP::CAPI Usage Guide for AI Coding Agents

## Account Token Field Names

**CRITICAL**: NP::Model::Account objects use `id_token` for the account token, NOT `account_token`.

```perl
# ✅ CORRECT
my $data = update_account(
    auth    => $auth,
    account => $account->{id_token},  # Note: id_token, not account_token
    ...
);

# ❌ WRONG - will result in 401 Unauthorized
my $data = update_account(
    auth    => $auth,
    account => $account->{account_token},  # This field doesn't exist!
    ...
);
```

**Why this matters**:
- API response uses `account_token` field
- But `_account_from_api_response()` stores it as `id_token` in blessed objects
- Using the wrong field name results in `undef`, causing missing `X-Account` header
- Missing header causes "authentication required" error (really authorization failure)

**When calling CAPI methods**:
- If you have an API response: use `$response->{data}{account}{account_token}`
- If you have a blessed NP::Model::Account: use `$account->{id_token}`
- Always check the field exists before using (add debug logging if uncertain)
