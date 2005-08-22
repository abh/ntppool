package NTPPool::DBI;
use strict;
use base qw(Class::DBI::mysql);
use Combust::DB qw(db_open);
use Class::DBI::Plugin::AbstractCount;      # pager needs this
use Class::DBI::Plugin::Pager;

sub dbh { db_Main(@_) }

sub db_Main {
    my $dbh;
    if ( $ENV{'MOD_PERL'} and !$Apache::ServerStarting ) {
        $dbh = Apache->request()->pnotes('dbh');
    }
    
    unless ($dbh) {
        $dbh = db_open('ntppool', { shift->_default_attributes });
        unless ($dbh->{private_tz_set}) {
            $dbh->do(q[set time_zone = '+00:00']);
            $dbh->{private_tz_set} = 1;
        }
        __PACKAGE__->_remember_handle('Main');
    }
    if ( $ENV{'MOD_PERL'} and !$Apache::ServerStarting ) {
        Apache->request()->pnotes('dbh', $dbh);
    }
    $dbh;
}

1;
