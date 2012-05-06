all: templates

templates:
	(cd docs/manage/tpl/client; hulk *.html > ../../../shared/static/js/admin-templates.js)
