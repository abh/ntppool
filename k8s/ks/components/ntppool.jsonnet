local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.ntppool;

local secrets_data = import '../secrets.libsonnet';

[
  {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: {
      name: params.name + '-secrets',
    },
    type: 'Opaque',
    data: secrets_data,
  },

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
      labels: {
        app: 'ntppool',
        component: 'web',
      },
    },
    spec: {
      replicas: params.replicas,
      selector: {
        matchLabels: {
          app: params.name,
          tier: 'frontend',
        },
      },
      template: {
        metadata: {
          labels: {
            app: params.name,
            tier: 'frontend',
          },
        },
        spec: {
          containers: [
            {
              image: params.image,
              name: params.name,
              imagePullPolicy: 'IfNotPresent',
              command: [
                '/ntppool/docker/entrypoint',
                '/ntppool/docker-run',
              ],
              env: [
                {
                  name: 'CBCONFIG',
                  value: '/var/ntppool/combust.conf',
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
              ],
              envFrom: [
                {
                  configMapRef: {
                    name: 'ntppool-env',
                  },
                },
              ],
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
                  port: 8980,
                  scheme: 'HTTP',
                },
                initialDelaySeconds: 4,
                periodSeconds: 3,
                successThreshold: 1,
                timeoutSeconds: 1,
              },
              volumeMounts: [
                {
                  mountPath: '/ntppool',
                  name: 'host-ntppool',
                },
              ],
            },
          ],
          volumes: [
            {
              hostPath: {
                path: '/Users/ask/.shared/src/ntppool',
                type: '',
              },
              name: 'host-ntppool',
            },
          ],

        },
      },
    },
  },
]
