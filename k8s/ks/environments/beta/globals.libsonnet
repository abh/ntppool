{
  deployment_mode: 'test',
  imagePullSecrets: [{name: 'ntppool-ntpkube-pull-secret'}],

  ingress_class: 'haproxy',
}
