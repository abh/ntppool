local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.geoip;
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
            tier: 'geoip',
          },
        },
        spec: {
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
