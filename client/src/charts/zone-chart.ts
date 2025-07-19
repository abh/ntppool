/**
 * Zone chart module for displaying server counts over time
 * TypeScript implementation with D3.js v7 and comprehensive type safety
 */

const d3 = await import('d3');
import {
  getElementDimensions,
  parseTimestamp,
  CHART_DEFAULTS,
  COLORS,
  createSvgContainer,
  addAccessibilityLabels,
  formatNumber
} from '@/utils/chart-utils.js';
import type {
  ZoneCountsResponse,
  ZoneHistoryPoint,
  ZoneChartOptions,
  TimeScale,
  LinearScale,
  GSelection
} from '@/types/index.js';

/**
 * Create a zone chart showing server counts over time
 */
export function createZoneChart(
  container: Element,
  data: ZoneCountsResponse,
  options: ZoneChartOptions = {}
): void {
  // Set default options with proper typing
  const config = {
    ipVersion: 'v4' as const,
    name: 'Zone',
    showBothVersions: true,
    width: undefined as number | undefined,
    height: undefined as number | undefined,
    ...options
  };

  console.log('📊 createZoneChart debug:', {
    'received options': options,
    'merged config': config,
    'container': container,
    'container.tagName': container.tagName,
    'container attrs': {
      width: (container as HTMLElement).getAttribute?.('width'),
      height: (container as HTMLElement).getAttribute?.('height')
    }
  });

  // Process history data with type safety
  const history: ZoneHistoryPoint[] = data.history.map(d => ({
    ...d,
    date: parseTimestamp(d.ts)
  }));

  // Calculate dimensions - use from options if provided, otherwise from container
  const fallbackDimensions = getElementDimensions(container, { width: 480, height: 246 });
  const dimensions = {
    width: config.width || fallbackDimensions.width,
    height: config.height || fallbackDimensions.height,
    padding: {
      horizontal: 40,
      vertical: 19
    }
  };

  console.log('📊 createZoneChart dimensions calculated:', {
    'config.width': config.width,
    'config.height': config.height,
    'fallbackDimensions': fallbackDimensions,
    'final dimensions': dimensions
  });

  const padding = dimensions.padding;

  const innerWidth = dimensions.width - (padding.horizontal * 2);
  const innerHeight = dimensions.height - (padding.vertical * 2);

  // Calculate Y-axis domain
  const yMax = calculateYMax(history);
  const yMin = 0;

  // Create scales with proper typing
  const yScale: LinearScale = d3.scaleLinear()
    .domain([yMax, yMin])
    .range([0, innerHeight]);

  const xScale: TimeScale = d3.scaleUtc()
    .domain(d3.extent(history, d => d.date) as [Date, Date])
    .range([0, innerWidth]);

  // Create SVG container
  const { svg, g } = createSvgContainer(container, {
    width: dimensions.width,
    height: dimensions.height
  });

  // Apply padding transform
  g.attr('transform', `translate(${padding.horizontal},${padding.vertical})`);

  // Add accessibility labels
  addAccessibilityLabels(
    svg.node()!,
    `Server counts for ${config.name}`,
    `Time series chart showing registered, active, and inactive server counts for ${config.name} zone`
  );

  // Draw grid lines and axes
  drawGrid(g, xScale, yScale, innerWidth, innerHeight, yMax);

  // Draw background rect
  g.append('rect')
    .attr('width', innerWidth)
    .attr('height', innerHeight)
    .attr('fill', 'none')
    .attr('stroke', COLORS.grid);

  // Define line generators with proper typing
  const lineGenerator = d3.line<{ date: Date; value: number }>()
    .x(d => xScale(d.date))
    .y(d => yScale(d.value))
    .curve(d3.curveMonotoneX);

  // Draw lines for each IP version
  const ipVersions: Array<'v4' | 'v6'> = config.showBothVersions ? ['v4', 'v6'] : [config.ipVersion];

  ipVersions.forEach(ipVersion => {
    drawVersionLines(g, history, ipVersion, lineGenerator);
  });

  // Add chart title
  g.append('text')
    .attr('x', 2)
    .attr('y', -5)
    .attr('font-weight', 'bold')
    .attr('font-size', '14px')
    .text(`Server counts for ${config.name}`);

  // Add legend if showing both versions
  if (config.showBothVersions) {
    addLegend(g, innerWidth, innerHeight);
  }
}

/**
 * Calculate appropriate Y-axis maximum
 */
function calculateYMax(history: ZoneHistoryPoint[]): number {
  let yMax = d3.max(history, d => d.rc) ?? 0;

  if (yMax < 5) {
    yMax = 5;
  } else if (yMax < 10) {
    yMax = yMax + 1;
  }

  return yMax;
}

/**
 * Draw grid lines and axis labels
 */
function drawGrid(
  g: GSelection,
  xScale: TimeScale,
  yScale: LinearScale,
  width: number,
  height: number,
  yMax: number
): void {
  // X-axis grid lines and labels
  const xTicks = xScale.ticks(CHART_DEFAULTS.ticks.x);
  const xAxisGroup = g.selectAll<SVGGElement, Date>('g.x-axis')
    .data(xTicks)
    .enter().append('g')
    .attr('class', 'x-axis');

  xAxisGroup.append('line')
    .attr('x1', d => xScale(d))
    .attr('x2', d => xScale(d))
    .attr('y1', 0)
    .attr('y2', height)
    .attr('stroke', COLORS.grid)
    .attr('stroke-dasharray', '2,2');

  xAxisGroup.append('text')
    .attr('x', d => xScale(d))
    .attr('y', height + 3)
    .attr('dy', '.71em')
    .attr('text-anchor', 'middle')
    .attr('font-size', '12px')
    .text(xScale.tickFormat(CHART_DEFAULTS.ticks.x));

  // Y-axis grid lines and labels
  const yTicks = yMax > 8 ? 8 : yMax;
  const yTickValues = yScale.ticks(yTicks);
  const yAxisGroup = g.selectAll<SVGGElement, number>('g.y-axis')
    .data(yTickValues)
    .enter().append('g')
    .attr('class', 'y-axis');

  yAxisGroup.append('line')
    .attr('x1', 0)
    .attr('x2', width)
    .attr('y1', d => yScale(d))
    .attr('y2', d => yScale(d))
    .attr('stroke', COLORS.grid)
    .attr('stroke-dasharray', '2,2');

  yAxisGroup.append('text')
    .attr('x', -3)
    .attr('y', d => yScale(d))
    .attr('dy', '.35em')
    .attr('text-anchor', 'end')
    .attr('font-size', '12px')
    .text(d => formatNumber(d));
}

/**
 * Draw lines for a specific IP version
 */
function drawVersionLines(
  g: GSelection,
  history: ZoneHistoryPoint[],
  ipVersion: 'v4' | 'v6',
  lineGenerator: d3.Line<{ date: Date; value: number }>
): void {
  // Filter data for this IP version
  const versionData = history.filter(d => d.iv === ipVersion);

  if (versionData.length === 0) return;

  // Define line styles with proper typing
  const lineStyles = {
    registered_count: {
      color: ipVersion === 'v4' ? COLORS.lines.registered : '#aec7e8',
      width: 2,
      dasharray: ipVersion === 'v6' ? '5,5' : 'none'
    },
    active_count: {
      color: ipVersion === 'v4' ? COLORS.lines.active : '#98df8a',
      width: 2,
      dasharray: ipVersion === 'v6' ? '5,5' : 'none'
    },
    inactive_count: {
      color: ipVersion === 'v4' ? COLORS.lines.inactive : '#ffbb78',
      width: 1.5,
      dasharray: ipVersion === 'v6' ? '3,3' : 'none'
    }
  } as const;

  // Draw registered count line
  g.append('path')
    .datum(versionData.map(d => ({ date: d.date, value: d.rc })))
    .attr('class', `line registered_count ${ipVersion}`)
    .attr('fill', 'none')
    .attr('stroke', lineStyles.registered_count.color)
    .attr('stroke-width', lineStyles.registered_count.width)
    .attr('stroke-dasharray', lineStyles.registered_count.dasharray)
    .attr('d', lineGenerator);

  // Draw active count line
  g.append('path')
    .datum(versionData.map(d => ({ date: d.date, value: d.ac })))
    .attr('class', `line active_count ${ipVersion}`)
    .attr('fill', 'none')
    .attr('stroke', lineStyles.active_count.color)
    .attr('stroke-width', lineStyles.active_count.width)
    .attr('stroke-dasharray', lineStyles.active_count.dasharray)
    .attr('d', lineGenerator);

  // Draw inactive count line (registered - active)
  g.append('path')
    .datum(versionData.map(d => ({ date: d.date, value: d.rc - d.ac })))
    .attr('class', `line inactive_count ${ipVersion}`)
    .attr('fill', 'none')
    .attr('stroke', lineStyles.inactive_count.color)
    .attr('stroke-width', lineStyles.inactive_count.width)
    .attr('stroke-dasharray', lineStyles.inactive_count.dasharray)
    .attr('d', lineGenerator);
}

/**
 * Add legend to the chart
 */
function addLegend(g: GSelection, width: number, _height: number): void {
  interface LegendItem {
    label: string;
    class: string;
    color: string;
    isDashed?: boolean;
  }

  const legendItems: LegendItem[] = [
    { label: 'Registered', class: 'registered_count', color: COLORS.lines.registered },
    { label: 'Active', class: 'active_count', color: COLORS.lines.active },
    { label: 'Inactive', class: 'inactive_count', color: COLORS.lines.inactive }
  ];

  const legend = g.append('g')
    .attr('class', 'legend')
    .attr('transform', `translate(${width - 120}, 15)`);

  const legendItem = legend.selectAll<SVGGElement, LegendItem>('.legend-item')
    .data(legendItems)
    .enter().append('g')
    .attr('class', 'legend-item')
    .attr('transform', (_d, i) => `translate(0, ${i * 18})`);

  // IPv4 (solid) lines
  legendItem.append('line')
    .attr('x1', 0)
    .attr('x2', 18)
    .attr('y1', 0)
    .attr('y2', 0)
    .attr('stroke', d => d.color)
    .attr('stroke-width', 2);

  // IPv6 (dashed) lines
  legendItem.append('line')
    .attr('x1', 0)
    .attr('x2', 18)
    .attr('y1', 6)
    .attr('y2', 6)
    .attr('stroke', d => d.color)
    .attr('stroke-width', 2)
    .attr('stroke-dasharray', '3,2')
    .attr('opacity', 0.8);

  legendItem.append('text')
    .attr('x', 22)
    .attr('y', 3)
    .attr('dy', '.35em')
    .attr('font-size', '11px')
    .text(d => d.label);

  // Add explanatory text for line styles
  legend.append('text')
    .attr('x', 0)
    .attr('y', legendItems.length * 18 + 8)
    .attr('font-size', '10px')
    .attr('fill', '#666')
    .text('Solid: IPv4, Dashed: IPv6');
}

// Export for backward compatibility with global function
declare global {
  interface Window {
    zone_chart?: typeof createZoneChart;
  }
}

if (typeof window !== 'undefined') {
  window.zone_chart = createZoneChart;
}
