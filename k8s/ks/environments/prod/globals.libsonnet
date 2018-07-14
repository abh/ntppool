{
  deployment_mode: 'prod',
  imagePullSecrets: [{name: 'ntppool-ntpkube-pull-secret'}],
  ingress_class: 'haproxy',
  cronSuspend: true,
}
