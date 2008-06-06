package NP::I18N;
use strict;
use warnings;

use base qw(Locale::Maketext);
use Locale::Maketext::Lexicon;

my $lh;

sub loc {
    return $lh->maketext(@_);
}

sub loc_lang { 
    $lh = __PACKAGE__->get_handle(@_);

    return;
}

sub add_directory {
    my $directory = shift;

    my $pattern = File::Spec->catfile($directory, '*.[pm]o');

    Locale::Maketext::Lexicon->import({
        '*' => [ Gettext => $pattern ],
        _auto   => 1,
        _style  => 'gettext',
        _decode => 0,
    });

    return;
}

1;
