package NP::Util;
use strict;
use HTML::Entities qw(encode_entities);
use Exporter;

our @EXPORT_OK = qw(convert_to_html);

sub convert_to_html {
    my $str = shift;

    encode_entities($str, '<>&"');  # how can we encode everything without messing up UTF8?
    $str =~ s!(https?://.+?)(\s|$)!<a href="$1">$1</a>$2!g;
                             $str =~ s!\n\s*[\n\s]+!<br/><br/>!g;
                             $str =~ s!\n!<br/>\n!g;

                             $str;
}


1;
