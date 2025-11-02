I need you to help maintain translations for the NTP Pool website. The English source files are in:
- i18n/en.po (gettext format)
- docs/ntppool/en/ (HTML templates)

The translations are in:
- i18n/[language-code].po
- docs/ntppool/[language-code]/

Please review every translation for accuracy and completeness.

Update @plans/translation-status.md with the information and then proceed to implement the fixes.

Be careful to preserve technical terms or names of commands, email addresses and web pages. Preserve HTML markup, or make it match the English source. Be careful with the template toolkit syntax, for example for page titles: `[% page.title = 'Join the NTP Pool!' %]`

On edited lines, if possible wrap the lines around 75 character width to make future diffs easier. Only do this to lines that are being edited anyway.
