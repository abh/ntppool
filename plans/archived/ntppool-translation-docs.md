# NTP Pool Translation Maintenance Documentation

## Overview

This documentation provides guidance for using Claude Code to maintain translations for the NTP Pool website. The system uses:
- **Gettext format (.po files)** in `i18n/[language-code].po`
- **HTML template files** in `docs/ntppool/[language-code]/`
- **Locale::Maketext** for processing .po files
- **Custom Template Toolkit filters** for rendering translations

## Translation Workflow Process

### 1. Daily Translation Sync
Run this check daily to identify changes in English source files:

```bash
# Check for modified English files
git diff --name-only HEAD~1 HEAD | grep -E "(en\.po|docs/ntppool/en/)"

# Generate diff report for translators
claude-code translate-diff --source=en --report
```

### 2. Weekly Consistency Check
Ensure all languages have the same msgids and no orphaned translations:

```bash
# Run consistency check across all languages
claude-code check-consistency --all-languages

# Generate missing translation report
claude-code missing-translations --format=csv > missing_$(date +%Y%m%d).csv
```

### 3. Monthly Quality Review
Review translations for accuracy and style:

```bash
# Generate review candidates (recently changed translations)
claude-code review-candidates --days=30 --languages=de,fr,es,ja,zh
```

## File Structure

```
ntppool/
├── i18n/
│   ├── en.po          # English source
│   ├── de.po          # German translations
│   ├── es.po          # Spanish translations
│   ├── ja.po          # Japanese translations
│   └── [lang].po      # Other language translations
└── docs/ntppool/
    ├── en/
    │   ├── homepage.html
    │   ├── join.html
    │   └── use.html
    └── [lang]/
        └── [same structure as en/]
```

## Key Translation Rules

### For .po Files
1. **Never modify msgid** - only msgstr should be translated
2. **Preserve placeholders** - Keep %1, %2, etc. in the same positions
3. **Maintain HTML tags** - Don't translate or modify HTML within strings
4. **Context matters** - Check comments for usage context

### For HTML Templates
1. **Preserve all Perl Template Toolkit syntax** - Don't translate [% %] blocks
2. **Keep URLs intact** - Don't translate web addresses
3. **Maintain structure** - Keep the same HTML structure as English version
4. **Update page.title** - This often appears at the top of templates

## Common Issues and Solutions

### Issue: Outdated Translations
**Symptom**: Translation doesn't match current English functionality
**Solution**: Use `claude-code sync-translation --lang=XX --file=YY` to update

### Issue: Missing Placeholders
**Symptom**: %1 or %2 missing in translated string
**Solution**: Review English version and ensure all placeholders are preserved

### Issue: Broken HTML
**Symptom**: Page displays incorrectly
**Solution**: Validate HTML structure matches English template

### Issue: Fuzzy Translations
**Symptom**: Lines marked with `#, fuzzy` in .po files
**Solution**: Review and update these translations, then remove fuzzy flag

## Language-Specific Guidelines

### European Languages (de, fr, es, it, etc.)
- Maintain formal tone for technical content
- Use appropriate regional variants (e.g., European vs Latin American Spanish)

### Asian Languages (ja, zh, ko)
- Pay attention to character encoding (UTF-8)
- Consider text expansion (translations may be longer/shorter)
- Use appropriate formal/polite forms

### RTL Languages (ar, he, fa)
- Ensure proper RTL markup in HTML
- Test layout thoroughly
- Keep Latin text (like commands) in LTR

## Quality Checklist

Before committing translations:
- [ ] All msgids have corresponding msgstr
- [ ] No fuzzy translations remain
- [ ] Placeholders match between source and translation
- [ ] HTML structure is preserved
- [ ] Links point to correct locations
- [ ] Technical terms are consistently translated
- [ ] File encoding is UTF-8
- [ ] No untranslated English text remains (except where appropriate)

## Glossary of Key Terms

| English | Description | Notes |
|---------|-------------|-------|
| pool | The NTP server pool | Often kept as "pool" in many languages |
| time server | NTP server | Technical term - check existing translations |
| stratum | Server hierarchy level | Technical term - often untranslated |
| offset | Time difference | Technical measurement |
| score | Server reliability metric | May need explanation in some languages |

## Contact and Resources

- **Translation questions**: Ask on the development forum
- **Technical issues**: Create GitHub issue
- **Style guides**: Check existing translations in your language
- **Testing**: Use local development environment before committing
