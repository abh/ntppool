package NTPPool::Control::Vendor;
use strict;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND FORBIDDEN);
use NP::Email      ();
use Email::Stuffer ();
use Sys::Hostname qw(hostname);
use JSON ();
use NP::Stripe;
use List::Util qw(uniq);
use Data::Dump qw(pp);

my $json = JSON::XS->new->pretty->utf8->convert_blessed;

sub manage_dispatch {
    my $self = shift;

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;
    }

    return $self->render_form if $self->request->uri =~ m!^/manage/vendor/new$!;

    if ($self->request->uri eq '/manage/vendor/zone') {

        return $self->render_edit if ($self->request->method eq 'post');

        return $self->render_zone($self->_get_id);
    }

    return $self->render_submit
      if (  $self->request->uri =~ m!^/manage/vendor/submit$!
        and $self->request->method eq 'post');

    return $self->render_subscription
      if $self->request->uri =~ m!^/manage/vendor/plan!;

    return $self->render_billing
      if $self->request->uri =~ m!^/manage/vendor/billing!;

    return $self->render_admin if $self->request->uri =~ m!^/manage/vendor/admin$!;

    return $self->redirect($self->manage_url('/manage/vendor/new'))
      unless @{$self->user->vendor_zones};

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

sub render_form {
    my $self = shift;
    my $vz   = shift;

    my @device_count_options = (
        500,     2500,    5000,     10000,    25000,    50000, 100000, 500000,
        1000000, 5000000, 10000000, 25000000, 50000000, 100000000
    );

    if ($vz) {
        $self->tpl_param('vz', $vz);

        push(@device_count_options, $vz->device_count)
          if $vz->device_count;

        $self->tpl_param('dns_roots', [$vz->dns_root]);
    }
    else {
        $self->tpl_param('dns_roots',
            NP::Model->dns_root->get_objects(query => [vendor_available => 1]));
    }

    my $opt = [uniq(sort { $a <=> $b } @device_count_options)];
    $self->tpl_param('device_count_options', $opt);

    return OK, $self->evaluate_template('tpl/vendor/form.html');
}

sub render_zones {
    my $self = shift;

    my $accounts = $self->user->accounts;
    $self->tpl_param('accounts' => $accounts);

    if (my @subs = $self->current_account->account_subscriptions) {
        $self->tpl_param('subscriptions', \@subs);
    }

    return OK, $self->evaluate_template('tpl/vendor.html');
}

sub render_zone {
    my ($self, $id, $mode) = @_;

    warn "rendering zone";

    return $self->redirect($self->manage_url('/manage/vendor')) unless $id;

    $mode ||= $self->req_param('mode') || '';

    my $vz = NP::Model->vendor_zone->fetch(id => $id);

    return $self->redirect($self->manage_url('/manage/vendor'))
      unless $vz and $vz->can_view($self->user);

    $self->tpl_param('vz', $vz);

    return $self->render_form($vz)
      if (  $mode eq 'edit'
        and $vz->can_edit($self->user));

    warn "looking for subscriptions";

    my $zone_device_count = $vz->device_count || 0;

    # todo: only load if we need to show this
    my ($products, $groups, $group_list) = NP::Stripe::product_groups($zone_device_count);
    if ($products->{error}) {
        warn "stripe gw error: ", $products->{error};

        # todo: show error?
    }
    else {
        $self->tpl_param('products_by_group',  $groups);
        $self->tpl_param('product_group_list', $group_list);
    }

    my @subs = $self->current_account->account_subscriptions;
    if (@subs) {

        # https://stripe.com/docs/billing/subscriptions/overview#subscription-statuses

        # trialing: ok
        # active: ok++
        # incomplete: ok to proceed
        # incomplete_expired: not ok, "cancelled"
        # past_due: don't allow new zones
        # canceled: don't allow new zones,
        # unpaid: don't allow new zones, link to payment

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
                 $sort{$a->{status}}   <=> $sort{$b->{status}}
              || $b->created_on->epoch <=> $a->created_on->epoch
        } @subs;

        # If subscription on file, and more zones can be added:
        # - Add to current subscription

        # If subscription on file, but plan has "max zones":
        # - ... Contact vendors@ to upgrade or change plan?

        warn "have subscriptions ...";
        $self->tpl_param('subscriptions', \@subs);

        return OK, $self->evaluate_template('tpl/vendor/show.html');

    }


    # TODO: add template variable if there's no subscription

    return OK, $self->evaluate_template('tpl/vendor/show.html');
}

sub render_submit {
    my $self = shift;

    my $id = $self->_get_id;

    my $vz = $id && NP::Model->vendor_zone->fetch(id => $id);

    return $self->render_zone($vz->id)
      unless $vz->can_edit($self->user)
      and $vz->status eq 'New';

    unless ($vz->validate) {
        my $errors = $vz->validation_errors;
        $self->tpl_param('errors', $errors);
        return $self->render_form($vz);
    }

    $vz->status('Pending');
    $vz->save;

    $self->tpl_param('vz',     $vz);
    $self->tpl_param('config', $self->config);

    my $msg = $self->evaluate_template('tpl/vendor/submit_email.txt');
    my $email =
      Email::Stuffer->from(NP::Email::address("sender"))->to(NP::Email::address("vendors"))
      ->cc(NP::Email::address("notifications"))->reply_to($self->user->email)
      ->subject("New vendor zone application: " . $vz->zone_name)->text_body($msg);

    my $return = NP::Email::sendmail($email->email);
    warn Data::Dumper->Dump([\$msg, \$email, \$return], [qw(msg email return)]);

    return OK, $self->evaluate_template('tpl/vendor/submitted.html');
}

sub render_edit {
    my $self = shift;
    my ($vz, $errors) = $self->_edit_zone;

    if ($errors) {
        $self->tpl_param('errors', $errors);
        warn "vendor form errors: ", pp($errors);
        return $self->render_form($vz);
    }

    # if no subscription, go to subscription page

    my $redirect = $self->manage_url('/manage/vendor/zone',
        {id => $vz->id_token, a => $self->current_account->id_token, mode => 'show'});

    return $self->redirect($redirect);
}

sub render_edit_json {
    my $self = shift;
    my ($vz, $errors) = $self->_edit_zone;

    return OK, $json->encode({zone => $vz->json_model, errors => $errors});
}

sub _edit_zone {
    my $self = shift;

    my $id = $self->_get_id;
    $id = 0 if $id and $id eq 'new';

    my $vz = $id ? NP::Model->vendor_zone->fetch(id => $id) : undef;

    if ($vz and !$vz->can_edit($self->user)) {
        return undef, ["Permission denied"];
    }

    my $zone_name = lc($self->req_param('zone_name') || '');
    $zone_name =~ s/[^a-z0-9-]+//g;

    # validation is in NP::Model::VendorZone
    my @fields = qw(organization_name request_information contact_information device_count);

    if ($vz) {
        $vz->zone_name($zone_name);
        for my $f (@fields) {
            $vz->$f($self->req_param($f) || '');
        }
    }
    else {

        # TODO: If we ever have more than one public dns_root, be smarter here.
        my $dns_root =
          (NP::Model->dns_root->get_objects(query => [vendor_available => 1], limit => 1))->[0];

        $vz = NP::Model->vendor_zone->create(
            zone_name  => $zone_name,
            user_id    => $self->user->id,
            account_id => $self->current_account->id,
            dns_root   => $dns_root->id,
            (map { $_ => ($self->req_param($_) || '') } @fields)
        );
    }

    unless ($vz->validate) {
        my $errors = $vz->validation_errors;
        return $vz, $errors;
    }

    $vz->save;

    return $vz;
}

sub _update_subscription {
    my ($self, $session_id, $account) = @_;

    warn "looking up session $session_id";
    my $session = NP::Stripe::get_session($session_id);
    warn "SESSION: ", Data::Dump::pp(\$session);

    my $customer_id     = $session->{customer_id};
    my $subscription_id = $session->{subscription} && $session->{subscription}->{id};

    warn "customer_id:     $customer_id";
    warn "subscription_id: $subscription_id";

    if ($subscription_id) {
        my $account_subscription = NP::Model->account_subscription->fetch_or_create(
            account_id             => $account->id,
            stripe_subscription_id => $subscription_id
        );

        unless ($session->{subscription}->{max_devices}) {
            $session->{subscription}->{max_devices} = $session->{subscription}->{max_clients}
              if $session->{subscription}->{max_clients};
        }

        for my $f (qw(status name max_zones max_devices)) {
            $account_subscription->$f($session->{subscription}->{$f});
        }
        $account_subscription->save();

        $account->stripe_customer_id($customer_id);
        $account->save();
    }

    # update subscription_id in database ...

    # show appropriate status page for the subscription status.

    return 200, "finished processing session";
}

sub render_subscription {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->can_edit($self->user);

    my $id = $self->_get_id;
    my $vz = $id && NP::Model->vendor_zone->fetch(id => $id);

    $self->tpl_param('account' => $account);

    if (my $session_id = $self->req_param('session_id')) {

        # todo: don't return here but process whatever is the appropriate template
        return $self->_update_subscription($account, $session_id);
    }

    my $return_url = $self->manage_url('/manage/vendor/plan',
        {($vz ? (id => $vz->id_token) : ()), a => $self->current_account->id_token});

    my $product_id = $self->req_param('product_id') || '';
    my $price_id   = $self->req_param('price_id')   || '';

    warn "product_id: $product_id";
    warn "price_id:   $price_id";

    # choosing a product
    if ($product_id) {

        my $zone_device_count = $vz->device_count || 0;
        my ($products, $groups, $group_list) = NP::Stripe::product_groups($zone_device_count);

        warn "STRIPE: ", Data::Dump::pp($products);
        if ($products->{error}) {
            warn "stripe gw error: ", $products->{error};
            return 500;
        }

        my ($product) = grep { $_->{ID} eq $product_id } @{$products->{Products}};
        $self->tpl_param('pr', $product);

        if ($price_id && $self->request->uri eq '/manage/vendor/plan/create_session') {
            my ($plan) = grep { $_->{ID} eq $price_id } @{$product->{Plans}};

            # TODO:
            #  - take parameters to create session for the right price
            #  - set the right urls for cancel, etc
            #  - set the right customer ID if one exists

            my $quantity = $vz->device_count;
            if ($plan->{TiersMode} eq "") {
                $quantity = 1;
            }

            my %args = (
                price_id => $price_id,
                quantity => $quantity,

                account_id  => $self->current_account->id_token,
                customer_id => $vz->account->stripe_customer_id,
                email       => $self->user->email,

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

    warn "customer id: ", $account->stripe_customer_id;

    if (my @subs = $self->current_account->account_subscriptions) {
        warn "have subscriptions ...";
        $self->tpl_param('subscriptions', \@subs);
    }

    return OK, $self->evaluate_template('tpl/vendor/subscription.html');

}

sub render_billing {
    my $self = shift;

    my $account = $self->current_account;
    return FORBIDDEN unless $account && $account->can_edit($self->user);

    my $return_url = $self->manage_url('/manage/vendor', {a => $account->id_token});

    return $self->redirect(
        NP::Stripe::billing_portal_url($account->stripe_customer_id, $return_url));
}


sub render_admin {
    my $self = shift;

    return $self->redirect("/manage/vendor")
      unless $self->user->privileges->vendor_admin;

    $self->tpl_params->{page}->{is_vendor_admin} = 1;

    if (my $id = $self->_get_id) {
        my $vz = $id ? NP::Model->vendor_zone->fetch(id => $id) : undef;
        return 404 unless $vz;

        if ($self->req_param('show')) {
            return $self->render_zone($id, 'show');
        }

        if (my $status = $self->req_param('status_change')) {
            if ($vz->status eq 'Pending' and $status =~ m/^Reject/) {
                $vz->status('Rejected');
                $vz->save;
                $self->tpl_param("msg" => $vz->zone_name . ' rejected');
            }
            elsif ($vz->status =~ m/(Pending|Rejected)/ and $status =~ m/^Approve/) {
                $vz->status('Approved');
                $vz->save;

                $self->tpl_param('vz' => $vz);
                $self->tpl_param('config', $self->config);

                my $msg = $self->evaluate_template('tpl/vendor/approved_email.txt');

                my $email =
                  Email::Stuffer->from(NP::Email::address("vendors"))->to($vz->user->email)
                  ->cc(NP::Email::address("notifications"))
                  ->reply_to(NP::Email::address("vendors"))
                  ->subject("Vendor zone activated: " . $vz->zone_name)->text_body($msg);

                my $return = NP::Email::sendmail($email->email);
                warn Data::Dumper->Dump([\$msg, \$email, \$return], [qw(msg email return)]);

                $self->tpl_param("msg" => $vz->zone_name . ' approved');

            }
        }
    }

    my $pending = NP::Model->vendor_zone->get_vendor_zones(
        query   => [status => 'Pending'],
        sort_by => 'id desc',
    );

    $self->tpl_param(pending_zones => $pending);

    return OK, $self->evaluate_template('tpl/vendor/admin.html');
}

1;
