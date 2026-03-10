# NTP Pool Translation Tools

This directory contains comprehensive tools for maintaining and improving translations across the NTP Pool project. These tools automate common translation maintenance tasks and ensure consistency across all supported languages.

## Overview

The translation toolset provides systematic analysis, validation, and automated fixing of translation issues including:

- **HTML modernization** (deprecated tags, entities)
- **Content consistency** (hosting providers, technical references)
- **Encoding validation** (UTF-8, character validation)
- **Systematic processing** (batch operations across language groups)

## Tools

### Analysis Tools

#### `analyze_html_issues.pl`
Comprehensive HTML analysis tool that identifies:
- Deprecated `<tt>` tags that should be `<code>`
- HTML entities that should be native UTF-8 characters
- Spacing issues around HTML tags
- Broken HTML and malformed markup
- Template Toolkit syntax issues
- Content structure comparison with English source

**Usage:**
```bash
perl analyze_html_issues.pl
```

#### `validate_content_consistency.pl`
Content accuracy checker that validates:
- Hosting provider references against English authoritative source
- Technical references (server counts, URLs, domains)
- Content structure consistency (missing sections, code blocks)
- Windows instructions modernization needs

**Usage:**
```bash
perl validate_content_consistency.pl
```

#### `check_encoding.pl`
UTF-8 and character validation tool that checks:
- File encoding validity and UTF-8 compliance
- HTML entities that should be native UTF-8 characters
- Language-specific character expectations
- Unicode normalization issues
- Encoding corruption detection

**Usage:**
```bash
perl check_encoding.pl
```

### Fixing Tools

#### `fix_html_modernization.pl`
HTML modernization fixer that automatically:
- Converts `<tt>` tags to modern `<code>` tags
- Converts HTML entities to UTF-8 characters (where appropriate)
- Fixes spacing issues around HTML tags
- Preserves Template Toolkit syntax integrity

**Usage:**
```bash
# Dry run to preview changes
perl fix_html_modernization.pl --dry-run

# Fix specific languages
perl fix_html_modernization.pl -l de -l fr -l es

# Interactive mode
perl fix_html_modernization.pl --interactive --verbose
```

**Options:**
- `-n, --dry-run`: Preview changes without modifying files
- `--no-backup`: Don't create .bak backup files
- `-v, --verbose`: Show detailed change information
- `-i, --interactive`: Ask for confirmation before changes
- `-l, --language LANG`: Specify language(s) to process

#### `sync_content_updates.pl`
Content synchronization tool that:
- Updates hosting provider references based on English source
- Fixes technical references (server counts, domains)
- Updates Windows instructions to modern format
- Preserves translation text while updating factual content

**Usage:**
```bash
# Update hosting references only
perl sync_content_updates.pl --hosting

# Update technical references for specific languages
perl sync_content_updates.pl --technical -l es -l it -l pt

# Full content sync with dry run
perl sync_content_updates.pl --all --dry-run
```

**Options:**
- `--hosting`: Only update hosting provider references
- `--technical`: Only update technical references
- `--all`: Update all content types (default)

### Orchestration Tools

#### `batch_translation_processor.pl`
Comprehensive orchestration engine that:
- Processes languages systematically by groups
- Runs full analysis and fixing pipeline
- Generates detailed reports
- Optionally creates git commits for changes

**Usage:**
```bash
# Process Nordic languages
perl batch_translation_processor.pl -g nordic

# Process all production languages (dry run)
perl batch_translation_processor.pl -g production --dry-run

# Process specific languages with git commits
perl batch_translation_processor.pl -l de -l fr -l es --git-commit

# Full processing with detailed report
perl batch_translation_processor.pl -g romance --report romance_report.txt
```

**Language Groups:**
- `nordic`: Danish, Swedish, Norwegian (Bokmål & Nynorsk), Finnish
- `romance`: Spanish, French, Italian, Portuguese, Romanian
- `germanic`: German, Dutch
- `slavic`: Czech, Polish, Russian, Ukrainian, Serbian, Bulgarian
- `asian`: Japanese, Korean, Chinese, Hindi, Vietnamese
- `middle_eastern`: Arabic, Persian, Hebrew, Turkish
- `other`: Greek, Hungarian, Indonesian, Kazakh, Basque, Sinhala, Catalan
- `production`: All production-ready languages
- `testing`: All beta/testing languages

### Legacy Tools

#### `analyze_all_translations.pl`
Original comprehensive analysis tool (now superseded by the new analysis tools above).

#### `check_translations.pl`
.po file sync checker that validates:
- Missing/extra msgids compared to English source
- Empty translations
- Fuzzy translations

**Usage:**
```bash
# Check specific languages
perl check_translations.pl de es fr

# Check default languages (de, da, it, es)
perl check_translations.pl
```

#### `sync_translations.pl`
.po file synchronization helper that:
- Shows missing msgids from English source
- Generates templates for adding missing entries
- Identifies untranslated entries

**Usage:**
```bash
perl sync_translations.pl <language_code>
```

## Workflow Recommendations

### For Systematic Translation Maintenance

1. **Analysis Phase** - Identify issues across all languages:
   ```bash
   perl analyze_html_issues.pl > html_issues.txt
   perl validate_content_consistency.pl > consistency_issues.txt
   perl check_encoding.pl > encoding_issues.txt
   ```

2. **Prioritize** - Focus on languages with the most issues or production languages

3. **Fix Phase** - Apply automated fixes:
   ```bash
   # Test with dry run first
   perl batch_translation_processor.pl -g production --dry-run

   # Apply fixes to high-priority groups
   perl batch_translation_processor.pl -g nordic
   perl batch_translation_processor.pl -g romance
   ```

4. **Validation** - Re-run analysis to confirm fixes

5. **Git Integration** - Commit changes systematically:
   ```bash
   perl batch_translation_processor.pl -g nordic --git-commit
   ```

### For Specific Language Updates

1. **Single Language Analysis**:
   ```bash
   perl analyze_html_issues.pl  # Check for issues in specific language
   ```

2. **Targeted Fixes**:
   ```bash
   perl fix_html_modernization.pl -l de --verbose
   perl sync_content_updates.pl -l de --hosting
   ```

3. **Validation**:
   ```bash
   # Re-run analysis to confirm fixes applied
   ```

### For New Content Updates

When English source content changes (hosting providers, technical details):

1. **Content Sync Across All Languages**:
   ```bash
   perl sync_content_updates.pl --hosting --dry-run  # Preview
   perl sync_content_updates.pl --hosting            # Apply
   ```

2. **Validate Results**:
   ```bash
   perl validate_content_consistency.pl
   ```

## Safety Features

### Backup Protection
- All fixing tools create `.bak` backup files by default
- Use `--no-backup` to disable (not recommended)
- Backups preserve original content for rollback

### Dry Run Mode
- All tools support `--dry-run` for safe preview
- Shows exactly what would be changed without modifications
- Essential for understanding impact before applying fixes

### Template Toolkit Preservation
- All tools preserve Template Toolkit syntax (`[% ... %]`)
- Validate TT block integrity before/after changes
- Prevent breaking dynamic content functionality

### Interactive Mode
- `--interactive` flag for confirmation before changes
- Shows detailed change previews
- Allows selective application of fixes

## Configuration

### Language Groups
Language groups are defined in `batch_translation_processor.pl` and can be customized for specific processing needs.

### HTML Entity Mappings
HTML entity to UTF-8 mappings are defined in individual tools and can be extended for additional character sets.

### Expected Character Sets
Language-specific expected characters are defined in `check_encoding.pl` for validation purposes.

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure tools are executable (`chmod +x *.pl`)

2. **Missing Dependencies**: Ensure Perl modules are available:
   - `JSON::XS`
   - `File::Copy`
   - `Getopt::Long`

3. **Git Integration**: Ensure you're in a git repository root when using `--git-commit`

4. **Template Toolkit Errors**: If TT validation fails, check for:
   - Unclosed `[% ... %]` blocks
   - Missing Template Toolkit syntax in modified content

### Tool-Specific Issues

**analyze_html_issues.pl**:
- Requires `i18n/languages.json` to exist
- Must be run from repository root directory

**fix_html_modernization.pl**:
- Validates TT syntax before applying changes
- May skip files with validation errors

**sync_content_updates.pl**:
- Depends on English source files being available
- Uses `docs/ntppool/en/` as authoritative reference

**batch_translation_processor.pl**:
- Requires all individual tools to be present in `i18n/tools/`
- May fail if repository is not in clean git state (when using `--git-commit`)

## Development

### Adding New Languages
1. Add language code to `i18n/languages.json`
2. Create translation files in `docs/ntppool/<lang>/`
3. Add language-specific character expectations to `check_encoding.pl` if needed

### Extending Analysis
New analysis patterns can be added to respective tools:
- HTML patterns in `analyze_html_issues.pl`
- Content patterns in `validate_content_consistency.pl`
- Encoding patterns in `check_encoding.pl`

### Custom Language Groups
Modify the `%language_groups` hash in `batch_translation_processor.pl` to create custom processing groups.

## Contributing

When modifying these tools:

1. **Test thoroughly** with `--dry-run` before applying changes
2. **Preserve existing functionality** and safety features
3. **Update documentation** for new features or changed behavior
4. **Test with multiple languages** to ensure broad compatibility
5. **Validate Template Toolkit preservation** for any HTML-modifying changes

## Support

For issues with these tools:
1. Check this README for troubleshooting steps
2. Run tools with `--verbose` for detailed error information
3. Use `--dry-run` to isolate issues without making changes
4. Review backup files (`.bak`) if unexpected changes occur
