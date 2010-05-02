#!/usr/bin/env perl

use 5.008001;

use strict;
use warnings;

# Son, when you participate in sporting events,
# it's not whether you win or lose, it's how drunk you get.
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'NTPPool',
    VERSION_FROM => 'lib/NTPPool.pm',
    AUTHOR       => 'Ask Bjørn Hansen <ask@develooper.com>',
    EXE_FILES => ['bin/*'],
    PREREQ_PM => { 
                  'Net::DNS' => 0.63,
                  'Data::Transformer' => 0,
                  'Net::NTP' => 0,
                  'namespace::clean' => 0,

                  'Rose::DB::Object' => 0,

                  'Locale::Maketext::Lexicon' => 0,
                  'Gearman::Client' => 0,
                  'Text::CSV_XS' => 0,
                  'Time::Duration' => 0,
                  'DateTime::Format::Duration' => 0,
                  'Email::Send' => 0,
                  'Email::Date' => 0,

                  'Imager' => 0,
                  'Geo::IP' => 0,

                  # should just be Net::IP ..
                  'Net::IPv6Addr' => 0,

    },
    test => {TESTS => 't/*.t t/*/*.t t/*/*/*.t'}
);

sub MY::postamble {
    return <<'MAKE_FRAG';

.PHONY: testcover

testcover:
	cover -delete
	HARNESS_PERL_SWITCHES=-MDevel::Cover \$(MAKE) test
	cover

MAKE_FRAG
}

