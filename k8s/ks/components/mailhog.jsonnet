local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.mailhog;

[] + if params.enabled then
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
            name: 'smtp',
            port: params.smtpPort,
            targetPort: 'smtp',
          },
          {
            name: 'http',
            port: params.httpPort,
            targetPort: 'http',
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
            containers: [
              {
                image: params.image,
                name: params.name,
                env: [
                  {
                    name: 'MH_HOSTNAME',
                    value: params.name,
                  },
                ],
                ports: [
                  {
                    name: 'smtp',
                    containerPort: params.smtpPort,
                  },
                  {
                    name: 'http',
                    containerPort: params.httpPort,
                  },
                ],
                livenessProbe: {
                  tcpSocket: {
                    port: 'smtp',
                  },
                  initialDelaySeconds: 10,
                  timeoutSeconds: 1,
                },
                readinessProbe: {
                  tcpSocket: { port: 'smtp' },
                },
                resources: {
                  limits: {
                    cpu: '50m',
                    memory: '150Mi',
                  },
                  requests: {
                    cpu: '10m',
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
else []
