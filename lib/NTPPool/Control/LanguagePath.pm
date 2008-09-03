package NTPPool::Control::LanguagePath;
use strict;
use Combust::Constant qw(OK DECLINED);

my $lang_regexp = "(" . join( "|", keys %NTPPool::Control::valid_languages) . ")";
$lang_regexp = qr!^/$lang_regexp/!;

sub handler {
    my $r = shift;
    my $uri = $r->uri;
    if ($uri =~ s!$lang_regexp!/!) {
        my $lang = $1;
        $r->pnotes('lang', $lang);
        $r->uri($uri);
    }

    return DECLINED;
}

1;
