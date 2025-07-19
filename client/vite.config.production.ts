import { defineConfig } from 'vite';
import legacy from '@vitejs/plugin-legacy';
import { resolve } from 'path';

export default defineConfig({
  // Base public path - use environment static_base + js/
  base: (process.env.static_base || '/static/') + 'js/',

  // Build configuration for production
  build: {
    // Output directly to the static directory
    outDir: '../docs/shared/static/js',

    // Clean only the built files, not everything in the directory
    emptyOutDir: false,

    // Generate source maps
    sourcemap: true,

    // Rollup options
    rollupOptions: {
      input: {
        // Main graphs bundle
        'graphs.bundle': resolve(__dirname, 'src/main.ts'),
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
          'd3-vendor': ['d3']
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
    // Legacy browser support - 2025 best practices
    legacy({
      targets: [
        'Chrome >= 63',  // Earlier for legacy compatibility
        'Firefox >= 67', // Earlier for legacy compatibility
        'Safari >= 12',  // Earlier for legacy compatibility
        'Edge >= 79'     // Earlier for legacy compatibility
      ],
      additionalLegacyPolyfills: ['regenerator-runtime/runtime'],
      renderLegacyChunks: true,
      polyfills: true,
      modernPolyfills: true
    })
  ],

  // Module resolution
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src')
    }
  }
});
