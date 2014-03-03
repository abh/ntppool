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
                  'namespace::clean' => 0.20,

                  'Moose' => 2,
                  'namespace::clean' => 0,
                  'namespace::autoclean' => 0,

                  'DBD::mysql' => 4.016,
                  'Rose::DB::Object' => 0,

                  'Locale::Maketext::Lexicon' => 0.84,

                  # Locale::Object needs DBD::SQLite
                  'DBD::SQLite'    => 0,
                  'Locale::Object' => 0,

                  'Gearman::Client' => 0,
                  'Text::CSV_XS' => 0,
                  'Time::Duration' => 0,
                  'Template::Plugin::Time::Duration' => 0,
                  'DateTime::Format::Duration' => 0,
                  'Email::Send' => 0,
                  'Email::Date' => 0,

                  'Geo::IP' => 1.39,

                  'Router::Simple' => 0,
                  'Plack' => 0,
                  'Plack::Middleware::Options' => 0,
                  'Plack::Middleware::ReverseProxy' => 0,
                  'Config::General' => 0,

                  'Math::Random::Secure' => 0,
                  'Math::BaseCalc'  => 0,

                  'I18N::LangTags' => 0,

                  'Net::IP' => 0,

                  'Socket6' => 0,
                  'IO::Socket::INET6' => 0,

		  'JSON::XS' => 2,

                 # For deployment scripts
                  'File::Find::Rule'  => 0,

    },
    test => {TESTS => 't/*.t t/*/*.t t/*/*/*.t'}
);

sub MY::postamble {
    return <<'MAKE_FRAG';

.PHONY: testcover

HULK ?= ./node_modules/hogan.js/bin/hulk

templates:
	($(HULK) docs/manage/tpl/client/*.html > docs/shared/static/js/admin-templates.js)

testcover:
	cover -delete
	HARNESS_PERL_SWITCHES=-MDevel::Cover $(MAKE) test
	cover

MAKE_FRAG
}

