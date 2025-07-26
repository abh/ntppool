/**
 * DOM utilities that don't require D3
 * Separated to avoid loading D3 unnecessarily
 */

import type {
  ChartDimensions,
  ChartColors,
  ChartThresholds,
  ChartDefaults,
  MonitorStatusConfig,
  FetchResult
} from '@/types/index.js';

// Chart dimension constants
export const CHART_DEFAULTS: ChartDefaults = {
  padding: {
    horizontal: 45,
    vertical: 19
  },
  dimensions: {
    defaultWidth: 500,  // Emergency fallback only
    defaultHeight: 246, // Emergency fallback only
    widthRatio: 0.7     // For container-based sizing
  },
  ticks: {
    x: 8,
    y: 8
  }
};

// Color schemes for different chart elements
export const COLORS: ChartColors = {
  offset: {
    good: 'green',
    warning: 'orange',
    error: 'hotpink'
  },
  score: {
    good: 'steelblue',
    warning: 'orange',
    error: 'darkslateblue'
  },
  lines: {
    registered: '#1f77b4',
    active: '#2ca02c',
    inactive: '#ff7f0e',
    totalScore: '#d62728'
  },
  grid: '#e0e0e0',
  zeroLine: '#666'
};

// Threshold values for chart display
export const THRESHOLDS: ChartThresholds = {
  offset: {
    good: 0.05,
    warning: 0.2,
    max: 2,
    min: -2
  },
  score: {
    max: 25,
    min: -105
  }
};

// Monitor status configuration
export const MONITOR_STATUS: Record<string, MonitorStatusConfig> = {
  active: { order: 0, class: 'table-success', label: 'Active' },
  testing: { order: 1, class: 'table-info', label: 'Testing' },
  candidate: { order: 2, class: 'table-secondary', label: 'Candidate' },
  pending: { order: 3, class: 'table-secondary', label: 'Pending' },
  paused: { order: 4, class: 'table-danger', label: 'Paused' },
  deleted: { order: 5, class: 'table-danger', label: 'Deleted' }
};

/**
 * Safely query DOM elements with fallback
 */
export function querySelector<T extends Element = Element>(
  selector: string,
  context: Document | Element = document
): T | null {
  try {
    return context.querySelector<T>(selector);
  } catch (error) {
    console.error('Invalid selector:', selector);
    return null;
  }
}

/**
 * Safely query all DOM elements
 */
export function querySelectorAll<T extends Element = Element>(
  selector: string,
  context: Document | Element = document
): NodeListOf<T> {
  try {
    return context.querySelectorAll<T>(selector);
  } catch (error) {
    console.error('Invalid selector:', selector);
    return document.querySelectorAll('__invalid__') as NodeListOf<T>;
  }
}

/**
 * Show loading state in container
 */
export function showLoading(container: Element, message = 'Loading chart...'): void {
  clearContainer(container);

  const loadingDiv = document.createElement('div');
  loadingDiv.className = 'chart-loading';
  loadingDiv.setAttribute('role', 'status');
  loadingDiv.setAttribute('aria-live', 'polite');

  const spinner = document.createElement('div');
  spinner.className = 'spinner-border spinner-border-sm';
  spinner.setAttribute('role', 'status');

  const hiddenSpan = document.createElement('span');
  hiddenSpan.className = 'visually-hidden';
  hiddenSpan.textContent = message;

  const messageSpan = document.createElement('span');
  messageSpan.className = 'ms-2';
  messageSpan.textContent = message;

  spinner.appendChild(hiddenSpan);
  loadingDiv.appendChild(spinner);
  loadingDiv.appendChild(messageSpan);
  container.appendChild(loadingDiv);
}

/**
 * Show error state in container
 */
export function showError(container: Element, message = 'Error loading chart data'): void {
  clearContainer(container);

  const alertDiv = document.createElement('div');
  alertDiv.className = 'alert alert-warning';
  alertDiv.setAttribute('role', 'alert');

  const strongElement = document.createElement('strong');
  strongElement.textContent = 'Error:';

  const messageText = document.createTextNode(' ' + message);

  alertDiv.appendChild(strongElement);
  alertDiv.appendChild(messageText);
  container.appendChild(alertDiv);
}

/**
 * Clear all children from container
 */
export function clearContainer(container: Element): void {
  while (container.firstChild) {
    container.removeChild(container.firstChild);
  }
}

/**
 * Show legacy browser message
 */
export function showLegacyMessage(container: Element | null): void {
  if (!container) return;

  clearContainer(container);

  const alertDiv = document.createElement('div');
  alertDiv.className = 'alert alert-warning';

  const firstParagraph = document.createElement('p');
  firstParagraph.textContent = 'Please upgrade to a modern browser that supports Web Components to see the charts.';

  const secondParagraph = document.createElement('p');
  secondParagraph.appendChild(document.createTextNode('Recommended browsers: '));

  const browsers = [
    { text: 'Chrome', url: 'https://www.google.com/chrome/' },
    { text: 'Firefox', url: 'https://www.mozilla.org/firefox' },
    { text: 'Safari', url: 'https://www.apple.com/safari/' },
    { text: 'Edge', url: 'https://www.microsoft.com/edge' }
  ];

  browsers.forEach((browser, index) => {
    if (index > 0) {
      secondParagraph.appendChild(document.createTextNode(index === browsers.length - 1 ? ', or ' : ', '));
    }

    const link = document.createElement('a');
    link.href = browser.url;
    link.textContent = browser.text;
    secondParagraph.appendChild(link);
  });

  alertDiv.appendChild(firstParagraph);
  alertDiv.appendChild(secondParagraph);
  container.appendChild(alertDiv);
}

/**
 * Format numbers with proper localization
 */
export function formatNumber(value: number, precision = 0): string {
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: precision,
    maximumFractionDigits: precision
  }).format(value);
}

/**
 * Format dates consistently
 */
export function formatDate(date: Date, format: 'short' | 'long' | 'time' = 'short'): string {
  switch (format) {
    case 'short':
      return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    case 'long':
      return date.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
    case 'time':
      return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
  }
}

/**
 * Parse Unix timestamp to Date
 */
export function parseTimestamp(timestamp: number): Date {
  return new Date(timestamp * 1000);
}

/**
 * Debounce function for performance
 */
export function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait = 250
): (...args: Parameters<T>) => void {
  let timeout: ReturnType<typeof setTimeout> | null = null;

  return function executedFunction(...args: Parameters<T>) {
    const later = () => {
      timeout = null;
      func(...args);
    };

    if (timeout !== null) {
      clearTimeout(timeout);
    }
    timeout = setTimeout(later, wait);
  };
}

/**
 * Add ARIA labels to SVG chart
 */
export function addAccessibilityLabels(
  svg: SVGSVGElement,
  title: string,
  description?: string
): void {
  svg.setAttribute('role', 'img');
  svg.setAttribute('aria-label', title);

  if (description) {
    const descId = `chart-desc-${Math.random().toString(36).slice(2, 11)}`;
    svg.setAttribute('aria-describedby', descId);

    const desc = document.createElementNS('http://www.w3.org/2000/svg', 'desc');
    desc.id = descId;
    desc.textContent = description;
    svg.insertBefore(desc, svg.firstChild);
  }
}

/**
 * Get element dimensions - HTML attributes are primary source
 */
export function getElementDimensions(
  element: Element | null,
  defaults: Partial<ChartDimensions> = {}
): ChartDimensions {
  const defaultPadding = defaults.padding ?? CHART_DEFAULTS.padding;

  if (!element) {
    return {
      width: defaults.width ?? CHART_DEFAULTS.dimensions.defaultWidth,
      height: defaults.height ?? CHART_DEFAULTS.dimensions.defaultHeight,
      padding: defaultPadding
    };
  }

  // Priority: defaults from web component attributes first, then emergency fallback
  // The container element (div) doesn't have width/height attributes - those are on the web component
  const calculatedWidth = defaults.width ?? CHART_DEFAULTS.dimensions.defaultWidth;
  const calculatedHeight = defaults.height ?? CHART_DEFAULTS.dimensions.defaultHeight;

  console.log('📏 getElementDimensions Fixed:', {
    element: (element as HTMLElement).tagName,
    calculatedWidth,
    calculatedHeight,
    source: defaults.width ? 'web component attributes' : 'fallback'
  });

  return {
    width: calculatedWidth,
    height: calculatedHeight,
    padding: defaultPadding
  };
}

/**
 * Sort monitors by status, then type (score first), then score (desc), then avg_rtt (asc), then name (asc)
 */
export function sortMonitors<T extends { status: string; type: string; score: number; avg_rtt?: number; name: string }>(
  monitors: T[]
): T[] {
  return [...monitors].sort((a, b) => {
    const aStatus = MONITOR_STATUS[a.status] ?? { order: 999 };
    const bStatus = MONITOR_STATUS[b.status] ?? { order: 999 };

    // Primary sort: status
    if (aStatus.order !== bStatus.order) {
      return aStatus.order - bStatus.order;
    }

    // Secondary sort: type (score type first)
    if (a.type !== b.type) {
      return b.type.localeCompare(a.type); // Descending order: "score" before "monitor"
    }

    // Tertiary sort: score (descending)
    if (a.score !== b.score) {
      return b.score - a.score;
    }

    // Quaternary sort: avg_rtt (ascending, handle undefined)
    const aRtt = a.avg_rtt ?? Number.MAX_SAFE_INTEGER;
    const bRtt = b.avg_rtt ?? Number.MAX_SAFE_INTEGER;
    if (aRtt !== bRtt) {
      return aRtt - bRtt;
    }

    // Fallback sort: name (ascending)
    return a.name.localeCompare(b.name);
  });
}

/**
 * Fetch data with error handling
 */
export async function fetchChartData<T = unknown>(url: string): Promise<FetchResult<T>> {
  try {
    const response = await fetch(url);

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const data = await response.json() as T;
    return { success: true, data };
  } catch (error) {
    console.error('Error fetching chart data:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Failed to load chart data'
    };
  }
}

/**
 * Initialize graph explanation functionality
 */
export function initializeGraphExplanation(): void {
  const link = querySelector('#graph_explanation_link');
  if (!link) return;

  // Update href to point to fragment
  link.setAttribute('href', '#graph_explanation');

  // Add click handler to show explanation box
  link.addEventListener('click', function(e) {
    e.preventDefault();
    const box = querySelector('#graph_explanation_box');
    if (box) {
      (box as HTMLElement).classList.add('tooltip-box-visible');
    }
    // Navigate to fragment
    window.location.hash = 'graph_explanation';
  });
}
