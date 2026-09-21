# NP::CAPI Usage Guide for AI Coding Agents

## Account Token Field Names

**CRITICAL**: Account data (plain hashrefs from CAPI responses, e.g. `current_account`) uses `id_token` for the account token, NOT `account_token`.

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
- The raw API response uses the `account_token` field
- Session/account context (e.g. `current_account`) exposes it as `id_token`
- Using the wrong field name results in `undef`, causing missing `X-Account` header
- Missing header causes "authentication required" error (really authorization failure)

**When calling CAPI methods**:
- If you have a raw API response: use `$response->{data}{account}{account_token}`
- If you have the account context hashref: use `$account->{id_token}`
- Always check the field exists before using (add debug logging if uncertain)
