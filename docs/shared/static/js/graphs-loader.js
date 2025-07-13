/**
 * Loader script for NTP Pool charts
 * This file manages loading of either bundled or unbundled chart modules
 * based on availability and browser support
 */

(function() {
    'use strict';

    // Check if we're using bundled version
    const script = document.currentScript;
    const useBundle = script && script.dataset.bundle !== 'false';

    if (useBundle) {
        // Try to load bundled version
        const bundleScript = document.createElement('script');
        bundleScript.type = 'module';
        bundleScript.src = script.src.replace('graphs-loader.js', 'graphs.bundle.js');

        bundleScript.onerror = function() {
            console.warn('Bundle not found, falling back to source modules');
            loadSourceModules();
        };

        document.head.appendChild(bundleScript);
    } else {
        loadSourceModules();
    }

    function loadSourceModules() {
        // Load source modules directly (development mode)
        const moduleScript = document.createElement('script');
        moduleScript.type = 'module';
        moduleScript.textContent = `
            import { initializeGraphs } from './graphs.js';

            // Initialize when DOM is ready
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', initializeGraphs);
            } else {
                initializeGraphs();
            }
        `;
        document.head.appendChild(moduleScript);
    }
})();
