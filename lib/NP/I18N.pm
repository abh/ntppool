package NP::I18N;
use strict;
use warnings;

use base qw(Locale::Maketext);
use Locale::Maketext::Lexicon 0.68;

use Carp qw(cluck carp);

__PACKAGE__->init_class;

my $lh;

sub loc {
    unless ($_[0]) {
        cluck 'no key specified for translation';
        return "";
    }
    return $lh->maketext(@_);
}

sub loc_lang {
    $lh = __PACKAGE__->get_handle(@_);
    $lh->fail_with(\&lex_fail);

    return;
}

sub add_directory {
    my $directory = shift;

    my $pattern = File::Spec->catfile($directory, '*.[pm]o');

    Locale::Maketext::Lexicon->import({
        '*' => [ Gettext => $pattern ],
        _auto   => 1,
        _style  => 'gettext',
        _decode => 1,
    });

    return;
}

sub init_class {
    my $config = Combust->config;
    add_directory( $config->root_local . '/i18n' );
}

1;
