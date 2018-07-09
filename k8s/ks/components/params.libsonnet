{
  global: {
    // User-defined global parameters; accessible to all component and environments, Ex:
    // replicas: 4,
  },
  components: {
    // Component-level parameters, defined initially from 'ks prototype use ...'
    // Each object below should correspond to a component in the components/ directory
    ns: {
      name: 'ntppool',
    },
    config: {
      data: {
        auth0_client: 'QP7HeAG2jRn9QCXxMTOeoIbFcKGmaVZ0',
        auth0_domain: 'ntp.auth0.com',
        db_dsn: 'dbi:mysql:database=ntpbeta;host=192.168.99.1',
        db_user: 'ntpbeta',
        deployment_mode: 'devel',

        email_default: 'ask@grundclock.com',
        email_help: 'beta-help@grundclock.com',
        email_notifications: 'ask@grundclock.com',
        email_sender: 'ask@grundclock.com',
        email_support: 'beta-help@grundclock.com',
        email_vendors: 'beta-vendors@grundclock.com',

        pool_domain: 'ntp-test2.empty.us',
        web_hostname: 'web.ntp.cluster,graphs.ntp.cluster',
        manage_hostname: 'manage.ntp.cluster',
        manage_tls: 'yes',
      },
      name: 'config',
    },
    secrets: {
      name: 'ntppool-secrets',
      data: {},
    },
    quota: {
    },
    smtp: {
      containerPort: 25,
      image: 'namshi/smtp',
      name: 'smtp',
      replicas: 2,
      servicePort: 25,
      type: 'ClusterIP',
      settings: {
        relay_networks: ':10.2.0.0/16:10.3.0.0/16:172.17.0.0/16',
        host: 'ntppool-mail',
        smarthost_address: '',
        smarthost_port: '587',
        smarthost_user: '',
        smarthost_password: '',
      },
    },
    mailhog: {
      enabled: false,
      image: 'mailhog/mailhog',
      name: 'mailhog',
      smtpPort: 1025,
      httpPort: 8025,
      replicas: 1,
      type: 'ClusterIP',
    },
    ntppool: {
      containerPort: 8299,
      image: 'quay.io/ntppool/ntppool:f77db0c',
      name: 'ntppool',
      imagePullSecrets: [],
      replicas: 2,
      servicePort: 80,
      type: 'ClusterIP',
    },
    splash: {
      containerPort: 8050,
      image: 'scrapinghub/splash:latest',
      name: 'splash',
      replicas: 2,
      servicePort: 80,
      type: 'ClusterIP',
    },
    geoip: {
      containerPort: 8009,
      image: 'quay.io/abh/geoipapi:0.2',
      name: 'geoip',
      replicas: 2,
      servicePort: 80,
      type: 'ClusterIP',
    },
  },
}
