#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
binmode(STDOUT, ":utf8");
use JSON::XS qw(decode_json);
# use File::Slurper qw(read_text);
use File::Find;
use Data::Dumper;

# ANSI color codes for output
my %colors = (
    reset  => "\033[0m",
    red    => "\033[31m",
    green  => "\033[32m",
    yellow => "\033[33m",
    blue   => "\033[34m",
    bold   => "\033[1m",
);

# Standard HTML files that should exist for each language
my @standard_html_files = (
    'homepage/intro.html',
    'join.html',
    'join/configuration.html',
    'tpl/server/graph_explanation.html',
    'use.html',
);

# Required msgids for .po files
my @required_msgids = (
    # Navigation & Core
    'go up', 'Translations',

    # Geographic Zones
    'Africa', 'Asia', 'North America', 'South America', 'Europe', 'Oceania', 'Global',
    'All Pool Servers',

    # Index Page
    'Introduction', 'Active Servers', 'Links', 'Terms of service',
    'Subscribe in a reader', 'Older news',

    # Forum & Community
    'archive', 'NTP Pool Forum', 'News site', 'Discussion list', 'Development',
    'forum_description', 'news_description', 'development_list_description',

    # Server Management
    'Back to the front page', 'Find', 'Stats for %1',
    'Not active in the pool, monitoring only', 'Zones:',
    'This server is <span class=\"deletion\">scheduled for deletion</span> on %1.',
    'Current score: %1 (only servers with a score higher than %2 are used in the pool)',
    'What do the graphs mean?', 'CSV log',

    # Navigation Sidebar
    'News', 'How do I <i>use</i> pool.ntp.org?', 'How do I <i>join</i> pool.ntp.org?',
    'Information for vendors', 'The mailing lists', 'Additional links', 'Can you translate?',
);

# Obsolete msgids that should be removed
my @obsolete_msgids = (
    'NTP Pool mailing lists',
    'subscribe',
    'Announcement list', 'Development list',
    'announcement_list_description', 'discussion_list_description',
    'irc_channel_description',
    'Discourse forum',
);

# Read file content
sub read_file {
    my ($file) = @_;
    open my $fh, '<:utf8', $file or die "Cannot open $file: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

# Load language list from JSON
sub load_languages {
    my $json_content = read_file('i18n/languages.json');
    utf8::encode($json_content) if utf8::is_utf8($json_content);
    my $languages = decode_json($json_content);
    return $languages;
}

# Read msgids from a .po file (handles multi-line entries)
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
        # Handle continuation lines for msgid
        elsif ($in_msgid && $line =~ /^"(.*)"$/) {
            $current_msgid .= $1;
        }
        # Handle msgstr or other lines - end msgid
        elsif ($line =~ /^msgstr/ || $line =~ /^(#.*|)$/) {
            if ($in_msgid && $current_msgid ne '') {
                $msgids{$current_msgid} = 1;
            }
            $current_msgid = '';
            $in_msgid = 0;
        }
    }
    close $fh;

    return %msgids;
}

# Check which HTML files exist for a language
sub check_html_files {
    my ($lang) = @_;
    my $base_dir = "docs/ntppool/$lang";
    my %files_exist;

    for my $file (@standard_html_files) {
        my $full_path = "$base_dir/$file";
        $files_exist{$file} = -f $full_path ? 1 : 0;
    }

    return %files_exist;
}

# Check for outdated hosting references in HTML files
sub check_hosting_refs {
    my ($lang) = @_;
    my $base_dir = "docs/ntppool/$lang";
    my @issues;

    # Check homepage/intro.html for hosting references
    my $intro_file = "$base_dir/homepage/intro.html";
    if (-f $intro_file) {
        my $content = read_file($intro_file);

        # Check for outdated references
        if ($content =~ /Packet(?!\s+Clearing\s+House)/i && $content !~ /Equinix\s+Metal/i) {
            push @issues, "Outdated: 'Packet' should be 'Equinix Metal'";
        }
        if ($content =~ /Develooper/i && $content !~ /Equinix|OSUOSL|Fastly/i) {
            push @issues, "Outdated: Missing modern hosting providers";
        }
        if ($content =~ /NetActuate/i && $content !~ /Equinix/i) {
            push @issues, "Outdated: 'NetActuate' should include 'Equinix'";
        }
    }

    return @issues;
}

# Main analysis function
sub analyze_language {
    my ($lang, $lang_info) = @_;
    my %report;

    $report{name} = $lang_info->{name};
    $report{testing} = $lang_info->{testing} ? 1 : 0;

    # Check .po file
    my $po_file = "i18n/$lang.po";
    if (-f $po_file) {
        my %msgids = read_msgids($po_file);
        my @missing_msgids;
        my @extra_msgids;

        # Check for missing required msgids
        for my $required (@required_msgids) {
            push @missing_msgids, $required unless exists $msgids{$required};
        }

        # Check for obsolete msgids
        for my $obsolete (@obsolete_msgids) {
            push @extra_msgids, $obsolete if exists $msgids{$obsolete};
        }

        $report{po_exists} = 1;
        $report{po_missing} = \@missing_msgids;
        $report{po_extra} = \@extra_msgids;
        $report{po_status} = scalar(@missing_msgids) == 0 && scalar(@extra_msgids) == 0 ? 'synced' : 'needs_update';
    } else {
        $report{po_exists} = 0;
        $report{po_status} = 'missing';
    }

    # Check HTML files
    my %html_files = check_html_files($lang);
    my $html_count = grep { $_ } values %html_files;

    $report{html_files} = \%html_files;
    $report{html_count} = $html_count;
    $report{html_status} = $html_count == 5 ? 'complete' : 'incomplete';

    # Check for hosting reference issues
    my @hosting_issues = check_hosting_refs($lang);
    $report{hosting_issues} = \@hosting_issues;

    return %report;
}

# Format report for a language
sub format_language_report {
    my ($lang, $report) = @_;
    my $output = "";

    # Header
    $output .= "\n$colors{bold}=== $lang - $report->{name} ===$colors{reset}\n";
    $output .= "Status: " . ($report->{testing} ? "$colors{yellow}Beta/Testing$colors{reset}" : "$colors{green}Production$colors{reset}") . "\n";

    # .po file status
    $output .= "\n$colors{bold}.po file:$colors{reset} ";
    if (!$report->{po_exists}) {
        $output .= "$colors{red}MISSING$colors{reset}\n";
    } else {
        if ($report->{po_status} eq 'synced') {
            $output .= "$colors{green}✓ Synced$colors{reset}\n";
        } else {
            $output .= "$colors{yellow}⚠ Needs update$colors{reset}\n";

            if (@{$report->{po_missing}}) {
                $output .= "  Missing msgids (" . scalar(@{$report->{po_missing}}) . "):\n";
                for my $msgid (@{$report->{po_missing}}) {
                    $output .= "    - $msgid\n";
                }
            }

            if (@{$report->{po_extra}}) {
                $output .= "  Obsolete msgids (" . scalar(@{$report->{po_extra}}) . "):\n";
                for my $msgid (@{$report->{po_extra}}) {
                    $output .= "    - $msgid\n";
                }
            }
        }
    }

    # HTML files status
    $output .= "\n$colors{bold}HTML files:$colors{reset} ";
    if ($report->{html_status} eq 'complete') {
        $output .= "$colors{green}✓ Complete (5/5)$colors{reset}\n";
    } else {
        $output .= "$colors{yellow}⚠ Incomplete ($report->{html_count}/5)$colors{reset}\n";
        $output .= "  Missing files:\n";
        for my $file (@standard_html_files) {
            if (!$report->{html_files}{$file}) {
                $output .= "    - $file\n";
            }
        }
    }

    # Hosting reference issues
    if (@{$report->{hosting_issues}}) {
        $output .= "\n$colors{bold}Hosting references:$colors{reset} $colors{yellow}⚠ Outdated$colors{reset}\n";
        for my $issue (@{$report->{hosting_issues}}) {
            $output .= "  - $issue\n";
        }
    }

    return $output;
}

# Generate summary statistics
sub generate_summary {
    my ($all_reports) = @_;
    my $output = "\n$colors{bold}========== TRANSLATION SUMMARY ==========$colors{reset}\n\n";

    my $total_langs = scalar(keys %$all_reports);
    my $production_langs = grep { !$all_reports->{$_}{testing} } keys %$all_reports;
    my $beta_langs = grep { $all_reports->{$_}{testing} } keys %$all_reports;

    my $po_synced = grep { $all_reports->{$_}{po_status} eq 'synced' } keys %$all_reports;
    my $po_missing = grep { !$all_reports->{$_}{po_exists} } keys %$all_reports;

    my $html_complete = grep { $all_reports->{$_}{html_status} eq 'complete' } keys %$all_reports;
    my $perfect_sync = grep {
        $all_reports->{$_}{po_status} eq 'synced' &&
        $all_reports->{$_}{html_status} eq 'complete' &&
        !@{$all_reports->{$_}{hosting_issues}}
    } keys %$all_reports;

    $output .= "Total languages: $total_langs\n";
    $output .= "Production: $production_langs | Beta: $beta_langs\n\n";

    $output .= ".po files:\n";
    $output .= "  - Synced: $po_synced\n";
    $output .= "  - Needs update: " . ($total_langs - $po_synced - $po_missing) . "\n";
    $output .= "  - Missing: $po_missing\n\n";

    $output .= "HTML files:\n";
    $output .= "  - Complete: $html_complete\n";
    $output .= "  - Incomplete: " . ($total_langs - $html_complete) . "\n\n";

    $output .= "Perfect sync (everything up to date): $perfect_sync\n";

    # List languages needing attention
    my @needs_attention;
    for my $lang (sort keys %$all_reports) {
        my $report = $all_reports->{$lang};
        if ($report->{po_status} ne 'synced' ||
            $report->{html_status} ne 'complete' ||
            @{$report->{hosting_issues}}) {
            push @needs_attention, $lang;
        }
    }

    if (@needs_attention) {
        $output .= "\n$colors{bold}Languages needing attention:$colors{reset}\n";
        for my $lang (@needs_attention) {
            $output .= "  - $lang ($all_reports->{$lang}{name})\n";
        }
    }

    return $output;
}

# Main execution
print "$colors{bold}NTP Pool Translation Analysis Tool$colors{reset}\n";
print "=" x 40 . "\n";

# Load languages
my $languages = load_languages();

# Add English to the analysis
$languages->{en} = { name => 'English' };

# Analyze all languages
my %all_reports;
for my $lang (sort keys %$languages) {
    my %report = analyze_language($lang, $languages->{$lang});
    $all_reports{$lang} = \%report;
}

# Generate summary first
print generate_summary(\%all_reports);

# Then detailed reports
print "\n$colors{bold}========== DETAILED REPORTS ==========$colors{reset}\n";

# Show languages with issues first
for my $lang (sort keys %all_reports) {
    my $report = $all_reports{$lang};
    if ($report->{po_status} ne 'synced' ||
        $report->{html_status} ne 'complete' ||
        @{$report->{hosting_issues}}) {
        print format_language_report($lang, $report);
    }
}

# Then show perfect languages
print "\n$colors{bold}========== LANGUAGES WITH PERFECT SYNC ==========$colors{reset}\n";
for my $lang (sort keys %all_reports) {
    my $report = $all_reports{$lang};
    if ($report->{po_status} eq 'synced' &&
        $report->{html_status} eq 'complete' &&
        !@{$report->{hosting_issues}}) {
        print "\n$colors{green}✓ $lang - $report->{name}$colors{reset}";
        print " (Beta)" if $report->{testing};
    }
}
print "\n";
