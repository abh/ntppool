{
  global: {
    // User-defined global parameters; accessible to all component and environments, Ex:
    // replicas: 4,
  },
  components: {
    // Component-level parameters, defined initially from 'ks prototype use ...'
    // Each object below should correspond to a component in the components/ directory
    ns: {
      name: "ntppool",
    },
    "ntppool-env": {
      data: {},
      name: "ntppool-env",
    },
    "smtp": {
      containerPort: 25,
      image: "namshi/smtp",
      name: "smtp",
      replicas: 2,
      servicePort: 25,
      type: "ClusterIP",
      settings: {
        relay_networks: ":10.2.0.0/16:10.3.0.0/16:172.17.0.0/16",
        host: "ntppool-mail",
        smarthost_address: "",
        smarthost_port: "587",
        smarthost_user: "",
        smarthost_password: "",
      },
    },
    "mailhog": {
      enabled: false,
      image: "mailhog/mailhog",
      name: "mailhog",
      smtpPort: 1025,
      httpPort: 8025,
      replicas: 1,
      type: "ClusterIP",
    },
    ntppool: {
      containerPort: 8980,
      image: "quay.io/ntppool/ntppool-devel:kube",
      name: "ntppool",
      replicas: 1,
      servicePort: 80,
      type: "ClusterIP",
    },
    splash: {
      containerPort: 8050,
      image: "scrapinghub/splash:latest",
      name: "splash",
      replicas: 2,
      servicePort: 80,
      type: "ClusterIP",
    },
  },
}
