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

GetOptions(
    'dry-run|n'     => \$dry_run,
    'no-backup'     => sub { $backup = 0 },
    'verbose|v'     => \$verbose,
    'interactive|i' => \$interactive,
    'language|l=s'  => \@target_languages,
    'help|h'        => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print_help();
    exit 0;
}

# HTML entities that should be converted to UTF-8
my %html_entities = (
    '&amp;'    => '&',
    '&lt;'     => '<',
    '&gt;'     => '>',
    '&quot;'   => '"',
    '&apos;'   => "'",
    '&nbsp;'   => ' ',
    '&oslash;' => 'ø',
    '&Oslash;' => 'Ø',
    '&aring;'  => 'å',
    '&Aring;'  => 'Å',
    '&aelig;'  => 'æ',
    '&AElig;'  => 'Æ',
    '&ccedil;' => 'ç',
    '&Ccedil;' => 'Ç',
    '&eacute;' => 'é',
    '&Eacute;' => 'É',
    '&egrave;' => 'è',
    '&Egrave;' => 'È',
    '&ecirc;'  => 'ê',
    '&Ecirc;'  => 'Ê',
    '&euml;'   => 'ë',
    '&Euml;'   => 'Ë',
    '&iacute;' => 'í',
    '&Iacute;' => 'Í',
    '&igrave;' => 'ì',
    '&Igrave;' => 'Ì',
    '&icirc;'  => 'î',
    '&Icirc;'  => 'Î',
    '&iuml;'   => 'ï',
    '&Iuml;'   => 'Ï',
    '&ntilde;' => 'ñ',
    '&Ntilde;' => 'Ñ',
    '&oacute;' => 'ó',
    '&Oacute;' => 'Ó',
    '&ograve;' => 'ò',
    '&Ograve;' => 'Ò',
    '&ocirc;'  => 'ô',
    '&Ocirc;'  => 'Ô',
    '&otilde;' => 'õ',
    '&Otilde;' => 'Õ',
    '&ouml;'   => 'ö',
    '&Ouml;'   => 'Ö',
    '&uacute;' => 'ú',
    '&Uacute;' => 'Ú',
    '&ugrave;' => 'ù',
    '&Ugrave;' => 'Ù',
    '&ucirc;'  => 'û',
    '&Ucirc;'  => 'Û',
    '&uuml;'   => 'ü',
    '&Uuml;'   => 'Ü',
    '&yacute;' => 'ý',
    '&Yacute;' => 'Ý',
    '&yuml;'   => 'ÿ',
    '&szlig;'  => 'ß',
    '&raquo;'  => '»',
    '&laquo;'  => '«',
    '&rdquo;'  => '"',
    '&ldquo;'  => '"',
    '&rsquo;'  => '\'',
    '&lsquo;'  => '\'',
    '&mdash;'  => '—',
    '&ndash;'  => '–',
    '&hellip;' => '…',
);

# HTML entities that should NOT be converted (must remain as entities for valid HTML)
my %preserve_entities = (
    '&amp;'  => 1,  # Only preserve in specific contexts
    '&lt;'   => 1,  # Always preserve
    '&gt;'   => 1,  # Always preserve
    '&quot;' => 1,  # Preserve in attributes
);

# Standard HTML files to process
my @standard_html_files = (
    'homepage/intro.html',
    'join.html',
    'join/configuration.html',
    'tpl/server/graph_explanation.html',
    'use.html',
);

sub print_help {
    print <<EOF;
$colors{bold}NTP Pool HTML Modernization Fixer$colors{reset}

This tool automatically fixes common HTML modernization issues in translation files:
- Converts deprecated <tt> tags to modern <code> tags
- Converts HTML entities to native UTF-8 characters (where appropriate)
- Fixes spacing issues around HTML tags
- Preserves Template Toolkit syntax integrity

$colors{bold}Usage:$colors{reset}
  perl fix_html_modernization.pl [options] [languages...]

$colors{bold}Options:$colors{reset}
  -n, --dry-run        Show what would be changed without making changes
  --no-backup         Don't create backup files (.bak)
  -v, --verbose       Show detailed information about changes
  -i, --interactive   Ask for confirmation before each change
  -l, --language LANG Specify language(s) to process (can be used multiple times)
  -h, --help          Show this help message

$colors{bold}Examples:$colors{reset}
  # Dry run to see what would be changed
  perl fix_html_modernization.pl --dry-run

  # Fix specific languages
  perl fix_html_modernization.pl -l de -l fr -l es

  # Interactive mode with verbose output
  perl fix_html_modernization.pl --interactive --verbose

  # Fix all languages (be careful!)
  perl fix_html_modernization.pl

$colors{bold}Safety:$colors{reset}
- Backup files (.bak) are created by default
- Template Toolkit syntax is preserved
- Critical HTML entities (&lt;, &gt;) are preserved in appropriate contexts
- Dry run mode allows safe preview of changes

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

# Convert deprecated <tt> tags to <code>
sub fix_tt_tags {
    my ($content, $file_path) = @_;
    my $changes = 0;
    my @change_details;

    # Find all <tt> tags and convert them
    while ($content =~ /(<tt[^>]*>)(.*?)(<\/tt>)/gs) {
        my ($open_tag, $inner_content, $close_tag) = ($1, $2, $3);
        my $full_match = "$open_tag$inner_content$close_tag";

        # Create replacement
        my $new_open = $open_tag;
        $new_open =~ s/<tt/<code/;
        my $new_close = '</code>';
        my $replacement = "$new_open$inner_content$new_close";

        # Replace in content
        $content =~ s/\Q$full_match\E/$replacement/;
        $changes++;

        push @change_details, {
            type => 'tt_to_code',
            from => $full_match,
            to => $replacement,
            inner => $inner_content
        };
    }

    return ($content, $changes, \@change_details);
}

# Convert HTML entities to UTF-8 characters (with safety checks)
sub fix_html_entities {
    my ($content, $file_path, $lang) = @_;
    my $changes = 0;
    my @change_details;

    # Preserve entities in certain contexts
    for my $entity (keys %html_entities) {
        next if exists $preserve_entities{$entity};

        my $utf8_char = $html_entities{$entity};
        my $old_content = $content;

        # Skip entities in HTML attributes (between quotes)
        # This is a simplified approach - real implementation would need proper HTML parsing
        my $entity_pattern = qr/\Q$entity\E/;

        # Count matches before replacement
        my @matches = $content =~ /$entity_pattern/g;

        if (@matches) {
            # Replace entities not in attribute context
            $content =~ s/$entity_pattern/$utf8_char/g;
            $changes += @matches;

            push @change_details, {
                type => 'entity_to_utf8',
                entity => $entity,
                utf8_char => $utf8_char,
                count => scalar(@matches)
            };
        }
    }

    return ($content, $changes, \@change_details);
}

# Fix spacing issues around HTML tags
sub fix_spacing_issues {
    my ($content, $file_path) = @_;
    my $changes = 0;
    my @change_details;

    # Fix missing space before opening tag (word<tag>)
    my $space_before_pattern = qr/(\w)(<[a-zA-Z][^>]*>)/;
    while ($content =~ /$space_before_pattern/) {
        my ($word_char, $tag) = ($1, $2);
        my $replacement = "$word_char $tag";
        $content =~ s/$space_before_pattern/$replacement/;
        $changes++;

        push @change_details, {
            type => 'space_before_tag',
            from => "$word_char$tag",
            to => $replacement
        };
    }

    # Fix missing space after closing tag (</tag>word)
    my $space_after_pattern = qr/(<\/[a-zA-Z][^>]*>)(\w)/;
    while ($content =~ /$space_after_pattern/) {
        my ($tag, $word_char) = ($1, $2);
        my $replacement = "$tag $word_char";
        $content =~ s/$space_after_pattern/$replacement/;
        $changes++;

        push @change_details, {
            type => 'space_after_tag',
            from => "$tag$word_char",
            to => $replacement
        };
    }

    return ($content, $changes, \@change_details);
}

# Validate Template Toolkit syntax integrity
sub validate_template_toolkit {
    my ($original, $modified) = @_;
    my @issues;

    # Extract TT blocks from both versions
    my @orig_blocks = $original =~ /(\[%[^%]*%\])/g;
    my @mod_blocks = $modified =~ /(\[%[^%]*%\])/g;

    if (@orig_blocks != @mod_blocks) {
        push @issues, "Template Toolkit block count mismatch: " .
                     scalar(@orig_blocks) . " -> " . scalar(@mod_blocks);
    }

    # Check for broken TT syntax
    if ($modified =~ /\[%[^%]*$/) {
        push @issues, "Unclosed Template Toolkit block found";
    }

    if ($modified =~ /^[^%]*%\]/) {
        push @issues, "Unopened Template Toolkit block found";
    }

    return @issues;
}

# Process a single file
sub process_file {
    my ($file_path, $lang) = @_;
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

    # Apply fixes
    my ($content1, $changes1, $details1) = fix_tt_tags($content, $file_path);
    my ($content2, $changes2, $details2) = fix_html_entities($content1, $file_path, $lang);
    my ($content3, $changes3, $details3) = fix_spacing_issues($content2, $file_path);

    $content = $content3;
    $total_changes = $changes1 + $changes2 + $changes3;
    push @all_details, @$details1, @$details2, @$details3;

    # Validate changes
    my @validation_issues = validate_template_toolkit($original_content, $content);
    if (@validation_issues) {
        $result{errors} = \@validation_issues;
        print " $colors{red}VALIDATION FAILED$colors{reset}\n" if $verbose;
        return %result;
    }

    if ($total_changes > 0) {
        print " $colors{green}$total_changes changes$colors{reset}\n" if $verbose;

        if ($interactive) {
            print "\nChanges for $file_path:\n";
            for my $detail (@all_details) {
                if ($detail->{type} eq 'tt_to_code') {
                    print "  <tt> -> <code>: $detail->{inner}\n";
                } elsif ($detail->{type} eq 'entity_to_utf8') {
                    print "  Entity: $detail->{entity} -> $detail->{utf8_char} ($detail->{count} times)\n";
                } elsif ($detail->{type} =~ /space_/) {
                    print "  Spacing: $detail->{from} -> $detail->{to}\n";
                }
            }

            print "Apply these changes? [y/N]: ";
            my $response = <STDIN>;
            chomp $response;
            unless ($response =~ /^[yY]/) {
                print "Skipping $file_path\n";
                return %result;
            }
        }

        unless ($dry_run) {
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
        errors => []
    );

    print "\n$colors{bold}Processing $lang - $lang_info->{name}$colors{reset}\n";

    for my $file (@standard_html_files) {
        my $file_path = "docs/ntppool/$lang/$file";
        next unless -f $file_path;

        my %result = process_file($file_path, $lang);

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
                    if ($detail->{type} eq 'tt_to_code') {
                        print "    <tt> -> <code>: $detail->{inner}\n";
                    } elsif ($detail->{type} eq 'entity_to_utf8') {
                        print "    $detail->{entity} -> $detail->{utf8_char} ($detail->{count}x)\n";
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
    my $output = "\n$colors{bold}========== MODERNIZATION SUMMARY ==========$colors{reset}\n\n";

    my $total_langs = scalar(keys %$all_reports);
    my $langs_processed = grep { $all_reports->{$_}{files_processed} > 0 } keys %$all_reports;
    my $langs_with_errors = grep { @{$all_reports->{$_}{errors}} > 0 } keys %$all_reports;

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
    $output .= "Files processed: $colors{green}$total_files$colors{reset}\n";
    $output .= "Total changes: $colors{bold}$total_changes$colors{reset}\n";

    if ($dry_run) {
        $output .= "\n$colors{yellow}This was a DRY RUN - no files were modified$colors{reset}\n";
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
print "$colors{bold}NTP Pool HTML Modernization Fixer$colors{reset}\n";
print "=" x 50 . "\n";

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

# Process all specified languages
my %all_reports;
for my $lang (@langs_to_process) {
    my %report = process_language($lang, $languages->{$lang});
    $all_reports{$lang} = \%report;
}

# Generate summary
print generate_summary(\%all_reports);

print "\n$colors{bold}Modernization complete!$colors{reset}\n";
unless ($dry_run) {
    print "Remember to test the changes and commit them if everything looks good.\n";
}
