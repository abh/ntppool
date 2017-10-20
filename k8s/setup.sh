#!/bin/sh
kubectl create ns ntpbeta
KUBE="kubectl -n ntpbeta"

$KUBE rollout pause deploy ntppool

$KUBE apply -f ntppool-quay-secrets.yaml

for f in ??-*.yaml; do
  $KUBE apply -f $f
done

$KUBE rollout resume deploy ntppool

sh setup-ingress.sh

