local env = std.extVar('__ksonnet/environments');
local params = std.extVar('__ksonnet/params').components.secrets;
{
  apiVersion: 'v1',
  kind: 'Secret',
  type: 'Opaque',

  metadata: {
    name: params.name,
  },
  data: params.data,
}
