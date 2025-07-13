#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use File::Basename;

# Translation sync tool for NTP Pool
# Usage: perl sync_translations.pl <language_code>

my $lang = shift @ARGV or die "Usage: perl sync_translations.pl <language_code>\n";

my $base_dir = dirname(__FILE__);
my $i18n_dir = "$base_dir/i18n";
my $en_file = "$i18n_dir/en.po";
my $lang_file = "$i18n_dir/$lang.po";

die "English source file not found: $en_file\n" unless -f $en_file;
die "Language file not found: $lang_file\n" unless -f $lang_file;

print "=== Syncing $lang translation with English source ===\n\n";

# Read English msgids and their context
my %en_entries = read_po_entries($en_file);
my %lang_entries = read_po_entries($lang_file);

print "English has " . scalar(keys %en_entries) . " entries\n";
print "Language file has " . scalar(keys %lang_entries) . " entries\n\n";

# Find missing entries
my @missing_entries;
for my $msgid (keys %en_entries) {
    unless (exists $lang_entries{$msgid}) {
        push @missing_entries, $msgid;
    }
}

if (@missing_entries) {
    print "Found " . scalar(@missing_entries) . " missing entries:\n";
    for my $msgid (@missing_entries) {
        print "  - '$msgid'\n";
    }
    print "\n";

    print "To add these entries to $lang.po, append the following:\n";
    print "=" x 50 . "\n";

    for my $msgid (@missing_entries) {
        my $entry = $en_entries{$msgid};
        print "\n";
        print $entry->{comments} if $entry->{comments};
        print "msgid \"$msgid\"\n";
        print "msgstr \"\"\n";
    }

    print "=" x 50 . "\n";
} else {
    print "✓ No missing entries found\n";
}

# Find entries that need translation
my @untranslated;
for my $msgid (keys %lang_entries) {
    my $entry = $lang_entries{$msgid};
    if ($entry->{msgstr} eq '' && $msgid ne '') {
        push @untranslated, $msgid;
    }
}

if (@untranslated) {
    print "\nFound " . scalar(@untranslated) . " untranslated entries:\n";
    for my $msgid (@untranslated) {
        print "  - '$msgid'\n";
    }
}

sub read_po_entries {
    my ($file) = @_;
    my %entries;
    my $current_msgid = '';
    my $current_msgstr = '';
    my $current_comments = '';
    my $in_msgstr = 0;

    open my $fh, '<:utf8', $file or die "Cannot open $file: $!";
    while (my $line = <$fh>) {
        chomp $line;

        # Handle comments
        if ($line =~ /^#/) {
            $current_comments .= "$line\n";
        }
        # Handle msgid lines
        elsif ($line =~ /^msgid\s+"(.+)"$/ || $line =~ /^msgid\s+""$/) {
            # Save previous entry if we have one
            if ($current_msgid && $in_msgstr) {
                $entries{$current_msgid} = {
                    msgstr => $current_msgstr,
                    comments => $current_comments
                };
            }

            $current_msgid = $1 || '';
            $current_msgstr = '';
            $current_comments = '';
            $in_msgstr = 0;
        }
        # Handle msgstr start
        elsif ($line =~ /^msgstr\s+"(.*)"$/) {
            $current_msgstr = $1 || '';
            $in_msgstr = 1;
        }
        # Handle continuation lines (quoted strings)
        elsif ($in_msgstr && $line =~ /^"(.*)"$/) {
            $current_msgstr .= $1;
        }
        # Handle empty lines - end current entry
        elsif ($line eq '') {
            if ($current_msgid && $in_msgstr) {
                $entries{$current_msgid} = {
                    msgstr => $current_msgstr,
                    comments => $current_comments
                };
                $current_msgid = '';
                $current_msgstr = '';
                $current_comments = '';
                $in_msgstr = 0;
            }
        }
    }

    # Don't forget the last entry
    if ($current_msgid && $in_msgstr) {
        $entries{$current_msgid} = {
            msgstr => $current_msgstr,
            comments => $current_comments
        };
    }

    close $fh;
    return %entries;
}
