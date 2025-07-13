/* Copyright 2012-2025 Ask Bjørn Hansen, Develooper LLC & NTP Pool Project */

/**
 * Main graph initialization module
 * Modern ES6+ implementation without jQuery or Modernizr dependencies
 */

import {
    querySelector,
    querySelectorAll,
    fetchChartData,
    showLoading,
    showError,
    clearContainer,
    debounce
} from './chart-utils.js';

// Import chart modules (will be created next)
import { createZoneChart } from './graphs.zone.js';
import { createServerChart } from './graphs.server.js';

// Global namespace for backward compatibility (if needed)
window.Pool = window.Pool || {};
window.Pool.Graphs = window.Pool.Graphs || {};

/**
 * Check for SVG support in the browser
 * @returns {boolean}
 */
function checkSvgSupport() {
    // Modern browsers all support SVG, but we'll check anyway
    return !!(document.createElementNS &&
             document.createElementNS('http://www.w3.org/2000/svg', 'svg').createSVGRect);
}

/**
 * Show legacy browser message
 * @param {Element} container - Container element
 */
function showLegacyMessage(container) {
    if (!container) return;

    container.innerHTML = `
        <div class="alert alert-warning">
            <p>Please upgrade to a modern browser that supports SVG to see the graphs.</p>
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
 * Load and render a single graph
 * @param {Element} container - Graph container element
 * @returns {Promise<void>}
 */
async function loadGraph(container) {
    // Show loading state
    showLoading(container);

    // Check for server IP (server chart)
    const serverIp = container.dataset.serverIp;
    if (serverIp) {
        const legendElement = container.nextElementSibling?.classList.contains('graph-legend')
            ? container.nextElementSibling
            : null;

        const url = `/scores/${serverIp}/json?monitor=*&limit=5000&source=c`;
        const result = await fetchChartData(url);

        if (result.success) {
            clearContainer(container);
            createServerChart(container, result.data, { legend: legendElement });

            // Signal that chart has loaded (for compatibility)
            setTimeout(() => {
                const loadedDiv = document.createElement('div');
                loadedDiv.id = 'loaded';
                document.body.appendChild(loadedDiv);
            }, 50);
        } else {
            showError(container, result.error);
        }
        return;
    }

    // Check for zone (zone chart)
    const zone = container.dataset.zone;
    if (zone) {
        const url = `/zone/${zone}.json?limit=480`;
        const result = await fetchChartData(url);

        if (result.success) {
            clearContainer(container);
            createZoneChart(container, result.data, { name: zone });
        } else {
            showError(container, result.error);
        }
    }
}

/**
 * Initialize all graphs on the page
 */
async function initializeGraphs() {
    // Check for SVG support
    const svgSupported = window.NP?.svg_graphs !== false && checkSvgSupport();

    if (!svgSupported) {
        const legacyContainer = querySelector('#legacy-graphs');
        showLegacyMessage(legacyContainer);
        return;
    }

    // Find all graph containers
    const graphContainers = querySelectorAll('div.graph');

    // Load graphs in parallel
    const loadPromises = Array.from(graphContainers).map(container =>
        loadGraph(container).catch(error => {
            console.error('Error loading graph:', error);
            showError(container, 'Failed to load graph');
        })
    );

    await Promise.all(loadPromises);
}

/**
 * Handle window resize for responsive charts
 */
const handleResize = debounce(() => {
    // Re-render all charts with new dimensions
    const graphContainers = querySelectorAll('div.graph svg');
    graphContainers.forEach(svg => {
        const container = svg.parentElement;
        if (container.dataset.serverIp || container.dataset.zone) {
            // Clear and reload the chart
            clearContainer(container);
            loadGraph(container);
        }
    });
}, 300);

// Set up event listeners
function setupEventListeners() {
    window.addEventListener('resize', handleResize);
}

// Export for backward compatibility
window.Pool.Graphs.SetupGraphs = initializeGraphs;

// Initialize when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        initializeGraphs();
        setupEventListeners();
    });
} else {
    // DOM is already ready
    initializeGraphs();
    setupEventListeners();
}

// Export functions for module usage
export { initializeGraphs, loadGraph };
