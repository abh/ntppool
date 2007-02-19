package Bundle::NP;

$VERSION = "1.00";

1;

__END__


=head1 NAME

Bundle::YP - Modules required to run the YPBot system

=head1 SYNOPSIS

    cd ~/src/ntppool/trunk
    sudo /pkg/bin/perl -MCPAN -I`pwd`/combust/misc/Bundle-Combust/lib \
         -I`pwd`/lib -e 'install "Bundle::NP"'

You should install Bundle::Combust first

=head1 CONTENTS

Params::Validate
DateTime::Locale
Class::Singleton
DateTime::TimeZone
DateTime
Clone
Class::Factory::Util
DateTime::Format::Strptime
DateTime::Format::Builder
DateTime::Format::MySQL
DateTime::Format::Pg
Test::Builder
Sub::Uplevel    # For Test::Exception
Test::Exception # For Object::Deadly
Devel::StackTrace
Devel::Symdump
Object::Deadly  # For Carp::Clan tests
Carp::Clan
Bit::Vector::Overload # For Carp::Clan

Sub::Install
Params::Util
Data::OptList
Sub::Exporter
SQL::ReservedWords

DBI
DBD::mysql

Rose::Object
Rose::DateTime
Time::Clock
Rose::DB
Clone::PP
Rose::DB::Object

HTML::Tree      # for HTML::Prototype
HTML::Prototype

Text::CSV_XS

JSON

Digest::SHA1
Math::BigInt
Class::ErrorHandler
Authen::Bitcard

Module::Pluggable
Return::Value
Email::Simple
Email::Address
Email::Send
Email::Abstract
Email::Date

Digest::HMAC_MD5
Net::IP
Net::DNS

DateTime::Format::Duration

Net::NTP

Geo::IP

Test::Pod
Locale::Object

Time::Duration




