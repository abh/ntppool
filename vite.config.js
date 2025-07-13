import { defineConfig } from 'vite';
import legacy from '@vitejs/plugin-legacy';
import { resolve } from 'path';

export default defineConfig({
  // Base public path for production
  base: '/static/js/',

  // Build configuration
  build: {
    // Output directory
    outDir: 'dist/js',

    // Don't empty outDir since it's within docs/shared/static
    emptyOutDir: false,

    // Generate source maps for production debugging
    sourcemap: true,

    // Build targets
    target: 'es2015',

    // Rollup options
    rollupOptions: {
      input: {
        // Main entry point that imports other modules
        graphs: resolve(__dirname, 'docs/shared/static/js/graphs.js'),
        // Chart utilities (will be bundled with graphs)
        // Other standalone scripts can be added here if needed
      },
      output: {
        // Output format
        format: 'es',
        // File naming
        entryFileNames: '[name].js',
        chunkFileNames: '[name]-[hash].js',
        assetFileNames: '[name]-[hash][extname]',
        // Manual chunks to control bundling
        manualChunks: {
          // D3.js as a separate chunk for caching
          'd3-vendor': ['d3']
        }
      }
    },

    // Minification options
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true
      },
      format: {
        comments: false
      }
    }
  },

  // Plugins
  plugins: [
    // Legacy browser support
    legacy({
      targets: ['defaults', 'not IE 11'],
      additionalLegacyPolyfills: ['regenerator-runtime/runtime'],
      // Generate both modern and legacy bundles
      renderLegacyChunks: true,
      polyfills: {
        // Polyfills for older browsers
        'es.promise': true,
        'es.array.includes': true,
        'es.object.assign': true,
        'es.object.entries': true
      }
    })
  ],

  // Development server configuration
  server: {
    port: 3000,
    open: '/test-charts.html',
    // Proxy API requests to the backend during development
    proxy: {
      '/scores': 'http://localhost:8299',
      '/zone': 'http://localhost:8299',
      '/api': 'http://localhost:8299'
    }
  },

  // Module resolution
  resolve: {
    alias: {
      '@': resolve(__dirname, 'docs/shared/static/js')
    }
  }
});
