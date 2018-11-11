local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.geoip;

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
        app: "ntppool",
        tier: params.name,
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
          app: 'ntppool',
          tier: params.name,
        },
      },
      template: {
        metadata: {
          labels: {
            app: 'ntppool',
            tier: params.name,
          },
        },
        spec: {
          affinity: affinity.PodAnti('tier', params.name),
          containers: [
            {
              image: params.image,
              name: params.name,
              ports: [
                {
                  containerPort: params.containerPort,
                },
              ],
              readinessProbe: {
                failureThreshold: 3,
                httpGet: {
                  path: '/healthz',
                  port: params.containerPort,
                  scheme: 'HTTP',
                },
                initialDelaySeconds: 3,
                periodSeconds: 10,
                successThreshold: 1,
                timeoutSeconds: 1,
              },
              livenessProbe: {
                httpGet: {
                  path: '/healthz',
                  port: params.containerPort,
                  scheme: 'HTTP',
                },
                initialDelaySeconds: 10,
                periodSeconds: 60,
                successThreshold: 1,
                failureThreshold: 3,
                timeoutSeconds: 2,
              },
              resources: {
                limits: {
                  cpu: '300m',
                  memory: '100Mi',
                },
                requests: {
                  cpu: '20m',
                  memory: '50Mi',
                },
              },
            },
          ],
        },
      },
    },
  },
]
