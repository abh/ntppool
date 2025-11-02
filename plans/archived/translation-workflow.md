# Suggested Translation Workflow for NTP Pool

## Quick Start Workflow (No Infrastructure Required)

Since you mentioned having no existing translation workflow, here's a simple process you can implement immediately using just Claude Code and Git:

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

## Simple Folder-Based Workflow

Create this structure to track translation work:

```
translations/
├── todo/
│   ├── 2024-01-15-english-changes.md
│   └── missing-critical.md
├── in-progress/
│   ├── de-update-2024-01.md
│   └── ja-update-2024-01.md
└── completed/
    └── 2024-01-archive/
```

## Minimal Git Workflow

### For Translator Volunteers

1. **Create branch for each language update:**
   ```bash
   git checkout -b translation-de-2024-01
   ```

2. **Make changes with Claude Code:**
   ```bash
   claude-code "Update German translations in i18n/de.po"
   ```

3. **Create pull request with summary:**
   ```bash
   git push origin translation-de-2024-01
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
   git tag translations-2024-01-stable
   ```

## Priority Language Tiers

Given your resource constraints, prioritize languages in tiers:

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

## Simple Quality Checklist

Before committing any translation update:

```markdown
- [ ] Run: `msgfmt -c i18n/[lang].po` (syntax check)
- [ ] Verify: No English text in msgstr (except technical terms)
- [ ] Check: All %1, %2 placeholders match
- [ ] Confirm: HTML files have matching structure to English
- [ ] Test: At least one page loads correctly
```

## Volunteer Coordination (Minimal Setup)

1. **Create a simple tracking document:**
   ```markdown
   # NTP Pool Translation Status

   ## Language Coordinators
   - German: @volunteer1
   - Japanese: @volunteer2
   - Spanish: @volunteer3

   ## Last Updated
   - de: 2024-01-15 (volunteer1)
   - ja: 2024-01-10 (volunteer2)
   - es: 2024-01-08 (volunteer3)
   ```

2. **Use GitHub Issues for coordination:**
   - Tag: `translation-needed`
   - Template: "English [file] updated on [date], needs translation to [languages]"

3. **Monthly volunteer email:**
   ```
   Subject: NTP Pool Translation Update - January 2024

   This month's changes:
   - 5 new strings in join.html
   - Updated server scoring explanation
   - New error messages added

   Priority languages needing update: de, ja, zh
   ```

## Getting Started This Week

1. **Monday:** Run missing translation report
2. **Tuesday:** Update one Tier 1 language
3. **Wednesday:** Update another Tier 1 language
4. **Thursday:** Check consistency across updated languages
5. **Friday:** Document what needs volunteer help

## Tools You'll Need

- **Git** (already have)
- **msgfmt** (part of gettext-tools)
- **Claude Code** (for automation)
- **Text editor** (for manual review)

That's it! No complex infrastructure needed. Start simple and build up as needed.
