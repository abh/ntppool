package NTPPool::Control::Vendor;
use strict;
use parent qw(NTPPool::Control::Manage);
use NP::Model;
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
    create_or_update_subscription
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

    return $self->render_subscription
      if $self->request->uri =~ m!^/manage/vendor/plan!;

    return $self->render_billing
      if $self->request->uri =~ m!^/manage/vendor/billing!;

    return $self->render_admin
      if $self->request->uri =~ m!^/manage/vendor/admin$!;

    # Check if user has any vendor zones via API
    my $zones_result = list_vendor_zones(
        auth    => $self->plain_cookie($self->user_cookie_name),
        account => $self->current_account->id_token,
        context => $self->_get_request_context(),
    );

    unless ($zones_result->{data} && @{$zones_result->{data}{zones}}) {
        return $self->redirect($self->manage_url('/manage/vendor/new'));
    }

    $self->tpl_params->{page}->{is_vendor} = 1;

    return $self->render_zones
      if $self->request->uri =~ m!^/manage/vendor/?$!;

    return NOT_FOUND;
}

sub _get_id {
    my $self  = shift;
    my $token = $self->req_param('id');
    my $id    = $token =~ m/^vz-/ ? NP::Model::VendorZone->token_id($token) : $token;
    return $id;
}

# _resolve_zone_token: Helper to convert ID parameter (numeric or token) to token format for API
# Accepts: numeric ID or token ID (vz-xxx)
# Returns: token ID (vz-xxx) for use with CAPI calls
sub _resolve_zone_token {
    my $self  = shift;
    my $input = shift || $self->req_param('id');

    return undef unless $input;

    # If already a token, return as-is
    return $input if $input =~ m/^vz-/;

    # If numeric ID, convert to token
    if ($input =~ m/^\d+$/) {

        # Use NP::Model to convert numeric ID to token
        return NP::Model::VendorZone->id_token($input);
    }

    return undef;
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
    my $token  = $self->_resolve_zone_token($id);
    my $result = get_vendor_zone(
        auth     => $self->plain_cookie($self->user_cookie_name),
        id_token => $token,
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
    my $sub_status    = $account_token
      ? get_account_subscription_status(
          $self->api_auth_params,
          account      => $account_token,
          device_count => $zone->{device_count},
      )
      : undef;
    my $sub_data = ($sub_status && !$sub_status->{error}) ? $sub_status->{data} : {};
    my $limits_ok =
      ($account_token && !$sub_data->{limits_exceeded}) ? 1 : 0;    # fail closed
    $self->tpl_param('have_subscription', $limits_ok);

    # Set can_edit flag for template (zones can be edited unless Approved)
    $self->tpl_param('can_edit_zone', $zone->{status} ne 'Approved');

    # For edit mode, check if user can edit (API handles permission, but check status)
    return $self->render_form($zone)
      if $mode eq 'edit' && $zone->{status} ne 'Approved';

    my $device_count = $zone->{device_count} || 0;

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

        # todo: only load if we need to show this
        my ($products, $groups, $group_list) =
          NP::Stripe::product_groups(1, $device_count);
        if ($products->{error}) {
            warn "stripe gw error: ", $products->{error};

            # todo: show error?
        }
        else {
            $self->tpl_param('products_by_group',  $groups);
            $self->tpl_param('product_group_list', $group_list);
        }

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
    my $token  = $self->_resolve_zone_token($id);
    my $result = get_vendor_zone(
        auth     => $self->plain_cookie($self->user_cookie_name),
        id_token => $token,
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

    return $self->render_zone($zone->{vendor_zone_id})
      unless $zone->{status} eq 'New';

    # Check subscription status for the zone's account
    my $account_token = $zone->{account_token};
    my $sub_status    = $account_token
      ? get_account_subscription_status(
          $self->api_auth_params,
          account      => $account_token,
          device_count => $zone->{device_count},
      )
      : undef;
    my $sub_data = ($sub_status && !$sub_status->{error}) ? $sub_status->{data} : {};

    # Basic validation happens in the API, but check subscription requirements client-side
    my $ok = ($account_token && !$sub_data->{limits_exceeded}) ? 1 : 0;    # fail closed
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
        return $self->render_zone($zone->{vendor_zone_id});
    }

    # Submit zone via API
    my $opensource =
      $self->req_param('opensource_request') ? JSON::XS::true : JSON::XS::false;
    my $submit_result = submit_vendor_zone(
        auth            => $self->plain_cookie($self->user_cookie_name),
        context         => $self->_get_request_context(),
        id_token        => $token,
        opensource      => $opensource,
        opensource_info => $opensource_info,
    );

    if ($submit_result->{error}) {
        warn "Failed to submit vendor zone: "
          . $submit_result->{error}
          . " (trace: "
          . ($submit_result->{trace_id} || 'none') . ")";
        $self->tpl_param('errors', {general => $submit_result->{error}});
        return $self->render_zone($zone->{vendor_zone_id});
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

    my @fields =
      qw(organization_name request_information device_information contact_information device_count opensource_info);

    # Convert form parameters to hash for API
    my %zone_params = (
        auth                => $self->plain_cookie($self->user_cookie_name),
        account             => $self->current_account->id_token,
        context             => $self->_get_request_context(),
        zone_name           => $zone_name,
        organization_name   => $self->req_param('organization_name')   || '',
        request_information => $self->req_param('request_information') || '',
        device_information  => $self->req_param('device_information')  || '',
        contact_information => $self->req_param('contact_information') || '',
        device_count        => 0 + int($self->req_param('device_count') || 0),
        opensource_info     => $self->req_param('opensource_info') || '',
    );

    my $result;
    if ($id) {

        # Update existing zone
        my $token = $self->_resolve_zone_token($id);
        $result = update_vendor_zone(%zone_params, id_token => $token,);
    }
    else {
        # Create new zone
        $result = request_vendor_zone(%zone_params);
    }

    if ($result->{error}) {
        warn "API error in _edit_zone: "
          . $result->{error}
          . " (trace: "
          . ($result->{trace_id} || 'none') . ")";

        # Return zone data if available, otherwise undef, plus error
        my $zone = $result->{data} ? $result->{data}{zone} : undef;
        return $zone, [$result->{error}];
    }

    my $zone = $result->{data}{zone};
    return $zone;
}

sub _update_subscription {
    my ($self, $account, $session_id) = @_;

    warn "looking up session $session_id";
    my $session = NP::Stripe::get_session($session_id);
    warn "SESSION: ", Data::Dump::pp(\$session);

    my $customer_id = $session->{customer_id};
    my $subscription_id =
      $session->{subscription} && $session->{subscription}->{id};

    warn "customer_id:     $customer_id";
    warn "subscription_id: $subscription_id";

    if ($subscription_id) {

        # Handle max_devices fallback from max_clients
        my $max_devices =
             $session->{subscription}->{max_devices}
          || $session->{subscription}->{max_clients}
          || 10000000;

        my $result = create_or_update_subscription(
            $self->api_auth_params,
            account                => $account->{id_token},
            stripe_subscription_id => $subscription_id,
            stripe_customer_id     => $customer_id,
            status                 => $session->{subscription}->{status},
            name                   => $session->{subscription}->{name}      || '',
            max_zones              => $session->{subscription}->{max_zones} || 1,
            max_devices            => $max_devices,
            created_on_unix        => time(),
        );

        if ($result->{error}) {
            warn "Failed to create/update subscription: $result->{error}";
            warn "Trace ID: $result->{trace_id}" if $result->{trace_id};
            return 500, "Failed to process subscription";
        }

        my $subscription = $result->{data}{subscription};
        if ($subscription && $subscription->{live_subscription}) {
            warn "got live subscription";
            return $self->render_submit();
        }
        else {
            warn "sub status: ", ($subscription ? $subscription->{status} : 'unknown');
        }
    }

    # Also update stripe_customer_id if needed
    if ($customer_id && !$account->{stripe_customer_id}) {
        my $update_result = update_account_stripe_customer(
            $self->api_auth_params,
            account            => $account->{id_token},
            stripe_customer_id => $customer_id,
        );
        if ($update_result->{error}) {
            warn "Failed to update stripe_customer_id: $update_result->{error}";
        }
    }

    return 200, "finished processing session";
}

sub render_subscription {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->{permissions}{can_edit};

    my $id = $self->_get_id;
    my $zone;

    # Fetch zone via API if ID provided
    if ($id) {
        my $token  = $self->_resolve_zone_token($id);
        my $result = get_vendor_zone(
            auth     => $self->plain_cookie($self->user_cookie_name),
            id_token => $token,
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

    $self->tpl_param('account' => $account);

    if (my $session_id = $self->req_param('session_id')) {

        # we are returning from the checkout session
        return $self->_update_subscription($account, $session_id);
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

        my $device_count = $zone ? ($zone->{device_count} || 0) : 0;
        my ($products, $groups, $group_list) =
          NP::Stripe::product_groups(1, $device_count);

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
            my ($plan) = grep { $_->{ID} eq $price_id } @{$product->{Plans}};

            # Use current_account instead of zone->account
            my $account = $self->current_account;

            # TODO:
            #  - take parameters to create session for the right price
            #  - set the right urls for cancel, etc
            #  - set the right customer ID if one exists

            my $quantity = $zone ? ($zone->{device_count} || 1) : 1;
            if ($plan->{TiersMode} eq "") {
                $quantity = 1;
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
                if ($customer && $customer->{id}) {
                    my $update_result = update_account_stripe_customer(
                        $self->api_auth_params,
                        account            => $account->{id_token},
                        stripe_customer_id => $customer->{id},
                    );
                    if ($update_result->{error}) {
                        warn
                          "Failed to update stripe_customer_id: $update_result->{error}";
                    }
                    else {
                        # Update local copy for immediate use
                        $account->{stripe_customer_id} = $customer->{id};
                    }
                }
            }

            my %args = (
                price_id => $price_id,
                quantity => $quantity,

                environment => "devel",
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

    my $subs_result = get_account_subscriptions($self->api_auth_params,
        account => $self->current_account->{id_token},);
    if ($subs_result->{data} && $subs_result->{data}{subscriptions}) {
        $self->tpl_param('subscriptions', $subs_result->{data}{subscriptions});
    }

    return OK, $self->evaluate_template('tpl/vendor/subscription.html');

}

sub render_billing {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->{permissions}{can_edit};

    my $return_url = $self->manage_url('/manage/vendor', {a => $account->id_token});

    return $self->redirect(
        NP::Stripe::billing_portal_url($account->stripe_customer_id, $return_url));
}

sub render_admin {
    my $self = shift;

    return $self->redirect("/manage/vendor")
      unless $self->user_is_vendor_admin;

    $self->tpl_params->{page}->{is_vendor_admin} = 1;

    if (my $id = $self->_get_id) {

        # Fetch zone via API
        my $token  = $self->_resolve_zone_token($id);
        my $result = get_vendor_zone(
            auth     => $self->plain_cookie($self->user_cookie_name),
            id_token => $token,
            context  => $self->_get_request_context(),
        );

        if ($result->{error}) {
            warn "API error getting vendor zone for admin: "
              . $result->{error}
              . " (trace: "
              . ($result->{trace_id} || 'none') . ")";
            return 404 if $result->{code} == 404;
            return $result->{code};
        }

        my $zone = $result->{data}{zone};

        if ($self->req_param('show')) {
            return $self->render_zone($id, 'show');
        }

        if (my $status_param = $self->req_param('status_change')) {
            if ($zone->{status} eq 'Pending' and $status_param =~ m/^Reject/) {

                # Reject zone via API
                my $update_result = update_vendor_zone_status(
                    auth     => $self->plain_cookie($self->user_cookie_name),
                    context  => $self->_get_request_context(),
                    id_token => $token,
                    status   => 'Rejected',
                );

                if ($update_result->{error}) {
                    warn "Failed to reject vendor zone: "
                      . $update_result->{error}
                      . " (trace: "
                      . ($update_result->{trace_id} || 'none') . ")";
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
                    auth     => $self->plain_cookie($self->user_cookie_name),
                    context  => $self->_get_request_context(),
                    id_token => $token,
                    status   => 'Approved',
                );

                if ($update_result->{error}) {
                    warn "Failed to approve vendor zone: "
                      . $update_result->{error}
                      . " (trace: "
                      . ($update_result->{trace_id} || 'none') . ")";
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
