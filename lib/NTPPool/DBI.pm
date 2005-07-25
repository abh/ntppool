package NTPPool::DBI;
use strict;
use base qw(Class::DBI::mysql);
use Combust::DB qw(db_open);

sub dbh { db_Main(@_) }

sub db_Main {
    my $dbh = db_open('ntppool', { shift->_default_attributes });
    $dbh;
}

1;
