#!/bin/sh

KUBE="kubectl -n ntpbeta"

cfg="`$KUBE get cm/ntppool-env -o json | jq .data`"

export hostnames=`echo $cfg | jq -r '.web_hostname'`  # | split(",") | .[]'
export manage_hostnames=`echo $cfg | jq -r '.manage_hostname'`
export web_tls=`echo $cfg | jq -r '.web_tls'`

sigil -f ./tmpl/ingress-web.tmpl -p | $KUBE apply -f -
sigil -f ./tmpl/ingress-manage.tmpl -p | $KUBE apply -f -
