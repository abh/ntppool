import { defineConfig } from 'vite';
import legacy from '@vitejs/plugin-legacy';
import { resolve } from 'path';

export default defineConfig({
  // Base public path - use relative paths to avoid hardcoded URLs
  base: './',

  // Build configuration for production
  build: {
    // Build targets - modern browsers
    target: 'es2022',
    // Output directly to the static directory
    outDir: '../docs/shared/static/js/dist/',

    // Clean only the built files, not everything in the directory
    emptyOutDir: false,

    // Generate source maps
    sourcemap: true,

    manifest: true,

    // CSS code splitting
    cssCodeSplit: false,

    // Rollup options
    rollupOptions: {
      input: {
        // Main entry point
        app: resolve(__dirname, 'src/main.ts'),
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
        manualChunks(id) {
          if (id.includes('node_modules/d3')) {
            return 'd3-vendor';
          }
        }
      },
      // External dependencies that should not be bundled
      external: [],
    },

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

  // Disable module preload to prevent Safari warnings
  modulePreload: false,

  // Plugins
  plugins: [
    // Legacy browser support - 2025 best practices
    legacy({
      targets: ['Chrome >= 87', 'Firefox >= 78', 'Safari >= 14', 'Edge >= 88'],
      additionalLegacyPolyfills: ['regenerator-runtime/runtime'],
      renderLegacyChunks: false, // No legacy for consistency
      polyfills: true
    })
  ],

  // Module resolution
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src')
    }
  },

  // Optimization
  optimizeDeps: {
    // Include dependencies that have dynamic imports
    include: ['d3']
  }
});
