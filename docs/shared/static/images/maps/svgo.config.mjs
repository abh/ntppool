export default {
  multipass: true,
  plugins: [
    {
      name: 'preset-default',
      params: {
        overrides: {
          // disable a default plugin
          // cleanupIds: false,

          // customize the params of a default plugin
          // inlineStyles: {
          //   onlyMatchedOnce: false,
          // },
          convertPathData: {
            floatPrecision: 8,
            transformPrecision: 8,
            smartArcRounding: 8
          }
        },
      },
    },
  ],
};
