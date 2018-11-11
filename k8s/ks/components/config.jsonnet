local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.config;
{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: params.name,
  },
  data: params.data,
}
