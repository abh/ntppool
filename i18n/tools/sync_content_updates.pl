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
my @target_languages;
my $help = 0;
my $update_hosting = 0;
my $update_technical = 0;
my $update_all = 0;

GetOptions(
    'dry-run|n'         => \$dry_run,
    'no-backup'         => sub { $backup = 0 },
    'verbose|v'         => \$verbose,
    'interactive|i'     => \$interactive,
    'language|l=s'      => \@target_languages,
    'hosting'           => \$update_hosting,
    'technical'         => \$update_technical,
    'all'               => \$update_all,
    'help|h'            => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print_help();
    exit 0;
}

if ($update_all) {
    $update_hosting = $update_technical = 1;
}

unless ($update_hosting || $update_technical) {
    $update_hosting = $update_technical = 1;  # Default to updating everything
}

# Expected hosting providers (extracted from English source)
my @expected_hosting_providers = (
    {
        name => 'Equinix',
        url => 'https://www.equinix.com/',
    },
    {
        name => 'Netactuate',
        url => 'https://www.netactuate.com/',
    },
);

# Outdated hosting providers that should be updated
my @outdated_hosting_patterns = (
    {
        pattern => qr/\bPacket\b(?!\s+Clearing\s+House)/i,
        replacement => 'Equinix',
        message => 'Packet → Equinix',
    },
    {
        pattern => qr/\bEquinix\s+Metal\b/i,
        replacement => 'Equinix',
        message => 'Equinix Metal → Equinix',
    },
    {
        pattern => qr/\bDevelooper\b/i,
        replacement => 'Equinix and Netactuate',
        message => 'Develooper → modern hosting providers',
    },
    {
        pattern => qr/\bNetActuate\b/i,  # Different capitalization
        replacement => 'Netactuate',
        message => 'NetActuate → Netactuate (correct capitalization)',
    },
    {
        pattern => qr/\bOSUOSL\b/i,
        replacement => 'Equinix and Netactuate',
        message => 'OSUOSL → modern hosting providers',
    },
    {
        pattern => qr/\bFastly\b/i,
        replacement => 'Equinix and Netactuate',
        message => 'Fastly → modern hosting providers',
    },
);

# Technical references that should be consistent
my %technical_updates = (
    'server_count' => {
        outdated_patterns => [
            qr/(?:use|more than|not more than)\s+(three|two)\s+(?:time\s*)?servers?/i,
        ],
        replacement_callback => sub {
            my ($match, $lang) = @_;
            $match =~ s/(three|two)/four/i;
            return $match;
        },
        message => 'Server count recommendation: three/two → four',
    },
    'pool_domains' => {
        # Ensure all four pool domains are mentioned
        validate_callback => sub {
            my ($content, $lang) = @_;
            my @found_domains = $content =~ /(\d+\.pool\.ntp\.org)/g;
            my @expected = ('0.pool.ntp.org', '1.pool.ntp.org', '2.pool.ntp.org', '3.pool.ntp.org');

            my %found = map { $_ => 1 } @found_domains;
            my @missing = grep { !exists $found{$_} } @expected;

            return @missing ? "Missing pool domains: " . join(", ", @missing) : undef;
        },
    },
);

sub print_help {
    print <<EOF;
$colors{bold}NTP Pool Content Synchronization Tool$colors{reset}

This tool synchronizes factual content updates from the English source to translations:
- Updates hosting provider references to current providers
- Fixes technical references (server counts, domains, etc.)
- Preserves translation text while updating factual content
- Handles language-specific adaptations

$colors{bold}Usage:$colors{reset}
  perl sync_content_updates.pl [options] [languages...]

$colors{bold}Options:$colors{reset}
  -n, --dry-run        Show what would be changed without making changes
  --no-backup         Don't create backup files (.bak)
  -v, --verbose       Show detailed information about changes
  -i, --interactive   Ask for confirmation before each change
  -l, --language LANG Specify language(s) to process (can be used multiple times)
  --hosting           Only update hosting provider references
  --technical         Only update technical references
  --all               Update all content types (default)
  -h, --help          Show this help message

$colors{bold}Examples:$colors{reset}
  # Dry run to see what would be changed
  perl sync_content_updates.pl --dry-run

  # Update hosting references only for specific languages
  perl sync_content_updates.pl --hosting -l de -l fr

  # Interactive update for all content
  perl sync_content_updates.pl --interactive --all

  # Update specific languages with verbose output
  perl sync_content_updates.pl -v -l es -l it -l pt

$colors{bold}Safety:$colors{reset}
- Always uses English source as authoritative reference
- Backup files (.bak) are created by default
- Preserves translation-specific text
- Validates changes before applying

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

# Write file content
sub write_file {
    my ($file, $content) = @_;
    open my $fh, '>:utf8', $file or die "Cannot write $file: $!";
    print $fh $content;
    close $fh;
}

# Load language list from JSON
sub load_languages {
    my $json_content = read_file('i18n/languages.json');
    utf8::encode($json_content) if utf8::is_utf8($json_content);
    my $languages = decode_json($json_content);
    return $languages;
}

# Create backup of file
sub create_backup {
    my ($file) = @_;
    my $backup_file = "$file.bak";
    copy($file, $backup_file) or die "Cannot create backup $backup_file: $!";
    return $backup_file;
}

# Get authoritative hosting information from English source
sub get_authoritative_hosting_info {
    my $en_intro = "docs/ntppool/en/homepage/intro.html";
    return {} unless -f $en_intro;

    my $content = read_file($en_intro);
    my %hosting_info;

    # Extract hosting paragraph
    if ($content =~ /(Hosting and bandwidth.*?<\/p>)/s) {
        my $hosting_section = $1;

        # Extract provider names and URLs
        my @providers;
        while ($hosting_section =~ /<a href="([^"]*)"[^>]*>([^<]+)<\/a>/g) {
            push @providers, {
                name => $2,
                url => $1,
            };
        }

        $hosting_info{providers} = \@providers;
        $hosting_info{full_text} = $hosting_section;

        # Extract the full sentence structure for reference
        if ($hosting_section =~ /(.*?)\s*<a href/s) {
            $hosting_info{prefix} = $1;
        }
        if ($hosting_section =~ /<\/a>\s*(.*)$/s) {
            $hosting_info{suffix} = $1;
        }
    }

    return %hosting_info;
}

# Update hosting provider references
sub update_hosting_references {
    my ($content, $lang, $file) = @_;
    my $changes = 0;
    my @change_details;

    return ($content, $changes, \@change_details) unless $file eq 'homepage/intro.html';

    my %auth_info = get_authoritative_hosting_info();
    return ($content, $changes, \@change_details) unless $auth_info{providers};

    # Update outdated provider references
    for my $update (@outdated_hosting_patterns) {
        my $pattern = $update->{pattern};
        my $replacement = $update->{replacement};

        if ($content =~ /$pattern/) {
            my $old_text = $&;
            $content =~ s/$pattern/$replacement/g;
            $changes++;

            push @change_details, {
                type => 'hosting_update',
                from => $old_text,
                to => $replacement,
                message => $update->{message}
            };
        }
    }

    # Ensure current providers are mentioned if hosting section exists
    if ($content =~ /hosting|bandwidth/i) {
        my $has_hosting_section = 0;
        my $missing_providers = [];

        for my $provider_info (@{$auth_info{providers}}) {
            my $provider = $provider_info->{name};
            if ($content =~ /\Q$provider\E/i) {
                $has_hosting_section = 1;
            } else {
                push @$missing_providers, $provider;
            }
        }

        if (@$missing_providers && $has_hosting_section) {
            push @change_details, {
                type => 'hosting_validation',
                message => "Warning: Missing hosting providers: " . join(", ", @$missing_providers),
                missing => $missing_providers
            };
        }
    }

    return ($content, $changes, \@change_details);
}

# Update technical references
sub update_technical_references {
    my ($content, $lang, $file) = @_;
    my $changes = 0;
    my @change_details;

    # Update server count recommendations
    if ($file eq 'use.html' && exists $technical_updates{server_count}) {
        my $update_info = $technical_updates{server_count};

        for my $pattern (@{$update_info->{outdated_patterns}}) {
            if ($content =~ /$pattern/) {
                my $old_match = $&;
                my $new_text = $update_info->{replacement_callback}->($old_match, $lang);

                $content =~ s/\Q$old_match\E/$new_text/;
                $changes++;

                push @change_details, {
                    type => 'technical_update',
                    subtype => 'server_count',
                    from => $old_match,
                    to => $new_text,
                    message => $update_info->{message}
                };
            }
        }
    }

    # Validate pool domains (warning only)
    if ($file eq 'use.html' && exists $technical_updates{pool_domains}) {
        my $update_info = $technical_updates{pool_domains};
        my $validation_result = $update_info->{validate_callback}->($content, $lang);

        if ($validation_result) {
            push @change_details, {
                type => 'technical_validation',
                subtype => 'pool_domains',
                message => $validation_result
            };
        }
    }

    return ($content, $changes, \@change_details);
}

# Update Windows instructions to modern format
sub update_windows_instructions {
    my ($content, $lang, $file) = @_;
    my $changes = 0;
    my @change_details;

    return ($content, $changes, \@change_details) unless $file eq 'use.html';

    # Check if content has outdated Windows instructions
    if ($content =~ /Control Panel/i && $content !~ /Win\+I|Settings/i) {
        # This is a complex update that would need careful language-specific handling
        # For now, just flag it for manual review
        push @change_details, {
            type => 'windows_validation',
            message => "Windows instructions may need updating to modern Settings app format"
        };
    }

    return ($content, $changes, \@change_details);
}

# Process a single file
sub process_file {
    my ($file_path, $lang, $file) = @_;
    my %result = (
        processed => 0,
        changes => 0,
        errors => [],
        details => []
    );

    return %result unless -f $file_path;

    print "Processing $file_path..." if $verbose;

    my $original_content = read_file($file_path);
    my $content = $original_content;
    my $total_changes = 0;
    my @all_details;

    # Apply updates based on options
    if ($update_hosting) {
        my ($content1, $changes1, $details1) = update_hosting_references($content, $lang, $file);
        $content = $content1;
        $total_changes += $changes1;
        push @all_details, @$details1;
    }

    if ($update_technical) {
        my ($content2, $changes2, $details2) = update_technical_references($content, $lang, $file);
        my ($content3, $changes3, $details3) = update_windows_instructions($content2, $lang, $file);

        $content = $content3;
        $total_changes += $changes2 + $changes3;
        push @all_details, @$details2, @$details3;
    }

    # Validate that Template Toolkit syntax is preserved
    my @orig_tt_blocks = $original_content =~ /(\[%[^%]*%\])/g;
    my @new_tt_blocks = $content =~ /(\[%[^%]*%\])/g;

    if (@orig_tt_blocks != @new_tt_blocks) {
        push @{$result{errors}}, "Template Toolkit block count changed: " .
                                scalar(@orig_tt_blocks) . " -> " . scalar(@new_tt_blocks);
        print " $colors{red}VALIDATION FAILED$colors{reset}\n" if $verbose;
        return %result;
    }

    if ($total_changes > 0 || @all_details) {
        print " $colors{green}$total_changes changes, " . scalar(@all_details) . " items$colors{reset}\n" if $verbose;

        if ($interactive) {
            print "\nChanges for $file_path:\n";
            for my $detail (@all_details) {
                if ($detail->{type} eq 'hosting_update') {
                    print "  Hosting: $detail->{message}\n";
                    print "    From: $detail->{from}\n";
                    print "    To: $detail->{to}\n";
                } elsif ($detail->{type} eq 'technical_update') {
                    print "  Technical: $detail->{message}\n";
                    print "    From: $detail->{from}\n";
                    print "    To: $detail->{to}\n";
                } elsif ($detail->{type} =~ /_validation$/) {
                    print "  Warning: $detail->{message}\n";
                }
            }

            if ($total_changes > 0) {
                print "Apply these changes? [y/N]: ";
                my $response = <STDIN>;
                chomp $response;
                unless ($response =~ /^[yY]/) {
                    print "Skipping $file_path\n";
                    return %result;
                }
            }
        }

        if ($total_changes > 0 && !$dry_run) {
            # Create backup
            if ($backup) {
                my $backup_file = create_backup($file_path);
                print "Created backup: $backup_file\n" if $verbose;
            }

            # Write modified content
            write_file($file_path, $content);
        }

        $result{processed} = 1;
        $result{changes} = $total_changes;
        $result{details} = \@all_details;
    } else {
        print " $colors{cyan}no changes needed$colors{reset}\n" if $verbose;
    }

    return %result;
}

# Process all files for a language
sub process_language {
    my ($lang, $lang_info) = @_;
    my %report = (
        name => $lang_info->{name},
        testing => $lang_info->{testing} ? 1 : 0,
        files_processed => 0,
        total_changes => 0,
        errors => [],
        warnings => []
    );

    print "\n$colors{bold}Processing $lang - $lang_info->{name}$colors{reset}\n";

    my @files_to_check = ('homepage/intro.html', 'use.html', 'join.html');

    for my $file (@files_to_check) {
        my $file_path = "docs/ntppool/$lang/$file";
        next unless -f $file_path;

        my %result = process_file($file_path, $lang, $file);

        if (@{$result{errors}}) {
            push @{$report{errors}}, {
                file => $file,
                errors => $result{errors}
            };
            print "$colors{red}ERROR in $file: " . join(", ", @{$result{errors}}) . "$colors{reset}\n";
        } elsif ($result{processed}) {
            $report{files_processed}++;
            $report{total_changes} += $result{changes};

            print "$colors{green}✓ $file: $result{changes} changes$colors{reset}\n";

            if ($verbose && $result{details}) {
                for my $detail (@{$result{details}}) {
                    if ($detail->{type} eq 'hosting_update') {
                        print "    Hosting: $detail->{message}\n";
                    } elsif ($detail->{type} eq 'technical_update') {
                        print "    Technical: $detail->{message}\n";
                    } elsif ($detail->{type} =~ /_validation$/) {
                        print "    Warning: $detail->{message}\n";
                        push @{$report{warnings}}, "$file: $detail->{message}";
                    }
                }
            }
        }
    }

    return %report;
}

# Generate summary report
sub generate_summary {
    my ($all_reports) = @_;
    my $output = "\n$colors{bold}========== CONTENT SYNC SUMMARY ==========$colors{reset}\n\n";

    my $total_langs = scalar(keys %$all_reports);
    my $langs_processed = grep { $all_reports->{$_}{files_processed} > 0 } keys %$all_reports;
    my $langs_with_errors = grep { @{$all_reports->{$_}{errors}} > 0 } keys %$all_reports;
    my $langs_with_warnings = grep { @{$all_reports->{$_}{warnings}} > 0 } keys %$all_reports;

    my $total_files = 0;
    my $total_changes = 0;

    for my $lang (keys %$all_reports) {
        my $report = $all_reports->{$lang};
        $total_files += $report->{files_processed};
        $total_changes += $report->{total_changes};
    }

    $output .= "Languages analyzed: $total_langs\n";
    $output .= "Languages with changes: $colors{green}$langs_processed$colors{reset}\n";
    $output .= "Languages with errors: $colors{red}$langs_with_errors$colors{reset}\n";
    $output .= "Languages with warnings: $colors{yellow}$langs_with_warnings$colors{reset}\n";
    $output .= "Files processed: $colors{green}$total_files$colors{reset}\n";
    $output .= "Total changes: $colors{bold}$total_changes$colors{reset}\n";

    $output .= "\nUpdate types processed:\n";
    $output .= "  - Hosting providers: " . ($update_hosting ? "$colors{green}Yes$colors{reset}" : "$colors{yellow}No$colors{reset}") . "\n";
    $output .= "  - Technical references: " . ($update_technical ? "$colors{green}Yes$colors{reset}" : "$colors{yellow}No$colors{reset}") . "\n";

    if ($dry_run) {
        $output .= "\n$colors{yellow}This was a DRY RUN - no files were modified$colors{reset}\n";
    }

    if ($langs_with_warnings > 0) {
        $output .= "\n$colors{bold}Warnings (manual review recommended):$colors{reset}\n";
        for my $lang (sort keys %$all_reports) {
            my $report = $all_reports->{$lang};
            next unless @{$report->{warnings}};

            $output .= "  $lang:\n";
            for my $warning (@{$report->{warnings}}) {
                $output .= "    $warning\n";
            }
        }
    }

    if ($langs_with_errors > 0) {
        $output .= "\n$colors{bold}Errors encountered:$colors{reset}\n";
        for my $lang (sort keys %$all_reports) {
            my $report = $all_reports->{$lang};
            next unless @{$report->{errors}};

            $output .= "  $lang:\n";
            for my $error (@{$report->{errors}}) {
                $output .= "    $error->{file}: " . join(", ", @{$error->{errors}}) . "\n";
            }
        }
    }

    return $output;
}

# Main execution
print "$colors{bold}NTP Pool Content Synchronization Tool$colors{reset}\n";
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
my @langs_to_process;
if (@target_languages) {
    @langs_to_process = @target_languages;
    # Validate language codes
    for my $lang (@langs_to_process) {
        unless (exists $languages->{$lang}) {
            die "Unknown language code: $lang\n";
        }
    }
} else {
    @langs_to_process = sort keys %$languages;
}

print "Processing languages: " . join(", ", @langs_to_process) . "\n";
print "Update types: ";
print "hosting " if $update_hosting;
print "technical " if $update_technical;
print "\n";

# Process all specified languages
my %all_reports;
for my $lang (@langs_to_process) {
    next if $lang eq 'en';  # Skip English as it's the authoritative source

    my %report = process_language($lang, $languages->{$lang});
    $all_reports{$lang} = \%report;
}

# Generate summary
print generate_summary(\%all_reports);

print "\n$colors{bold}Content synchronization complete!$colors{reset}\n";
unless ($dry_run) {
    print "Remember to test the changes and commit them if everything looks good.\n";
}
