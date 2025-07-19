/**
 * Shared utilities for NTP Pool charts
 * TypeScript version with comprehensive type safety
 */

const d3 = await import('d3');

// Re-export DOM utilities to maintain backward compatibility
export {
  querySelector,
  querySelectorAll,
  showLoading,
  showError,
  clearContainer,
  formatNumber,
  formatDate,
  parseTimestamp,
  debounce,
  addAccessibilityLabels,
  getElementDimensions,
  sortMonitors,
  fetchChartData,
  CHART_DEFAULTS,
  COLORS,
  THRESHOLDS,
  MONITOR_STATUS
} from '@/utils/dom-utils.js';

// Import getElementDimensions for use in this file
import { getElementDimensions as getElementDimensionsImpl } from '@/utils/dom-utils.js';

import type {
  ChartDimensions,
  SvgDimensions,
  ChartElements,
  SvgSelection,
  GSelection
} from '@/types/index.js';


/**
 * Calculate responsive chart dimensions
 */
export function calculateResponsiveDimensions(container: Element): ChartDimensions & {
  innerWidth: number;
  innerHeight: number;
} {
  const { width, height, padding } = getElementDimensionsImpl(container);

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
