local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.splash;
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
          name: 'http',
          port: params.servicePort,
          targetPort: params.containerPort,
        },
        {
          // do both port 80 and 8050 for the service for now
          name: 'http-old',
          port: params.containerPort,
          targetPort: params.containerPort,
        },
      ],
      selector: {
        app: 'ntppool',
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
              resources: {
                limits: {
                  cpu: '1',
                  memory: '500Mi',
                },
                requests: {
                  cpu: '10m',
                  memory: '90Mi',
                },
              },
            },
          ],
        },
      },
    },
  },
]
