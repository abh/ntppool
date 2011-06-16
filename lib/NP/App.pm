package NP::App;
use Moose;
use Plack::Builder;
extends 'Combust::App';
with 'Combust::App::ApacheRouters';
with 'Combust::Redirect';
use NP::Model;

require NTPPool::Control;

after 'init' => sub {
    my $self = shift;
};

my $lang_regexp = "(" . join( "|", keys %NTPPool::Control::valid_languages) . ")";
$lang_regexp = qr!^/$lang_regexp/!;

augment 'reference' => sub {
    my $self = shift;

    enable sub {
        my $app = shift;
        sub {
            my $env = shift;
            my $uri = $env->{PATH_INFO};
            if ($uri =~ s!$lang_regexp!/!) {
                my $lang = $1;
                $env->{'combust.notes'}->{lang} = $lang;
                $env->{PATH_INFO} = $uri;
            }
            my $res = $app->($env);
            return $res;
        };
    };
};

1;

