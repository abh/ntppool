# NTP Pool Translation Maintenance Roadmap

## Overview

This document provides a comprehensive, prioritized action plan for achieving accurate and complete translations across all 37 supported languages in the NTP Pool project. The roadmap addresses critical findings from the December 2025 content review that revealed significant gaps in previously "perfect sync" languages.

## 🎯 Mission Critical Issues (Week 1-2)

### Content Accuracy Fixes for "Perfect Sync" Languages

#### 1. Spanish (es) - HIGH PRIORITY
**Status**: ⚠️ Partially fixed, needs completion
**Issues Found**:
- Missing geographic server explanation paragraph in `use.html`
- HTML entity inconsistencies (&aacute; vs á)
- Incomplete content structure compared to English

**Tasks**:
- [x] Complete fix of missing paragraph about geographic server selection
- [x] Convert all HTML entities to proper UTF-8 characters
- [x] Verify all 5 HTML files have complete content structure
- [x] Test RTL/LTR handling for mixed content

**Files to Fix**:
- `docs/ntppool/es/use.html` (primary)
- `docs/ntppool/es/join.html` (verify completeness)
- `docs/ntppool/es/join/configuration.html` (verify completeness)

#### 2. German (de) - HIGH PRIORITY
**Status**: 🔴 Multiple encoding and content issues
**Issues Found**:
- Extensive HTML entity usage (&uuml;, &auml;, &szlig;) instead of UTF-8
- Content structure differences from English source
- Potentially missing technical explanations

**Tasks**:
- [x] Convert HTML entities to proper German characters (ü, ä, ß)
- [x] Paragraph-by-paragraph content comparison with English source
- [x] Verify technical command accuracy (`ntpq -pn`, `ntpdate`, etc.)
- [x] Ensure formal German tone consistency

**Files to Fix**:
- `docs/ntppool/de/use.html` (primary issue)
- `docs/ntppool/de/join.html` (review needed)
- `docs/ntppool/de/join/configuration.html` (review needed)
- `docs/ntppool/de/homepage/intro.html` (review needed)

#### 3. Content Review for Remaining "Perfect Sync" Languages
**Languages to Review**: da, el, fi, fr, hi, it, ja, ko, nb, nl, nn, pt, ru, sr, sv, tr, uk, zh

**Tasks for Each Language**:
- [ ] Line-by-line comparison with English source files
- [ ] Verify all technical terms are correctly translated
- [ ] Check for missing paragraphs or content sections
- [ ] Validate HTML encoding (UTF-8 vs entities)
- [ ] Ensure Template Toolkit syntax is preserved
- [ ] Verify link accuracy and email addresses

**Priority Order** (based on usage and production status):
1. **French (fr)** - Major production language
2. **Italian (it)** - Major production language
3. **Portuguese (pt)** - Major production language
4. **Russian (ru)** - Major production language
5. **Japanese (ja)** - Major production language
6. **Dutch (nl)** - Production language
7. **Finnish (fi)** - Production language
8. **Others** - Systematic review

## 🚨 Critical Missing Content (Week 2-3)

### 4. Complete Missing HTML Files

#### Polish (pl) - CRITICAL
**Status**: 🔴 Only 1/5 files exist
**Missing Files**:
- [x] `docs/ntppool/pl/homepage/intro.html`
- [x] `docs/ntppool/pl/join.html`
- [x] `docs/ntppool/pl/join/configuration.html`
- [x] `docs/ntppool/pl/tpl/server/graph_explanation.html`

**Existing**: `docs/ntppool/pl/use.html` (verify accuracy)

#### Hebrew (he) - HIGH PRIORITY
**Status**: 🔴 3/5 files exist, missing 2 critical files
**Missing Files**:
- [x] `docs/ntppool/he/join/configuration.html`
- [x] `docs/ntppool/he/use.html`

**Existing Files to Verify**:
- [ ] `docs/ntppool/he/homepage/intro.html` (RTL layout verification)
- [ ] `docs/ntppool/he/join.html` (RTL layout verification)
- [ ] `docs/ntppool/he/tpl/server/graph_explanation.html` (RTL layout verification)

**Special Requirements for Hebrew**:
- [ ] RTL (right-to-left) layout verification
- [ ] Mixed LTR/RTL content handling (commands, URLs)
- [ ] Hebrew typography conventions
- [ ] UTF-8 encoding verification

#### Romanian (ro) - HIGH PRIORITY
**Status**: 🔴 0/5 files exist, .po file needs major updates
**Missing Files** (create all):
- [x] `docs/ntppool/ro/homepage/intro.html`
- [x] `docs/ntppool/ro/join.html`
- [x] `docs/ntppool/ro/join/configuration.html`
- [x] `docs/ntppool/ro/tpl/server/graph_explanation.html`
- [x] `docs/ntppool/ro/use.html`

**Additional Tasks**:
- [x] Fix .po file (13 missing msgids, 6 obsolete)

#### Basque (eu) - HIGH PRIORITY
**Status**: 🔴 0/5 files exist, .po file severely incomplete
**Missing Files** (create all):
- [ ] `docs/ntppool/eu/homepage/intro.html`
- [ ] `docs/ntppool/eu/join.html`
- [ ] `docs/ntppool/eu/join/configuration.html`
- [ ] `docs/ntppool/eu/tpl/server/graph_explanation.html`
- [ ] `docs/ntppool/eu/use.html`

**Additional Tasks**:
- [ ] Fix .po file (31 missing msgids, 2 obsolete)

#### Sinhalese (si) - MEDIUM PRIORITY
**Status**: 🔴 1/5 files exist
**Missing Files**:
- [ ] `docs/ntppool/si/join.html`
- [ ] `docs/ntppool/si/join/configuration.html`
- [ ] `docs/ntppool/si/tpl/server/graph_explanation.html`
- [ ] `docs/ntppool/si/use.html`

**Existing**: `docs/ntppool/si/homepage/intro.html` (verify accuracy)
**Additional Tasks**:
- [ ] Fix .po file (6 missing msgids, 7 obsolete)

### 5. Kazakh (kk) - Special Case
**Status**: 🔴 No .po file, 3/5 HTML files exist
**Tasks**:
- [ ] Create complete .po file with all 40 required msgids
- [ ] Create missing files:
  - `docs/ntppool/kk/join/configuration.html`
  - `docs/ntppool/kk/tpl/server/graph_explanation.html`

## 🔧 .po File Completeness (Week 3-4)

### 6. Fix Missing .po Entries

#### Croatian (hr) - HIGH PRIORITY
**Status**: 🔴 Missing 20 msgids, 6 obsolete
**Tasks**:
- [x] Add 20 missing navigation and forum entries
- [x] Remove 6 obsolete mailing list entries
- [x] Verify Croatian language conventions

#### Traditional Chinese (zh_TW) - MEDIUM PRIORITY
**Status**: 🔴 Missing 12 msgids, 6 obsolete
**Tasks**:
- [x] Add 12 missing navigation entries
- [x] Remove 6 obsolete mailing list entries
- [x] Verify Traditional Chinese character usage
- [x] Ensure distinction from Simplified Chinese

#### Bulgarian (bg) - LOW PRIORITY
**Status**: ✅ Mostly complete, 1 missing msgid
**Tasks**:
- [x] Add missing "Discussion list" msgid
- [x] Verify Bulgarian translations are accurate

## 🛠️ Infrastructure and Tooling (Week 4-5)

### 7. Enhanced Analysis Tools

#### Content Comparison Tool
**File**: `analyze_content_accuracy.pl`
**Purpose**: Paragraph-by-paragraph comparison of translations vs English source

**Features to Implement**:
- [ ] Line-by-line content structure comparison
- [ ] Technical term consistency checking
- [ ] HTML entity vs UTF-8 detection
- [ ] Template Toolkit syntax validation
- [ ] Missing paragraph detection
- [ ] Link and email validation

#### HTML Encoding Fixer
**File**: `fix_html_entities.pl`
**Purpose**: Convert HTML entities to proper UTF-8 characters

**Languages Needing Entity Fixes**:
- [ ] German (de) - High priority
- [ ] Spanish (es) - Medium priority
- [ ] Others as discovered during review

#### Translation Template Generator
**File**: `generate_translation_templates.pl`
**Purpose**: Create HTML file templates for missing translations

**Features**:
- [ ] Generate template with English content and translation markers
- [ ] Preserve HTML structure and Template Toolkit syntax
- [ ] Include technical terms that shouldn't be translated
- [ ] Generate appropriate language-specific character encoding

### 8. Quality Assurance Framework

#### Automated Testing
- [ ] Content completeness validation
- [ ] HTML syntax validation
- [ ] Template Toolkit syntax checking
- [ ] Link validation
- [ ] UTF-8 encoding verification

#### Review Checklist Enhancement
**Update existing checklist to include**:
- [ ] Paragraph-by-paragraph content match
- [ ] Technical term consistency
- [ ] Cultural appropriateness
- [ ] HTML encoding verification
- [ ] RTL layout validation (for Arabic, Hebrew, Persian)
- [ ] Character encoding verification (for Asian languages)

## 📋 Systematic Review Process (Week 5-8)

### 9. Production Language Deep Review

#### Phase 1: Major European Languages (Week 5)
**Languages**: de, es, fr, it, pt, ru
**Process**:
1. Content accuracy verification
2. Technical term standardization
3. HTML encoding fixes
4. Cultural appropriateness review

#### Phase 2: Nordic and Northern European (Week 6)
**Languages**: da, fi, nl, sv, nb, nn
**Process**:
1. Content structure verification
2. Technical accuracy review
3. Regional variant appropriateness

#### Phase 3: Asian Languages (Week 7)
**Languages**: ja, ko, zh, hi
**Process**:
1. Character encoding verification
2. Formal/informal tone consistency
3. Technical term localization review
4. Text expansion/contraction handling

#### Phase 4: Other Production Languages (Week 8)
**Languages**: el, sr, tr, uk
**Process**:
1. Content completeness verification
2. Character set and encoding review
3. Cultural adaptation verification

### 10. Beta Language Prioritization

#### Tier 1 Beta Languages (Complete Support Priority)
**Languages**: ar, ca, hu, id, vi
**Tasks**:
- [ ] Content accuracy verification
- [ ] Promote to production status if quality sufficient

#### Tier 2 Beta Languages (Major Fixes Needed)
**Languages**: bg, fa, he, hr, kk, pl, ro, si, zh_TW
**Tasks**:
- [ ] Complete missing files and content
- [ ] Fix .po file issues
- [ ] Content accuracy review

#### Tier 3 Beta Languages (Rebuild Required)
**Languages**: eu
**Tasks**:
- [ ] Complete rebuild from English templates
- [ ] Find qualified Basque translator
- [ ] Implement full HTML file set

## 📊 Success Metrics and Milestones

### Week 1-2 Targets
- [x] Spanish content gaps fixed
- [x] German HTML entities converted
- [ ] 5 major production languages content-verified

### Week 3-4 Targets
- [x] Polish HTML files created
- [x] Hebrew HTML files created
- [x] Croatian .po file fixed
- [x] Traditional Chinese .po file fixed

### Week 5-8 Targets
- [ ] All production languages content-verified
- [ ] All beta languages file-complete
- [ ] Enhanced tooling implemented
- [ ] Quality assurance framework operational

### Final Success Criteria
- [ ] All 37 languages have complete 5-file HTML sets
- [ ] All .po files have 40 required msgids
- [ ] Content accuracy verified against English source
- [ ] No HTML entity encoding issues
- [ ] RTL languages properly validated
- [ ] Automated quality assurance operational

## 🔄 Maintenance Process

### Monthly Tasks
- [ ] Run comprehensive analysis tool
- [ ] Review any new English source changes
- [ ] Update hosting provider references as needed
- [ ] Verify link accuracy

### Quarterly Tasks
- [ ] Full content accuracy review for production languages
- [ ] Beta language quality assessment for promotion
- [ ] Tooling updates and improvements
- [ ] Translation contributor recognition

### Annual Tasks
- [ ] Complete infrastructure reference updates
- [ ] Major version synchronization with English changes
- [ ] Translation contributor recruitment
- [ ] Documentation updates

## 👥 Resource Requirements

### Translation Expertise Needed
- **Native speakers** for content accuracy review
- **Technical translators** familiar with NTP/networking concepts
- **RTL language specialists** for Arabic, Hebrew, Persian
- **CJK specialists** for Chinese, Japanese, Korean

### Development Resources
- **Perl scripting** for enhanced analysis tools
- **HTML/CSS expertise** for RTL layout validation
- **Template Toolkit knowledge** for syntax preservation
- **UTF-8/encoding expertise** for character set issues

## 📞 Escalation and Support

### Translation Quality Issues
- **Technical accuracy**: Consult with NTP Pool maintainers
- **Cultural appropriateness**: Engage native speaker community
- **Missing expertise**: Post requests in project community forum

### Tool Development Issues
- **Perl scripting problems**: Reference existing tool patterns
- **Complex analysis needs**: Iterate on tool requirements
- **Performance issues**: Optimize for codebase size

---

**Document Owner**: Translation Maintenance Team
**Last Updated**: 2025-01-05
**Review Frequency**: Weekly during active implementation, monthly during maintenance
**Success Tracking**: translation-status.md updated weekly with progress

This roadmap provides the systematic approach needed to achieve truly accurate and complete translations across all NTP Pool supported languages.
