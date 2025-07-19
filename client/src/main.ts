/**
 * Main chart initialization module
 * Modern Web Components implementation for NTP Pool charts
 */

import {
  registerAllComponents,
  ensureWebComponentsSupport,
  isWebComponentsSupported
} from '@/components/index.js';
import { querySelector } from '@/utils/chart-utils.js';

// Global namespace for backward compatibility
declare global {
  interface Window {
    Pool?: {
      Graphs?: {
        SetupGraphs?: () => Promise<void>;
        initializeWebComponents?: () => Promise<void>;
      };
    };
    NP?: {
      svg_graphs?: boolean;
    };
  }
}

window.Pool = window.Pool ?? {};
window.Pool.Graphs = window.Pool.Graphs ?? {};

/**
 * Show legacy browser message
 */
function showLegacyMessage(container: Element | null): void {
  if (!container) return;

  container.innerHTML = `
    <div class="alert alert-warning">
      <p>Please upgrade to a modern browser that supports Web Components to see the charts.</p>
      <p>Recommended browsers:
        <a href="https://www.google.com/chrome/">Chrome</a>,
        <a href="https://www.mozilla.org/firefox">Firefox</a>,
        <a href="https://www.apple.com/safari/">Safari</a>, or
        <a href="https://www.microsoft.com/edge">Edge</a>
      </p>
    </div>
  `;
}

/**
 * Initialize Web Components for charts
 */
export async function initializeWebComponents(): Promise<void> {
  try {
    // Ensure Web Components support (loads polyfills if needed)
    await ensureWebComponentsSupport();

    // Register all chart components
    registerAllComponents();

    console.log('NTP Pool chart components initialized successfully');

    // Dispatch ready event
    document.dispatchEvent(new CustomEvent('ntp-charts-ready'));

  } catch (error) {
    console.error('Failed to initialize chart components:', error);

    // Show legacy message if Web Components aren't supported
    const legacyContainer = querySelector('#legacy-graphs');
    showLegacyMessage(legacyContainer);

    throw error;
  }
}

/**
 * Legacy function for backward compatibility
 * @deprecated Use initializeWebComponents instead
 */
export async function initializeGraphs(): Promise<void> {
  console.warn('initializeGraphs() is deprecated. Web Components are now used automatically.');
  return initializeWebComponents();
}

/**
 * Check if charts are supported in current browser
 */
export function areChartsSupported(): boolean {
  return window.NP?.svg_graphs !== false && isWebComponentsSupported();
}

// Export functions for backward compatibility
window.Pool.Graphs.SetupGraphs = initializeGraphs;
window.Pool.Graphs.initializeWebComponents = initializeWebComponents;

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    initializeWebComponents().catch(error => {
      console.error('Failed to initialize charts on DOM ready:', error);
    });
  });
} else {
  // DOM is already ready
  initializeWebComponents().catch(error => {
    console.error('Failed to initialize charts:', error);
  });
}
