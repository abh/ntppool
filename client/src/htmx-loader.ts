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
 * Load HTMX with retry logic for Firefox compatibility
 */
async function loadHTMXWithRetry(maxRetries = 3, delay = 100): Promise<any> {
  const isFirefox = navigator.userAgent.includes('Firefox');

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      // Add small delay for Firefox to handle module loading
      if (isFirefox && attempt > 1) {
        await new Promise(resolve => setTimeout(resolve, delay * attempt));
      }

      const htmx = await import('htmx.org');
      return htmx;
    } catch (error) {
      if (attempt === maxRetries) {
        throw new Error(`HTMX import failed after ${maxRetries} attempts: ${error}`);
      }

      // Progressive delay for retries
      await new Promise(resolve => setTimeout(resolve, delay * attempt));
    }
  }
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

    // Dynamically import HTMX with retry logic
    const htmx = await loadHTMXWithRetry();

    // Make HTMX globally available (required for proper functionality)
    (window as any).htmx = htmx.default;

    // Set up additional event handlers
    setupHTMXHandlers();

    // Initialize HTMX enhanced features (auto-redirect, error handling)
    initializeHTMXFeatures();

    // Initialize HTMX analytics
    await initializeHTMXAnalytics();

    console.log('HTMX initialized successfully with enhanced features');

    // Firefox-specific fix: Force HTMX to reprocess forms after DOM is fully ready
    const isFirefox = navigator.userAgent.includes('Firefox');
    if (isFirefox) {
      ensureDOMReadyThenFix();
    }

  } catch (error) {
    console.error('Failed to load HTMX:', error);
    throw error;
  }
}

/**
 * Ensure DOM is fully ready before applying Firefox fix
 */
function ensureDOMReadyThenFix(): void {
  if (document.readyState === 'loading') {
    // DOM is still loading, wait for DOMContentLoaded
    document.addEventListener('DOMContentLoaded', verifyHTMXFunctionality);
  } else if (document.readyState === 'interactive') {
    // DOM is ready but resources may still be loading, use a small delay
    setTimeout(verifyHTMXFunctionality, 50);
  } else {
    // DOM and resources are fully loaded
    verifyHTMXFunctionality();
  }
}

/**
 * Firefox-specific fix: Force HTMX to reprocess forms to ensure proper event binding
 */
function verifyHTMXFunctionality(): void {
  const htmx = (window as any).htmx;
  if (!htmx) {
    console.error('HTMX not available for Firefox fix');
    return;
  }

  // Firefox-specific: Force HTMX to process forms again
  // This ensures HTMX properly attaches to forms that may have been missed during initial load
  const formsWithHX = document.querySelectorAll('form[hx-post], form[hx-get]');
  if (formsWithHX.length > 0) {
    try {
      htmx.process(document.body);
      console.log('Firefox compatibility: HTMX reprocessed forms successfully');
    } catch (error) {
      console.error('Firefox compatibility: Failed to reprocess forms:', error);
    }
  }
}

// Global type declaration for HTMX is in types/htmx.ts
