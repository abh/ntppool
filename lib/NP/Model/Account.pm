package NP::Model::Account;
use strict;
use Math::BaseCalc qw();
use Math::Random::Secure qw(irand);
use NP::Model::TokenID;
use base qw(NP::Model::TokenID);
use Combust::Config ();

sub BAD_SERVER_THRESHOLD {-15}

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

sub validate {
    my $account = shift;
    my $errors  = {};
    for my $f (qw(name)) {
        $errors->{$f} = 'Required field' unless $account->$f and $account->$f =~ m/\S/;
    }

    if ($account->public_profile and !$account->url_slug) {
        my $base36 = Math::BaseCalc->new(digits => ['a' .. 'k', 'm' .. 'z', 2 .. 9]);
        my $url    = join "", map { $base36->to_base(irand) } (undef) x 2;
        $account->url_slug($url);
    }

    if (my $url = $account->url_slug) {
        if ($url =~ m{[^a-z0-9-_]}i) {
            $errors->{url_slug} =
              "Page URL can only contain basic letters, numbers, hypens and underscores";
        }

        # check uniqueness
    }

    $account->{_validation_errors} = $errors;

    %$errors ? 0 : 1;
}

sub validation_errors {
    my $self = shift;
    $self->{_validation_errors} || {};
}

sub can_edit {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if $user->privileges->support_staff;
    return 1 if grep { $_->id == $user->id } $self->users;
    return 0;
}

sub can_view {
    return shift->can_edit(shift);
}

sub live_subscriptions {
    my $self = shift;

    # todo: this should return a list instead to be more like ->account_subscriptions
    return [grep { $_->live_subscription } $self->account_subscriptions];
}

sub subscription_limits_not_exceeded {
    my $self = shift;
    my @args = @_;
    for my $sub (@{$self->live_subscriptions}) {
        return 1 if not $sub->limits_exceeded(@args);
    }
    return 0;
}

sub bad_servers {
    my $s = [grep { $_->score < BAD_SERVER_THRESHOLD } shift->servers];
    wantarray ? @$s : $s;
}

sub servers {
    my $self = shift;

    #local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;
    my $s = NP::Model->server->get_servers(
        query => [
            account_id => $self->id,
            or         => [
                deletion_on => undef,                       # not deleted
                deletion_on => {'gt' => DateTime->today}    # deleted in the future
            ],
        ],
    );
    $s = [
        sort {
            my $r  = 0;
            my $ia = Net::IP->new($a->ip);
            my $ib = Net::IP->new($b->ip);

            if (my $c = $ia->version <=> $ib->version) {
                return $c;
            }

            if ($ia->bincomp('lt', $ib)) {
                $r = -1;
            }
            elsif ($ia->bincomp('gt', $ib)) {
                $r = 1;
            }
            $r;
        } @$s
    ];
    wantarray ? @$s : $s;
}

package NP::Model::Account::Manager;
use strict;

sub accounts_to_notify {
    my $class = shift;
    my $ids   = NP::Model->dbh->selectcol_arrayref(
        qq[SELECT distinct a.id as account_id
           FROM
             servers s
             LEFT JOIN accounts a ON(s.account_id=a.id)
             LEFT JOIN server_alerts sa ON(sa.server_id=s.id)
           WHERE
             s.score_raw <= ?
              AND s.in_pool = 1
              AND (s.deletion_on IS NULL
                   OR s.deletion_on > DATE_ADD(NOW(), INTERVAL ? DAY)
                  )
              AND (sa.last_email_time IS NULL
                   OR (DATE_SUB(NOW(), INTERVAL 14 DAY) > sa.last_email_time
                       AND (sa.last_score+10) >= s.score_raw
                      )
                  )
          ORDER BY a.id
        ],
        undef,
        NP::Model::Account->BAD_SERVER_THRESHOLD,
        NP::Model::Zone->deletion_grace_days + 2,
    );
    return unless $ids and @$ids;

    warn "some server doesn't have an account" if grep { not defined $_ } @$ids;

    return $class->get_accounts(query => [id => $ids]);
}

1;
