/**
 * Server chart module for displaying offset and score data
 * TypeScript implementation with D3.js v7 and comprehensive type safety
 */

const d3 = await import('d3');
import {
  getElementDimensions,
  parseTimestamp,
  CHART_DEFAULTS,
  COLORS,
  THRESHOLDS,
  createSvgContainer,
  addAccessibilityLabels,
  MONITOR_STATUS,
  sortMonitors
} from '@/utils/chart-utils.js';
import type {
  ServerScoreHistoryResponse,
  ServerHistoryPoint,
  Monitor,
  ServerChartOptions,
  TimeScale,
  PowerScale,
  GSelection
} from '@/types/index.js';

/**
 * Create a server chart showing offset and score over time
 */
export function createServerChart(
  container: Element,
  data: ServerScoreHistoryResponse,
  options: ServerChartOptions = {}
): void {
  const config = {
    legend: null,
    showTooltips: true,
    responsive: true,
    width: undefined,
    height: undefined,
    ...options
  } as Required<ServerChartOptions>;

  // Process history data with type safety - filter out points with missing offset data
  const history: ServerHistoryPoint[] = data.history
    .filter(d => d.offset != null)
    .map(d => ({
      ...d,
      date: parseTimestamp(d.ts),
      offset: parseFloat(d.offset.toString())
    }));

  // Calculate offset bounds
  let yOffsetMax = d3.max(history, d => d.offset) ?? 0;
  let yOffsetMin = d3.min(history, d => d.offset) ?? 0;

  // Clamp offset values to reasonable bounds
  if (yOffsetMax > THRESHOLDS.offset.max) yOffsetMax = THRESHOLDS.offset.max;
  if (yOffsetMin < THRESHOLDS.offset.min) yOffsetMin = THRESHOLDS.offset.min;

  // Show graph description if element exists
  const graphDesc = document.querySelector('.graph_desc') as HTMLElement | null;
  if (graphDesc) graphDesc.style.display = 'block';

  // Get dimensions from HTML attributes (via options) or container
  const dimensions = getElementDimensions(container, options);
  const innerWidth = dimensions.width;
  const innerHeight = dimensions.height;

  // Calculate total dimensions based on chart content + padding
  const totalWidth = innerWidth + (CHART_DEFAULTS.padding.horizontal * 2);
  const totalHeight = innerHeight + (CHART_DEFAULTS.padding.vertical * 2);

  console.log('🔍 Server Chart Dimensions Debug v3:', {
    serverIp: data.server.ip,
    optionsProvided: {
      width: options.width,
      height: options.height
    },
    fallbackDimensions: getElementDimensions(container),
    finalDimensions: {
      innerWidth,
      innerHeight,
      totalWidth,
      totalHeight
    },
    padding: CHART_DEFAULTS.padding,
    containerElement: container
  });

  // Create scales with proper typing
  const yOffsetScale: PowerScale = d3.scalePow()
    .exponent(0.5)
    .domain([yOffsetMax, yOffsetMin])
    .range([0, innerHeight])
    .clamp(true);

  const yScoreScale: PowerScale = d3.scaleSqrt()
    .domain([THRESHOLDS.score.max, THRESHOLDS.score.min])
    .range([0, innerHeight]);

  const xScale: TimeScale = d3.scaleUtc()
    .domain(d3.extent(history, d => d.date) as [Date, Date])
    .range([0, innerWidth]);

  // Create SVG container with total dimensions
  const { svg, g } = createSvgContainer(container, {
    width: totalWidth,
    height: totalHeight
  });

  // Apply padding transform to position chart content
  g.attr('transform', `translate(${CHART_DEFAULTS.padding.horizontal},${CHART_DEFAULTS.padding.vertical})`);

  console.log('🎨 SVG Creation Debug:', {
    svgElement: svg.node(),
    svgAttributes: {
      width: svg.attr('width'),
      height: svg.attr('height'),
      viewBox: svg.attr('viewBox')
    },
    gElement: g.node(),
    gTransform: g.attr('transform')
  });

  // Add accessibility labels
  addAccessibilityLabels(
    svg.node()!,
    `Offset and scores for ${data.server.ip}`,
    `Time series chart showing NTP server offset and score measurements over time`
  );

  // Draw chart elements
  drawGrid(g, xScale, yOffsetScale, yScoreScale, innerWidth, innerHeight, yOffsetMax, yOffsetMin);
  drawDataPoints(g, history, xScale, yOffsetScale, yScoreScale);
  drawTotalScoreLine(g, history, xScale, yScoreScale);

  // Add chart title
  g.append('text')
    .attr('x', 0)
    .attr('y', -5)
    .attr('font-weight', 'bold')
    .attr('font-size', '14px')
    .text(`Offset and scores for ${data.server.ip}`);

  // Create legend if specified
  if (config.legend) {
    createLegend(config.legend, data.monitors, g);
  }
}

/**
 * Draw grid lines and axes
 */
function drawGrid(
  g: GSelection,
  xScale: TimeScale,
  yOffsetScale: PowerScale,
  yScoreScale: PowerScale,
  width: number,
  height: number,
  yOffsetMax: number,
  yOffsetMin: number
): void {
  // Draw X-axis grid and labels
  const xTicks = CHART_DEFAULTS.ticks.x;
  const xAxisGroup = g.selectAll<SVGGElement, Date>('g.x-axis')
    .data(xScale.ticks(xTicks))
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
    .text(d => d3.timeFormat('%b %d')(d));

  // Draw Y-axis grid and labels for offset
  const yOffsetTicks = yOffsetScale.ticks(8);
  const yOffsetGroup = g.selectAll<SVGGElement, number>('g.y-offset')
    .data(yOffsetTicks)
    .enter().append('g')
    .attr('class', 'y-offset');

  yOffsetGroup.append('line')
    .attr('x1', 0)
    .attr('x2', width)
    .attr('y1', d => yOffsetScale(d))
    .attr('y2', d => yOffsetScale(d))
    .attr('stroke', COLORS.grid)
    .attr('stroke-dasharray', '2,2');

  // Format for offset values
  const offsetFormat = d3.format(
    (yOffsetMax * 1000 < 3 && yOffsetMin * 1000 > -3) ? '0.1f' : '0.0f'
  );

  yOffsetGroup.append('text')
    .attr('x', -4)
    .attr('y', d => yOffsetScale(d))
    .attr('dy', '.35em')
    .attr('text-anchor', 'end')
    .attr('font-size', '12px')
    .text((_, i) => {
      const ms = yOffsetTicks[i]! * 1000;
      const formatted = offsetFormat(ms);
      return i === 0 ? 'ms' : formatted;
    })
    .attr('font-weight', (_, i) => i === 0 ? 'bold' : 'normal');

  // Draw Y-axis labels for score
  const scoreValues = [20, 0, -20, -50, -100];
  const yScoreGroup = g.selectAll<SVGGElement, number>('g.y-score')
    .data(scoreValues)
    .enter().append('g')
    .attr('class', 'y-score');

  yScoreGroup.append('line')
    .attr('x1', 0)
    .attr('x2', width)
    .attr('y1', d => yScoreScale(d))
    .attr('y2', d => yScoreScale(d))
    .attr('stroke', COLORS.grid)
    .attr('stroke-dasharray', '1,3')
    .attr('opacity', 0.5);

  yScoreGroup.append('text')
    .attr('x', width + 30)
    .attr('y', d => yScoreScale(d))
    .attr('dy', '.35em')
    .attr('text-anchor', 'end')
    .attr('font-size', '11px')
    .attr('fill', '#666')
    .text(d => d.toString());

  // Draw zero offset line
  g.append('line')
    .attr('class', 'zero-offset')
    .attr('x1', 0)
    .attr('x2', width)
    .attr('y1', yOffsetScale(0))
    .attr('y2', yOffsetScale(0))
    .attr('stroke', COLORS.zeroLine)
    .attr('stroke-width', 2);

  // Draw chart border
  g.append('rect')
    .attr('width', width)
    .attr('height', height)
    .attr('fill', 'none')
    .attr('stroke', COLORS.grid);
}

/**
 * Draw score and offset data points
 */
function drawDataPoints(
  g: GSelection,
  history: ServerHistoryPoint[],
  xScale: TimeScale,
  yOffsetScale: PowerScale,
  yScoreScale: PowerScale
): void {
  const monitorData = history.filter(d => d.monitor_id !== null);

  // Draw score points
  g.selectAll<SVGCircleElement, ServerHistoryPoint>('circle.scores')
    .data(monitorData)
    .enter().append('circle')
    .attr('class', 'scores monitor-data')
    .attr('r', 2)
    .attr('cx', d => xScale(d.date))
    .attr('cy', d => yScoreScale(d.score))
    .attr('fill', d => getScoreColor(d.step))
    .on('mouseover', function(_event: MouseEvent, d: ServerHistoryPoint) {
      fadeOtherMonitors(g, d.monitor_id, 0.2);
    })
    .on('mouseout', function() {
      fadeOtherMonitors(g, null, 1);
    });

  // Draw offset points
  g.selectAll<SVGCircleElement, ServerHistoryPoint>('circle.offsets')
    .data(monitorData)
    .enter().append('circle')
    .attr('class', 'offsets monitor-data')
    .attr('r', 1.5)
    .attr('cx', d => xScale(d.date))
    .attr('cy', d => yOffsetScale(d.offset))
    .attr('fill', d => getOffsetColor(d.offset))
    .on('mouseover', function(_event: MouseEvent, d: ServerHistoryPoint) {
      fadeOtherMonitors(g, d.monitor_id, 0.25);
    })
    .on('mouseout', function() {
      fadeOtherMonitors(g, null, 1);
    });
}

/**
 * Draw total score line
 */
function drawTotalScoreLine(
  g: GSelection,
  history: ServerHistoryPoint[],
  xScale: TimeScale,
  yScoreScale: PowerScale
): void {
  const totalScoreData = history.filter(d => d.monitor_id === null);

  if (totalScoreData.length > 0) {
    g.append('path')
      .datum(totalScoreData)
      .attr('class', 'line total-score')
      .attr('fill', 'none')
      .attr('stroke', COLORS.lines.totalScore)
      .attr('stroke-width', 2)
      .attr('d', d3.line<ServerHistoryPoint>()
        .x(d => xScale(d.date))
        .y(d => yScoreScale(d.score))
        .curve(d3.curveMonotoneX)
      );
  }
}

/**
 * Get color for score point based on step value
 */
function getScoreColor(step: number): string {
  if (step < -1) return COLORS.score.error;
  if (step < 0) return COLORS.score.warning;
  return COLORS.score.good;
}

/**
 * Get color for offset point based on absolute offset value
 */
function getOffsetColor(offset: number): string {
  const absOffset = Math.abs(offset);
  if (absOffset < THRESHOLDS.offset.good) return COLORS.offset.good;
  if (absOffset < THRESHOLDS.offset.warning) return COLORS.offset.warning;
  return COLORS.offset.error;
}

/**
 * Create interactive legend table
 */
function createLegend(
  legendContainer: Element,
  monitors: Monitor[],
  chartGroup: GSelection
): void {
  // Apply styles to container
  const htmlContainer = legendContainer as HTMLElement;
  htmlContainer.style.width = '50%';
  htmlContainer.style.marginLeft = `${CHART_DEFAULTS.padding.horizontal}px`;

  // Sort monitors
  const sortedMonitors = sortMonitors(monitors);

  // Create table
  const table = document.createElement('table');
  table.className = 'table table-hover table-sm small';

  const tbody = document.createElement('tbody');
  let currentStatus = '';

  sortedMonitors.forEach(monitor => {
    // Add status header row if status changed
    if (currentStatus !== monitor.status) {
      const statusConfig = MONITOR_STATUS[monitor.status];
      if (statusConfig) {
        const headerRow = document.createElement('tr');
        headerRow.className = statusConfig.class;

        const headerCell = document.createElement('th');
        headerCell.textContent = statusConfig.label;
        headerRow.appendChild(headerCell);

        const scoreCell = document.createElement('td');
        scoreCell.textContent = 'Score';
        headerRow.appendChild(scoreCell);

        tbody.appendChild(headerRow);
        currentStatus = monitor.status;
      }
    }

    // Add monitor row
    const row = document.createElement('tr');
    row.dataset['monitorId'] = monitor.id.toString();

    let name = monitor.name;
    let rowClass = 'table-light';
    let textClass = '';

    if (monitor.type === 'score') {
      if (monitor.name === 'recentmedian') {
        textClass = 'fw-bold';
        name = 'overall';
      } else {
        rowClass = 'table-secondary';
      }
      if (monitor.name === 'every') {
        name = 'legacy';
      }
      name += ' score';
    }

    row.className = rowClass;

    const nameCell = document.createElement('td');
    nameCell.textContent = name;
    nameCell.className = textClass;
    row.appendChild(nameCell);

    const scoreCell = document.createElement('td');
    scoreCell.textContent = monitor.score.toString();
    scoreCell.className = textClass;
    row.appendChild(scoreCell);

    tbody.appendChild(row);
  });

  table.appendChild(tbody);

  // Add hover interactions
  const rows = table.querySelectorAll<HTMLTableRowElement>('tr[data-monitor-id]');
  rows.forEach(row => {
    row.addEventListener('mouseenter', function() {
      const monitorId = this.dataset['monitorId'];
      if (monitorId) {
        fadeOtherMonitors(chartGroup, parseInt(monitorId, 10), 0.25);
      }
    });

    row.addEventListener('mouseleave', function() {
      fadeOtherMonitors(chartGroup, null, 1);
    });
  });

  // Clear and append table to legend container
  legendContainer.innerHTML = '';
  legendContainer.appendChild(table);
}

/**
 * Fade monitors except the specified one
 */
function fadeOtherMonitors(
  chartGroup: GSelection,
  monitorId: number | null,
  opacity: number
): void {
  chartGroup.selectAll<SVGElement, ServerHistoryPoint>('.monitor-data')
    .transition()
    .duration(200)
    .style('opacity', d => {
      if (monitorId === null) return 1;
      return d.monitor_id === monitorId ? 1 : opacity;
    });
}

// Export for backward compatibility with global function
declare global {
  interface Window {
    server_chart?: typeof createServerChart;
  }
}

if (typeof window !== 'undefined') {
  window.server_chart = createServerChart;
}
