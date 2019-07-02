local params = std.extVar('__ksonnet/params').components.ntppool;
local config = std.extVar('__ksonnet/params').components.config.data;

local affinity = import 'affinity.libsonnet';

local ingress(name, domains, tls) = {
  apiVersion: 'extensions/v1beta1',
  kind: 'Ingress',
  metadata: {
    name: params.name + '-' + name,
    annotations: {
      [if tls then 'kubernetes.io/tls-acme']: 'true',
      [if std.objectHas(params, 'ingress_class') then 'ingress.class']: params.ingress_class,
    },
  },
  spec: {
    rules: [
      {
        host: domainName,
        http: {
          paths: [
            {
              backend: {
                serviceName: params.name,
                servicePort: params.servicePort,
              },
              path: '/',
            },
          ],
        },
      }
      for domainName in domains
    ],
    [if tls then 'tls']: [
      {
        hosts: domains,
        secretName: name + '-tls',
      },
    ],
  },
};

local volumes = [
  {
    emptyDir: {},
    name: 'data',
  },
] + if params.deployment_mode == 'devel' then [
  {
    hostPath: {
      path: '/Users/ask/.shared/src/ntppool',
      type: '',
    },
    name: 'host-ntppool',
  },
] else [];

{
  Ingress: ingress,
  Container: {
    local container = self,

    args:: error 'Must override "args"',
    name: error 'Must override "name"',
    params:: error 'Must override "params"',

    image: params.image,
    imagePullPolicy:: 'IfNotPresent',
    //imagePullPolicy:: 'Always',

    command: [
      '/ntppool/docker/entrypoint',
    ] + self.args,
    env: [
      {
        name: 'CBCONFIG',
        value: '/var/ntppool/combust.conf',
      },
      {
        name: 'config-md5',
        value: std.md5(std.manifestJson(config)),
      },
      {
        name: 'auth0_secret',
        valueFrom: {
          secretKeyRef: {
            key: 'auth0_secret',
            name: 'ntppool-secrets',
          },
        },
      },
      {
        name: 'db_pass',
        valueFrom: {
          secretKeyRef: {
            key: 'db_pass',
            name: 'ntppool-secrets',
          },
        },
      },
      {
        name: 'account_id_key',
        valueFrom: {
          secretKeyRef: {
            key: 'account_id_key',
            name: 'ntppool-secrets',
          },
        },
      },
    ],
    envFrom: [
      {
        configMapRef: {
          name: 'config',
        },
      },
    ],

    securityContext: {
      fsGroup: 1000,
      runAsUser: 1000,
    },

    resources: {
      limits: {
        cpu: '2',
        memory: '1400Mi',
      },
      requests: {
        cpu: '10m',
        # in development ~300Mi is fine, production needs more
        memory: '700Mi',
      },
    },
    volumeMounts: [
      {
        mountPath: '/ntppool/data',
        name: 'data',
      },
    ] + if params.deployment_mode == 'devel' then
      [{
        mountPath: '/ntppool',
        name: 'host-ntppool',
      }] else [],
  },

  Deployment: {
    local deployment = self,

    name:: error "Must override 'name'",
    tier:: error "Must override 'tier'",
    containers:: error "Must set 'containers'",
    params:: error "Must set 'params'",

    apiVersion: 'apps/v1beta2',
    kind: 'Deployment',
    metadata: {
      name: deployment.name,
      labels: {
        app: deployment.name,
        tier: deployment.tier,
      },
    },
    spec: {
      replicas: params.replicas,
      selector: {
        matchLabels: {
          app: deployment.name,
          tier: deployment.tier,
        },
      },
      template: {
        metadata: {
          labels: {
            app: deployment.name,
            tier: deployment.tier,
          },
        },
        spec: {
          affinity: affinity.PodAnti('tier', deployment.tier),
          containers:
            deployment.containers,
          volumes: volumes,
          [if std.length(params.imagePullSecrets) > 0 then 'imagePullSecrets']: params.imagePullSecrets,
          tolerations: [
            {
              effect: 'NoSchedule',
              key: 'node-role.kubernetes.io/master',
              operator: 'Exists',
            },
          ],

        },
      },
    },
  },

  CronJob: {
    local cronjob = self,

    params:: {},
    name: error "Must override 'name'",
    containers:: error "Must set 'containers'",
    schedule:: error "Must set 'schedule'",

    apiVersion: 'batch/v1beta1',
    kind: 'CronJob',

    metadata: {
      name: cronjob.name,
    },
    spec: {
      concurrencyPolicy: 'Forbid',
      successfulJobsHistoryLimit: 2,
      failedJobsHistoryLimit: 2,
      schedule: cronjob.schedule,
      suspend: params.cronSuspend,
      startingDeadlineSeconds: 172400,
      jobTemplate: {
        spec: {
          template: {
            spec: {
              activeDeadlineSeconds: 1800,
              restartPolicy: 'Never',
              volumes: volumes,
              [if std.length(params.imagePullSecrets) > 0 then 'imagePullSecrets']: params.imagePullSecrets,
              containers: cronjob.containers,
            },
          },
        },
      },
    },
  },
}
