#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
binmode(STDOUT, ":utf8");
use JSON::XS qw(decode_json);
use File::Find;
use File::Basename;

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

# Standard HTML files that should exist for each language
my @standard_html_files = (
    'homepage/intro.html',
    'join.html',
    'join/configuration.html',
    'tpl/server/graph_explanation.html',
    'use.html',
);

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

# Analyze a single HTML file for issues
sub analyze_html_file {
    my ($file_path, $lang) = @_;
    my %issues;

    return %issues unless -f $file_path;

    my $content = read_file($file_path);
    my @lines = split /\n/, $content;

    # Check for deprecated <tt> tags
    my @tt_tags;
    for my $i (0..$#lines) {
        my $line_num = $i + 1;
        my $line = $lines[$i];
        if ($line =~ /<tt[^>]*>/) {
            push @tt_tags, {
                line => $line_num,
                content => $line,
                match => $&
            };
        }
    }
    $issues{tt_tags} = \@tt_tags if @tt_tags;

    # Check for HTML entities that should be UTF-8
    my @html_entities_found;
    for my $i (0..$#lines) {
        my $line_num = $i + 1;
        my $line = $lines[$i];
        for my $entity (keys %html_entities) {
            if ($line =~ /\Q$entity\E/) {
                push @html_entities_found, {
                    line => $line_num,
                    content => $line,
                    entity => $entity,
                    replacement => $html_entities{$entity}
                };
            }
        }
    }
    $issues{html_entities} = \@html_entities_found if @html_entities_found;

    # Check for spacing issues around HTML tags
    my @spacing_issues;
    for my $i (0..$#lines) {
        my $line_num = $i + 1;
        my $line = $lines[$i];

        # Missing space before opening tag (word<tag>)
        if ($line =~ /\w<[a-zA-Z]/) {
            push @spacing_issues, {
                line => $line_num,
                content => $line,
                issue => "Missing space before opening tag",
                match => $&
            };
        }

        # Missing space after closing tag (</tag>word)
        if ($line =~ /<\/[a-zA-Z][^>]*>\w/) {
            push @spacing_issues, {
                line => $line_num,
                content => $line,
                issue => "Missing space after closing tag",
                match => $&
            };
        }
    }
    $issues{spacing_issues} = \@spacing_issues if @spacing_issues;

    # Check for broken HTML (basic validation)
    my @broken_html;
    for my $i (0..$#lines) {
        my $line_num = $i + 1;
        my $line = $lines[$i];

        # Unclosed opening tags (simple heuristic)
        if ($line =~ /<a\s[^>]*[^>\/]$/) {
            push @broken_html, {
                line => $line_num,
                content => $line,
                issue => "Potentially unclosed <a> tag"
            };
        }

        # Malformed href attributes
        if ($line =~ /<a\s[^>]*href="[^"]*[^"]$/) {
            push @broken_html, {
                line => $line_num,
                content => $line,
                issue => "Unclosed href attribute"
            };
        }

        # Missing closing angle bracket
        if ($line =~ /<[a-zA-Z][^<>]*$/ && $line !~ /<[a-zA-Z][^<>]*\/$/) {
            push @broken_html, {
                line => $line_num,
                content => $line,
                issue => "Missing closing angle bracket"
            };
        }
    }
    $issues{broken_html} = \@broken_html if @broken_html;

    # Check for Template Toolkit syntax issues
    my @tt_syntax_issues;
    for my $i (0..$#lines) {
        my $line_num = $i + 1;
        my $line = $lines[$i];

        # Unclosed TT blocks
        if ($line =~ /\[%\s*(?!.*%\])/) {
            push @tt_syntax_issues, {
                line => $line_num,
                content => $line,
                issue => "Unclosed Template Toolkit block"
            };
        }

        # Malformed TT syntax
        if ($line =~ /\[%[^%]*$/) {
            push @tt_syntax_issues, {
                line => $line_num,
                content => $line,
                issue => "Incomplete Template Toolkit syntax"
            };
        }
    }
    $issues{tt_syntax_issues} = \@tt_syntax_issues if @tt_syntax_issues;

    return %issues;
}

# Compare content structure with English source
sub compare_with_english {
    my ($lang, $file) = @_;
    my %comparison;

    my $lang_file = "docs/ntppool/$lang/$file";
    my $en_file = "docs/ntppool/en/$file";

    return %comparison unless -f $lang_file && -f $en_file;

    my $lang_content = read_file($lang_file);
    my $en_content = read_file($en_file);

    # Compare Template Toolkit blocks
    my @lang_tt_blocks = $lang_content =~ /\[%[^%]*%\]/g;
    my @en_tt_blocks = $en_content =~ /\[%[^%]*%\]/g;

    if (@lang_tt_blocks != @en_tt_blocks) {
        $comparison{tt_block_count_mismatch} = {
            lang_count => scalar(@lang_tt_blocks),
            en_count => scalar(@en_tt_blocks)
        };
    }

    # Compare major HTML sections
    my @lang_h3_headers = $lang_content =~ /<h3[^>]*>([^<]*)<\/h3>/g;
    my @en_h3_headers = $en_content =~ /<h3[^>]*>([^<]*)<\/h3>/g;

    if (@lang_h3_headers != @en_h3_headers) {
        $comparison{h3_count_mismatch} = {
            lang_count => scalar(@lang_h3_headers),
            en_count => scalar(@en_h3_headers),
            lang_headers => \@lang_h3_headers,
            en_headers => \@en_h3_headers
        };
    }

    return %comparison;
}

# Check hosting provider references
sub check_hosting_refs {
    my ($lang) = @_;
    my @issues;

    my $intro_file = "docs/ntppool/$lang/homepage/intro.html";
    return @issues unless -f $intro_file;

    my $content = read_file($intro_file);

    # Get authoritative English version
    my $en_content = read_file("docs/ntppool/en/homepage/intro.html");
    my ($en_hosting) = $en_content =~ /(Hosting and bandwidth.*?<\/p>)/s;

    if ($en_hosting) {
        # Extract current providers from English
        my @en_providers;
        while ($en_hosting =~ /<a href="[^"]*">([^<]+)<\/a>/g) {
            push @en_providers, $1;
        }

        # Check if translation has outdated references
        if ($content =~ /Packet(?!\s+Clearing\s+House)/i && $content !~ /Equinix/i) {
            push @issues, "Outdated: 'Packet' should be updated to current providers: " . join(", ", @en_providers);
        }

        if ($content =~ /Develooper/i && $content !~ /Equinix|Netactuate/i) {
            push @issues, "Outdated: 'Develooper' should be updated to current providers: " . join(", ", @en_providers);
        }

        # Check if translation is missing modern providers
        my $has_modern_providers = 0;
        for my $provider (@en_providers) {
            if ($content =~ /\Q$provider\E/i) {
                $has_modern_providers = 1;
                last;
            }
        }

        unless ($has_modern_providers) {
            push @issues, "Missing current hosting providers. English has: " . join(", ", @en_providers);
        }
    }

    return @issues;
}

# Format issues report for a file
sub format_file_report {
    my ($file, $lang, $issues, $comparison) = @_;
    my $output = "";

    my $total_issues = 0;
    for my $type (keys %$issues) {
        $total_issues += scalar(@{$issues->{$type}});
    }
    for my $type (keys %$comparison) {
        $total_issues++;
    }

    return "" unless $total_issues > 0;

    $output .= "\n  $colors{bold}$file$colors{reset}";
    if ($total_issues > 0) {
        $output .= " $colors{yellow}($total_issues issues)$colors{reset}";
    }
    $output .= "\n";

    # Deprecated <tt> tags
    if ($issues->{tt_tags}) {
        $output .= "    $colors{red}Deprecated <tt> tags:$colors{reset} " . scalar(@{$issues->{tt_tags}}) . "\n";
        for my $issue (@{$issues->{tt_tags}}) {
            $output .= "      Line $issue->{line}: $issue->{match}\n";
        }
    }

    # HTML entities
    if ($issues->{html_entities}) {
        $output .= "    $colors{yellow}HTML entities to convert:$colors{reset} " . scalar(@{$issues->{html_entities}}) . "\n";
        my %entity_counts;
        for my $issue (@{$issues->{html_entities}}) {
            $entity_counts{$issue->{entity}}++;
        }
        for my $entity (sort keys %entity_counts) {
            $output .= "      $entity → $html_entities{$entity} ($entity_counts{$entity} occurrences)\n";
        }
    }

    # Spacing issues
    if ($issues->{spacing_issues}) {
        $output .= "    $colors{cyan}Spacing issues:$colors{reset} " . scalar(@{$issues->{spacing_issues}}) . "\n";
        for my $issue (@{$issues->{spacing_issues}}) {
            $output .= "      Line $issue->{line}: $issue->{issue}\n";
        }
    }

    # Broken HTML
    if ($issues->{broken_html}) {
        $output .= "    $colors{red}Broken HTML:$colors{reset} " . scalar(@{$issues->{broken_html}}) . "\n";
        for my $issue (@{$issues->{broken_html}}) {
            $output .= "      Line $issue->{line}: $issue->{issue}\n";
        }
    }

    # Template Toolkit syntax issues
    if ($issues->{tt_syntax_issues}) {
        $output .= "    $colors{red}Template Toolkit syntax:$colors{reset} " . scalar(@{$issues->{tt_syntax_issues}}) . "\n";
        for my $issue (@{$issues->{tt_syntax_issues}}) {
            $output .= "      Line $issue->{line}: $issue->{issue}\n";
        }
    }

    # Content structure comparison
    if ($comparison->{tt_block_count_mismatch}) {
        my $comp = $comparison->{tt_block_count_mismatch};
        $output .= "    $colors{yellow}TT block mismatch:$colors{reset} $comp->{lang_count} vs English $comp->{en_count}\n";
    }

    if ($comparison->{h3_count_mismatch}) {
        my $comp = $comparison->{h3_count_mismatch};
        $output .= "    $colors{yellow}Header count mismatch:$colors{reset} $comp->{lang_count} vs English $comp->{en_count}\n";
    }

    return $output;
}

# Main analysis function
sub analyze_language {
    my ($lang, $lang_info) = @_;
    my %report;

    $report{name} = $lang_info->{name};
    $report{testing} = $lang_info->{testing} ? 1 : 0;

    my $total_issues = 0;
    my $files_with_issues = 0;

    # Analyze each standard HTML file
    for my $file (@standard_html_files) {
        my $file_path = "docs/ntppool/$lang/$file";
        next unless -f $file_path;

        my %issues = analyze_html_file($file_path, $lang);
        my %comparison = compare_with_english($lang, $file);

        my $file_issue_count = 0;
        for my $type (keys %issues) {
            $file_issue_count += scalar(@{$issues{$type}});
        }
        for my $type (keys %comparison) {
            $file_issue_count++;
        }

        if ($file_issue_count > 0) {
            $report{files}{$file} = {
                issues => \%issues,
                comparison => \%comparison,
                issue_count => $file_issue_count
            };
            $files_with_issues++;
            $total_issues += $file_issue_count;
        }
    }

    # Check hosting references
    my @hosting_issues = check_hosting_refs($lang);
    if (@hosting_issues) {
        $report{hosting_issues} = \@hosting_issues;
        $total_issues += scalar(@hosting_issues);
    }

    $report{total_issues} = $total_issues;
    $report{files_with_issues} = $files_with_issues;

    return %report;
}

# Format language report
sub format_language_report {
    my ($lang, $report) = @_;
    my $output = "";

    return "" unless $report->{total_issues} > 0;

    # Header
    $output .= "\n$colors{bold}=== $lang - $report->{name} ===$colors{reset}\n";
    $output .= "Status: " . ($report->{testing} ? "$colors{yellow}Beta/Testing$colors{reset}" : "$colors{green}Production$colors{reset}") . "\n";
    $output .= "Total issues: $colors{red}$report->{total_issues}$colors{reset} across $report->{files_with_issues} files\n";

    # File-specific issues
    if ($report->{files}) {
        for my $file (sort keys %{$report->{files}}) {
            my $file_data = $report->{files}{$file};
            $output .= format_file_report($file, $lang, $file_data->{issues}, $file_data->{comparison});
        }
    }

    # Hosting reference issues
    if ($report->{hosting_issues}) {
        $output .= "\n  $colors{bold}Hosting references:$colors{reset} $colors{yellow}⚠ Outdated$colors{reset}\n";
        for my $issue (@{$report->{hosting_issues}}) {
            $output .= "    - $issue\n";
        }
    }

    return $output;
}

# Generate summary statistics
sub generate_summary {
    my ($all_reports) = @_;
    my $output = "\n$colors{bold}========== HTML ISSUES ANALYSIS SUMMARY ==========$colors{reset}\n\n";

    my $total_langs = scalar(keys %$all_reports);
    my $langs_with_issues = grep { $all_reports->{$_}{total_issues} > 0 } keys %$all_reports;
    my $langs_clean = $total_langs - $langs_with_issues;

    my $total_issues = 0;
    my $total_tt_tags = 0;
    my $total_html_entities = 0;
    my $total_spacing_issues = 0;
    my $total_broken_html = 0;

    for my $lang (keys %$all_reports) {
        my $report = $all_reports->{$lang};
        $total_issues += $report->{total_issues};

        if ($report->{files}) {
            for my $file (keys %{$report->{files}}) {
                my $issues = $report->{files}{$file}{issues};
                $total_tt_tags += scalar(@{$issues->{tt_tags} || []});
                $total_html_entities += scalar(@{$issues->{html_entities} || []});
                $total_spacing_issues += scalar(@{$issues->{spacing_issues} || []});
                $total_broken_html += scalar(@{$issues->{broken_html} || []});
            }
        }
    }

    $output .= "Languages analyzed: $total_langs\n";
    $output .= "Languages with issues: $colors{red}$langs_with_issues$colors{reset}\n";
    $output .= "Languages clean: $colors{green}$langs_clean$colors{reset}\n\n";

    $output .= "Issue breakdown:\n";
    $output .= "  - Deprecated <tt> tags: $colors{red}$total_tt_tags$colors{reset}\n";
    $output .= "  - HTML entities to convert: $colors{yellow}$total_html_entities$colors{reset}\n";
    $output .= "  - Spacing issues: $colors{cyan}$total_spacing_issues$colors{reset}\n";
    $output .= "  - Broken HTML: $colors{red}$total_broken_html$colors{reset}\n";
    $output .= "  - Total issues: $colors{bold}$total_issues$colors{reset}\n\n";

    # Priority languages (most issues first)
    my @priority_langs = sort { $all_reports->{$b}{total_issues} <=> $all_reports->{$a}{total_issues} }
                         grep { $all_reports->{$_}{total_issues} > 0 } keys %$all_reports;

    if (@priority_langs) {
        $output .= "Priority languages (most issues first):\n";
        for my $i (0..9) {  # Top 10
            last if $i >= @priority_langs;
            my $lang = $priority_langs[$i];
            my $report = $all_reports->{$lang};
            $output .= sprintf("  %2d. %s (%s) - %d issues\n",
                $i+1, $lang, $report->{name}, $report->{total_issues});
        }
        $output .= "  ... and " . (@priority_langs - 10) . " more\n" if @priority_langs > 10;
    }

    return $output;
}

# Main execution
print "$colors{bold}NTP Pool HTML Issues Analysis Tool$colors{reset}\n";
print "=" x 50 . "\n";

# Change to repository root
my $script_dir = dirname(__FILE__);
chdir("$script_dir/../..") or die "Cannot change to repository root: $!";

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

# Then detailed reports for languages with issues
print "\n$colors{bold}========== DETAILED REPORTS ==========$colors{reset}\n";

for my $lang (sort keys %all_reports) {
    my $report = $all_reports{$lang};
    my $formatted = format_language_report($lang, $report);
    print $formatted if $formatted;
}

# Show clean languages
my @clean_langs = grep { $all_reports{$_}{total_issues} == 0 } sort keys %all_reports;
if (@clean_langs) {
    print "\n$colors{bold}========== CLEAN LANGUAGES ==========$colors{reset}\n";
    for my $lang (@clean_langs) {
        my $report = $all_reports{$lang};
        print "\n$colors{green}✓ $lang - $report->{name}$colors{reset}";
        print " (Beta)" if $report->{testing};
    }
    print "\n";
}

print "\n$colors{bold}Analysis complete!$colors{reset}\n";
print "Use fix_html_modernization.pl to automatically fix many of these issues.\n";
