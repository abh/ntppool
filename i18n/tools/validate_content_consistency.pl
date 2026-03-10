#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
binmode(STDOUT, ":utf8");
use JSON::XS qw(decode_json);
use File::Find;
use File::Basename;
use URI;

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

# Expected hosting providers (extracted from English source)
my @expected_hosting_providers = (
    'Equinix',
    'Netactuate',
);

# Outdated hosting providers that should be updated
my @outdated_hosting_providers = (
    'Packet',
    'Equinix Metal',
    'Develooper',
    'NetActuate',  # Different capitalization
    'OSUOSL',
    'Fastly',
);

# Technical references that should be consistent
my %technical_references = (
    'server_count_recommendation' => {
        expected => 'four',
        pattern => qr/(?:use|more than|not more than)\s+(\w+)\s+(?:time\s*)?servers?/i,
        outdated => ['three', 'two'],
    },
    'ntp_version' => {
        expected => 'ntp.org',
        pattern => qr/(ntp\.org|openntpd|chrony)/i,
        context => 'ntpd program',
    },
    'pool_domains' => {
        expected => ['0.pool.ntp.org', '1.pool.ntp.org', '2.pool.ntp.org', '3.pool.ntp.org'],
        pattern => qr/(\d+\.pool\.ntp\.org)/g,
    },
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

# Extract hosting provider information from English source
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
    }

    return %hosting_info;
}

# Check hosting provider consistency
sub check_hosting_consistency {
    my ($lang) = @_;
    my @issues;

    my $intro_file = "docs/ntppool/$lang/homepage/intro.html";
    return @issues unless -f $intro_file;

    my $content = read_file($intro_file);
    my %auth_info = get_authoritative_hosting_info();

    # Check for outdated provider names
    for my $outdated (@outdated_hosting_providers) {
        if ($content =~ /\Q$outdated\E/i) {
            push @issues, {
                type => 'outdated_provider',
                provider => $outdated,
                message => "Found outdated hosting provider '$outdated'"
            };
        }
    }

    # Check if current providers are mentioned
    if ($auth_info{providers}) {
        my @missing_providers;
        for my $provider_info (@{$auth_info{providers}}) {
            my $provider = $provider_info->{name};
            unless ($content =~ /\Q$provider\E/i) {
                push @missing_providers, $provider;
            }
        }

        if (@missing_providers) {
            push @issues, {
                type => 'missing_providers',
                providers => \@missing_providers,
                message => "Missing current hosting providers: " . join(", ", @missing_providers)
            };
        }
    }

    # Check if hosting section exists
    unless ($content =~ /hosting|bandwidth/i) {
        push @issues, {
            type => 'missing_hosting_section',
            message => "No hosting/bandwidth information found"
        };
    }

    return @issues;
}

# Check technical reference consistency
sub check_technical_consistency {
    my ($lang, $file) = @_;
    my @issues;

    my $file_path = "docs/ntppool/$lang/$file";
    return @issues unless -f $file_path;

    my $content = read_file($file_path);
    my $en_content = read_file("docs/ntppool/en/$file");

    # Check server count recommendation
    if ($file eq 'use.html') {
        my $ref = $technical_references{server_count_recommendation};
        if ($content =~ /$ref->{pattern}/) {
            my $found_count = lc($1);
            if (grep { $_ eq $found_count } @{$ref->{outdated}}) {
                push @issues, {
                    type => 'outdated_server_count',
                    found => $found_count,
                    expected => $ref->{expected},
                    message => "Server count recommendation '$found_count' should be '$ref->{expected}'"
                };
            }
        }

        # Check for pool domains consistency
        my @found_domains = $content =~ /$technical_references{pool_domains}{pattern}/g;
        my @expected_domains = @{$technical_references{pool_domains}{expected}};

        if (@found_domains != @expected_domains) {
            push @issues, {
                type => 'pool_domains_mismatch',
                found => \@found_domains,
                expected => \@expected_domains,
                message => "Pool domains mismatch: found " . scalar(@found_domains) . " expected " . scalar(@expected_domains)
            };
        }
    }

    return @issues;
}

# Check URL consistency and validity
sub check_url_consistency {
    my ($lang, $file) = @_;
    my @issues;

    my $file_path = "docs/ntppool/$lang/$file";
    return @issues unless -f $file_path;

    my $content = read_file($file_path);
    my $en_content = read_file("docs/ntppool/en/$file");

    # Extract all URLs from both files
    my @lang_urls = $content =~ /(?:href|src)="([^"]+)"/g;
    my @en_urls = $en_content =~ /(?:href|src)="([^"]+)"/g;

    # Check for missing URLs in translation
    my %lang_url_set = map { $_ => 1 } @lang_urls;
    my %en_url_set = map { $_ => 1 } @en_urls;

    for my $url (@en_urls) {
        # Skip Template Toolkit variables and fragments
        next if $url =~ /^\[%|^#|^mailto:/;
        next if $url =~ /^\//;  # Skip relative URLs for now

        unless (exists $lang_url_set{$url}) {
            push @issues, {
                type => 'missing_url',
                url => $url,
                message => "URL '$url' present in English but missing in translation"
            };
        }
    }

    # Check for potentially incorrect URLs
    for my $url (@lang_urls) {
        next if $url =~ /^\[%|^#|^mailto:|^\//;

        # Basic URL validation
        eval {
            my $uri = URI->new($url);
            unless ($uri->scheme && $uri->scheme =~ /^https?$/) {
                push @issues, {
                    type => 'invalid_url',
                    url => $url,
                    message => "URL '$url' appears to be invalid or malformed"
                };
            }
        };
        if ($@) {
            push @issues, {
                type => 'malformed_url',
                url => $url,
                message => "URL '$url' could not be parsed: $@"
            };
        }
    }

    return @issues;
}

# Compare content structure
sub compare_content_structure {
    my ($lang, $file) = @_;
    my @issues;

    my $file_path = "docs/ntppool/$lang/$file";
    my $en_file_path = "docs/ntppool/en/$file";

    return @issues unless -f $file_path && -f $en_file_path;

    my $content = read_file($file_path);
    my $en_content = read_file($en_file_path);

    # Check for missing major sections
    my @en_h3_sections = $en_content =~ /<h3[^>]*id="([^"]*)"[^>]*>/g;
    my @lang_h3_sections = $content =~ /<h3[^>]*id="([^"]*)"[^>]*>/g;

    my %lang_sections = map { $_ => 1 } @lang_h3_sections;
    for my $section (@en_h3_sections) {
        unless (exists $lang_sections{$section}) {
            push @issues, {
                type => 'missing_section',
                section => $section,
                message => "Missing section with id='$section'"
            };
        }
    }

    # Check for missing code blocks or examples
    my @en_code_blocks = $en_content =~ /(<code[^>]*>.*?<\/code>)/gs;
    my @lang_code_blocks = $content =~ /(<code[^>]*>.*?<\/code>)/gs;

    if (@en_code_blocks != @lang_code_blocks) {
        push @issues, {
            type => 'code_block_count_mismatch',
            en_count => scalar(@en_code_blocks),
            lang_count => scalar(@lang_code_blocks),
            message => "Code block count mismatch: " . scalar(@lang_code_blocks) . " vs English " . scalar(@en_code_blocks)
        };
    }

    # Check for missing Template Toolkit includes
    my @en_includes = $en_content =~ /\[%\s*INCLUDE\s+"([^"]+)"/g;
    my @lang_includes = $content =~ /\[%\s*INCLUDE\s+"([^"]+)"/g;

    my %lang_includes = map { $_ => 1 } @lang_includes;
    for my $include (@en_includes) {
        unless (exists $lang_includes{$include}) {
            push @issues, {
                type => 'missing_include',
                include => $include,
                message => "Missing Template Toolkit include: $include"
            };
        }
    }

    return @issues;
}

# Check Windows instructions consistency (specific to use.html)
sub check_windows_instructions {
    my ($lang) = @_;
    my @issues;

    my $use_file = "docs/ntppool/$lang/use.html";
    return @issues unless -f $use_file;

    my $content = read_file($use_file);
    my $en_content = read_file("docs/ntppool/en/use.html");

    # Check for Windows section
    if ($en_content =~ /Windows/i && $content !~ /Windows/i) {
        push @issues, {
            type => 'missing_windows_section',
            message => "Windows instructions section appears to be missing"
        };
    }

    # Check for modern Windows path references
    if ($content =~ /Control Panel/i && $content !~ /Win\+I|Settings/i) {
        push @issues, {
            type => 'outdated_windows_instructions',
            message => "Windows instructions may be outdated (mentions Control Panel but not modern Settings app)"
        };
    }

    return @issues;
}

# Main analysis function
sub analyze_language_consistency {
    my ($lang, $lang_info) = @_;
    my %report;

    $report{name} = $lang_info->{name};
    $report{testing} = $lang_info->{testing} ? 1 : 0;

    my @all_issues;

    # Check hosting provider consistency
    my @hosting_issues = check_hosting_consistency($lang);
    push @all_issues, @hosting_issues;

    # Check each standard file for consistency issues
    for my $file (@standard_html_files) {
        next unless -f "docs/ntppool/$lang/$file";

        my @tech_issues = check_technical_consistency($lang, $file);
        my @url_issues = check_url_consistency($lang, $file);
        my @structure_issues = compare_content_structure($lang, $file);

        my @file_issues = (@tech_issues, @url_issues, @structure_issues);

        if ($file eq 'use.html') {
            my @windows_issues = check_windows_instructions($lang);
            push @file_issues, @windows_issues;
        }

        if (@file_issues) {
            $report{files}{$file} = \@file_issues;
        }

        push @all_issues, @file_issues;
    }

    $report{hosting_issues} = \@hosting_issues if @hosting_issues;
    $report{total_issues} = scalar(@all_issues);

    return %report;
}

# Format report for a language
sub format_language_report {
    my ($lang, $report) = @_;
    my $output = "";

    return "" unless $report->{total_issues} > 0;

    # Header
    $output .= "\n$colors{bold}=== $lang - $report->{name} ===$colors{reset}\n";
    $output .= "Status: " . ($report->{testing} ? "$colors{yellow}Beta/Testing$colors{reset}" : "$colors{green}Production$colors{reset}") . "\n";
    $output .= "Total consistency issues: $colors{red}$report->{total_issues}$colors{reset}\n";

    # Hosting issues
    if ($report->{hosting_issues}) {
        $output .= "\n  $colors{bold}Hosting Provider Issues:$colors{reset}\n";
        for my $issue (@{$report->{hosting_issues}}) {
            my $color = $issue->{type} eq 'outdated_provider' ? $colors{red} : $colors{yellow};
            $output .= "    $color• $issue->{message}$colors{reset}\n";
        }
    }

    # File-specific issues
    if ($report->{files}) {
        for my $file (sort keys %{$report->{files}}) {
            my $issues = $report->{files}{$file};
            $output .= "\n  $colors{bold}$file:$colors{reset}\n";

            for my $issue (@$issues) {
                my $color = $issue->{type} =~ /missing|outdated/ ? $colors{red} : $colors{yellow};
                $output .= "    $color• $issue->{message}$colors{reset}\n";

                # Additional details for some issue types
                if ($issue->{type} eq 'missing_providers' && $issue->{providers}) {
                    $output .= "      Expected: " . join(", ", @{$issue->{providers}}) . "\n";
                }
                if ($issue->{type} eq 'pool_domains_mismatch') {
                    $output .= "      Found: " . join(", ", @{$issue->{found}}) . "\n";
                    $output .= "      Expected: " . join(", ", @{$issue->{expected}}) . "\n";
                }
            }
        }
    }

    return $output;
}

# Generate summary statistics
sub generate_summary {
    my ($all_reports) = @_;
    my $output = "\n$colors{bold}========== CONTENT CONSISTENCY SUMMARY ==========$colors{reset}\n\n";

    my $total_langs = scalar(keys %$all_reports);
    my $langs_with_issues = grep { $all_reports->{$_}{total_issues} > 0 } keys %$all_reports;
    my $langs_consistent = $total_langs - $langs_with_issues;

    my $total_issues = 0;
    my $hosting_issues = 0;
    my $structure_issues = 0;
    my $technical_issues = 0;

    for my $lang (keys %$all_reports) {
        my $report = $all_reports->{$lang};
        $total_issues += $report->{total_issues};
        $hosting_issues += scalar(@{$report->{hosting_issues} || []});

        if ($report->{files}) {
            for my $file (keys %{$report->{files}}) {
                for my $issue (@{$report->{files}{$file}}) {
                    if ($issue->{type} =~ /missing_section|code_block|missing_include/) {
                        $structure_issues++;
                    } elsif ($issue->{type} =~ /server_count|pool_domains|windows/) {
                        $technical_issues++;
                    }
                }
            }
        }
    }

    $output .= "Languages analyzed: $total_langs\n";
    $output .= "Languages with consistency issues: $colors{red}$langs_with_issues$colors{reset}\n";
    $output .= "Languages consistent: $colors{green}$langs_consistent$colors{reset}\n\n";

    $output .= "Issue breakdown:\n";
    $output .= "  - Hosting provider issues: $colors{red}$hosting_issues$colors{reset}\n";
    $output .= "  - Content structure issues: $colors{yellow}$structure_issues$colors{reset}\n";
    $output .= "  - Technical reference issues: $colors{cyan}$technical_issues$colors{reset}\n";
    $output .= "  - Total issues: $colors{bold}$total_issues$colors{reset}\n\n";

    # High priority languages (most issues)
    my @priority_langs = sort { $all_reports->{$b}{total_issues} <=> $all_reports->{$a}{total_issues} }
                         grep { $all_reports->{$_}{total_issues} > 0 } keys %$all_reports;

    if (@priority_langs) {
        $output .= "Languages needing attention (most issues first):\n";
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
print "$colors{bold}NTP Pool Content Consistency Validator$colors{reset}\n";
print "=" x 50 . "\n";

# Change to repository root
my $script_dir = dirname(__FILE__);
chdir("$script_dir/../..") or die "Cannot change to repository root: $!";

# Load languages
my $languages = load_languages();

# Add English to the analysis (as reference)
$languages->{en} = { name => 'English' };

# Analyze all languages
my %all_reports;
for my $lang (sort keys %$languages) {
    next if $lang eq 'en';  # Skip English as it's the authoritative source

    my %report = analyze_language_consistency($lang, $languages->{$lang});
    $all_reports{$lang} = \%report;
}

# Generate summary
print generate_summary(\%all_reports);

# Generate detailed reports
print "\n$colors{bold}========== DETAILED REPORTS ==========$colors{reset}\n";

for my $lang (sort keys %all_reports) {
    my $report = $all_reports{$lang};
    my $formatted = format_language_report($lang, $report);
    print $formatted if $formatted;
}

# Show consistent languages
my @consistent_langs = grep { $all_reports{$_}{total_issues} == 0 } sort keys %all_reports;
if (@consistent_langs) {
    print "\n$colors{bold}========== CONSISTENT LANGUAGES ==========$colors{reset}\n";
    for my $lang (@consistent_langs) {
        my $report = $all_reports{$lang};
        print "\n$colors{green}✓ $lang - $report->{name}$colors{reset}";
        print " (Beta)" if $report->{testing};
    }
    print "\n";
}

print "\n$colors{bold}Analysis complete!$colors{reset}\n";
print "Use sync_content_updates.pl to fix consistency issues.\n";
