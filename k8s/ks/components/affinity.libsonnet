{
  PodAnti(key, vals): {
    podAntiAffinity: {
      requiredDuringSchedulingIgnoredDuringExecution: [
        {
          labelSelector: {
            matchExpressions: [
              {
                key: key,
                operator: 'In',
                values: [
                  vals,
                ],
              },
            ],
          },
          topologyKey: 'kubernetes.io/hostname',
        },
      ],
    },
  },
}
