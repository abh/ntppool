local params = std.extVar('__ksonnet/params');
local globals = import 'globals.libsonnet';
local envParams = params {
  components+: {
    ns+: {
      name: 'ntppool',
    },
    secrets+: {
      data+: import 'secrets.libsonnet',
    },
    ntppool+: {
      replicas: 3,
      #image: 'quay.io/ntppool/ntppool:c0d0d7d',
    },
    config+: {
      data+: {
        auth0_client: 'kDlOYWYyIQlLMjgyzrKJhQmARaM8rOaM',
        auth0_domain: 'login.ntppool.org',
        #auth0_domain: 'ntp.auth0.com',

        db_dsn: 'dbi:mysql:database=ntppool;host=ntp-db-mysql-master.ntpdb;mysql_enable_utf8=1',
        db_user: 'ntppool',

        deployment_mode: 'prod',

        email_default: 'ask@ntppool.org',
        email_help: 'help@ntppool.org',
        email_notifications: 'ask@ntppool.org',
        email_sender: 'ask@ntppool.org',
        email_support: 'server-owner-help@ntppool.org',
        email_vendors: 'vendors@ntppool.org',

        manage_hostname: 'manage.ntppool.org',
        pool_domain: 'pool.ntp.org',
        # static_base: 'https://st.pimg.net/ntppool/',
        static_base: '/static/',
        www_cname: 'www-lb.ntppool.org.',

        web_tls: 'yes',
        web_hostname: 'www.ntppool.org,api.ntppool.org,www.pool.ntp.org',
        // web_hostname: 'www2.ntppool.org',
      },
    },
    smtp+: {
      settings+: {
        relay_networks: ':10.2.0.0/16:10.3.0.0/16:10.42.0.0/16',
        smarthost_address: 'smtp.sparkpostmail.com',
        smarthost_port: '587',
        smarthost_user: 'SMTP_Injection',
      },
    },
  },
};

{
  components: {
    [x]: envParams.components[x] + globals
    for x in std.objectFields(envParams.components)
  },
}
