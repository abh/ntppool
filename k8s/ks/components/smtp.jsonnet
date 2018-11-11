local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.smtp;
local affinity = import 'affinity.libsonnet';
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
  {
    apiVersion: 'apps/v1beta2',
    kind: 'Deployment',
    metadata: {
      name: params.name,
    },
    spec: {
      replicas: params.replicas,
      selector: {
        matchLabels: {
          app: params.name,
        },
      },
      template: {
        metadata: {
          labels: {
            app: params.name,
          },
        },
        spec: {
          affinity: affinity.PodAnti('app', params.name),
          containers: [
            {
              image: params.image,
              name: params.name,
              env: [
                {
                  name: 'RELAY_NETWORKS',
                  value: params.settings.relay_networks,
                },
                { name: 'DISABLE_IPV6', value: '1' },
                {
                  name: 'MAILNAME',
                  value: params.settings.host,
                },
                {
                  name: 'PORT',
                  value: '25',
                },
                {
                  name: 'SMARTHOST_ADDRESS',
                  value: params.settings.smarthost_address,
                },
                {
                  name: 'SMARTHOST_PORT',
                  value: params.settings.smarthost_port,
                },
                {
                  name: 'SMARTHOST_USER',
                  value: params.settings.smarthost_user,
                },
                {
                  name: 'SMARTHOST_PASSWORD',
                  valueFrom: {
                    secretKeyRef: {
                      key: 'smtp_pass',
                      name: 'ntppool-secrets',
                    },
                  },
                },
                {
                  name: 'SMARTHOST_ALIASES',
                  value: params.settings.smarthost_address,
                },
              ],
              ports: [
                {
                  containerPort: params.containerPort,
                },
              ],
              resources: {
                limits: {
                  cpu: '200m',
                  memory: '80Mi',
                },
                requests: {
                  cpu: '20m',
                  memory: '20Mi',
                },
              },
            },
          ],
        },
      },
    },
  },
]
