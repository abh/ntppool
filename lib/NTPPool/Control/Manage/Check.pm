package NTPPool::Control::Manage::Check;
use v5.30.0;
use warnings;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use NP::NTP;
use Combust::Constant qw(OK NOT_FOUND FORBIDDEN);
use JSON              ();

my $json = JSON::XS->new->pretty->utf8->convert_blessed;

sub manage_dispatch {
    my $self = shift;
    $self->set_span_name("manage.check");

    if ($self->request->method eq 'post') {
        return 403 unless $self->check_auth_token;
    }

    if ($self->request->uri ne '/manage/check') {
        return NOT_FOUND;
    }

    if ($self->request->method eq 'post') {
        return $self->render_check();

    }

    return $self->render_form;

}

sub render_check {
    my $self = shift;

    my $ip_param = $self->req_param('ip');
    unless ($ip_param) {
        return $self->render_form;
    }

    $ip_param =~ s/\s+//;

    my $ip = Net::IP->new($ip_param);

    unless ($ip) {
        $self->tpl_param('errors' => {ip => 'not a valid IP address'});
        $self->tpl_param('ip'     => $ip_param);
        return $self->render_form;
    }
    $ip = $ip->short;
    $self->tpl_param('ip' => $ip);

    my @ntp = NP::NTP::info($ip);

    @ntp = sort {
        if (!$a->{error} and !$b->{error}) {
            return ($a->{NTP}->{RTT} || 0) <=> ($b->{NTP}->{RTT} || 0);
        }
        if ($a->{error} and $b->{error}) {
            return $a->{Server} cmp $b->{Server};
        }
        if ($a->{error}) {
            return 1;
        }
        return -1;
    } @ntp;

    $self->tpl_param('results', \@ntp);

    return OK, $self->evaluate_template('tpl/check/results.html');
}

sub render_form {
    my $self = shift;
    return OK, $self->evaluate_template('tpl/check/form.html');
}

1;
