/**
 * HTMX Conditional Loader
 * Loads and configures HTMX only when needed, with proper CSP compliance
 */

import { initializeHTMXAnalytics } from './htmx-analytics-loader.js';
import { initializeHTMXFeatures } from './htmx-features.js';

// HTMX attributes to detect
const HTMX_ATTRIBUTES = [
  'hx-get', 'hx-post', 'hx-put', 'hx-patch', 'hx-delete',
  'hx-target', 'hx-swap', 'hx-trigger', 'hx-include',
  'hx-confirm', 'hx-vals', 'hx-headers', 'hx-boost',
  'hx-indicator', 'hx-select', 'hx-params', 'hx-encoding',
  'data-hx-get', 'data-hx-post', 'data-hx-put', 'data-hx-patch', 'data-hx-delete',
  'data-hx-target', 'data-hx-swap', 'data-hx-trigger', 'data-hx-include',
  'data-hx-confirm', 'data-hx-vals', 'data-hx-headers', 'data-hx-boost',
  'data-hx-indicator', 'data-hx-select', 'data-hx-params', 'data-hx-encoding'
];

/**
 * Check if the current page has any HTMX attributes
 */
function hasHTMXFeatures(): boolean {
  for (const attr of HTMX_ATTRIBUTES) {
    if (document.querySelector(`[${attr}]`)) {
      return true;
    }
  }
  return false;
}

/**
 * Configure HTMX before it initializes
 */
function configureHTMX() {
  // Ensure window.htmx exists for configuration
  if (!window.htmx) {
    // Set up configuration object before HTMX loads
    (window as any).htmx = { config: {} };
  }

  // Configure HTMX to prevent CSP violations
  window.htmx.config.includeIndicatorStyles = false;
  window.htmx.config.historyCacheSize = 20;

  // Other configuration options can be added here
  // window.htmx.config.defaultSwapStyle = 'outerHTML';
  // window.htmx.config.refreshOnHistoryMiss = true;
}

/**
 * Set up HTMX event handlers for enhanced functionality
 * Now handled by the separate htmx-features module
 */
function setupHTMXHandlers() {
  // Enhanced features are now initialized via initializeHTMXFeatures()
  // This function is kept for any additional custom handlers if needed
}

/**
 * Load and initialize HTMX conditionally
 */
export async function initializeHTMX(): Promise<void> {
  // Only load HTMX if the page actually uses it
  if (!hasHTMXFeatures()) {
    console.log('No HTMX features detected, skipping HTMX initialization');
    return;
  }

  try {
    console.log('HTMX features detected, loading HTMX...');

    // Configure HTMX before loading
    configureHTMX();

    // Dynamically import HTMX
    const htmx = await import('htmx.org');

    // Make HTMX globally available (required for proper functionality)
    (window as any).htmx = htmx.default;

    // Set up additional event handlers
    setupHTMXHandlers();

    // Initialize HTMX enhanced features (auto-redirect, error handling)
    initializeHTMXFeatures();

    // Initialize HTMX analytics
    await initializeHTMXAnalytics();

    console.log('HTMX initialized successfully with enhanced features');

  } catch (error) {
    console.error('Failed to load HTMX:', error);
    throw error;
  }
}

// Global type declaration for HTMX is in types/htmx.ts
