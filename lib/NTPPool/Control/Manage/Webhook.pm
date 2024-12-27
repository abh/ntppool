package NTPPool::Control::Manage::Webhook;
use strict;
use NTPPool::Control::Manage;
use parent qw(NTPPool::Control::Manage);
use NP::Model;
use Combust::Constant qw(OK NOT_FOUND FORBIDDEN);
use Combust::Config   ();
use JSON::XS          ();
use Crypt::JWT        qw(decode_jwt);

my $config     = Combust::Config->new;
my $config_ntp = $config->site->{ntppool};

my $json = JSON::XS->new->utf8;

sub render {
    my $self = shift;
    $self->set_span_name("manage.webhook");

    my $bearer = $self->request->header_in("Authorization");
    return FORBIDDEN unless $self->_check_jwt($bearer);

    return $self->webhook() if ($self->request->method eq 'post');

    return NOT_FOUND;
}

sub _check_jwt {
    my ($self, $bearer) = @_;
    return 0 unless $bearer;
    return 0 unless $bearer =~ s/^Bearer //;

    warn "checking jwt: $bearer";

    my @keys;

    my $next_version = 0;

    while (@keys < 4) {
        my $data = NP::Vault::get_kv("stripe-jwt", $next_version);
        unless ($data && %$data) {
            warn "no stripe-jwt keys available from vault";
            return 0;
        }

        # warn Data::Dump::pp( \$data );
        last unless $data->{data} && $data->{data}->{token};
        push @keys, $data->{data}->{token};

        $next_version = $data->{metadata}->{version} - 1;
        last if $next_version <= 0;
    }

    my $err;
    for my $key (@keys) {
        my $jwt = eval {
            decode_jwt(
                token      => $bearer,
                verify_iss => 'stripe-gw',

                #verify_aud => 'ntppool',
                verify_iat => 1,
                verify_nbf => 1,
                verify_exp => 1,
                key        => $key,
            );
        };
        if ($@) {
            $err = $@;
            $jwt = undef;
        }
        return 1 if $jwt;
    }
    warn "jwt error: $err";
    return 0;
}

sub webhook {
    my $self = shift;

    my $content = $self->request->raw_body;
    warn "GOT CONTENT: \n", $content;

    my $event = $json->decode($content);

    warn "EVENT: \n", Data::Dump::pp(\$event);

    if ($event->{Type} eq "subscription") {
        my $data            = $event->{Data};
        my $subscription_id = $data->{SubscriptionID};
        my $customer_id     = $data->{CustomerID};
        my $status          = $data->{Status};

        my $sub = NP::Model->account_subscription->get_account_subscriptions(
            require_objects => ['account'],
            query           => [stripe_subscription_id => $subscription_id],
        );

        $sub = $sub && $sub->[0];

        unless ($sub) {
            warn "could not find subscription id: $subscription_id";
            return NOT_FOUND, "no subscription";
        }

        warn "got sub: ", $sub->id if $sub;
        if ($sub->account->stripe_customer_id ne $customer_id) {
            warn "Unexpected customer id: ", $customer_id, " vs ",
              $sub->account->stripe_customer_id;
        }
        $sub->status($status);
        if ($data->{CreatedOn}) {
            $sub->created_on(DateTime->from_epoch(epoch => $data->{CreatedOn}));
        }
        if ($data->{EndedOn}) {
            $sub->ended_on(DateTime->from_epoch(epoch => $data->{EndedOn}));
        }
        else {
            $sub->ended_on(undef);
        }
        $sub->save();
    }

    return OK, "foo\n";
}

1;
