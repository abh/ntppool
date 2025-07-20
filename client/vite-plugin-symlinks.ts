import { Plugin } from 'vite';
import { readFileSync, symlinkSync, existsSync, unlinkSync } from 'fs';
import { join, basename } from 'path';

// Custom plugin to create symlinks for non-hashed filenames
export const createSymlinksPlugin = (): Plugin => {
  return {
    name: 'create-symlinks',
    apply: 'build',
    writeBundle(options, bundle) {
      const outDir = options.dir || '../docs/shared/static/build/';
      const manifestPath = join(outDir, '.vite/manifest.json');

      try {
        // Read the manifest file
        const manifestContent = readFileSync(manifestPath, 'utf-8');
        const manifest = JSON.parse(manifestContent);

        // Create symlinks for main entry points
        for (const [originalName, fileInfo] of Object.entries(manifest)) {
          if (typeof fileInfo === 'object' && fileInfo !== null && 'file' in fileInfo) {
            const hashedFile = (fileInfo as any).file;

            // Determine the non-hashed filename
            let nonHashedName: string | null = null;

            if (originalName === 'src/main.ts') {
              nonHashedName = 'app.js';
            } else if (hashedFile.endsWith('.css') && hashedFile.includes('.v')) {
              // For CSS files, create style.css symlink for the main stylesheet
              if (hashedFile.startsWith('style.v')) {
                nonHashedName = 'style.css';
              }
            } else if (hashedFile.includes('d3-vendor.v')) {
              nonHashedName = 'd3-vendor.js';
            }

            if (nonHashedName) {
              const hashedPath = join(outDir, hashedFile);
              const symlinkPath = join(outDir, nonHashedName);

              // Remove existing symlink if it exists
              if (existsSync(symlinkPath)) {
                try {
                  unlinkSync(symlinkPath);
                } catch (e) {
                  // Ignore errors
                }
              }

              // Create the symlink
              try {
                // Use relative path for the symlink target
                symlinkSync(basename(hashedFile), symlinkPath);
                console.log(`Created symlink: ${nonHashedName} -> ${basename(hashedFile)}`);
              } catch (error) {
                console.error(`Failed to create symlink for ${nonHashedName}:`, error);
              }
            }
          }
        }

        // Also handle legacy polyfill if it exists
        for (const fileName of Object.keys(bundle)) {
          if (fileName.includes('legacy-polyfills') && fileName.endsWith('.js')) {
            const symlinkPath = join(outDir, 'legacy-polyfills.js');

            if (existsSync(symlinkPath)) {
              try {
                unlinkSync(symlinkPath);
              } catch (e) {
                // Ignore errors
              }
            }

            try {
              symlinkSync(basename(fileName), symlinkPath);
              console.log(`Created symlink: legacy-polyfills.js -> ${basename(fileName)}`);
            } catch (error) {
              console.error('Failed to create symlink for legacy-polyfills.js:', error);
            }
          }
        }
      } catch (error) {
        console.error('Error processing manifest for symlinks:', error);
      }
    }
  };
};
