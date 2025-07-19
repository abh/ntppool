import { defineConfig } from 'vite';
import legacy from '@vitejs/plugin-legacy';
import { resolve } from 'path';

export default defineConfig({
  // Base public path - use relative paths to avoid hardcoded URLs
  base: './',

  // Build configuration
  build: {
    // Output directory for development builds
    outDir: '../docs/shared/static/js/dist/',

    // Don't empty outDir
    emptyOutDir: false,

    // Generate source maps for debugging
    sourcemap: true,

    manifest: true,

    // Build targets - modern browsers for development
    target: 'es2022',

    // Rollup options
    rollupOptions: {
      input: {
        // Main entry point
        graphs: resolve(__dirname, 'src/main.ts'),
      },
      output: {
        // Output format
        format: 'es',
        // File naming
        entryFileNames: '[name]-v[hash].js',
        chunkFileNames: '[name]-v[hash].js',
        assetFileNames: '[name]-v[hash][extname]',
        inlineDynamicImports: false,
        // Manual chunks - only separate D3 vendor
        manualChunks: {
          // D3.js as a separate chunk for caching
          'd3-vendor': ['d3']
        }
      }
    },

    // Disable module preload to prevent Safari warnings
    modulePreload: false,

    // Minification options
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: false, // Keep console for development
        drop_debugger: false
      },
      format: {
        comments: true
      },
      keep_classnames: true,
      keep_fnames: true
    }
  },

  // Plugins
  plugins: [
    // Legacy browser support
    legacy({
      targets: ['Chrome >= 87', 'Firefox >= 78', 'Safari >= 14', 'Edge >= 88'],
      additionalLegacyPolyfills: ['regenerator-runtime/runtime'],
      renderLegacyChunks: false, // No legacy for development
      polyfills: true
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
      '@': resolve(__dirname, 'src')
    }
  }
});
