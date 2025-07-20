import { defineConfig } from 'vite';
import legacy from '@vitejs/plugin-legacy';
import { resolve } from 'path';
import { createSymlinksPlugin } from './vite-plugin-symlinks';

export default defineConfig({
  // Base public path - use relative paths to avoid hardcoded URLs
  base: './',

  // Build configuration
  build: {
    // Build targets - modern browsers
    target: 'es2022',
    // Output directory for builds
    outDir: '../docs/shared/static/build/',

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
        entryFileNames: '[name].v[hash].js',
        chunkFileNames: '[name].v[hash].js',
        assetFileNames: '[name].v[hash][extname]',
        inlineDynamicImports: false,
        // Manual chunks - only separate D3 vendor
        manualChunks(id) {
          if (id.includes('node_modules/d3')) {
            return 'd3-vendor';
          }
        }
      }
    },

    // Minification options
    minify: false,
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

  // Disable module preload to prevent Safari warnings
  modulePreload: false,

  // Plugins
  plugins: [
    // Legacy browser support
    legacy({
      targets: ['Chrome >= 87', 'Firefox >= 78', 'Safari >= 14', 'Edge >= 88'],
      additionalLegacyPolyfills: ['regenerator-runtime/runtime'],
      renderLegacyChunks: false, // No legacy for development
      polyfills: true
    }),
    // Create symlinks for non-hashed filenames
    createSymlinksPlugin()
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
  },

  // Optimization
  optimizeDeps: {
    // Include dependencies that have dynamic imports
    include: ['d3']
  },

  // CSS preprocessor options
  css: {
    preprocessorOptions: {
      scss: {
        quietDeps: true, // Suppress deprecation warnings from dependencies (like Bootstrap)
        logger: {
          warn: (message, options) => {
            // TEMPORARY: Suppress Sass @import deprecation warnings
            //
            // Why: Bootstrap 5.3.7 still uses @import syntax, which generates 20+ warnings
            // When to remove: When Bootstrap 6.x is released with native @use support
            // OR when we migrate to a Bootstrap alternative that uses modern Sass
            //
            // TODO: Remove this suppression when upgrading to Bootstrap 6.x
            if (message.includes('Sass @import rules are deprecated')) {
              return;
            }
            console.warn(message);
          }
        }
      }
    }
  }
});
