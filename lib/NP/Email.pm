package NP::Email;
use strict;
use 5.20.0;
use Email::Simple                  ();
use Email::Sender                  ();
use Email::Sender::Simple          ();
use Email::Date                    ();
use Email::Sender::Transport::SMTP ();
use Data::Dump qw(pp);
use Combust::Config;
use Sys::Hostname qw(hostname);
use JSON ();

my $config = Combust::Config->new;

my $deployment_mode = $config->site->{ntppool}->{deployment_mode}
  or die "deployment_mode not set for 'ntppool' site";

my $email_default = $config->site->{ntppool}->{email_default}
  or warn "email_default not set for 'ntppool' site";

sub address {
    my $label = shift;
    return $config->site->{ntppool}->{"email_$label"} || $email_default;
}

sub sendmail {
    my $email = shift;
    my $opts  = shift || {};

    if ($email->isa("Email::Stuffer")) { $email = $email->email }

    # for sparkpost
    my $msys = {options => {transactional => $JSON::true}};
    $email->header("X-MSYS-API", JSON->new->encode($msys));

    if (!$email->header('Message-ID')) {
        $email->header_set(
            'Message-ID' => '<' . join(".", int(rand(1000)), $$, time) . '@' . hostname . '>');
    }

    if (!$email->header('Date')) {
        $email->header_set("Date" => Email::Date::format_date());
    }

    my $sender = address("sender");

    my $send_options = {from => $sender};

    if ($deployment_mode eq 'devel') {
        $send_options->{to} = 'ask+devel-site@ntppool.org';
        say "development mode - printing email: ", $email->as_string;
        return;
    }

    warn "email to send ($deployment_mode)\n", $email->as_string(), "\n";

    # kubernetes relay service must be running on 'smtp' port 25
    my $smtp_service = $ENV{smtp_service} || 'smtp';
    my $transport    = Email::Sender::Transport::SMTP->new(
        {   host => $smtp_service,
            port => 25,
        }
    );
    $send_options->{transport} = $transport;

    Email::Sender::Simple->send($email, $send_options);

}

1;
