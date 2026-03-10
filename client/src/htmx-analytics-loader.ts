/**
 * HTMX Analytics Loader
 * Conditionally loads HTMX analytics only when HTMX is loaded
 */

/**
 * Initialize HTMX analytics tracking
 * This must be called after HTMX is loaded
 */
export async function initializeHTMXAnalytics(): Promise<void> {
  try {
    // Only initialize if HTMX is available
    if (!window.htmx) {
      console.log('HTMX not available, skipping analytics initialization');
      return;
    }

    // Dynamically import the analytics module
    await import('./htmx-analytics.js');

    console.log('HTMX analytics initialized successfully');

  } catch (error) {
    console.error('Failed to initialize HTMX analytics:', error);
    // Don't throw - analytics failure shouldn't break HTMX functionality
  }
}
