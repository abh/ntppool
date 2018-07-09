local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.ntppool;
local config = std.extVar('__ksonnet/params').components.config.data;

local appBase = import 'ntppool-app.libsonnet';

local web_tls = std.objectHas(config, 'web_tls') && config.web_tls == 'yes';
local manage_tls = std.objectHas(config, 'manage_tls') && config.manage_tls == 'yes';


local resourcesLow = {
  limits: {
    cpu: '500m',
    memory: '200Mi',
  },
  requests: {
    cpu: '50m',
    memory: '100Mi',
  },
};

[
  {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: params.name,
    },
    spec: {
      ports: [
        {
          port: params.servicePort,
          targetPort: params.containerPort,
        },
      ],
      selector: {
        app: params.name,
      },
      type: params.type,
    },
  },
  appBase.Deployment {
    name: 'ntppool',
    tier: 'frontend',
    params: params,
    containers: [
      appBase.Container {
        name: 'httpd',
        params: params,
        args: ['/ntppool/docker-run'],
        ports: [
          {
            containerPort: params.containerPort,
          },
        ],
        readinessProbe: {
          failureThreshold: 3,
          httpGet: {
            httpHeaders: [
              {
                name: 'Host',
                value: 'web.ntp.cluster',
              },
            ],
            path: '/combust-healthz',
            port: params.containerPort,
            scheme: 'HTTP',
          },
          initialDelaySeconds: 4,
          periodSeconds: 3,
          successThreshold: 1,
          timeoutSeconds: 1,
        },
      },
      appBase.Container {
        name: 'httpd-cron',
        params: params,
        args: ['/ntppool/bin/cron/runner'],
        resources: resourcesLow,
      },
    ],
  },

  appBase.CronJob {
    name: 'server-notifications',
    schedule: '*/15 * * * *',
    params: params,
    containers: [
      appBase.Container {
        name: 'server-removals',
        params: params,
        args: ['sh', '/ntppool/bin/bad_server_notifications'],
        resources: resourcesLow,
      },
    ],
  },

  appBase.CronJob {
    name: 'server-removals',
    schedule: '50 */3 * * *',
    params: params,
    containers: [
      appBase.Container {
        name: 'server-removals',
        params: params,
        args: ['sh', '/ntppool/bin/bad_server_removals'],
        resources: resourcesLow,
      },
    ],
  },

  appBase.Ingress('web', std.split(config.web_hostname, ','), web_tls),
  appBase.Ingress('manage', std.split(config.manage_hostname, ','), manage_tls),
]
