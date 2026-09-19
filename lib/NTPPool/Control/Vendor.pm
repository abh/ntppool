package NTPPool::Control::Vendor;
use strict;
use parent            qw(NTPPool::Control::Manage);
use Combust::Constant qw(OK NOT_FOUND FORBIDDEN);
use NP::Email         ();
use Email::Stuffer    ();
use Sys::Hostname     qw(hostname);
use JSON              ();
use NP::Stripe;
use List::Util           qw(uniq);
use Data::Dump           qw(pp);
use NP::CAPI::VendorZone qw(
    list_vendor_zones
    get_vendor_zone
    request_vendor_zone
    update_vendor_zone
    submit_vendor_zone
    update_vendor_zone_status
    list_vendor_zones_admin
    get_vendor_zone_form_metadata
);
use NP::CAPI::Subscription qw(
    get_account_subscriptions
    get_account_subscription_status
    update_account_stripe_customer
);
use JSON::XS ();

my $json = JSON::XS->new->pretty->utf8->convert_blessed;

sub manage_dispatch {
    my $self = shift;

    unless ($self->current_account) {
        return $self->redirect("/manage/account");
    }

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;
    }

    return $self->render_form if $self->request->uri =~ m!^/manage/vendor/new$!;

    if ($self->request->uri eq '/manage/vendor/zone') {

        return $self->render_edit if ($self->request->method eq 'post');

        return $self->render_zone($self->_get_id);
    }

    return $self->render_submit
      if (    $self->request->uri =~ m!^/manage/vendor/submit$!
          and $self->request->method eq 'post');

    return $self->render_plan_upgrade
      if (    $self->request->uri eq '/manage/vendor/plan/upgrade'
          and $self->request->method eq 'post');

    return $self->render_plan_upgraded
      if $self->request->uri eq '/manage/vendor/plan/upgraded';

    return $self->render_subscription
      if $self->request->uri =~ m!^/manage/vendor/plan!;

    return $self->render_billing
      if $self->request->uri =~ m!^/manage/vendor/billing!;

    return $self->render_admin
      if $self->request->uri =~ m!^/manage/vendor/admin$!;

    # Check if user has any vendor zones via API
    my $zones_result = list_vendor_zones(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->{id_token},
        context => $self->_get_request_context(),
    );

    # On API error, show it - don't fall through to the "create your first
    # zone" redirect, which would mislead a vendor who already has zones.
    if (my $status = $self->capi_error_status($zones_result, $zones_result->{data})) {
        return $status;
    }

    unless (@{$zones_result->{data}{zones}}) {
        return $self->redirect($self->manage_url('/manage/vendor/new'));
    }

    $self->tpl_params->{page}->{is_vendor} = 1;

    return $self->render_zones
      if $self->request->uri =~ m!^/manage/vendor/?$!;

    return NOT_FOUND;
}

# _get_id: read the 'id' request param and pass it through to the CAPI calls
# unchanged. Accept a token (vz_...) or a purely numeric id (the Go API may
# resolve numerics later); anything else returns undef and callers redirect to
# /manage/vendor.
sub _get_id {
    my $self = shift;
    my $id   = $self->req_param('id');
    return undef unless defined $id;
    return $id if $id =~ m/^vz_/ || $id =~ m/^\d+$/;
    return undef;
}

sub can_edit_zone {
    my ($self, $zone) = @_;
    return 1 if $self->user_is_vendor_admin;
    return $zone->{status} ne 'Approved';
}

sub render_form {
    my $self = shift;
    my $zone = shift;    # Now a hashref from API, not blessed object

    my @device_count_options = (
        500,      2500,   5000,    10000,   25000,    50000,
        100000,   500000, 1000000, 5000000, 10000000, 25000000,
        50000000, 100000000
    );

    if ($zone) {
        $self->tpl_param('vz', $zone);

        push(@device_count_options, $zone->{device_count})
          if $zone->{device_count};

        # API zone hashrefs carry dns_root_origin; the template reads it directly.
    }
    else {
        # Get DNS roots from API
        my $metadata_result = get_vendor_zone_form_metadata(
            auth    => $self->plain_cookie($self->user_cookie_name),
            context => $self->_get_request_context(),
        );

        if ($metadata_result->{data} && $metadata_result->{data}{dns_roots}) {

            # Pass API DNS root hashrefs straight through to the template
            $self->tpl_param('dns_roots', $metadata_result->{data}{dns_roots});
        }
        else {
            # Fail hard - no database fallback during migration
            warn "Failed to get DNS roots from API: "
              . ($metadata_result->{error} || 'unknown error')
              . " (trace: "
              . ($metadata_result->{trace_id} || 'none') . ")";
            $self->tpl_param('dns_roots', []);
        }
    }

    my $opt = [uniq(sort { $a <=> $b } @device_count_options)];
    $self->tpl_param('device_count_options', $opt);

    return OK, $self->evaluate_template('tpl/vendor/form.html');
}

sub render_zones {
    my $self = shift;

    my $accounts = $self->user_accounts();
    $self->tpl_param('accounts' => $accounts);

    # Fetch the account's vendor zones from the API. The template used to read
    # combust.current_account.vendor_zones (an ORM relationship), but
    # current_account is now a plain CAPI hashref, so we pass the zones in.
    my $zones_result = list_vendor_zones(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->{id_token},
        context => $self->_get_request_context(),
    );
    if (my $status = $self->capi_error_status($zones_result, $zones_result->{data})) {
        return $status;
    }
    $self->tpl_param('vendor_zones', $zones_result->{data}{zones} || []);

    # have_subscription was combust.current_account.have_live_subscription (an
    # ORM method); fetch it from the subscription status API instead. Used only
    # to label a Pending zone as "Processing", so degrade gracefully: on a
    # transient API error, default to false and still render the zone list.
    my $status_result = get_account_subscription_status($self->api_auth_params,
        account => $self->current_account->{id_token},);
    my $status_data =
      ($status_result->{data} && !$status_result->{error}) ? $status_result->{data} : {};
    $self->tpl_param('have_subscription', $status_data->{has_live_subscription} ? 1 : 0);

    # Live subscriptions drive the optional billing block; also decorative, so
    # degrade gracefully rather than failing the whole page on error.
    my $subs_result = get_account_subscriptions($self->api_auth_params,
        account => $self->current_account->{id_token},);
    if ($subs_result->{data} && $subs_result->{data}{subscriptions}) {
        my @live =
          grep { $_->{live_subscription} } @{$subs_result->{data}{subscriptions}};
        $self->tpl_param('subscriptions', \@live);
    }

    return OK, $self->evaluate_template('tpl/vendor.html');
}

sub render_zone {
    my ($self, $id, $mode) = @_;

    return $self->redirect($self->manage_url('/manage/vendor')) unless $id;

    $mode ||= $self->req_param('mode') || '';

    # Fetch zone via API
    my $result = get_vendor_zone(
        auth     => $self->plain_cookie($self->user_cookie_name),
        id_token => $id,
        context  => $self->_get_request_context(),
    );

    if ($result->{error}) {
        if ($result->{code} == 404 || $result->{code} == 403) {
            return $self->redirect($self->manage_url('/manage/vendor'));
        }
        warn "API error getting vendor zone: "
          . $result->{error}
          . " (trace: "
          . ($result->{trace_id} || 'none') . ")";
        return $result->{code};
    }

    my $zone = $result->{data}{zone};
    $self->tpl_param('vz', $zone);

# Check subscription status for the zone's account (not current_account, which might be admin)
    my $account_token = $zone->{account_token};
    my $sub_status =
      $account_token
      ? get_account_subscription_status(
          $self->api_auth_params,
          account      => $account_token,
          device_count => $zone->{device_count},
      )
      : undef;
    my $sub_data = ($sub_status && !$sub_status->{error}) ? $sub_status->{data} : {};

    # The over-limit block in show.html reads max_devices, required_devices
    # and the upgrade offer straight from the API's answer.
    $self->tpl_param('coverage', $sub_data);

    # $limits_ok drives need_subscription, which hides the zone detail and the
    # submit control. It stays keyed off limits_exceeded alone: an uncovered
    # vendor must keep reaching the open-source form, which sits in the ELSE of
    # that submit control (show.html, _opensource.html). The product picker has
    # its own gate below.
    my $limits_ok =
      ($account_token && !$sub_data->{limits_exceeded}) ? 1 : 0;    # fail closed

    # have_subscription is has_live_subscription alone, matching render_zones.
    # The submit control and the Pending wording route on it, so it stays
    # separate from $limits_ok above, which additionally requires the zone to
    # fit inside the plan (#39).
    $self->tpl_param('have_subscription',
        ($account_token && $sub_data->{has_live_subscription}) ? 1 : 0);

    $self->tpl_param('can_edit_zone',   $self->can_edit_zone($zone));
    $self->tpl_param('is_vendor_admin', $self->user_is_vendor_admin ? 1 : 0);

    # For edit mode, render the form when editable (API enforces the details)
    return $self->render_form($zone)
      if $mode eq 'edit' && $self->can_edit_zone($zone);

    # Get subscriptions from zone's account (not current account, which might be admin)
    my @subs = ();
    if ($account_token) {
        my $subs_result =
          get_account_subscriptions($self->api_auth_params, account => $account_token,);
        if ($subs_result->{data} && $subs_result->{data}{subscriptions}) {
            @subs =
              grep { $_->{live_subscription} } @{$subs_result->{data}{subscriptions}};
        }
    }

    if ($zone->{status} eq 'New') {

        # The plan picker prices what the account needs: its approved devices
        # plus this zone, as the API computed them. Without the API's answer
        # there is nothing to price, so the picker lists no plans; the
        # open-source form below it still renders.
        if (defined $sub_data->{required_devices}) {
            my ($products, $groups, $group_list) =
              NP::Stripe::product_groups(1, $sub_data->{required_devices});
            if ($products->{error}) {
                warn "stripe gw error: ", $products->{error};

                # todo: show error?
            }
            else {
                $self->tpl_param('products_by_group',  $groups);
                $self->tpl_param('product_group_list', $group_list);
            }
        }
        else {
            warn "no required_devices for zone $zone->{id_token}; listing no plans"
              . ( ($sub_status && $sub_status->{error})
                  ? " (API error: $sub_status->{error}, trace: "
                  . ($sub_status->{trace_id} || 'none') . ")"
                  : ""
              );
        }

        # show_products gates the plan picker on its own. limits_exceeded is
        # false for an account with no subscription at all (AccountCoverage
        # returns early on !HasLive), so $limits_ok alone left an uncovered
        # vendor with no way to buy a plan. An uncovered vendor now gets both
        # the picker and the open-source form; @subs decides which of the two
        # branches inside the picker block renders.
        $self->tpl_param('show_products' => 1)
          if $account_token
          && (!$sub_data->{has_live_subscription} || $sub_data->{limits_exceeded});

        unless ($limits_ok) {
            $self->tpl_param('need_subscription' => 1);
            if (@subs) {    # already have subscriptions, but it wasn't enough...
                warn "need upgrade";
                $self->tpl_param('need_upgrade' => 1);
            }
        }
    }

    if (@subs) {

        # https://stripe.com/docs/billing/subscriptions/overview#subscription-statuses

        # trialing: ok
        # active: ok++
        # incomplete: ok to proceed
        # incomplete_expired: not ok, "cancelled"
        # past_due: don't allow new zones
        # canceled: don't allow new zones,
        # unpaid: don't allow new zones, link to payment

        # todo:
        #  - help incomplete subscriptions along?

        # invoice.status
        #   open: show payment link?
        #   paid: all ok.

        my %sort = (
            'trialing'           => 2,
            'active'             => 1,
            'incomplete'         => 2,
            'incomplete_expired' => 4,
            'past_due'           => 3,
            'canceled'           => 4,
            'unpaid'             => 3,
        );

        @subs = sort {
                 $sort{$a->{status}} <=> $sort{$b->{status}}
              || $b->{created_on} cmp $a->{created_on}    # RFC3339 strings sort correctly
        } @subs;

        # If subscription on file, but plan has "max zones":
        # - ... Contact vendors@ to upgrade or change plan?

        $self->tpl_param('subscriptions', \@subs);

        return OK, $self->evaluate_template('tpl/vendor/show.html');

    }

    return OK, $self->evaluate_template('tpl/vendor/show.html');
}

sub render_submit {
    my $self = shift;

    my $id = $self->_get_id;

    # Fetch zone via API
    my $result = get_vendor_zone(
        auth     => $self->plain_cookie($self->user_cookie_name),
        id_token => $id,
        context  => $self->_get_request_context(),
    );

    if ($result->{error}) {
        warn "API error getting vendor zone for submit: "
          . $result->{error}
          . " (trace: "
          . ($result->{trace_id} || 'none') . ")";
        return $self->redirect($self->manage_url('/manage/vendor'));
    }

    my $zone = $result->{data}{zone};

    return $self->render_zone($zone->{id_token})
      unless $zone->{status} eq 'New' || $zone->{status} eq 'Rejected';

    # Check subscription status for the zone's account
    my $account_token = $zone->{account_token};
    my $sub_status =
      $account_token
      ? get_account_subscription_status(
          $self->api_auth_params,
          account      => $account_token,
          device_count => $zone->{device_count},
      )
      : undef;
    my $sub_data = ($sub_status && !$sub_status->{error}) ? $sub_status->{data} : {};

    # Gate production submission on real coverage: a live subscription that is
    # within limits. limits_exceeded alone is false for an account with NO
    # subscription, so keying off it would let an uncovered vendor submit
    # straight to production with no claim (#39). The opensource_request block
    # below is the other way to pass this gate.
    my $ok =
      (      $account_token
          && $sub_data->{has_live_subscription}
          && !$sub_data->{limits_exceeded}) ? 1 : 0;    # fail closed
    $self->tpl_param('have_subscription', $ok);
    my $errors;
    my $opensource_info = '';

    if ($self->req_param('opensource_request')) {
        if (my $osinfo = $self->req_param('opensource_info')) {

            # todo: sanity check the data?
            $ok              = 1;
            $opensource_info = $osinfo;
        }
        else {
            $errors = {opensource_info => 'Please provide open source information'};
        }
    }

    unless ($ok) {
        if (!$errors) {

            # for products page if no accounts exist
            $self->tpl_param('need_subscription', 1);

            $errors->{missing_plan} =
              'Please choose a subscription plan or choose open source below'
              unless ($sub_data->{has_live_subscription});
        }

        # warn "errors ", Data::Dump::pp($errors);
        $self->tpl_param('errors', $errors);
        return $self->render_zone($zone->{id_token});
    }

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

    if ($submit_result->{error}) {
        warn "Failed to submit vendor zone: "
          . $submit_result->{error}
          . " (trace: "
          . ($submit_result->{trace_id} || 'none') . ")";
        $self->tpl_param(
            'errors',
            {   general  => $submit_result->{error},
                trace_id => $submit_result->{trace_id}
            }
        );
        return $self->render_zone($zone->{id_token});
    }

    $zone = $submit_result->{data}{zone};

    $self->tpl_param('vz',     $zone);
    $self->tpl_param('config', $self->config);

    my $msg = $self->evaluate_template('tpl/vendor/submit_email.txt');
    my $email =
      Email::Stuffer->from(NP::Email::address("sender"))
      ->to(NP::Email::address("vendors"))
      ->cc(NP::Email::address("notifications"))
      ->reply_to($self->user->{email})
      ->subject("New vendor zone application: " . $zone->{zone_name})
      ->text_body($msg);

    my $return = NP::Email::sendmail($email->email);
    warn Data::Dumper->Dump([\$msg, \$email, \$return], [qw(msg email return)]);

    return OK, $self->evaluate_template('tpl/vendor/submitted.html');
}

sub render_edit {
    my $self = shift;
    my ($zone, $errors) = $self->_edit_zone;

    if ($errors) {
        $self->tpl_param('errors', $errors);
        warn "vendor form errors: ", pp($errors);
        return $self->render_form($zone);
    }

    # if no subscription, go to subscription page

    my $redirect = $self->manage_url(
        '/manage/vendor/zone',
        {   id   => $zone->{id_token},
            a    => $self->current_account->{id_token},
            mode => 'show'
        }
    );

    return $self->redirect($redirect);
}

sub render_edit_json {
    my $self = shift;
    my ($zone, $errors) = $self->_edit_zone;

    return OK, $json->encode({zone => $zone, errors => $errors});
}

sub _edit_zone {
    my $self = shift;

    my $id = $self->_get_id;
    $id = 0 if $id and $id eq 'new';

    my $zone_name = lc($self->req_param('zone_name') || '');
    $zone_name =~ s/[^a-z0-9-]+//g;

    my %content = (
        zone_name           => $zone_name,
        organization_name   => $self->req_param('organization_name')   || '',
        request_information => $self->req_param('request_information') || '',
        device_information  => $self->req_param('device_information')  || '',
        contact_information => $self->req_param('contact_information') || '',
        device_count        => 0 + int($self->req_param('device_count') || 0),
    );

    # opensource / opensource_info are not part of the edit form; they are set
    # in the submit flow (render_submit). Sending opensource_info here would
    # blank a stored value and, for opensource zones, fail update validation.

    my %auth = (
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->{id_token},
        context => $self->_get_request_context(),
    );

    my $result;
    if ($id) {
        $result = update_vendor_zone(%auth, id_token => $id, content => \%content);
    }
    else {
        # request_vendor_zone keeps its flat shape (proto unchanged). Only send
        # the optional info fields when they have a value: an empty
        # contact_information would trip the vendor_admin-only guard for a
        # regular user creating a zone, and an empty device_information would
        # store "" instead of leaving the field unset.
        my %request = %content;
        for my $field (qw(device_information contact_information)) {
            delete $request{$field} unless length($request{$field} // '');
        }
        $result = request_vendor_zone(%auth, %request);
    }

    if ($result->{error}) {
        warn "API error in _edit_zone: "
          . $result->{error}
          . " (trace: "
          . ($result->{trace_id} || 'none') . ")";

        my $zone;
        if ($id) {
            my $fetch = get_vendor_zone(
                auth     => $self->plain_cookie($self->user_cookie_name),
                id_token => $id,
                context  => $self->_get_request_context(),
            );
            $zone = $fetch->{data} ? $fetch->{data}{zone} : undef;
        }
        return $zone, {general => $result->{error}, trace_id => $result->{trace_id}};
    }

    return $result->{data}{zone};
}

sub _update_subscription {
    my ($self, $account, $session_id) = @_;

    my $result = NP::Stripe::complete_checkout($session_id);

    if ($result->{error}) {
        warn "Failed to complete checkout: $result->{error}";
        return 500, "Failed to process subscription";
    }

    my $subscription = $result->{subscription};

    if ($subscription && $subscription->{live_subscription}) {

        # Display guard, not enforcement: stripe-gw has already saved the
        # subscription to the account Stripe named, so a session_id belonging
        # to someone else cannot land on this account's rows. This only decides
        # whether to render this account's zone as submitted, and fails closed
        # so a missing account_token never compares equal.
        my $token = $result->{account_token} // '';
        return $self->render_submit()
          if $token && $token eq ($account->{id_token} // '');
        warn
          "checkout session $session_id belongs to account $token, not $account->{id_token}";
    }
    else {
        warn "sub status: ", ($subscription ? $subscription->{status} : 'none');
    }

    return 200, "finished processing session";
}

sub render_subscription {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->{permissions}{can_edit};

    $self->tpl_param('account' => $account);

    if (my $session_id = $self->req_param('session_id')) {

        # we are returning from the checkout session; render_submit fetches the
        # zone itself, so don't pay for it here.
        return $self->_update_subscription($account, $session_id);
    }

    my $id = $self->_get_id;
    my $zone;

    # Fetch zone via API if ID provided
    if ($id) {
        my $result = get_vendor_zone(
            auth     => $self->plain_cookie($self->user_cookie_name),
            id_token => $id,
            context  => $self->_get_request_context(),
        );

        if ($result->{error}) {
            warn "API error getting vendor zone for subscription: "
              . $result->{error}
              . " (trace: "
              . ($result->{trace_id} || 'none') . ")";

            # Continue without zone - subscription page can still work
        }
        else {
            $zone = $result->{data}{zone};
        }
    }

    my $return_url = $self->manage_url(
        '/manage/vendor/plan',
        {   ($zone ? (id => $zone->{id_token}) : ()),
            a => $self->current_account->{id_token}
        }
    );

    my $product_id = $self->req_param('product_id') || '';
    my $price_id   = $self->req_param('price_id')   || '';

    warn "product_id: $product_id";
    warn "price_id:   $price_id";

    # choosing a product
    if ($product_id) {

        # Checkout buys what the account needs: its approved devices plus
        # this zone, as the API computes them. Without a zone there is no
        # such number, and only a flat price can be bought (below).
        my $required_devices = 0;
        if ($zone) {

            # The session charges the current account's Stripe customer, so
            # the zone it is priced for has to be that account's. A zone URL
            # without the zone's own a= leaves current_account as the
            # viewer's own account -- staff reach any zone that way -- and
            # the subscription would land on the wrong account. Fail closed,
            # as render_plan_upgrade does: a missing token on either side
            # never compares equal.
            unless ($zone->{account_token}
                and $zone->{account_token} eq ($account->{id_token} // ''))
            {
                warn "refusing checkout for zone "
                  . ($zone->{id_token} // 'none')
                  . " of account "
                  . ($zone->{account_token} // 'none')
                  . " from account "
                  . ($account->{id_token} // 'none');
                return FORBIDDEN;
            }

            my $status = get_account_subscription_status(
                $self->api_auth_params,
                account      => $zone->{account_token},
                device_count => $zone->{device_count},
            );
            if ($status->{error}) {
                warn "API error getting subscription status for checkout: "
                  . $status->{error}
                  . " (trace: "
                  . ($status->{trace_id} || 'none') . ")";
                return OK,
                  $json->encode({error => "Could not start checkout; please try again."});
            }
            $required_devices = $status->{data}{required_devices};

            # An answer without the number is not one to price a tiered
            # checkout from: 0 + undef would quietly buy a quantity of 0.
            # render_zone makes the same check before listing plans.
            unless (defined $required_devices) {
                warn "no required_devices for zone "
                  . ($zone->{id_token} // 'none')
                  . "; refusing checkout";
                return OK,
                  $json->encode({error => "Could not start checkout; please try again."});
            }
        }

        my ($products, $groups, $group_list) =
          NP::Stripe::product_groups(1, $required_devices);

        warn "STRIPE: ", Data::Dump::pp($products);
        if ($products->{error}) {
            warn "stripe gw error: ", $products->{error};
            return 500;
        }

        my ($product) =
          grep { $_->{ID} eq $product_id } @{$products->{Products}};
        $self->tpl_param('pr', $product);

        if (   $price_id
            && $self->request->uri eq '/manage/vendor/plan/create_session')
        {
            my ($plan) =
              grep { $_->{ID} eq $price_id } @{$product ? $product->{Plans} : []};
            unless ($plan) {
                warn "price $price_id is not a plan of product $product_id";
                return OK, $json->encode({error => "Unknown plan; please choose again."});
            }

            # A frozen account (deletion_on set) never reaches here: the
            # can_edit gate at the top of this sub is the API's
            # !deletion_on (AccountWritable), so checkout is already refused.

            # TODO:
            #  - take parameters to create session for the right price
            #  - set the right urls for cancel, etc
            #  - set the right customer ID if one exists

            # A flat price is bought once. A tiered price is bought for the
            # devices the account needs, which takes a zone; the plan
            # picker's forms always send one.
            my $quantity = 1;
            if ($plan->{TiersMode} ne "") {
                unless ($zone) {
                    warn "refusing tiered checkout for price $price_id without a zone";
                    return OK,
                      $json->encode({error => "Choose a plan from the zone's page."});
                }
                $quantity = 0 + $required_devices;
            }

            unless ($account->{stripe_customer_id}) {
                my $customer = NP::Stripe::create_customer(
                    email       => $self->user->{email},
                    name        => $account->{name},
                    description => $account->{organization_name},

                    account_id  => $account->{id_token},
                    account_url =>
                      $self->manage_url('/manage/vendor', {a => $account->{id_token}}),
                );

                # Without a saved customer id Stripe would mint a second,
                # unlinked customer and checkout/complete would fail after the
                # vendor has paid, so both failures stop here instead.
                unless ($customer && $customer->{id}) {
                    warn "Failed to create stripe customer: ",
                      (($customer && $customer->{error}) || 'no id returned');
                    return OK,
                      $json->encode(
                          {error => "Could not start checkout; please try again."});
                }

                my $update_result = update_account_stripe_customer(
                    $self->api_auth_params,
                    account            => $account->{id_token},
                    stripe_customer_id => $customer->{id},
                );
                if ($update_result->{error}) {
                    warn "Failed to update stripe_customer_id: "
                      . $update_result->{error}
                      . " (trace: "
                      . ($update_result->{trace_id} || 'none') . ")";
                    return OK,
                      $json->encode(
                          {error => "Could not start checkout; please try again."});
                }

                # Update local copy for immediate use
                $account->{stripe_customer_id} = $customer->{id};
            }

            my %args = (
                price_id => $price_id,
                quantity => $quantity,

                environment => $self->deployment_mode,
                account_id  => $account->{id_token},

                customer_id => $account->{stripe_customer_id},
                email       => $self->user->{email},

                return_url => $return_url,
            );

            my $session = NP::Stripe::create_session(%args);
            if ($session->{error}) {
                warn "create session error: ", $session->{error};

                # TODO: formatted error page
                return OK, $json->encode({error => $session->{error}});
            }
            return $self->redirect($session->{url});

            #return OK, $json->encode({checkoutSessionId => $session->{id}});
        }

        return OK, $self->evaluate_template('tpl/vendor/subscription.html');
    }

    warn "customer id: ", $account->{stripe_customer_id};

    # Decorative: degrade gracefully rather than replacing the plan page with a
    # bare error response on a transient blip.
    my $subs_result = get_account_subscriptions($self->api_auth_params,
        account => $self->current_account->{id_token},);
    if ($subs_result->{data} && $subs_result->{data}{subscriptions}) {
        $self->tpl_param('subscriptions', $subs_result->{data}{subscriptions});
    }

    return OK, $self->evaluate_template('tpl/vendor/subscription.html');

}

# render_plan_upgrade sends the vendor to Stripe's billing portal to raise
# the quantity on their tiered subscription. The subscription and quantity
# come from the API's upgrade offer, fetched again here; the form only names
# the zone. Anyone who can edit the current account may upgrade, staff who
# switched into it included, but only for a zone of that account: the Stripe
# customer is the current account's.
sub render_plan_upgrade {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->{permissions}{can_edit};

    my $id = $self->_get_id
      or return $self->redirect($self->manage_url('/manage/vendor'));

    my $result = get_vendor_zone(
        auth     => $self->plain_cookie($self->user_cookie_name),
        id_token => $id,
        context  => $self->_get_request_context(),
    );
    if ($result->{error}) {
        warn "API error getting vendor zone for upgrade: "
          . $result->{error}
          . " (trace: "
          . ($result->{trace_id} || 'none') . ")";
        return $self->redirect($self->manage_url('/manage/vendor'));
    }
    my $zone = $result->{data}{zone};

    # The offer describes the zone's account and the portal session uses the
    # current account's Stripe customer, so the two must be the same account.
    # Fail closed, as _update_subscription does: a zone with no account (the
    # API returns an empty token for one) must never match an account whose
    # own token is missing.
    unless ($zone->{account_token}
        and $zone->{account_token} eq ($account->{id_token} // ''))
    {
        warn "refusing upgrade for zone "
          . ($zone->{id_token} // 'none')
          . " of account "
          . ($zone->{account_token} // 'none')
          . " from account "
          . ($account->{id_token} // 'none');
        return FORBIDDEN;
    }

    my $zone_url = $self->manage_url('/manage/vendor/zone', {id => $zone->{id_token}});

    my $status = get_account_subscription_status(
        $self->api_auth_params,
        account      => $zone->{account_token},
        device_count => $zone->{device_count},
    );
    if ($status->{error}) {
        warn "API error getting subscription status for upgrade: "
          . $status->{error}
          . " (trace: "
          . ($status->{trace_id} || 'none') . ")";
        return $self->redirect($zone_url);
    }

    # No offer any more (the zone changed, or the plan already covers it):
    # the zone page shows what applies now.
    my $upgrade = $status->{data}{upgrade}
      or return $self->redirect($zone_url);

    my $session = NP::Stripe::upgrade_session(
        customer_id     => $account->{stripe_customer_id} // '',
        subscription_id => $upgrade->{stripe_subscription_id},
        quantity        => $upgrade->{quantity},
        return_url      => $self->manage_url(
            '/manage/vendor/plan/upgraded',
            {   id              => $zone->{id_token},
                subscription_id => $upgrade->{stripe_subscription_id},
            }
        ),
        cancel_url => $zone_url,
    );
    unless ($session->{url} && !$session->{error}) {
        warn "stripe-gw refused the upgrade for zone $zone->{id_token}: "
          . ($session->{error} || 'no url returned');
        $self->tpl_param('upgrade_refused' => 1);
        return $self->render_zone($zone->{id_token});
    }

    return $self->redirect($session->{url});
}

# render_plan_upgraded is where the billing portal sends the vendor after a
# confirmed upgrade. stripe-gw syncs the subscription with the webhook's own
# code, so the zone page shows the new limits without waiting for the
# webhook. A failed sync is an error response, as a failed checkout is in
# _update_subscription; the payment has gone through and the webhook writes
# the same row when it arrives.
sub render_plan_upgraded {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->{permissions}{can_edit};

    my $id = $self->_get_id
      or return $self->redirect($self->manage_url('/manage/vendor'));

    my $subscription_id = $self->req_param('subscription_id') // '';
    unless ($subscription_id =~ m/^sub_\w+$/) {
        warn "upgrade return for zone $id without a valid subscription_id";
        return 400, "Invalid upgrade return link";
    }

    # NP::Stripe's error carries stripe-gw's request id.
    my $r = NP::Stripe::sync_subscription(
        subscription_id => $subscription_id,
        customer_id     => $account->{stripe_customer_id} // '',
    );
    if ($r->{error}) {
        warn "Failed to sync upgraded subscription $subscription_id: $r->{error}";
        return 500, "Your payment went through. Your plan will update shortly.";
    }

    return $self->redirect($self->manage_url('/manage/vendor/zone', {id => $id}));
}

sub render_billing {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->{permissions}{can_edit};

    my $return_url = $self->manage_url('/manage/vendor', {a => $account->{id_token}});

    return $self->redirect(
        NP::Stripe::billing_portal_url($account->{stripe_customer_id}, $return_url));
}

sub render_admin {
    my $self = shift;

    return $self->redirect("/manage/vendor")
      unless $self->user_is_vendor_admin;

    $self->tpl_params->{page}->{is_vendor_admin} = 1;

    if (my $id = $self->_get_id) {

        # Fetch zone via API
        my $result = get_vendor_zone(
            auth     => $self->plain_cookie($self->user_cookie_name),
            id_token => $id,
            context  => $self->_get_request_context(),
        );

        if (my $status = $self->capi_error_status($result, $result->{data}{zone})) {
            warn "API error getting vendor zone for admin: "
              . $result->{error}
              . " (trace: "
              . ($result->{trace_id} || 'none') . ")"
              if $result->{error};
            return $status;
        }

        my $zone = $result->{data}{zone};

        if ($self->req_param('show')) {
            return $self->render_zone($id, 'show');
        }

        if (my $status_param = $self->req_param('status_change')) {
            if ($zone->{status} eq 'Pending' and $status_param =~ m/^Reject/) {

                # Send undef (not '') for a blank reason so the API leaves
                # rejection_reason NULL rather than storing an empty string.
                my $rejection_reason = $self->req_param('rejection_reason');
                $rejection_reason = undef
                  unless defined $rejection_reason && length $rejection_reason;

                # Reject zone via API
                my $update_result = update_vendor_zone_status(
                    auth                => $self->plain_cookie($self->user_cookie_name),
                    context             => $self->_get_request_context(),
                    id_token            => $id,
                    status              => 'Rejected',
                    opensource_approved => JSON::XS::false,
                    rejection_reason    => $rejection_reason,
                );

                if ($update_result->{error}) {
                    warn "Failed to reject vendor zone: "
                      . $update_result->{error}
                      . " (trace: "
                      . ($update_result->{trace_id} || 'none') . ")";
                    $self->tpl_param(
                        'errors',
                        {   general  => $update_result->{error},
                            trace_id => $update_result->{trace_id}
                        }
                    );
                }
                else {
                    $zone = $update_result->{data}{zone};
                    $self->tpl_param("msg" => $zone->{zone_name} . ' rejected');
                }
            }
            elsif ( $zone->{status} =~ m/(Pending|Rejected)/
                and $status_param =~ m/^Approve/)
            {
                # Approve zone via API
                my $update_result = update_vendor_zone_status(
                    auth                => $self->plain_cookie($self->user_cookie_name),
                    context             => $self->_get_request_context(),
                    id_token            => $id,
                    status              => 'Approved',
                    opensource_approved => $self->req_param('opensource_grant')
                    ? JSON::XS::true
                    : JSON::XS::false,
                );

                if ($update_result->{error}) {
                    warn "Failed to approve vendor zone: "
                      . $update_result->{error}
                      . " (trace: "
                      . ($update_result->{trace_id} || 'none') . ")";
                    $self->tpl_param(
                        'errors',
                        {   general  => $update_result->{error},
                            trace_id => $update_result->{trace_id}
                        }
                    );
                }
                else {
                    $zone = $update_result->{data}{zone};
                    my $user_email = $update_result->{data}{user_email};

                    $self->tpl_param('vz' => $zone);
                    $self->tpl_param('config', $self->config);

                    # Create dns_root hashref from API data (no database fetch needed)
                    $self->tpl_param('dns_root', {origin => $zone->{dns_root_origin}});

                    my $msg = $self->evaluate_template('tpl/vendor/approved_email.txt');

                    my $email =
                      Email::Stuffer->from(NP::Email::address("vendors"))
                      ->to($user_email)
                      ->cc(NP::Email::address("notifications"))
                      ->reply_to(NP::Email::address("vendors"))
                      ->subject("Vendor zone activated: " . $zone->{zone_name})
                      ->text_body($msg);

                    my $return = NP::Email::sendmail($email->email);
                    warn Data::Dumper->Dump([\$msg, \$email, \$return],
                        [qw(msg email return)]);

                    $self->tpl_param("msg" => $zone->{zone_name} . ' approved');
                }
            }
        }
    }

    # Fetch pending zones via API
    my $pending_result = list_vendor_zones_admin(
        auth    => $self->plain_cookie($self->user_cookie_name),
        context => $self->_get_request_context(),
        status  => 'Pending',
    );

    if ($pending_result->{error}) {
        warn "Failed to list pending zones: "
          . $pending_result->{error}
          . " (trace: "
          . ($pending_result->{trace_id} || 'none') . ")";
        $self->tpl_param(pending_zones => []);
    }
    else {
        # API returns VendorZoneAdmin objects with zone + account details
        $self->tpl_param(pending_zones => $pending_result->{data}{zones});
    }

    return OK, $self->evaluate_template('tpl/vendor/admin.html');
}

1;
