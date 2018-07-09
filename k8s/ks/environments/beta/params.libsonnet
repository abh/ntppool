local params = std.extVar('__ksonnet/params');
local globals = import 'globals.libsonnet';
local envParams = params {
  components+: {
    ns+: {
      name: 'ntpbeta',
    },
    config+: {
      data+: {
        auth0_client: 'B9BhV7ihWP7BErj2w1WqcZujqH9gwF43',
        auth0_domain: 'ntp.auth0.com',

        db_dsn: 'dbi:mysql:database=ntpbeta;host=lax10.ntppool.net;mysql_enable_utf8=1',
        db_user: 'ntpbeta',

        deployment_mode: 'test',

        email_default: 'ask@grundclock.com',
        email_help: 'beta-help@grundclock.com',
        email_notifications: 'ask@grundclock.com',
        email_sender: 'ask@grundclock.com',
        email_support: 'beta-help@grundclock.com',
        email_vendors: 'beta-vendors@grundclock.com',

        manage_hostname: 'manage-beta.grundclock.com,kube-manage.grundclock.com',
        pool_domain: 'beta.grundclock.com',
        static_base: 'https://st.pimg.net/ntpbeta/',
        www_cname: 'beta-lb.ntppool.org.',

        web_tls: 'yes',
        web_hostname: 'web.beta.grundclock.com,graphs-beta.grundclock.com,kube-beta.grundclock.com,www.beta.grundclock.com',
      },
    },
    smtp+: {
      settings+: {
        relay_networks: ':10.2.0.0/16:10.3.0.0/16',
        smarthost_address: 'smtp.sparkpostmail.com',
        smarthost_password: '69bfbe7df516cb93e7d224a3d658431850848cec',
        smarthost_port: '587',
        smarthost_user: 'SMTP_Injection',
      },
    },
    secrets+: {
      data+: import 'secrets.libsonnet',
    },
  },
};

{
  components: {
    [x]: envParams.components[x] + globals
    for x in std.objectFields(envParams.components)
  },
}
