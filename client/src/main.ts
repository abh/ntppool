/**
 * Main application entrypoint
 * Includes analytics and chart initialization for NTP Pool
 */

// Import Bootstrap CSS (SCSS will be processed by Vite)
import './styles/bootstrap.scss';


import {
  registerAllComponents,
  ensureWebComponentsSupport,
  CHART_TAG_NAMES
} from '@/components/index';
import { querySelector, showLegacyMessage, initializeGraphExplanation } from '@/utils/dom-utils';



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

  // Initialize status page
  initializeStatusPage().catch(error => {
    console.error('Failed to initialize status page:', error);
  });

  // Initialize graph explanation functionality
  initializeGraphExplanation();

  // Initialize HTMX conditionally
  initializeHTMX().catch(error => {
    console.error('Failed to initialize HTMX:', error);
  });

  // Initialize Bootstrap components conditionally
  initializeBootstrap();
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', checkAndInitialize);
} else {
  // DOM is already ready
  checkAndInitialize();
}


// Load analytics
import './analytics';

// Load status page integration
import { initializeStatusPage } from './status-page';

// Load HTMX conditionally
import { initializeHTMX } from './htmx-loader';

// Load Bootstrap components conditionally
import { initializeBootstrap } from './bootstrap-loader';

// Load mobile navigation
import './mobile-nav';
