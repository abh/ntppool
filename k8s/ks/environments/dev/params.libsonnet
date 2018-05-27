local params = std.extVar("__ksonnet/params");
local globals = import "globals.libsonnet";
local envParams = params + {
  components+: {
    ns+: {
      name: "ntpdev"
    },
    mailhog+: {
      enabled: true,
    },
    smtp+: {
      replicas: 1,
    },
    splash+: {
      replicas: 1,
    },
  }
};

{
  components: {
    [x]: envParams.components[x] + globals for x in std.objectFields(envParams.components)
  }
}