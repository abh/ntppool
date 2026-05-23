package NP::Model::Account;
use strict;
use NP::Model::TokenID;
use base              qw(NP::Model::TokenID);
use Combust::Config   ();
use NP::CAPI::Account qw(get_account_server_verification_status);
use NP::CAPI::Subscription qw(get_account_subscription_status get_account_subscriptions);
use OpenTelemetry::Trace;
use OpenTelemetry -all;
use OpenTelemetry::Constants qw( SPAN_STATUS_ERROR );

my $config = Combust::Config->new;

sub token_key_config {
    return 'account_id_key';
}

sub url {
    my $self = shift;
    return $config->base_url('manage') . '/manage?a=' . $self->id_token;
}

sub public_url {
    my $self = shift;
    return "" unless $self->url_slug;
    return $config->base_url('ntppool') . '/a/' . $self->url_slug;
}

sub display_name {
    my $self = shift;
    return $self->name || $self->organization_name || $self->url_slug;
}

sub is_member {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if grep { $_->id == $user->id } $self->users;
    return 0;
}

sub can_edit {
    my ($self, $user, $controller) = @_;
    return 0 unless $user;

    # Check controller-level privileges if controller is provided
    return 1 if $controller && $controller->user_is_staff;
    return 1 if $self->is_member($user);
    return 0;
}

sub can_view {
    my ($self, $user, $controller) = @_;
    return 1 if $self->can_edit($user, $controller);

    # Check controller-level privileges if controller is provided
    return 1 if $controller && $controller->user_is_monitor_admin;
    return 0;
}

sub can_add_servers {
    my $self = shift;

    my $id_token = $self->id_token;
    unless ($id_token) {
        my $account_id = $self->id || 'undef';
        warn "can_add_servers: account has no id_token, account_id=$account_id";

        # Add span information for observability
        my $span = otel_current_context->span;
        if ($span) {
            $span->set_status(SPAN_STATUS_ERROR, "Account missing id_token");
            $span->set_attribute("account.id", $account_id) if $account_id ne 'undef';
            $span->set_attribute("account.id_token.missing", 1);
            $span->add_event(
                "id_token_missing",
                {   "account.id" => $account_id,
                    "message"    => "Account object has no id_token for verification"
                }
            );
        }

        # Fail safely - don't allow adding servers if we can't verify
        return 0;
    }

    my $result = get_account_server_verification_status(account => $id_token,);

    # Return 0 on API error (don't allow adding servers)
    if ($result->{error}) {
        my $span = otel_current_context->span;
        $span->set_status(SPAN_STATUS_ERROR, $result->{error});
        $span->record_exception($result->{error});
        warn "Failed to get server verification status: " . $result->{error};
        warn "Trace ID: " . ($result->{trace_id} || 'none');
        return 0;
    }

    my $data = $result->{data};

    # allow adding servers if none are there
    return 1 unless ($data->{verified_count} || $data->{unverified_count});

    # todo: make this an account flag
    if ($data->{unverified_count} && $data->{unverified_count} >= 2) {
        return 0;
    }

    return 1;
}

sub have_live_subscription {
    my $self = shift;

    my $result = get_account_subscription_status(
        account => $self->id_token,
    );

    if ($result->{error}) {
        warn "get_account_subscription_status error: $result->{error}";
        warn "Trace ID: $result->{trace_id}" if $result->{trace_id};
        return 0;
    }

    return $result->{data}{has_live_subscription} ? 1 : 0;
}

sub live_subscriptions {
    my $self = shift;

    my $result = get_account_subscriptions(
        account => $self->id_token,
    );

    if ($result->{error}) {
        warn "get_account_subscriptions error: $result->{error}";
        warn "Trace ID: $result->{trace_id}" if $result->{trace_id};
        return ();
    }

    return grep { $_->{live_subscription} } @{$result->{data}{subscriptions} || []};
}

sub subscription_limits_not_exceeded {
    my $self             = shift;
    my $new_device_count = shift || 0;

    my $result = get_account_subscription_status(
        account      => $self->id_token,
        device_count => $new_device_count,
    );

    if ($result->{error}) {
        warn "get_account_subscription_status error: $result->{error}";
        warn "Trace ID: $result->{trace_id}" if $result->{trace_id};
        return 0;    # Fail closed on error
    }

    return $result->{data}{limits_exceeded} ? 0 : 1;
}

1;
