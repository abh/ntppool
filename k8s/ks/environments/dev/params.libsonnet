local params = std.extVar('__ksonnet/params');
local globals = import 'globals.libsonnet';
local envParams = params {
  components+: {
    ns+: {
      name: 'ntpdev',
    },
    mailhog+: {
      enabled: true,
    },
    ntppool+: {
      image: 'quay.io/ntppool/ntppool-devel:kube',
    },
    config+: {
      data+: {
        manage_tls: "no",
      },
    },
    secrets+: {
      data+: import 'secrets.libsonnet',
    },
  },
};

{
  components: {
    [x]: envParams.components[x] + globals
    for x in std.objectFields(envParams.components)
  },
}
