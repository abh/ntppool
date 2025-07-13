#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use File::Basename;

# Translation sync checker for NTP Pool
# Usage: perl check_translations.pl [language_codes...]

my @target_languages = @ARGV ? @ARGV : qw(de da it es);
my $base_dir = dirname(__FILE__);
my $i18n_dir = "$base_dir/i18n";

print "=== NTP Pool Translation Sync Checker ===\n\n";

# Read English source file
my $en_file = "$i18n_dir/en.po";
my %en_msgids = read_msgids($en_file);
print "English source has " . scalar(keys %en_msgids) . " message IDs\n\n";

# Check each target language
for my $lang (@target_languages) {
    my $lang_file = "$i18n_dir/$lang.po";

    print "--- Checking $lang translation ---\n";

    unless (-f $lang_file) {
        print "ERROR: $lang_file not found!\n\n";
        next;
    }

    my %lang_msgids = read_msgids($lang_file);
    my %lang_msgstrs = read_msgstrs($lang_file);

    print "Language file has " . scalar(keys %lang_msgids) . " message IDs\n";

    # Find missing msgids
    my @missing_msgids;
    for my $msgid (keys %en_msgids) {
        unless (exists $lang_msgids{$msgid}) {
            push @missing_msgids, $msgid;
        }
    }

    # Find empty translations
    my @empty_translations;
    for my $msgid (keys %lang_msgids) {
        if (exists $lang_msgstrs{$msgid} && $lang_msgstrs{$msgid} eq '') {
            push @empty_translations, $msgid;
        }
    }

    # Find extra msgids (not in English)
    my @extra_msgids;
    for my $msgid (keys %lang_msgids) {
        unless (exists $en_msgids{$msgid}) {
            push @extra_msgids, $msgid;
        }
    }

    # Report findings
    if (@missing_msgids) {
        print "MISSING " . scalar(@missing_msgids) . " msgids:\n";
        for my $msgid (sort @missing_msgids) {
            print "  - $msgid\n";
        }
        print "\n";
    }

    if (@empty_translations) {
        print "EMPTY " . scalar(@empty_translations) . " translations:\n";
        for my $msgid (sort @empty_translations) {
            print "  - $msgid\n";
        }
        print "\n";
    }

    if (@extra_msgids) {
        print "EXTRA " . scalar(@extra_msgids) . " msgids (not in English):\n";
        for my $msgid (sort @extra_msgids) {
            print "  - $msgid\n";
        }
        print "\n";
    }

    unless (@missing_msgids || @empty_translations || @extra_msgids) {
        print "✓ Translation appears to be in sync with English\n\n";
    }
}

# Check for fuzzy translations
print "--- Checking for fuzzy translations ---\n";
for my $lang (@target_languages) {
    my $lang_file = "$i18n_dir/$lang.po";
    next unless -f $lang_file;

    my @fuzzy_lines = `grep -n "#, fuzzy" "$lang_file" 2>/dev/null`;
    if (@fuzzy_lines) {
        print "$lang has " . scalar(@fuzzy_lines) . " fuzzy translations:\n";
        for my $line (@fuzzy_lines) {
            chomp $line;
            print "  $line\n";
        }
        print "\n";
    }
}

print "=== Summary ===\n";
print "Checked languages: " . join(', ', @target_languages) . "\n";
print "Run with specific languages: perl check_translations.pl de es\n";

# Helper functions
sub read_msgids {
    my ($file) = @_;
    my %msgids;
    my $current_msgid = '';
    my $in_msgid = 0;

    open my $fh, '<:utf8', $file or die "Cannot open $file: $!";
    while (my $line = <$fh>) {
        chomp $line;

        # Handle msgid start
        if ($line =~ /^msgid\s+"(.+)"$/ || $line =~ /^msgid\s+""$/) {
            $current_msgid = $1 || '';
            $in_msgid = 1;
        }
        # Handle continuation lines for msgid (quoted strings)
        elsif ($in_msgid && $line =~ /^"(.*)"$/) {
            $current_msgid .= $1;
        }
        # Handle msgstr or other lines - end msgid
        elsif ($line =~ /^msgstr/ || $line =~ /^(#.*|)$/) {
            if ($in_msgid) {
                $msgids{$current_msgid} = 1 if $current_msgid ne '';
                $current_msgid = '';
                $in_msgid = 0;
            }
        }
    }

    # Don't forget the last msgid
    if ($in_msgid && $current_msgid ne '') {
        $msgids{$current_msgid} = 1;
    }

    close $fh;
    return %msgids;
}

sub read_msgstrs {
    my ($file) = @_;
    my %msgstrs;
    my $current_msgid = '';
    my $current_msgstr = '';
    my $in_msgstr = 0;

    open my $fh, '<:utf8', $file or die "Cannot open $file: $!";
    while (my $line = <$fh>) {
        chomp $line;

        # Handle msgid lines
        if ($line =~ /^msgid\s+"(.+)"$/ || $line =~ /^msgid\s+""$/) {
            # Save previous msgstr if we have one
            if ($current_msgid && $in_msgstr) {
                $msgstrs{$current_msgid} = $current_msgstr;
            }

            $current_msgid = $1 || '';
            $current_msgstr = '';
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
        # Handle empty lines or comments - end msgstr continuation
        elsif ($line =~ /^(#.*|)$/) {
            if ($current_msgid && $in_msgstr) {
                $msgstrs{$current_msgid} = $current_msgstr;
                $current_msgstr = '';
                $in_msgstr = 0;
            }
        }
    }

    # Don't forget the last entry
    if ($current_msgid && $in_msgstr) {
        $msgstrs{$current_msgid} = $current_msgstr;
    }

    close $fh;
    return %msgstrs;
}
