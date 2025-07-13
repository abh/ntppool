/* Copyright 2025 NTP Pool Project */

/**
 * Shared utilities for NTP Pool charts
 * Modern ES6+ module with common functions and constants
 */

// Chart dimension constants
export const CHART_DEFAULTS = {
    padding: {
        horizontal: 45,
        vertical: 19
    },
    dimensions: {
        defaultWidth: 500,
        defaultHeight: 246,
        widthRatio: 0.7
    },
    ticks: {
        x: 8,
        y: 8
    }
};

// Color schemes for different chart elements
export const COLORS = {
    offset: {
        good: 'green',
        warning: 'orange',
        error: 'red'
    },
    score: {
        good: 'steelblue',
        warning: 'orange',
        error: 'red'
    },
    lines: {
        registered: '#1f77b4',
        active: '#2ca02c',
        inactive: '#ff7f0e',
        totalScore: '#d62728'
    },
    grid: '#e0e0e0',
    zeroLine: 'black'
};

// Thresholds for data visualization
export const THRESHOLDS = {
    offset: {
        good: 0.050,
        warning: 0.100,
        max: 2,
        min: -2
    },
    score: {
        max: 25,
        min: -105
    }
};

/**
 * Safely query DOM elements with fallback
 * @param {string} selector - CSS selector
 * @param {Element} context - Optional context element
 * @returns {Element|null}
 */
export function querySelector(selector, context = document) {
    try {
        return context.querySelector(selector);
    } catch (e) {
        console.error('Invalid selector:', selector);
        return null;
    }
}

/**
 * Safely query all DOM elements
 * @param {string} selector - CSS selector
 * @param {Element} context - Optional context element
 * @returns {NodeList}
 */
export function querySelectorAll(selector, context = document) {
    try {
        return context.querySelectorAll(selector);
    } catch (e) {
        console.error('Invalid selector:', selector);
        return [];
    }
}

/**
 * Get element dimensions with fallbacks
 * @param {Element} element - DOM element
 * @param {Object} defaults - Default dimensions
 * @returns {Object} {width, height}
 */
export function getElementDimensions(element, defaults = CHART_DEFAULTS.dimensions) {
    if (!element) {
        return {
            width: defaults.defaultWidth,
            height: defaults.defaultHeight
        };
    }

    const dataWidth = parseInt(element.dataset.width);
    const dataHeight = parseInt(element.dataset.height);

    return {
        width: dataWidth || (element.offsetWidth * defaults.widthRatio) || defaults.defaultWidth,
        height: dataHeight || element.offsetHeight || defaults.defaultHeight
    };
}

/**
 * Format date for display
 * @param {Date} date - Date object
 * @param {string} format - Format type ('short', 'long', 'time')
 * @returns {string}
 */
export function formatDate(date, format = 'short') {
    const options = {
        short: { month: 'short', day: 'numeric' },
        long: { year: 'numeric', month: 'long', day: 'numeric' },
        time: { hour: '2-digit', minute: '2-digit' }
    };

    return new Intl.DateTimeFormat('en-US', options[format] || options.short).format(date);
}

/**
 * Parse timestamp to Date object
 * @param {number} timestamp - Unix timestamp
 * @returns {Date}
 */
export function parseTimestamp(timestamp) {
    return new Date(timestamp * 1000);
}

/**
 * Debounce function for resize handlers
 * @param {Function} func - Function to debounce
 * @param {number} wait - Wait time in milliseconds
 * @returns {Function}
 */
export function debounce(func, wait = 250) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

/**
 * Fetch data with error handling
 * @param {string} url - API endpoint
 * @returns {Promise<Object>}
 */
export async function fetchChartData(url) {
    try {
        const response = await fetch(url);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return { success: true, data };
    } catch (error) {
        console.error('Error fetching chart data:', error);
        return {
            success: false,
            error: error.message || 'Failed to load chart data'
        };
    }
}

/**
 * Create loading placeholder
 * @param {Element} container - Container element
 * @param {string} message - Loading message
 */
export function showLoading(container, message = 'Loading chart...') {
    container.innerHTML = `
        <div class="chart-loading" role="status" aria-live="polite">
            <div class="spinner-border spinner-border-sm" role="status">
                <span class="visually-hidden">${message}</span>
            </div>
            <span class="ms-2">${message}</span>
        </div>
    `;
}

/**
 * Show error message
 * @param {Element} container - Container element
 * @param {string} message - Error message
 */
export function showError(container, message = 'Error loading chart data') {
    container.innerHTML = `
        <div class="alert alert-warning" role="alert">
            <strong>Error:</strong> ${message}
        </div>
    `;
}

/**
 * Clear container content
 * @param {Element} container - Container element
 */
export function clearContainer(container) {
    while (container.firstChild) {
        container.removeChild(container.firstChild);
    }
}

/**
 * Add ARIA labels to SVG chart
 * @param {SVGElement} svg - SVG element
 * @param {string} title - Chart title
 * @param {string} description - Chart description
 */
export function addAccessibilityLabels(svg, title, description) {
    svg.setAttribute('role', 'img');
    svg.setAttribute('aria-label', title);

    if (description) {
        const descId = `chart-desc-${Math.random().toString(36).substr(2, 9)}`;
        svg.setAttribute('aria-describedby', descId);

        const desc = document.createElementNS('http://www.w3.org/2000/svg', 'desc');
        desc.id = descId;
        desc.textContent = description;
        svg.insertBefore(desc, svg.firstChild);
    }
}

/**
 * Format number with appropriate precision
 * @param {number} value - Number to format
 * @param {number} precision - Decimal places
 * @returns {string}
 */
export function formatNumber(value, precision = 0) {
    return new Intl.NumberFormat('en-US', {
        minimumFractionDigits: precision,
        maximumFractionDigits: precision
    }).format(value);
}

/**
 * Calculate responsive chart dimensions
 * @param {Element} container - Container element
 * @returns {Object} {width, height, padding}
 */
export function calculateResponsiveDimensions(container) {
    const { width, height } = getElementDimensions(container);

    // Adjust padding for smaller screens
    const padding = { ...CHART_DEFAULTS.padding };
    if (width < 400) {
        padding.horizontal = 30;
        padding.vertical = 15;
    }

    return {
        width,
        height,
        padding,
        innerWidth: width - (padding.horizontal * 2),
        innerHeight: height - (padding.vertical * 2)
    };
}

/**
 * Create responsive SVG container
 * @param {Element} container - Container element
 * @param {Object} dimensions - Chart dimensions
 * @returns {Object} {svg, g} - SVG and group elements
 */
export function createSvgContainer(container, dimensions) {
    const svg = d3.select(container)
        .append('svg')
        .attr('width', dimensions.width)
        .attr('height', dimensions.height)
        .attr('viewBox', `0 0 ${dimensions.width} ${dimensions.height}`)
        .attr('preserveAspectRatio', 'xMidYMid meet');

    const g = svg.append('g')
        .attr('transform', `translate(${dimensions.padding.horizontal},${dimensions.padding.vertical})`);

    return { svg, g };
}

/**
 * Monitor status configuration
 */
export const MONITOR_STATUS = {
    active: { order: 0, class: 'table-success', label: 'Active' },
    testing: { order: 1, class: 'table-info', label: 'Testing' },
    candidate: { order: 2, class: 'table-secondary', label: 'Candidate' },
    pending: { order: 3, class: 'table-secondary', label: 'Pending' },
    paused: { order: 4, class: 'table-danger', label: 'Paused' },
    deleted: { order: 5, class: 'table-danger', label: 'Deleted' }
};

/**
 * Sort monitors by status and type
 * @param {Array} monitors - Array of monitor objects
 * @returns {Array} Sorted monitors
 */
export function sortMonitors(monitors) {
    return [...monitors].sort((a, b) => {
        const aStatus = MONITOR_STATUS[a.status] || { order: 999 };
        const bStatus = MONITOR_STATUS[b.status] || { order: 999 };

        if (aStatus.order !== bStatus.order) {
            return aStatus.order - bStatus.order;
        }

        if (a.type !== b.type) {
            return b.type.localeCompare(a.type);
        }

        return (a.score_ts || 0) - (b.score_ts || 0);
    });
}
