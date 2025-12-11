package NP::Model::AccountSubscription;
use strict;

# ORM methods deprecated - use NP::CAPI::Subscription instead
# All subscription logic now handled by Go API via:
#   - get_account_subscriptions
#   - get_account_subscription_status
#   - create_or_update_subscription
#   - update_account_stripe_customer

1;
