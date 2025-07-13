#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
binmode(STDOUT, ":utf8");
use JSON::XS qw(decode_json);
use File::Find;
use File::Basename;
use Encode qw(decode_utf8 is_utf8 encode_utf8);

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

# Language-specific character expectations
my %language_chars = (
    'da' => {
        name => 'Danish',
        expected_chars => ['æ', 'ø', 'å', 'Æ', 'Ø', 'Å'],
        common_words => ['kørende', 'ønsker', 'så', 'før', 'både', 'måde'],
    },
    'de' => {
        name => 'German',
        expected_chars => ['ä', 'ö', 'ü', 'ß', 'Ä', 'Ö', 'Ü'],
        common_words => ['für', 'möchten', 'können', 'größer', 'wäre', 'müssen'],
    },
    'es' => {
        name => 'Spanish',
        expected_chars => ['ñ', 'á', 'é', 'í', 'ó', 'ú', 'ü', 'Ñ', 'Á', 'É', 'Í', 'Ó', 'Ú'],
        common_words => ['información', 'configuración', 'también', 'después', 'así', 'más'],
    },
    'fr' => {
        name => 'French',
        expected_chars => ['à', 'â', 'ä', 'ç', 'è', 'é', 'ê', 'ë', 'î', 'ï', 'ô', 'ù', 'û', 'ü', 'ÿ', 'À', 'Â', 'Ç', 'È', 'É', 'Ê', 'Ë', 'Î', 'Ï', 'Ô', 'Ù', 'Û', 'Ü'],
        common_words => ['français', 'configuré', 'être', 'très', 'après', 'général'],
    },
    'it' => {
        name => 'Italian',
        expected_chars => ['à', 'è', 'é', 'ì', 'í', 'î', 'ò', 'ó', 'ù', 'ú', 'À', 'È', 'É', 'Ì', 'Í', 'Î', 'Ò', 'Ó', 'Ù', 'Ú'],
        common_words => ['però', 'così', 'più', 'città', 'qualità', 'università'],
    },
    'pt' => {
        name => 'Portuguese',
        expected_chars => ['á', 'â', 'ã', 'à', 'ç', 'é', 'ê', 'í', 'ó', 'ô', 'õ', 'ú', 'ü', 'Á', 'Â', 'Ã', 'À', 'Ç', 'É', 'Ê', 'Í', 'Ó', 'Ô', 'Õ', 'Ú'],
        common_words => ['configuração', 'não', 'informações', 'versão', 'também', 'operação'],
    },
    'sv' => {
        name => 'Swedish',
        expected_chars => ['å', 'ä', 'ö', 'Å', 'Ä', 'Ö'],
        common_words => ['för', 'så', 'större', 'kör', 'även', 'både'],
    },
    'fi' => {
        name => 'Finnish',
        expected_chars => ['ä', 'ö', 'Ä', 'Ö'],
        common_words => ['käyttää', 'määrittää', 'työskentelyn', 'sähköposti', 'yhteisö'],
    },
    'nb' => {
        name => 'Norwegian Bokmål',
        expected_chars => ['æ', 'ø', 'å', 'Æ', 'Ø', 'Å'],
        common_words => ['før', 'både', 'også', 'så', 'større', 'møte'],
    },
    'nn' => {
        name => 'Norwegian Nynorsk',
        expected_chars => ['æ', 'ø', 'å', 'Æ', 'Ø', 'Å'],
        common_words => ['før', 'både', 'òg', 'så', 'større', 'møte'],
    },
    'nl' => {
        name => 'Dutch',
        expected_chars => ['é', 'ë', 'í', 'ï', 'ó', 'ö', 'ú', 'ü', 'É', 'Ë', 'Í', 'Ï', 'Ó', 'Ö', 'Ú', 'Ü'],
        common_words => ['één', 'configuré', 'systéém', 'problème'],
    },
    'cs' => {
        name => 'Czech',
        expected_chars => ['á', 'č', 'ď', 'é', 'ě', 'í', 'ň', 'ó', 'ř', 'š', 'ť', 'ú', 'ů', 'ý', 'ž', 'Á', 'Č', 'Ď', 'É', 'Ě', 'Í', 'Ň', 'Ó', 'Ř', 'Š', 'Ť', 'Ú', 'Ů', 'Ý', 'Ž'],
        common_words => ['čeština', 'systém', 'správné', 'nějaké', 'příliš'],
    },
    'pl' => {
        name => 'Polish',
        expected_chars => ['ą', 'ć', 'ę', 'ł', 'ń', 'ó', 'ś', 'ź', 'ż', 'Ą', 'Ć', 'Ę', 'Ł', 'Ń', 'Ó', 'Ś', 'Ź', 'Ż'],
        common_words => ['można', 'używać', 'więcej', 'także', 'później'],
    },
    'ru' => {
        name => 'Russian',
        expected_chars => ['а', 'б', 'в', 'г', 'д', 'е', 'ё', 'ж', 'з', 'и', 'й', 'к', 'л', 'м', 'н', 'о', 'п', 'р', 'с', 'т', 'у', 'ф', 'х', 'ц', 'ч', 'ш', 'щ', 'ъ', 'ы', 'ь', 'э', 'ю', 'я'],
        common_words => ['сервер', 'время', 'настройка', 'система', 'можете'],
    },
    'el' => {
        name => 'Greek',
        expected_chars => ['α', 'β', 'γ', 'δ', 'ε', 'ζ', 'η', 'θ', 'ι', 'κ', 'λ', 'μ', 'ν', 'ξ', 'ο', 'π', 'ρ', 'σ', 'ς', 'τ', 'υ', 'φ', 'χ', 'ψ', 'ω'],
        common_words => ['σύστημα', 'χρόνος', 'πληροφορίες', 'έχετε'],
    },
    'ja' => {
        name => 'Japanese',
        expected_chars => ['あ', 'い', 'う', 'え', 'お', 'か', 'き', 'く', 'け', 'こ', 'が', 'ぎ', 'ぐ', 'げ', 'ご'],
        common_words => ['システム', 'サーバー', '設定', '時間'],
    },
    'ko' => {
        name => 'Korean',
        expected_chars => ['가', '나', '다', '라', '마', '바', '사', '아', '자', '차', '카', '타', '파', '하'],
        common_words => ['시스템', '서버', '설정', '시간'],
    },
    'zh' => {
        name => 'Chinese Simplified',
        expected_chars => ['的', '是', '在', '了', '不', '和', '有', '大', '这', '主', '要', '我', '一', '们'],
        common_words => ['系统', '服务器', '设置', '时间', '网络'],
    },
    'ar' => {
        name => 'Arabic',
        expected_chars => ['ا', 'ب', 'ت', 'ث', 'ج', 'ح', 'خ', 'د', 'ذ', 'ر', 'ز', 'س', 'ش', 'ص', 'ض', 'ط', 'ظ', 'ع', 'غ', 'ف', 'ق', 'ك', 'ل', 'م', 'ن', 'ه', 'و', 'ي'],
        common_words => ['النظام', 'الخادم', 'الوقت', 'الشبكة'],
    },
    'he' => {
        name => 'Hebrew',
        expected_chars => ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ', 'ק', 'ר', 'ש', 'ת'],
        common_words => ['מערכת', 'שרת', 'זמן', 'רשת'],
    },
    'tr' => {
        name => 'Turkish',
        expected_chars => ['ç', 'ğ', 'ı', 'ö', 'ş', 'ü', 'Ç', 'Ğ', 'İ', 'Ö', 'Ş', 'Ü'],
        common_words => ['sistem', 'sunucu', 'yapılandırma', 'için', 'büyük'],
    },
    'uk' => {
        name => 'Ukrainian',
        expected_chars => ['а', 'б', 'в', 'г', 'ґ', 'д', 'е', 'є', 'ж', 'з', 'и', 'і', 'ї', 'й', 'к', 'л', 'м', 'н', 'о', 'п', 'р', 'с', 'т', 'у', 'ф', 'х', 'ц', 'ч', 'ш', 'щ', 'ь', 'ю', 'я'],
        common_words => ['система', 'сервер', 'час', 'мережа'],
    },
);

# HTML entities that should be native UTF-8 characters
my %suspicious_entities = (
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
);

# Read file content with encoding detection
sub read_file_with_encoding {
    my ($file) = @_;

    # Try UTF-8 first
    eval {
        open my $fh, '<:utf8', $file or die "Cannot open $file: $!";
        local $/;
        my $content = <$fh>;
        close $fh;
        return ($content, 'utf8', undef);
    };

    if ($@) {
        # Try raw bytes and detect encoding issues
        open my $fh, '<:raw', $file or die "Cannot open $file: $!";
        local $/;
        my $raw_content = <$fh>;
        close $fh;

        # Try to decode as UTF-8
        eval {
            my $utf8_content = decode_utf8($raw_content, Encode::FB_CROAK);
            return ($utf8_content, 'utf8_decoded', undef);
        };

        if ($@) {
            return ($raw_content, 'raw', "UTF-8 decode error: $@");
        }
    }
}

# Load language list from JSON
sub load_languages {
    my ($content, $encoding, $error) = read_file_with_encoding('i18n/languages.json');
    die "Cannot read languages.json: $error" if $error;

    utf8::encode($content) if utf8::is_utf8($content);
    my $languages = decode_json($content);
    return $languages;
}

# Check file encoding and UTF-8 validity
sub check_file_encoding {
    my ($file_path) = @_;
    my @issues;

    my ($content, $encoding, $error) = read_file_with_encoding($file_path);

    if ($error) {
        push @issues, {
            type => 'encoding_error',
            message => $error,
            severity => 'high'
        };
        return @issues;
    }

    if ($encoding eq 'raw') {
        push @issues, {
            type => 'not_utf8',
            message => "File is not valid UTF-8",
            severity => 'high'
        };
        return @issues;
    }

    # Check for BOM (Byte Order Mark)
    if ($content =~ /^\x{FEFF}/) {
        push @issues, {
            type => 'bom_found',
            message => "UTF-8 BOM found at beginning of file",
            severity => 'medium'
        };
    }

    # Check for suspicious byte sequences that might indicate encoding issues
    my @lines = split /\n/, $content;
    for my $i (0..$#lines) {
        my $line_num = $i + 1;
        my $line = $lines[$i];

        # Check for replacement characters (indicating encoding problems)
        if ($line =~ /\x{FFFD}/) {
            push @issues, {
                type => 'replacement_character',
                line => $line_num,
                message => "Replacement character (�) found - indicates encoding corruption",
                severity => 'high'
            };
        }

        # Check for suspicious character combinations
        if ($line =~ /[Ã¡Ã©Ã­Ã³ÃºÃ±]/) {
            push @issues, {
                type => 'double_encoding',
                line => $line_num,
                message => "Possible double-encoding detected",
                severity => 'medium',
                example => $&
            };
        }

        # Check for control characters (except common ones)
        if ($line =~ /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/) {
            push @issues, {
                type => 'control_characters',
                line => $line_num,
                message => "Control characters found",
                severity => 'medium'
            };
        }
    }

    return @issues;
}

# Check for HTML entities that should be native UTF-8
sub check_html_entities {
    my ($file_path, $lang) = @_;
    my @issues;

    my ($content, $encoding, $error) = read_file_with_encoding($file_path);
    return @issues if $error;

    my @lines = split /\n/, $content;
    my %entity_counts;

    for my $i (0..$#lines) {
        my $line_num = $i + 1;
        my $line = $lines[$i];

        for my $entity (keys %suspicious_entities) {
            if ($line =~ /\Q$entity\E/) {
                $entity_counts{$entity}++;

                # Check if this should be a native character for this language
                my $native_char = $suspicious_entities{$entity};
                if ($language_chars{$lang} &&
                    grep { $_ eq $native_char } @{$language_chars{$lang}{expected_chars}}) {

                    push @issues, {
                        type => 'should_be_native',
                        entity => $entity,
                        native => $native_char,
                        line => $line_num,
                        message => "HTML entity '$entity' should be native UTF-8 '$native_char' for $lang",
                        severity => 'medium'
                    };
                }
            }
        }
    }

    # Report entity summary
    for my $entity (keys %entity_counts) {
        push @issues, {
            type => 'entity_count',
            entity => $entity,
            count => $entity_counts{$entity},
            native => $suspicious_entities{$entity},
            message => "Found $entity_counts{$entity} occurrences of '$entity'",
            severity => 'low'
        };
    }

    return @issues;
}

# Check for missing language-specific characters
sub check_language_characters {
    my ($file_path, $lang) = @_;
    my @issues;

    return @issues unless exists $language_chars{$lang};

    my ($content, $encoding, $error) = read_file_with_encoding($file_path);
    return @issues if $error;

    my $lang_info = $language_chars{$lang};
    my @expected_chars = @{$lang_info->{expected_chars}};
    my @common_words = @{$lang_info->{common_words}};

    # Check if any expected characters are present
    my @found_chars;
    for my $char (@expected_chars) {
        if ($content =~ /\Q$char\E/) {
            push @found_chars, $char;
        }
    }

    # If very few or no expected characters found, might indicate encoding issues
    my $expected_ratio = @found_chars / @expected_chars;
    if ($expected_ratio < 0.1 && @expected_chars > 5) {
        push @issues, {
            type => 'missing_language_chars',
            found => \@found_chars,
            expected => \@expected_chars,
            ratio => $expected_ratio,
            message => "Very few expected $lang_info->{name} characters found ($expected_ratio ratio)",
            severity => 'medium'
        };
    }

    # Check for common words in ASCII when they should have accents
    for my $word (@common_words) {
        # Create ASCII version of word (simplified)
        my $ascii_word = $word;
        $ascii_word =~ s/[^\x00-\x7F]/./g;  # Replace non-ASCII with dots

        if ($ascii_word ne $word && $content =~ /\Q$ascii_word\E/ && $content !~ /\Q$word\E/) {
            push @issues, {
                type => 'ascii_instead_of_accented',
                ascii_word => $ascii_word,
                correct_word => $word,
                message => "Found ASCII '$ascii_word' but should be '$word'",
                severity => 'low'
            };
        }
    }

    return @issues;
}

# Check normalization (NFC vs NFD)
sub check_unicode_normalization {
    my ($file_path) = @_;
    my @issues;

    my ($content, $encoding, $error) = read_file_with_encoding($file_path);
    return @issues if $error;

    # This is a simplified check - in practice you'd use Unicode::Normalize
    # Look for character sequences that might indicate NFD when NFC is expected
    my @lines = split /\n/, $content;

    for my $i (0..$#lines) {
        my $line_num = $i + 1;
        my $line = $lines[$i];

        # Look for base character + combining character sequences
        if ($line =~ /[a-zA-Z]\x{0300}-\x{036F}/) {
            push @issues, {
                type => 'possible_nfd',
                line => $line_num,
                message => "Possible NFD normalization (separate base + combining characters)",
                severity => 'low'
            };
        }
    }

    return @issues;
}

# Analyze encoding for a single file
sub analyze_file_encoding {
    my ($file_path, $lang) = @_;
    my @all_issues;

    return @all_issues unless -f $file_path;

    # Check basic encoding
    my @encoding_issues = check_file_encoding($file_path);
    push @all_issues, @encoding_issues;

    # If basic encoding is OK, do more detailed checks
    unless (grep { $_->{severity} eq 'high' } @encoding_issues) {
        my @entity_issues = check_html_entities($file_path, $lang);
        my @char_issues = check_language_characters($file_path, $lang);
        my @norm_issues = check_unicode_normalization($file_path);

        push @all_issues, @entity_issues, @char_issues, @norm_issues;
    }

    return @all_issues;
}

# Analyze encoding for all files of a language
sub analyze_language_encoding {
    my ($lang, $lang_info) = @_;
    my %report;

    $report{name} = $lang_info->{name};
    $report{testing} = $lang_info->{testing} ? 1 : 0;

    my @all_issues;
    my $files_checked = 0;

    # Check .po file
    my $po_file = "i18n/$lang.po";
    if (-f $po_file) {
        my @po_issues = analyze_file_encoding($po_file, $lang);
        if (@po_issues) {
            $report{po_issues} = \@po_issues;
        }
        push @all_issues, @po_issues;
        $files_checked++;
    }

    # Check HTML files
    my @html_files = (
        'homepage/intro.html',
        'join.html',
        'join/configuration.html',
        'tpl/server/graph_explanation.html',
        'use.html',
    );

    for my $file (@html_files) {
        my $file_path = "docs/ntppool/$lang/$file";
        next unless -f $file_path;

        my @file_issues = analyze_file_encoding($file_path, $lang);
        if (@file_issues) {
            $report{html_files}{$file} = \@file_issues;
        }
        push @all_issues, @file_issues;
        $files_checked++;
    }

    $report{total_issues} = scalar(@all_issues);
    $report{files_checked} = $files_checked;
    $report{files_with_issues} = scalar(keys %{$report{html_files} || {}}) + (exists $report{po_issues} ? 1 : 0);

    return %report;
}

# Format issues for display
sub format_issues {
    my ($issues, $context) = @_;
    my $output = "";

    return "" unless @$issues;

    my %by_severity = (high => [], medium => [], low => []);
    for my $issue (@$issues) {
        push @{$by_severity{$issue->{severity}}}, $issue;
    }

    for my $severity ('high', 'medium', 'low') {
        next unless @{$by_severity{$severity}};

        my $color = $severity eq 'high' ? $colors{red} :
                   $severity eq 'medium' ? $colors{yellow} : $colors{cyan};

        $output .= "      $color" . ucfirst($severity) . " issues:$colors{reset}\n";

        for my $issue (@{$by_severity{$severity}}) {
            $output .= "        • $issue->{message}";
            $output .= " (line $issue->{line})" if $issue->{line};
            $output .= "\n";

            if ($issue->{type} eq 'should_be_native') {
                $output .= "          Replace: $issue->{entity} → $issue->{native}\n";
            }
        }
    }

    return $output;
}

# Format language report
sub format_language_report {
    my ($lang, $report) = @_;
    my $output = "";

    return "" unless $report->{total_issues} > 0;

    # Header
    $output .= "\n$colors{bold}=== $lang - $report->{name} ===$colors{reset}\n";
    $output .= "Status: " . ($report->{testing} ? "$colors{yellow}Beta/Testing$colors{reset}" : "$colors{green}Production$colors{reset}") . "\n";
    $output .= "Files checked: $report->{files_checked}, Issues found: $colors{red}$report->{total_issues}$colors{reset}\n";

    # .po file issues
    if ($report->{po_issues}) {
        $output .= "\n  $colors{bold}$lang.po:$colors{reset}\n";
        $output .= format_issues($report->{po_issues}, 'po');
    }

    # HTML file issues
    if ($report->{html_files}) {
        for my $file (sort keys %{$report->{html_files}}) {
            $output .= "\n  $colors{bold}$file:$colors{reset}\n";
            $output .= format_issues($report->{html_files}{$file}, 'html');
        }
    }

    return $output;
}

# Generate summary statistics
sub generate_summary {
    my ($all_reports) = @_;
    my $output = "\n$colors{bold}========== ENCODING ANALYSIS SUMMARY ==========$colors{reset}\n\n";

    my $total_langs = scalar(keys %$all_reports);
    my $langs_with_issues = grep { $all_reports->{$_}{total_issues} > 0 } keys %$all_reports;
    my $langs_clean = $total_langs - $langs_with_issues;

    my $total_issues = 0;
    my $high_severity = 0;
    my $medium_severity = 0;
    my $low_severity = 0;

    for my $lang (keys %$all_reports) {
        my $report = $all_reports->{$lang};
        $total_issues += $report->{total_issues};

        # Count by severity
        for my $file_type ('po_issues', 'html_files') {
            next unless $report->{$file_type};

            my $issues = $file_type eq 'po_issues' ? $report->{$file_type} :
                        [map { @{$report->{$file_type}{$_}} } keys %{$report->{$file_type}}];

            for my $issue (@$issues) {
                if ($issue->{severity} eq 'high') { $high_severity++; }
                elsif ($issue->{severity} eq 'medium') { $medium_severity++; }
                else { $low_severity++; }
            }
        }
    }

    $output .= "Languages analyzed: $total_langs\n";
    $output .= "Languages with encoding issues: $colors{red}$langs_with_issues$colors{reset}\n";
    $output .= "Languages with clean encoding: $colors{green}$langs_clean$colors{reset}\n\n";

    $output .= "Issue breakdown by severity:\n";
    $output .= "  - $colors{red}High:$colors{reset} $high_severity (encoding errors, corruption)\n";
    $output .= "  - $colors{yellow}Medium:$colors{reset} $medium_severity (HTML entities, missing chars)\n";
    $output .= "  - $colors{cyan}Low:$colors{reset} $low_severity (normalization, counts)\n";
    $output .= "  - $colors{bold}Total:$colors{reset} $total_issues\n\n";

    # Priority languages (most issues first)
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
print "$colors{bold}NTP Pool Encoding and Character Validation Tool$colors{reset}\n";
print "=" x 60 . "\n";

# Change to repository root
my $script_dir = dirname(__FILE__);
chdir("$script_dir/../..") or die "Cannot change to repository root: $!";

# Load languages
my $languages = load_languages();

# Analyze all languages
my %all_reports;
for my $lang (sort keys %$languages) {
    my %report = analyze_language_encoding($lang, $languages->{$lang});
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

# Show clean languages
my @clean_langs = grep { $all_reports{$_}{total_issues} == 0 } sort keys %all_reports;
if (@clean_langs) {
    print "\n$colors{bold}========== LANGUAGES WITH CLEAN ENCODING ==========$colors{reset}\n";
    for my $lang (@clean_langs) {
        my $report = $all_reports{$lang};
        print "\n$colors{green}✓ $lang - $report->{name}$colors{reset}";
        print " (Beta)" if $report->{testing};
    }
    print "\n";
}

print "\n$colors{bold}Analysis complete!$colors{reset}\n";
print "Use fix_html_modernization.pl to fix HTML entity issues automatically.\n";
