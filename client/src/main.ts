/**
 * Main application entrypoint
 * Includes analytics and chart initialization for NTP Pool
 */


import {
  registerAllComponents,
  ensureWebComponentsSupport,
  CHART_TAG_NAMES
} from '@/components/index.js';
import { querySelector, showLegacyMessage } from '@/utils/dom-utils.js';


// Global namespace
declare global {
  interface Window {
    NP?: {
      svg_graphs?: boolean;
    };
  }
}

/**
 * Initialize Web Components for charts
 */
async function initializeWebComponents(): Promise<void> {
  try {
    // Ensure Web Components support (loads polyfills if needed)
    await ensureWebComponentsSupport();

    // Register all chart components
    await registerAllComponents();

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

// Auto-initialize when DOM is ready if chart elements are present
function checkAndInitialize(): void {
  // Check if any chart elements are present
  const selector = CHART_TAG_NAMES.join(', ');
  if (document.querySelector(selector)) {
    initializeWebComponents().catch(error => {
      console.error('Failed to initialize charts:', error);
    });
  }
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', checkAndInitialize);
} else {
  // DOM is already ready
  checkAndInitialize();
}


// Load analytics
import './analytics.js';
