package NP::Version;
use strict;
use Sys::Hostname qw();
use List::Util ();

my $dir = $ENV{CBROOTLOCAL};

my $hostname = Sys::Hostname::hostname;
$hostname =~ s/\..*//;

my $startup_revision;
my $current_revision;

__PACKAGE__->refresh(1);

sub refresh {
    my ($class, $startup) = @_;

    my $new_revision;

    if (!$new_revision and open(my $fh, "$dir/REVISION")) {
        my $rev = <$fh>;
        $new_revision = ($rev =~ m/^(\S+)/)[0];
    }

    if ($startup) {
        $startup_revision = $new_revision;
    }

    $current_revision = $new_revision;

    $new_revision;
}

# OO to be Template Toolkit friendly
my $singleton;

sub new {
    return $singleton if $singleton;
    my $class = shift;
    $singleton = bless {}, $class;
}

sub startup_release {
    $startup_revision;
}

sub current_release {
    $current_revision;
}

sub hostname {
    $hostname;
}


sub installed_version {

    my $sha1_len = 8;
    my $git_desc =
      `git --git-dir=$ENV{CBROOTLOCAL}/.git describe --long --abbrev=$sha1_len 2>/dev/null`
      || substr(`git --git-dir=$ENV{CBROOTLOCAL}/.git rev-parse HEAD`, 0, $sha1_len);
    chomp($git_desc);

    # Determine if we are running on a modified installation
    my $git_status = `git --git-dir=$ENV{CBROOTLOCAL}/.git status 2>/dev/null`;
    $git_desc .= "-M" unless $git_status =~ /nothing to commit .working directory clean/;

    $git_desc;
}

1;
