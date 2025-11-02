# NTP Pool Translation Workflow Guide

**Created from consolidation of multiple translation planning documents**

## Overview

This guide provides comprehensive workflows and tools for maintaining translations across the NTP Pool's 37 supported languages. Following the successful July 2025 translation campaign, this workflow helps maintain ongoing translation quality and completeness.

## Current Status (Post-July 2025 Campaign)

- **37 languages** with complete PO file coverage (100%)
- **35/37 languages** with complete HTML coverage (94.6%)
- **23 production languages** fully stable and supported
- **12 languages promoted** from testing to production status

## Quick Start Workflow (Claude Code Based)

### Daily Routine (5 minutes)

```bash
# 1. Check what changed in English
git log --oneline -n 10 -- i18n/en.po docs/ntppool/en/

# 2. If changes found, ask Claude Code:
claude-code "Compare yesterday's English files with today's and list what text changed"
```

### Weekly Translation Update (Per Language)

```bash
# 1. Pick a language to update (e.g., German)
claude-code "Update German translations for any changed English strings from the past week"

# 2. Review the changes
claude-code "Show me a summary of German translations that need human review"

# 3. Commit changes
git add i18n/de.po docs/ntppool/de/
git commit -m "Update German translations - $(date +%Y-%m-%d)"
```

### Monthly Health Check

```bash
# 1. Overall status
claude-code "Generate translation completion status for all languages"

# 2. Find critical gaps
claude-code "List navigation and error messages missing translations in any language"

# 3. Consistency check
claude-code "Check if key technical terms are translated consistently"
```

## Claude Code Prompts for Translation Maintenance

### 1. Initial Translation Sync Check

```
I need you to help maintain translations for the NTP Pool website. The English source files are in:
- i18n/en.po (gettext format)
- docs/ntppool/en/ (HTML templates)

The translations are in:
- i18n/[language-code].po
- docs/ntppool/[language-code]/

Please:
1. Compare i18n/en.po with i18n/de.po and identify any msgids in English that are missing or different in German
2. List any msgstr entries that are empty or marked as fuzzy
3. Check if all HTML files in docs/ntppool/en/ have corresponding files in docs/ntppool/de/
4. For any differences found, show me the English text and current German translation side by side

Use Locale::Maketext conventions and remember that Template Toolkit syntax [% %] should never be translated.
```

### 2. Update Specific Translation

```
I need to update the German translations for recent changes in English.

The English file i18n/en.po has been updated with new strings. Please:
1. Read i18n/en.po and i18n/de.po
2. For each msgid in en.po that's missing from de.po, add it to de.po with an empty msgstr
3. For any changed msgids, mark the old translation as fuzzy with "#, fuzzy" comment
4. Preserve all formatting, comments, and file structure
5. Show me a diff of the changes you're making

Important: Only modify msgstr values, never change msgid. Keep all placeholders like %1, %2 in the same positions.
```

### 3. HTML Template Translation Update

```
I need to update the Japanese version of the join.html page.

Please:
1. Read docs/ntppool/en/join.html and docs/ntppool/ja/join.html
2. Identify sections in the English version that are missing or different in Japanese
3. For any Template Toolkit code [% %], ensure it remains exactly the same
4. Preserve all HTML structure and attributes
5. Update the Japanese file while keeping:
   - All URLs unchanged
   - All email addresses unchanged
   - All technical commands (like ntpdate, ntpq) unchanged
   - The page.title variable translated appropriately

Show me the sections that need updating with current Japanese and proposed changes.
```

### 4. Consistency Check Across Languages

```
Please check translation consistency across multiple languages for the NTP Pool project.

Check these languages: es, fr, ja, de
Focus on these key terms that should be consistently translated:
- "pool"
- "time server"
- "score"
- "offset"
- "stratum"

For each term:
1. Show how it's translated in each language's .po file
2. Identify any inconsistencies within the same language
3. Flag if critical UI strings are missing in any language
4. Check that placeholders (%1, %2, etc) match the English version

Output a report grouped by term showing all translations.
```

## Priority Language Tiers

### Tier 1 (Update Weekly)
- **de** (German) - Large user base
- **ja** (Japanese) - Significant usage
- **zh** (Chinese) - Growing usage
- **fr** (French) - Wide geographic distribution

### Tier 2 (Update Bi-weekly)
- **es** (Spanish) - Americas coverage
- **ru** (Russian) - Eastern coverage
- **nl** (Dutch) - Host country
- **pt** (Portuguese) - Brazil usage

### Tier 3 (Update Monthly)
- All other active languages

## Translation Standards and Guidelines

### Required .po msgid Entries (40 total)
Every language file should contain exactly these 40 message IDs:

#### Navigation & Core
- `go up`, `Translations`

#### Geographic Zones
- `Africa`, `Asia`, `North America`, `South America`, `Europe`, `Oceania`, `Global`
- `All Pool Servers`

#### Index Page
- `Introduction`, `Active Servers`, `Links`, `Terms of service`
- `Subscribe in a reader`, `Older news`

#### Forum & Community
- `archive`, `NTP Pool Forum`, `News site`, `Discussion list`, `Development`
- `forum_description`, `news_description`, `development_list_description`

#### Server Management
- `Back to the front page`, `Find`, `Stats for %1`
- `Not active in the pool, monitoring only`, `Zones:`
- `This server is <span class=\"deletion\">scheduled for deletion</span> on %1.`
- `Current score: %1 (only servers with a score higher than %2 are used in the pool)`
- `What do the graphs mean?`, `CSV log`

#### Navigation Sidebar
- `News`, `How do I <i>use</i> pool.ntp.org?`, `How do I <i>join</i> pool.ntp.org?`
- `Information for vendors`, `The mailing lists`, `Additional links`, `Can you translate?`

### Quality Checklist

Before committing any translation update:

```markdown
- [ ] Run: `msgfmt -c i18n/[lang].po` (syntax check)
- [ ] Verify: No English text in msgstr (except technical terms)
- [ ] Check: All %1, %2 placeholders match
- [ ] Confirm: HTML files have matching structure to English
- [ ] Test: At least one page loads correctly
- [ ] All .po msgids have corresponding msgstr
- [ ] No fuzzy translations remain
- [ ] Placeholders (%1, %2) match between source and translation
- [ ] HTML structure is preserved in all files
- [ ] Links point to correct locations
- [ ] Technical terms are consistently translated
- [ ] File encoding is UTF-8
- [ ] No obsolete msgids remain
- [ ] All 5 standard HTML files exist per language
- [ ] Infrastructure references are current
```

### Language-Specific Guidelines

#### RTL Languages (Arabic, Hebrew, Persian)
- Ensure proper UTF-8 encoding
- Test layout thoroughly with RTL text
- Keep Latin text (commands, URLs) in LTR direction

#### Asian Languages (Japanese, Korean, Chinese)
- Pay attention to character encoding (UTF-8)
- Consider text expansion (translations may be longer/shorter)
- Use appropriate formal/polite forms

#### European Languages
- Maintain formal tone for technical content
- Use appropriate regional variants
- Follow local typography conventions

## Analysis Tools

Located in `bin/` directory:

- **`analyze_all_translations.pl`** - Comprehensive analysis of all translation status
- **`check_translations.pl`** - Analyzes .po sync status, finds missing/extra msgids
- **`get_all_active_languages.pl`** - Lists all active languages from languages.json
- **`batch_update_languages.pl`** - Batch update utility for multiple languages
- **`find_missing_translations.pl`** - Identifies translation gaps
- **`extract_translatable_text.pl`** - Extracts new translatable strings

### Usage Examples
```bash
# Check .po sync status for all languages
perl check_translations.pl de da it es nn nb nl sv zh ca

# Get detailed sync info for a specific language
perl sync_translations.pl fr

# Check specific language group
perl check_translations.pl ar fa he  # RTL languages
```

## Git Workflow

### For Translator Volunteers

1. **Create branch for each language update:**
   ```bash
   git checkout -b translation-de-2025-08
   ```

2. **Make changes with Claude Code:**
   ```bash
   claude-code "Update German translations in i18n/de.po"
   ```

3. **Create pull request with summary:**
   ```bash
   git push origin translation-de-2025-08
   # Include translation stats in PR description
   ```

### For Maintainers

1. **Weekly translation sync:**
   ```bash
   # Every Monday
   git checkout -b translation-sync-week-$(date +%U)
   claude-code "Check all languages for missing translations from last week's English changes"
   ```

2. **Tag stable translation sets:**
   ```bash
   git tag translations-2025-08-stable
   ```

## Volunteer Coordination

### Simple Tracking Document
```markdown
# NTP Pool Translation Status

## Language Coordinators
- German: @volunteer1
- Japanese: @volunteer2
- Spanish: @volunteer3

## Last Updated
- de: 2025-08-15 (volunteer1)
- ja: 2025-08-10 (volunteer2)
- es: 2025-08-08 (volunteer3)
```

### GitHub Issues
- Tag: `translation-needed`
- Template: "English [file] updated on [date], needs translation to [languages]"

### Monthly Volunteer Communication
```
Subject: NTP Pool Translation Update - August 2025

This month's changes:
- 5 new strings in join.html
- Updated server scoring explanation
- New error messages added

Priority languages needing update: de, ja, zh
```

## Maintenance Schedule

### Daily (5 minutes)
- Check for English source changes
- Update any critical translations

### Weekly (30 minutes)
- Update Tier 1 languages
- Run consistency checks
- Review volunteer contributions

### Monthly (2 hours)
- Update all language tiers
- Health check across all languages
- Coordinate with volunteer community
- Update status documentation

### Quarterly (4 hours)
- Full content accuracy review
- Tool improvements
- Documentation updates
- Volunteer recognition

## Tools and Dependencies

### Required Software
- **Git** (version control)
- **msgfmt** (part of gettext-tools)
- **Claude Code** (for automation)
- **Text editor** (for manual review)

### Central Configuration
- **`i18n/languages.json`** - Master language configuration file
- **`i18n/ntppool.pot`** - Template file for all translations

## Historical Context

This workflow builds on the successful July 2025 translation campaign that:
- Completed 37 language PO files
- Created missing HTML files for Polish, Hebrew, Romanian
- Fixed major content issues in Greek, Spanish, German
- Promoted 12 languages from testing to production
- Established modern tooling for ongoing maintenance

The current system represents a mature, battle-tested approach to multilingual content management.
