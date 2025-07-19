import { defineConfig } from 'vite';
import legacy from '@vitejs/plugin-legacy';
import { resolve } from 'path';

export default defineConfig({
  // Base public path - use environment static_base + js/dist/
  base: (process.env.static_base || '/static/') + 'js/dist/',

  // Build configuration
  build: {
    // Output directory for development builds
    outDir: '../docs/shared/static/js/dist/',

    // Don't empty outDir
    emptyOutDir: false,

    // Generate source maps for debugging
    sourcemap: true,

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
        entryFileNames: '[name].js',
        chunkFileNames: '[name]-[hash].js',
        assetFileNames: '[name]-[hash][extname]',
        inlineDynamicImports: true,
        manualChunks: undefined
        // Manual chunks to control bundling
        //manualChunks: {
          // D3.js as a separate chunk for caching
        //  'd3-vendor': ['d3']
        //}
      }
    },

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
