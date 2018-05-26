local env = std.extVar("__ksonnet/environments");
local params = std.extVar("__ksonnet/params").components["ntppool-env"];
{
   "apiVersion": "v1",
   "data": params.data,
   "kind": "ConfigMap",
   "metadata": {
    "name": params.name
  }
}