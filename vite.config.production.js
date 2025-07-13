import { defineConfig } from 'vite';
import legacy from '@vitejs/plugin-legacy';
import { resolve } from 'path';

export default defineConfig({
  // Base public path
  base: '/cdn/',

  // Build configuration for production
  build: {
    // Output directly to the static directory
    outDir: 'docs/shared/static/js',

    // Clean only the built files, not everything in the directory
    emptyOutDir: false,

    // Generate source maps
    sourcemap: true,

    // Build targets
    target: 'es2015',

    // Rollup options
    rollupOptions: {
      input: {
        // Main graphs bundle
        'graphs.bundle': resolve(__dirname, 'docs/shared/static/js/graphs.js'),
      },
      output: {
        // Output format
        format: 'es',
        // File naming - use .bundle.js to distinguish from source files
        entryFileNames: '[name].js',
        chunkFileNames: 'chunks/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
        // Manual chunks
        manualChunks: {
          // D3.js as a separate chunk
          'd3-vendor': ['d3'],
          // Chart utilities as a separate chunk
          'chart-utils': [resolve(__dirname, 'docs/shared/static/js/chart-utils.js')]
        }
      },
      // External dependencies that should not be bundled
      external: [],
    },

    // CSS code splitting
    cssCodeSplit: true,

    // Minification
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true,
        pure_funcs: ['console.log', 'console.debug']
      },
      format: {
        comments: false
      },
      keep_classnames: true,
      keep_fnames: true
    }
  },

  // Plugins
  plugins: [
    // Legacy browser support
    legacy({
      targets: ['> 0.5%', 'last 2 versions', 'Firefox ESR', 'not dead'],
      additionalLegacyPolyfills: ['regenerator-runtime/runtime'],
      renderLegacyChunks: true,
      polyfills: true
    })
  ],

  // Module resolution
  resolve: {
    alias: {
      '@': resolve(__dirname, 'docs/shared/static/js')
    }
  }
});
