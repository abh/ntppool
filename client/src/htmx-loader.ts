/**
 * HTMX Loader
 * Loads and configures HTMX with proper CSP compliance
 */

import htmx from 'htmx.org';
import { initializeHTMXAnalytics } from './htmx-analytics-loader.js';
import { initializeHTMXFeatures } from './htmx-features.js';

/**
 * Initialize and configure HTMX
 */
export async function initializeHTMX(): Promise<void> {
  try {
    // Make HTMX globally available (required for proper functionality)
    (window as any).htmx = htmx;

    // Configure HTMX to prevent CSP violations
    htmx.config.includeIndicatorStyles = false;
    htmx.config.historyCacheSize = 20;

    // Initialize HTMX enhanced features (auto-redirect, error handling)
    initializeHTMXFeatures();

    // Initialize HTMX analytics
    await initializeHTMXAnalytics();

    console.log('HTMX initialized successfully');

  } catch (error) {
    console.error('Failed to initialize HTMX:', error);
    throw error;
  }
}

// Global type declaration for HTMX is in types/htmx.ts
