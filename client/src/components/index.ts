/**
 * Web Components for NTP Pool Charts
 * Modern, encapsulated chart components using Web Components standard
 */

/**
 * Register all NTP Pool chart components
 * Call this function to register all components globally
 */
// Define chart loaders - Vite can statically analyze these
const chartLoaders = {
  'ntp-server-chart': () => import('./server-chart'),
  'ntp-zone-chart': () => import('./zone-chart')
};

// Export chart tag names for reuse
export const CHART_TAG_NAMES = Object.keys(chartLoaders);

export async function registerAllComponents(): Promise<void> {
  // Only load components that are actually present on the page
  const promises: Promise<any>[] = [];

  for (const [tagName, loader] of Object.entries(chartLoaders)) {
    if (document.querySelector(tagName) && !customElements.get(tagName)) {
      promises.push(loader());
    }
  }

  await Promise.all(promises);
}

/**
 * Check if Web Components are supported
 */
export function isWebComponentsSupported(): boolean {
  return (
    'customElements' in window &&
    'attachShadow' in Element.prototype &&
    'getRootNode' in Element.prototype &&
    'addEventListener' in Element.prototype &&
    'dispatchEvent' in Element.prototype
  );
}

/**
 * Polyfill Web Components if needed
 * Returns a promise that resolves when polyfills are loaded
 */
export async function ensureWebComponentsSupport(): Promise<void> {
  if (isWebComponentsSupported()) {
    return;
  }

  // For legacy browsers, the Vite legacy plugin should provide polyfills
  // If not available, we'll gracefully degrade
  console.warn('Web Components not fully supported. Modern features may not work.');

  // Check if polyfills are available globally (loaded by legacy plugin)
  if (typeof (window as any).webComponentsReady !== 'undefined') {
    return;
  }

  // If no polyfills available, we'll still try to continue
  // Modern browsers that reach this point should still work
  console.warn('Web Components polyfills not available. Some features may not work in older browsers.');
}
