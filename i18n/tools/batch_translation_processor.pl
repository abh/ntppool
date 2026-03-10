#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
binmode(STDOUT, ":utf8");
use JSON::XS qw(decode_json);
use File::Find;
use File::Basename;
use File::Copy;
use Getopt::Long;
use Time::HiRes qw(time);

# ANSI color codes for output
my %colors = (
    reset  => "\033[0m",
    red    => "\033[31m",
    green  => "\033[32m",
    yellow => "\033[33m",
    blue   => "\033[34m",
    bold   => "\033[1m",
    cyan   => "\033[36m",
);

# Command line options
my $dry_run = 0;
my $backup = 1;
my $verbose = 0;
my $interactive = 0;
my @target_groups;
my @target_languages;
my $help = 0;
my $skip_analysis = 0;
my $git_commit = 0;
my $report_file = '';

GetOptions(
    'dry-run|n'         => \$dry_run,
    'no-backup'         => sub { $backup = 0 },
    'verbose|v'         => \$verbose,
    'interactive|i'     => \$interactive,
    'group|g=s'         => \@target_groups,
    'language|l=s'      => \@target_languages,
    'skip-analysis'     => \$skip_analysis,
    'git-commit'        => \$git_commit,
    'report=s'          => \$report_file,
    'help|h'            => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print_help();
    exit 0;
}

# Language groups for systematic processing
my %language_groups = (
    'nordic' => {
        name => 'Nordic Languages',
        languages => ['da', 'sv', 'nb', 'nn', 'fi'],
        description => 'Danish, Swedish, Norwegian (Bokmål & Nynorsk), Finnish'
    },
    'romance' => {
        name => 'Romance Languages',
        languages => ['es', 'fr', 'it', 'pt', 'ro'],
        description => 'Spanish, French, Italian, Portuguese, Romanian'
    },
    'germanic' => {
        name => 'Germanic Languages',
        languages => ['de', 'nl'],
        description => 'German, Dutch'
    },
    'slavic' => {
        name => 'Slavic Languages',
        languages => ['cs', 'pl', 'ru', 'uk', 'sr', 'bg'],
        description => 'Czech, Polish, Russian, Ukrainian, Serbian, Bulgarian'
    },
    'asian' => {
        name => 'Asian Languages',
        languages => ['ja', 'ko', 'zh', 'hi', 'vi'],
        description => 'Japanese, Korean, Chinese, Hindi, Vietnamese'
    },
    'middle_eastern' => {
        name => 'Middle Eastern Languages',
        languages => ['ar', 'fa', 'he', 'tr'],
        description => 'Arabic, Persian, Hebrew, Turkish'
    },
    'other' => {
        name => 'Other Languages',
        languages => ['el', 'hu', 'id', 'kk', 'eu', 'si', 'ca'],
        description => 'Greek, Hungarian, Indonesian, Kazakh, Basque, Sinhala, Catalan'
    },
    'production' => {
        name => 'Production Languages',
        languages => [],  # Will be populated from languages.json
        description => 'All languages marked as production-ready'
    },
    'testing' => {
        name => 'Testing/Beta Languages',
        languages => [],  # Will be populated from languages.json
        description => 'All languages marked as testing/beta'
    },
);

# Processing steps in order
my @processing_steps = (
    {
        name => 'HTML Issues Analysis',
        script => 'analyze_html_issues.pl',
        required => 1,
        skip_on_no_issues => 0,
    },
    {
        name => 'Content Consistency Validation',
        script => 'validate_content_consistency.pl',
        required => 1,
        skip_on_no_issues => 0,
    },
    {
        name => 'Encoding Validation',
        script => 'check_encoding.pl',
        required => 1,
        skip_on_no_issues => 0,
    },
    {
        name => 'HTML Modernization',
        script => 'fix_html_modernization.pl',
        required => 0,
        skip_on_no_issues => 1,
        backup_required => 1,
    },
    {
        name => 'Content Synchronization',
        script => 'sync_content_updates.pl',
        required => 0,
        skip_on_no_issues => 1,
        backup_required => 1,
    },
);

sub print_help {
    print <<EOF;
$colors{bold}NTP Pool Batch Translation Processor$colors{reset}

This tool orchestrates systematic translation maintenance across language groups:
- Analyzes translation issues across multiple languages
- Applies fixes in a coordinated manner
- Generates comprehensive reports
- Optionally creates git commits for changes

$colors{bold}Usage:$colors{reset}
  perl batch_translation_processor.pl [options]

$colors{bold}Options:$colors{reset}
  -n, --dry-run        Show what would be done without making changes
  --no-backup         Don't create backup files during fixes
  -v, --verbose       Show detailed progress information
  -i, --interactive   Ask for confirmation before major steps
  -g, --group GROUP   Process specific language group(s) (can be used multiple times)
  -l, --language LANG Specify individual language(s) (can be used multiple times)
  --skip-analysis     Skip analysis steps, go directly to fixes
  --git-commit        Create git commits for changes (per language group)
  --report FILE       Write detailed report to file
  -h, --help          Show this help message

$colors{bold}Language Groups:$colors{reset}
EOF

    for my $group (sort keys %language_groups) {
        my $info = $language_groups{$group};
        print sprintf("  %-15s %s\n", $group, $info->{description});
    }

    print <<EOF;

$colors{bold}Examples:$colors{reset}
  # Process Nordic languages with full analysis and fixes
  perl batch_translation_processor.pl -g nordic

  # Dry run for all production languages
  perl batch_translation_processor.pl -g production --dry-run

  # Interactive processing of specific languages
  perl batch_translation_processor.pl -l de -l fr -l es --interactive

  # Skip analysis and apply fixes to Romance languages
  perl batch_translation_processor.pl -g romance --skip-analysis

  # Full processing with git commits and detailed report
  perl batch_translation_processor.pl -g nordic --git-commit --report nordic_report.txt

$colors{bold}Processing Steps:$colors{reset}
  1. HTML Issues Analysis (identifies problems)
  2. Content Consistency Validation (checks against English source)
  3. Encoding Validation (UTF-8 and character checks)
  4. HTML Modernization (fixes deprecated tags, entities)
  5. Content Synchronization (updates hosting/technical references)

EOF
}

# Read file content
sub read_file {
    my ($file) = @_;
    open my $fh, '<:utf8', $file or die "Cannot open $file: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

# Load language list and populate dynamic groups
sub load_languages {
    my $json_content = read_file('i18n/languages.json');
    utf8::encode($json_content) if utf8::is_utf8($json_content);
    my $languages = decode_json($json_content);

    # Populate production and testing groups
    for my $lang (keys %$languages) {
        my $lang_info = $languages->{$lang};
        if ($lang_info->{testing}) {
            push @{$language_groups{testing}{languages}}, $lang;
        } else {
            push @{$language_groups{production}{languages}}, $lang;
        }
    }

    return $languages;
}

# Run a tool script and capture output
sub run_tool {
    my ($script, $args, $capture_output) = @_;
    my $script_path = "i18n/tools/$script";

    die "Tool script not found: $script_path\n" unless -f $script_path;

    my $cmd = "perl $script_path";
    $cmd .= " $args" if $args;

    print "Running: $cmd\n" if $verbose;

    if ($capture_output) {
        my $output = `$cmd 2>&1`;
        my $exit_code = $? >> 8;
        return ($exit_code, $output);
    } else {
        my $exit_code = system($cmd);
        $exit_code = $exit_code >> 8;
        return ($exit_code, '');
    }
}

# Analyze languages for issues
sub analyze_languages {
    my ($languages_ref) = @_;
    my @languages = @$languages_ref;
    my %analysis_results;

    print "\n$colors{bold}========== ANALYSIS PHASE ==========$colors{reset}\n";

    # Run each analysis tool
    for my $step (@processing_steps) {
        next unless $step->{name} =~ /Analysis|Validation/;

        print "\n$colors{cyan}Running $step->{name}...$colors{reset}\n";

        my ($exit_code, $output) = run_tool($step->{script}, '', 1);

        $analysis_results{$step->{name}} = {
            exit_code => $exit_code,
            output => $output,
            success => $exit_code == 0
        };

        if ($exit_code != 0) {
            print "$colors{red}ERROR: $step->{name} failed with exit code $exit_code$colors{reset}\n";
            if ($step->{required}) {
                die "Required analysis step failed, aborting.\n";
            }
        } else {
            print "$colors{green}✓ $step->{name} completed$colors{reset}\n";
        }
    }

    return %analysis_results;
}

# Apply fixes to languages
sub apply_fixes {
    my ($languages_ref, $analysis_results) = @_;
    my @languages = @$languages_ref;
    my %fix_results;

    print "\n$colors{bold}========== FIXING PHASE ==========$colors{reset}\n";

    # Build arguments for fix tools
    my $lang_args = join(' ', map { "-l $_" } @languages);
    my $base_args = $lang_args;
    $base_args .= " --dry-run" if $dry_run;
    $base_args .= " --no-backup" unless $backup;
    $base_args .= " --verbose" if $verbose;
    $base_args .= " --interactive" if $interactive;

    # Run fix tools
    for my $step (@processing_steps) {
        next if $step->{name} =~ /Analysis|Validation/;

        print "\n$colors{cyan}Running $step->{name}...$colors{reset}\n";

        # Skip if no issues found and step allows skipping
        if ($step->{skip_on_no_issues}) {
            # This is simplified - in practice would check analysis results
            print "Checking if fixes are needed...\n" if $verbose;
        }

        my ($exit_code, $output) = run_tool($step->{script}, $base_args, 1);

        $fix_results{$step->{name}} = {
            exit_code => $exit_code,
            output => $output,
            success => $exit_code == 0
        };

        if ($exit_code != 0) {
            print "$colors{red}ERROR: $step->{name} failed with exit code $exit_code$colors{reset}\n";
            if ($step->{required}) {
                die "Required fix step failed, aborting.\n";
            }
        } else {
            print "$colors{green}✓ $step->{name} completed$colors{reset}\n";
        }
    }

    return %fix_results;
}

# Create git commit for changes
sub create_git_commit {
    my ($group_name, $languages_ref) = @_;
    my @languages = @$languages_ref;

    return if $dry_run;

    print "\n$colors{cyan}Creating git commit for $group_name...$colors{reset}\n";

    # Check if there are any changes to commit
    my $status_output = `git status --porcelain 2>/dev/null`;
    chomp $status_output;

    unless ($status_output) {
        print "$colors{yellow}No changes to commit for $group_name$colors{reset}\n";
        return;
    }

    # Add translation files
    my @files_to_add;
    for my $lang (@languages) {
        push @files_to_add, "docs/ntppool/$lang/";
        push @files_to_add, "i18n/$lang.po" if -f "i18n/$lang.po";
    }

    for my $file (@files_to_add) {
        if (-e $file) {
            system("git add '$file'");
        }
    }

    # Create commit message
    my $commit_msg = "feat(i18n): update $group_name translations\n\n";
    $commit_msg .= "Automated translation maintenance for: " . join(", ", @languages) . "\n\n";
    $commit_msg .= "Changes include:\n";
    $commit_msg .= "- HTML modernization (deprecated tags, entities)\n";
    $commit_msg .= "- Content synchronization (hosting providers, technical refs)\n";
    $commit_msg .= "- Encoding and consistency fixes\n\n";
    $commit_msg .= "Generated by batch_translation_processor.pl";

    # Create commit
    my $commit_file = "/tmp/batch_commit_msg_$$.txt";
    open my $fh, '>:utf8', $commit_file or die "Cannot create commit message file: $!";
    print $fh $commit_msg;
    close $fh;

    my $exit_code = system("git commit -F '$commit_file'");
    unlink $commit_file;

    if ($exit_code == 0) {
        print "$colors{green}✓ Git commit created for $group_name$colors{reset}\n";
    } else {
        print "$colors{red}ERROR: Git commit failed for $group_name$colors{reset}\n";
    }
}

# Generate comprehensive report
sub generate_report {
    my ($groups_processed, $analysis_results, $fix_results) = @_;
    my $start_time = time;

    my $report = "$colors{bold}NTP Pool Batch Translation Processing Report$colors{reset}\n";
    $report .= "=" x 60 . "\n\n";
    $report .= "Generated: " . localtime() . "\n";
    $report .= "Processing mode: " . ($dry_run ? "DRY RUN" : "LIVE") . "\n\n";

    # Groups processed
    $report .= "$colors{bold}Groups Processed:$colors{reset}\n";
    for my $group_info (@$groups_processed) {
        $report .= "  - $group_info->{name}: " . join(", ", @{$group_info->{languages}}) . "\n";
    }
    $report .= "\n";

    # Analysis results
    if ($analysis_results && %$analysis_results) {
        $report .= "$colors{bold}Analysis Results:$colors{reset}\n";
        for my $step (keys %$analysis_results) {
            my $result = $analysis_results->{$step};
            my $status = $result->{success} ? "$colors{green}PASS$colors{reset}" : "$colors{red}FAIL$colors{reset}";
            $report .= "  - $step: $status\n";

            if (!$result->{success}) {
                $report .= "    Exit code: $result->{exit_code}\n";
            }
        }
        $report .= "\n";
    }

    # Fix results
    if ($fix_results && %$fix_results) {
        $report .= "$colors{bold}Fix Results:$colors{reset}\n";
        for my $step (keys %$fix_results) {
            my $result = $fix_results->{$step};
            my $status = $result->{success} ? "$colors{green}SUCCESS$colors{reset}" : "$colors{red}FAILED$colors{reset}";
            $report .= "  - $step: $status\n";

            if (!$result->{success}) {
                $report .= "    Exit code: $result->{exit_code}\n";
            }
        }
        $report .= "\n";
    }

    # Processing time
    my $end_time = time;
    my $duration = $end_time - $start_time;
    $report .= "Total processing time: " . sprintf("%.2f seconds", $duration) . "\n";

    return $report;
}

# Main execution
print "$colors{bold}NTP Pool Batch Translation Processor$colors{reset}\n";
print "=" x 60 . "\n";

if ($dry_run) {
    print "$colors{yellow}DRY RUN MODE - No files will be modified$colors{reset}\n\n";
}

# Change to repository root
my $script_dir = dirname(__FILE__);
chdir("$script_dir/../..") or die "Cannot change to repository root: $!";

# Load languages
my $languages = load_languages();

# Determine which languages to process
my @groups_to_process;
my @individual_languages;

if (@target_groups) {
    for my $group (@target_groups) {
        unless (exists $language_groups{$group}) {
            die "Unknown language group: $group\n";
        }
        push @groups_to_process, {
            name => $language_groups{$group}{name},
            group_id => $group,
            languages => $language_groups{$group}{languages}
        };
    }
}

if (@target_languages) {
    # Validate language codes
    for my $lang (@target_languages) {
        unless (exists $languages->{$lang}) {
            die "Unknown language code: $lang\n";
        }
    }
    @individual_languages = @target_languages;
}

# If no specific groups/languages specified, default to production
unless (@groups_to_process || @individual_languages) {
    push @groups_to_process, {
        name => $language_groups{production}{name},
        group_id => 'production',
        languages => $language_groups{production}{languages}
    };
}

# Add individual languages as a custom group
if (@individual_languages) {
    push @groups_to_process, {
        name => 'Custom Selection',
        group_id => 'custom',
        languages => \@individual_languages
    };
}

print "Processing groups:\n";
for my $group (@groups_to_process) {
    print "  - $group->{name}: " . join(", ", @{$group->{languages}}) . "\n";
}
print "\n";

# Confirm before proceeding if interactive
if ($interactive && !$dry_run) {
    print "Proceed with processing? [y/N]: ";
    my $response = <STDIN>;
    chomp $response;
    unless ($response =~ /^[yY]/) {
        print "Aborted by user.\n";
        exit 0;
    }
}

my $overall_start_time = time;
my (%all_analysis_results, %all_fix_results);

# Process each group
for my $group (@groups_to_process) {
    print "\n$colors{bold}========== PROCESSING $group->{name} ==========$colors{reset}\n";
    print "Languages: " . join(", ", @{$group->{languages}}) . "\n";

    my $group_start_time = time;

    # Analysis phase
    my %analysis_results;
    unless ($skip_analysis) {
        %analysis_results = analyze_languages($group->{languages});
        %all_analysis_results = (%all_analysis_results, %analysis_results);
    }

    # Fixing phase
    my %fix_results = apply_fixes($group->{languages}, \%analysis_results);
    %all_fix_results = (%all_fix_results, %fix_results);

    # Git commit if requested
    if ($git_commit) {
        create_git_commit($group->{name}, $group->{languages});
    }

    my $group_end_time = time;
    my $group_duration = $group_end_time - $group_start_time;
    print "\n$colors{green}✓ $group->{name} completed in " . sprintf("%.2f seconds", $group_duration) . "$colors{reset}\n";
}

# Generate final report
my $final_report = generate_report(\@groups_to_process, \%all_analysis_results, \%all_fix_results);
print "\n$final_report";

# Write report to file if requested
if ($report_file) {
    # Strip ANSI colors for file output
    my $file_report = $final_report;
    $file_report =~ s/\033\[[0-9;]*m//g;

    open my $fh, '>:utf8', $report_file or die "Cannot write report file: $!";
    print $fh $file_report;
    close $fh;

    print "\nReport written to: $report_file\n";
}

my $overall_end_time = time;
my $total_duration = $overall_end_time - $overall_start_time;

print "\n$colors{bold}Batch processing complete!$colors{reset}\n";
print "Total time: " . sprintf("%.2f seconds", $total_duration) . "\n";

unless ($dry_run) {
    print "Remember to review changes and test before deploying.\n";
}
