local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.ns;
{
  apiVersion: 'v1',
  kind: 'Namespace',
  metadata: {
    labels: {
      name: params.name,
    },
    name: params.name,
  },
}
