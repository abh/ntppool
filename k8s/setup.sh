#!/bin/sh
kubectl create ns ntpbeta
KUBE="kubectl -n ntpbeta"

$KUBE apply -f ntppool-quay-secrets.yaml

for f in ??-*.yaml; do
  $KUBE apply -f $f
done

sh setup-ingress.sh

