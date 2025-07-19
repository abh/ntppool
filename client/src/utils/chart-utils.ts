/**
 * Shared utilities for NTP Pool charts
 * TypeScript version with comprehensive type safety
 */

import * as d3 from 'd3';
import type {
  ChartDimensions,
  SvgDimensions,
  ChartColors,
  ChartThresholds,
  ChartDefaults,
  MonitorStatusConfig,
  ChartElements,
  SvgSelection,
  GSelection,
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
export const THRESHOLDS: ChartThresholds = {
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
 * Monitor status configuration
 */
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
  } catch (e) {
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
  } catch (e) {
    console.error('Invalid selector:', selector);
    return document.createDocumentFragment().querySelectorAll<T>(selector);
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

  const htmlElement = element as HTMLElement;

  // Simple priority: HTML attributes first, then defaults, then emergency fallback
  const attrWidth = parseInt(htmlElement.getAttribute('width') ?? '0', 10);
  const attrHeight = parseInt(htmlElement.getAttribute('height') ?? '0', 10);

  const calculatedWidth = attrWidth ||
                         defaults.width ||
                         CHART_DEFAULTS.dimensions.defaultWidth;

  const calculatedHeight = attrHeight ||
                          defaults.height ||
                          CHART_DEFAULTS.dimensions.defaultHeight;

  console.log('📏 getElementDimensions Simplified:', {
    element: htmlElement.tagName,
    attrWidth,
    attrHeight,
    calculatedWidth,
    calculatedHeight,
    source: attrWidth ? 'HTML attributes' : defaults.width ? 'options' : 'fallback'
  });

  return {
    width: calculatedWidth,
    height: calculatedHeight,
    padding: defaultPadding
  };
}

/**
 * Format date for display
 */
export function formatDate(date: Date, format: 'short' | 'long' | 'time' = 'short'): string {
  const options: Record<typeof format, Intl.DateTimeFormatOptions> = {
    short: { month: 'short', day: 'numeric' },
    long: { year: 'numeric', month: 'long', day: 'numeric' },
    time: { hour: '2-digit', minute: '2-digit' }
  };

  return new Intl.DateTimeFormat('en-US', options[format]).format(date);
}

/**
 * Parse timestamp to Date object
 */
export function parseTimestamp(timestamp: number): Date {
  return new Date(timestamp * 1000);
}

/**
 * Debounce function for resize handlers
 */
export function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait = 250
): (...args: Parameters<T>) => void {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  return function executedFunction(...args: Parameters<T>) {
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
 * Create loading placeholder
 */
export function showLoading(container: Element, message = 'Loading chart...'): void {
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
 */
export function showError(container: Element, message = 'Error loading chart data'): void {
  container.innerHTML = `
    <div class="alert alert-warning" role="alert">
      <strong>Error:</strong> ${message}
    </div>
  `;
}

/**
 * Clear container content
 */
export function clearContainer(container: Element): void {
  while (container.firstChild) {
    container.removeChild(container.firstChild);
  }
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
 * Format number with appropriate precision
 */
export function formatNumber(value: number, precision = 0): string {
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: precision,
    maximumFractionDigits: precision
  }).format(value);
}

/**
 * Calculate responsive chart dimensions
 */
export function calculateResponsiveDimensions(container: Element): ChartDimensions & {
  innerWidth: number;
  innerHeight: number;
} {
  const { width, height, padding } = getElementDimensions(container);

  // Adjust padding for smaller screens
  const responsivePadding = { ...padding };
  if (width < 400) {
    responsivePadding.horizontal = 30;
    responsivePadding.vertical = 15;
  }

  return {
    width,
    height,
    padding: responsivePadding,
    innerWidth: width - (responsivePadding.horizontal * 2),
    innerHeight: height - (responsivePadding.vertical * 2)
  };
}

/**
 * Create responsive SVG container
 */
export function createSvgContainer(
  container: Element,
  dimensions: SvgDimensions
): ChartElements {
  const svg = d3.select(container)
    .append('svg')
    .attr('width', dimensions.width)
    .attr('height', dimensions.height)
    .attr('viewBox', `0 0 ${dimensions.width} ${dimensions.height}`)
    .attr('preserveAspectRatio', 'xMidYMid meet') as SvgSelection;

  const g = svg.append('g') as GSelection;

  return { svg, g };
}

/**
 * Sort monitors by status and type
 */
export function sortMonitors<T extends { status: string; type: string; score_ts?: number }>(
  monitors: T[]
): T[] {
  return [...monitors].sort((a, b) => {
    const aStatus = MONITOR_STATUS[a.status] ?? { order: 999 };
    const bStatus = MONITOR_STATUS[b.status] ?? { order: 999 };

    if (aStatus.order !== bStatus.order) {
      return aStatus.order - bStatus.order;
    }

    if (a.type !== b.type) {
      return a.type.localeCompare(b.type);
    }

    return (a.score_ts ?? 0) - (b.score_ts ?? 0);
  });
}
