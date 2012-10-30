# User interface files

There is [information for translators](http://www.pool.ntp.org/en/translators.html)
on the website. If you are looking to translate to a new language or update a translation,
look there first.

## HTML Templates

We use [template toolkit](http://www.template-toolkit.org) to template
the server generated html. For the www site the templates are in
`docs/ntppool`, the manage site files are in `docs/manage` and files
used across both are in `docs/shared`.

Under any of these paths there's a `tpl/` directory for "internal
resources" (files that are included from user visible files).

The "layout template" is in `docs/shared/tpl/style/default.html`.

## CSS

The CSS files for both the www and the manage site are in
`docs/shared/static/css`. They are currently shared across both sites.

In production some files get concatenated and served as one according
to the configuration in `docs/shared/static/.static.groups.json`.

## Javascript

Similar to the CSS files the javascript files are in
`docs/shared/static/js`.

## Issue tracker

The [issue tracker](https://github.com/abh/ntppool/issues) for the
project is the best place to report issues (and find things that need
improvement).
