# Claude Code Prompts for NTP Pool Translation Maintenance

## 1. Initial Translation Sync Check

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

## 2. Update Specific Translation

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

## 3. Consistency Check Across Languages

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

## 4. HTML Template Translation Update

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

## 5. Missing Translation Report

```
Generate a missing translation report for the NTP Pool project.

Please:
1. Check all active languages: da, de, es, fr, it, ja, ko, nl, pt, ru, zh
2. For each language's .po file, count:
   - Total msgids
   - Translated msgstr (non-empty)
   - Fuzzy translations
   - Missing translations (empty msgstr)
3. For HTML templates, list which files exist in English but not in each language
4. Create a CSV report with columns:
   Language, Total Strings, Translated, Fuzzy, Missing, Percentage Complete, Missing HTML Files

Focus on identifying languages that need the most attention.
```

## 6. Review Recent Translations

```
Review recent Spanish translations for quality and accuracy.

For i18n/es.po:
1. Find all translations that have been modified recently (you can identify these by looking for completed msgstr entries)
2. For each translation, check:
   - Are technical terms appropriately translated or left in English?
   - Do translations maintain the same level of formality as English?
   - Are placeholders (%1, %2) in the correct positions?
   - Is the translation length reasonable (not too verbose)?
   - For HTML content, are tags properly preserved?

Provide feedback on any translations that may need improvement, explaining why.
```

## 7. Fix Common Translation Issues

```
Please scan all language files and fix these common issues:

1. Trailing whitespace in msgstr entries - remove it
2. Missing ending punctuation that exists in msgid - add matching punctuation
3. Double spaces within translations - reduce to single space
4. Placeholder mismatches - ensure %1, %2 etc. appear in msgstr if they're in msgid
5. Empty msgstr for critical UI elements (like navigation) - flag these for urgent translation

For each fix:
- Show the before and after
- Indicate which file and line number
- Group by language

Don't attempt to translate empty msgstr - just flag them.
```

## 8. Prepare Translation Status Dashboard

```
Create a translation status overview for all supported languages.

Please analyze:
1. Coverage percentage for each language (both .po and HTML files)
2. Number of fuzzy translations that need review
3. Age of translations (identify potentially outdated content)
4. Critical missing translations (navigation, errors, key instructions)

Format as a markdown table that I can share with volunteer translators, highlighting:
- 🟢 Green: >90% complete, no fuzzy
- 🟡 Yellow: 70-90% complete or has fuzzy entries
- 🔴 Red: <70% complete

Include specific action items for each language.
```

## Usage Tips

1. **Start with language pairs** - Work on one language at a time to avoid confusion
2. **Always preserve formatting** - Gettext files are sensitive to formatting
3. **Test locally** - Mention you'll need to test rendering after changes
4. **Keep context** - Always consider where strings are used in the interface
5. **Document changes** - Ask Claude Code to summarize what was changed

## Example Workflow

```bash
# Monday: Check for English changes
claude-code "Check what changed in English source files since last week"

# Tuesday-Thursday: Update translations
claude-code "Update German translations for changed English strings"
claude-code "Update Japanese translations for changed English strings"

# Friday: Quality check
claude-code "Run consistency check across all languages"
claude-code "Generate missing translation report"
```
