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
  sortMonitors,
  clearContainer
} from '@/utils/chart-utils.js';
import { createHoverDebouncer, DEFAULT_HOVER_DEBOUNCE_DELAY } from '@/utils/debounce-utils.js';
import type {
  ServerScoreHistoryResponse,
  ServerHistoryPoint,
  Monitor,
  ServerChartOptions,
  TimeScale,
  PowerScale,
  GSelection,
  ChartGroupElement
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
    showOnlyActiveTesting: false,
    developerMode: false,
    dateFormat: 'default',
    compactHours: false,
    showYearOnFirstTick: false,
    ...options
  } as Required<ServerChartOptions>;

  // Create shared debouncer for ALL chart interactions (prevents race conditions)
  const sharedDebouncer = createHoverDebouncer(DEFAULT_HOVER_DEBOUNCE_DELAY);

  // Process history data with type safety - convert all entries
  const history: ServerHistoryPoint[] = data.history.map(d => ({
    ...d,
    date: parseTimestamp(d.ts),
    offset: d.offset != null ? parseFloat(d.offset.toString()) : null
  }));

  // Calculate offset bounds only from entries with valid offset data (include offset = 0, exclude null)
  const validOffsetHistory = history.filter(d => d.offset != null);
  let yOffsetMax = d3.max(validOffsetHistory, d => d.offset!) ?? 0;
  let yOffsetMin = d3.min(validOffsetHistory, d => d.offset!) ?? 0;

  // Clamp offset values to reasonable bounds
  if (yOffsetMax > THRESHOLDS.offset.max) yOffsetMax = THRESHOLDS.offset.max;
  if (yOffsetMin < THRESHOLDS.offset.min) yOffsetMin = THRESHOLDS.offset.min;

  // Show graph description if element exists
  const graphDesc = document.querySelector('.graph_desc') as HTMLElement | null;
  if (graphDesc) graphDesc.classList.add('graph-desc-visible');

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

  // Pre-process chart data for efficient rendering
  const processedData = processChartData(history);

  // Draw chart elements
  drawGrid(g, xScale, yOffsetScale, yScoreScale, innerWidth, innerHeight, yOffsetMax, yOffsetMin, config);
  drawDataPoints(g, processedData, xScale, yOffsetScale, yScoreScale, sharedDebouncer);
  drawTotalScoreLine(g, processedData, xScale, yScoreScale);

  // Add chart title
  g.append('text')
    .attr('x', 0)
    .attr('y', -5)
    .attr('font-weight', 'bold')
    .attr('font-size', '14px')
    .text(`Offset and scores for ${data.server.ip}`);

  // Create legend if specified
  if (config.legend) {
    createLegend(config.legend, data.monitors, g, sharedDebouncer, config.showOnlyActiveTesting);
  }
}

/**
 * Create simplified date formatter for chart x-axis
 */
function createDateFormatter(
  compactHours: boolean,
  timeRange: number,
  isFirstTickOfDate = false
): (date: Date) => string {
  const oneDay = 24 * 60 * 60 * 1000;

  return (date: Date) => {
    if (timeRange <= oneDay) {
      // Single day: use compact hour format for zero minutes if enabled
      if (compactHours && date.getUTCMinutes() === 0) {
        return `${date.getUTCHours()}h`;
      }
      return d3.utcFormat('%H:%M')(date);
    }

    // Multi-day ranges: show date only once per day
    if (isFirstTickOfDate) {
      // First time showing this date
      if (date.getUTCHours() === 0 && date.getUTCMinutes() === 0) {
        // At midnight - show just the date
        return d3.utcFormat('%Y-%m-%d')(date);
      } else {
        // Not at midnight - show date + time
        if (compactHours && date.getUTCMinutes() === 0) {
          return d3.utcFormat('%Y-%m-%d')(date) + ` ${date.getUTCHours()}h`;
        } else {
          return d3.utcFormat('%Y-%m-%d %H:%M')(date);
        }
      }
    } else {
      // Already showed date for this day, just show time
      if (compactHours && date.getUTCMinutes() === 0) {
        // At zero minutes - show compact hour format if enabled
        return `${date.getUTCHours()}h`;
      } else {
        // Not at zero minutes or compact hours disabled - show hour:minute
        return d3.utcFormat('%H:%M')(date);
      }
    }
  };
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
  yOffsetMin: number,
  config: Required<ServerChartOptions>
): void {
  // Draw X-axis grid and labels
  // Reduce tick count to prevent overlapping when showing longer timestamps
  const domain = xScale.domain();
  const timeRange = (domain[0] && domain[1]) ? domain[1].getTime() - domain[0].getTime() : 24 * 60 * 60 * 1000;
  const oneDay = 24 * 60 * 60 * 1000;
  const xTicks = timeRange <= oneDay ? 6 : 5; // Fewer ticks for longer ranges

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

  // Track which dates we've already shown for multi-day ranges
  const shownDates = new Set<string>();

  xAxisGroup.append('text')
    .attr('x', d => xScale(d))
    .attr('y', height + 3)
    .attr('dy', '.71em')
    .attr('text-anchor', 'middle')
    .attr('font-size', '11px')
    // .attr('transform', d => `rotate(-45, ${xScale(d)}, ${height + 3})`)
    .text(d => {
      // For multi-day ranges, check if this is the first time showing this date
      let isFirstTickOfDate = false;
      if (timeRange > oneDay) {
        const dateKey = `${d.getUTCFullYear()}-${d.getUTCMonth()}-${d.getUTCDate()}`;
        isFirstTickOfDate = !shownDates.has(dateKey);
        if (isFirstTickOfDate) {
          shownDates.add(dateKey);
        }
      }

      const formatter = createDateFormatter(config.compactHours, timeRange, isFirstTickOfDate);
      return formatter(d);
    });

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
    .attr('stroke-width', 1);

  // Draw chart border
  g.append('rect')
    .attr('width', width)
    .attr('height', height)
    .attr('fill', 'none')
    .attr('stroke', COLORS.grid);
}

/**
 * Pre-process chart data for efficient rendering
 */
interface ProcessedChartData {
  scorePoints: ServerHistoryPoint[];
  offsetPoints: ServerHistoryPoint[];
  totalScorePoints: ServerHistoryPoint[];
}

function processChartData(history: ServerHistoryPoint[]): ProcessedChartData {
  const scorePoints: ServerHistoryPoint[] = [];
  const offsetPoints: ServerHistoryPoint[] = [];
  const totalScorePoints: ServerHistoryPoint[] = [];

  for (const point of history) {
    if (point.monitor_id === null) {
      totalScorePoints.push(point);
    } else {
      scorePoints.push(point);
      if (point.offset != null) {
        offsetPoints.push(point);
      }
    }
  }

  return { scorePoints, offsetPoints, totalScorePoints };
}

/**
 * Draw score and offset data points
 */
function drawDataPoints(
  g: GSelection,
  processedData: ProcessedChartData,
  xScale: TimeScale,
  yOffsetScale: PowerScale,
  yScoreScale: PowerScale,
  sharedDebouncer: ReturnType<typeof createHoverDebouncer>
): void {

  // Draw score points (all monitor data, regardless of offset)
  g.selectAll<SVGCircleElement, ServerHistoryPoint>('circle.scores')
    .data(processedData.scorePoints)
    .enter().append('circle')
    .attr('class', 'scores monitor-data')
    .attr('r', 1.5) // Circle radius for score data points
    .attr('cx', d => xScale(d.date))
    .attr('cy', d => yScoreScale(d.score))
    .attr('fill', d => getScoreColor(d.step))
    .on('mouseover', function (_event: MouseEvent, d: ServerHistoryPoint) {
      const startTime = performance.now();
      console.log('🎨 Score point mouseover (debounced):', { monitorId: d.monitor_id, timestamp: startTime });

      // Use shared debouncer for hover actions
      sharedDebouncer.debounce(() => {
        console.log('🎨 Score point executing debounced action:', { monitorId: d.monitor_id });
        fadeOtherMonitors(g, d.monitor_id, 0.05);
        highlightTableCellsGlobally(d.monitor_id, true);
      }, d.monitor_id);
    })
    .on('mouseout', function () {
      const startTime = performance.now();
      console.log('🎨 Score point mouseout (debounced):', { timestamp: startTime });

      // Use shared debouncer for mouseout to allow smooth transitions
      sharedDebouncer.debounce(() => {
        console.log('🎨 Score point executing mouseout action');
        fadeOtherMonitors(g, null, 1);
        highlightTableCellsGlobally(null, false);
      }, null);
    });

  // Draw offset points (only data with valid offset values)
  g.selectAll<SVGCircleElement, ServerHistoryPoint>('circle.offsets')
    .data(processedData.offsetPoints)
    .enter().append('circle')
    .attr('class', 'offsets monitor-data')
    .attr('r', 1) // Circle radius for offset data points
    .attr('cx', d => xScale(d.date))
    .attr('cy', d => yOffsetScale(d.offset!))
    .attr('fill', d => getOffsetColor(d.offset!))
    .on('mouseover', function (_event: MouseEvent, d: ServerHistoryPoint) {
      const startTime = performance.now();
      console.log('📊 Offset point mouseover (debounced):', { monitorId: d.monitor_id, timestamp: startTime });

      // Use shared debouncer for hover actions
      sharedDebouncer.debounce(() => {
        console.log('📊 Offset point executing debounced action:', { monitorId: d.monitor_id });
        fadeOtherMonitors(g, d.monitor_id, 0.12);
        highlightTableCellsGlobally(d.monitor_id, true);
      }, d.monitor_id);
    })
    .on('mouseout', function () {
      const startTime = performance.now();
      console.log('📊 Offset point mouseout (debounced):', { timestamp: startTime });

      // Use shared debouncer for mouseout to allow smooth transitions
      sharedDebouncer.debounce(() => {
        console.log('📊 Offset point executing mouseout action');
        fadeOtherMonitors(g, null, 1);
        highlightTableCellsGlobally(null, false);
      }, null);
    });
}

/**
 * Draw total score line
 */
function drawTotalScoreLine(
  g: GSelection,
  processedData: ProcessedChartData,
  xScale: TimeScale,
  yScoreScale: PowerScale
): void {
  if (processedData.totalScorePoints.length > 0) {
    g.append('path')
      .datum(processedData.totalScorePoints)
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
  if (step < -2) return COLORS.score.error;
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
 * Get the appropriate padding CSS class based on pixel value
 */
function getPaddingClass(paddingValue: number): string {
  // Round to nearest 10 and clamp to available classes
  const rounded = Math.round(paddingValue / 10) * 10;
  const clamped = Math.max(20, Math.min(100, rounded));
  return `padding-${clamped}`;
}

/**
 * Create interactive legend with multi-column layout
 */
function createLegend(
  legendContainer: Element,
  monitors: Monitor[],
  chartGroup: GSelection,
  sharedDebouncer: ReturnType<typeof createHoverDebouncer>,
  showOnlyActiveTesting = false
): void {
  // Store monitor status map on chartGroup for use by fadeOtherMonitors
  const monitorStatusMap = new Map(monitors.map(m => [m.id, m.status]));
  const chartGroupElement = chartGroup.node() as ChartGroupElement | null;
  if (chartGroupElement) {
    chartGroupElement.__monitorStatusMap = monitorStatusMap;
  }

  // Apply styles to container
  const htmlContainer = legendContainer as HTMLElement;
  htmlContainer.classList.add('legend-container');
  htmlContainer.classList.add(getPaddingClass(CHART_DEFAULTS.padding.horizontal));

  // CSS styles are now in /src/styles/_components.scss

  // Filter monitors if showOnlyActiveTesting is enabled
  let filteredMonitors = monitors;
  if (showOnlyActiveTesting) {
    filteredMonitors = monitors.filter(monitor =>
      monitor.status === 'active' || monitor.status === 'testing'
    );
  }

  // Sort monitors and group by status
  const sortedMonitors = sortMonitors(filteredMonitors);
  const statusGroups = groupMonitorsByStatus(sortedMonitors);

  // Clear container
  clearContainer(legendContainer);

  // Create single table with multi-column layout
  createSingleTableLegend(legendContainer, statusGroups, chartGroup, sharedDebouncer);
}

/**
 * Group monitors by status
 */
function groupMonitorsByStatus(monitors: Monitor[]): Record<string, Monitor[]> {
  const groups: Record<string, Monitor[]> = {};
  monitors.forEach(monitor => {
    if (!groups[monitor.status]) {
      groups[monitor.status] = [];
    }
    groups[monitor.status]!.push(monitor);
  });
  return groups;
}

/**
 * Create separate tables for priority and other statuses
 */
function createSingleTableLegend(
  container: Element,
  statusGroups: Record<string, Monitor[]>,
  chartGroup: GSelection,
  sharedDebouncer: ReturnType<typeof createHoverDebouncer>
): void {

  // Process statuses in priority order: Active, Testing first, then others
  const priorityStatuses = ['active', 'testing'];
  const sortedStatuses = Object.keys(statusGroups).sort((a, b) => {
    const aConfig = MONITOR_STATUS[a] ?? { order: 999 };
    const bConfig = MONITOR_STATUS[b] ?? { order: 999 };
    return aConfig.order - bConfig.order;
  });

  // Separate priority and other statuses
  const priorityGroups: Record<string, Monitor[]> = {};
  const otherGroups: Record<string, Monitor[]> = {};

  sortedStatuses.forEach(status => {
    if (priorityStatuses.includes(status) && statusGroups[status]) {
      priorityGroups[status] = statusGroups[status];
    } else if (statusGroups[status]) {
      otherGroups[status] = statusGroups[status];
    }
  });

  // Create priority table (Active | Testing) with RTT
  if (Object.keys(priorityGroups).length > 0) {
    const priorityTable = createTable('priority-table');
    const priorityTbody = document.createElement('tbody');
    createTableSection(priorityTbody, priorityGroups, chartGroup, true);
    priorityTable.appendChild(priorityTbody);
    addTableEventListeners(priorityTable, chartGroup, sharedDebouncer);
    container.appendChild(priorityTable);
  }

  // Add spacing between tables if both exist
  if (Object.keys(priorityGroups).length > 0 && Object.keys(otherGroups).length > 0) {
    const spacer = document.createElement('div');
    spacer.classList.add('legend-spacer');
    container.appendChild(spacer);
  }

  // Create other statuses table (3-column layout)
  if (Object.keys(otherGroups).length > 0) {
    const otherTable = createTable('other-statuses-table');
    const otherTbody = document.createElement('tbody');
    createTableSection(otherTbody, otherGroups, chartGroup, false);
    otherTable.appendChild(otherTbody);
    addTableEventListeners(otherTable, chartGroup, sharedDebouncer);
    container.appendChild(otherTable);
  }
}

/**
 * Create a table element with standard classes
 */
function createTable(additionalClass: string): HTMLTableElement {
  const table = document.createElement('table');
  table.className = `table table-sm small legend-table ${additionalClass}`;
  return table;
}

/**
 * Unified state management function - handles both monitor and status filtering
 * Eliminates race conditions by using single state clearing logic
 */
function setState(
  target: number | string | null,
  type: 'monitor' | 'status',
  chartGroup: GSelection,
  table: HTMLTableElement
): void {
  const startTime = performance.now();
  console.log('🎯 setState:', { target, type, timestamp: startTime });

  // Always clear existing highlights first (atomic operation)
  const allHighlighted = table.querySelectorAll('.monitor-cell-hover');
  allHighlighted.forEach(cell => cell.classList.remove('monitor-cell-hover'));

  if (target !== null) {
    if (type === 'monitor') {
      // Highlight specific monitor
      const targetCells = table.querySelectorAll(`[data-monitor-id="${target}"]`);
      targetCells.forEach(cell => cell.classList.add('monitor-cell-hover'));
      fadeOtherMonitors(chartGroup, target as number, 0.15);
    } else if (type === 'status') {
      // Highlight all monitors with the target status
      const monitorStatusMap = (chartGroup.node() as ChartGroupElement | null)?.__monitorStatusMap;
      if (monitorStatusMap) {
        const monitorCells = table.querySelectorAll('[data-monitor-id]');
        monitorCells.forEach(cell => {
          const monitorId = parseInt((cell as HTMLElement).dataset['monitorId']!, 10);
          const monitorStatus = monitorStatusMap.get(monitorId);
          if (monitorStatus === target) {
            cell.classList.add('monitor-cell-hover');
          }
        });
        fadeOtherMonitors(chartGroup, target as string, 0.15, 'status');
      }
    }
  } else {
    // Clear all filters
    fadeOtherMonitors(chartGroup, null, 1);
  }

  console.log('🎯 setState complete:', {
    target,
    type,
    duration: performance.now() - startTime
  });
}

/**
 * Add event delegation listeners to a table with shared debouncing
 */
function addTableEventListeners(
  table: HTMLTableElement,
  chartGroup: GSelection,
  sharedDebouncer: ReturnType<typeof createHoverDebouncer>
): void {

  table.addEventListener('mouseenter', function (e) {
    const startTime = performance.now();
    const target = e.target as Element;

    // Check for status header hover
    if (target instanceof HTMLElement && target.classList.contains('status-header') && target.dataset['monitorStatus']) {
      const status = target.dataset['monitorStatus'];
      console.log('🏓 Status header mouseenter (debounced):', { status, timestamp: startTime });

      // Use unified debounced state management for status
      sharedDebouncer.debounce(() => {
        console.log('🏓 Status header executing debounced mouseenter:', { status });
        setState(status, 'status', chartGroup, table);
      }, `status:${status}`); // Use unique identifier for status operations
    }
    // Check if we're hovering over a monitor cell (has data-monitor-id)
    else if (target instanceof HTMLElement && target.dataset['monitorId']) {
      const monitorId = parseInt(target.dataset['monitorId'], 10);
      console.log('🏓 Table mouseenter (debounced):', { monitorId, timestamp: startTime });

      // Use unified debounced state management
      sharedDebouncer.debounce(() => {
        console.log('🏓 Table executing debounced mouseenter:', { monitorId });
        setState(monitorId, 'monitor', chartGroup, table);
      }, `monitor:${monitorId}`); // Use unique identifier for monitor operations
    }
  }, true);

  table.addEventListener('mouseleave', function (e) {
    const startTime = performance.now();
    const target = e.target as Element;

    // Check if we're leaving a status header or monitor cell
    if (target instanceof HTMLElement && (target.classList.contains('status-header') || target.dataset['monitorId'])) {
      const identifier = target.dataset['monitorId'] || target.dataset['monitorStatus'];
      console.log('🏓 Table mouseleave (debounced):', { identifier, timestamp: startTime });

      // Use unified debounced state management (KEY FIX: no more immediate clearing)
      sharedDebouncer.debounce(() => {
        console.log('🏓 Table executing debounced mouseleave:', { identifier });
        if (target.classList.contains('status-header')) {
          setState(null, 'status', chartGroup, table);
        } else {
          setState(null, 'monitor', chartGroup, table);
        }
      }, 'clear'); // Use unique identifier for clear operations
    }
  }, true);
}


/**
 * Create a section of the table with monitors arranged in columns
 */
function createTableSection(
  tbody: HTMLElement,
  statusGroups: Record<string, Monitor[]>,
  _chartGroup: GSelection, // Used in nested functions but not directly here
  isPrioritySection: boolean
): void {
  // Get statuses in proper sorted order, not arbitrary Object.keys order
  const statuses = Object.keys(statusGroups).sort((a, b) => {
    const aConfig = MONITOR_STATUS[a] ?? { order: 999 };
    const bConfig = MONITOR_STATUS[b] ?? { order: 999 };
    return aConfig.order - bConfig.order;
  });

  if (isPrioritySection) {
    // Priority section: Active in column 1, Testing in column 2
    const activeMonitors = statusGroups['active'] || [];
    const testingMonitors = statusGroups['testing'] || [];
    const maxRows = Math.max(activeMonitors.length, testingMonitors.length);

    // Add headers
    if (activeMonitors.length > 0 || testingMonitors.length > 0) {
      const headerRow = document.createElement('tr');

      // Active header (Name | Score | RTT)
      const activeHeader = document.createElement('th');
      activeHeader.className = `status-header ${MONITOR_STATUS['active']?.class || ''}`;
      activeHeader.textContent = MONITOR_STATUS['active']?.label || 'Active';
      activeHeader.colSpan = 3;
      activeHeader.dataset['monitorStatus'] = 'active';
      headerRow.appendChild(activeHeader);

      // Gap
      const gapHeader = document.createElement('th');
      gapHeader.className = 'column-gap empty-cell';
      headerRow.appendChild(gapHeader);

      // Testing header (Name | Score | RTT)
      const testingHeader = document.createElement('th');
      testingHeader.className = `status-header ${MONITOR_STATUS['testing']?.class || ''}`;
      testingHeader.textContent = MONITOR_STATUS['testing']?.label || 'Testing';
      testingHeader.colSpan = 3;
      testingHeader.dataset['monitorStatus'] = 'testing';
      headerRow.appendChild(testingHeader);

      tbody.appendChild(headerRow);
    }

    // Add monitor rows
    for (let i = 0; i < maxRows; i++) {
      const row = document.createElement('tr');

      // Column 1: Active monitor (Name | Score | RTT)
      if (i < activeMonitors.length) {
        const monitor = activeMonitors[i]!;
        const monitorRow = createMonitorRow(monitor, true); // true for includeRtt
        // Extract cells from the created row and add to current row
        while (monitorRow.firstChild) {
          row.appendChild(monitorRow.firstChild);
        }
      } else {
        // Empty cells (Name | Score | RTT)
        row.appendChild(createEmptyCell());
        row.appendChild(createEmptyCell());
        row.appendChild(createEmptyCell());
      }

      // Gap
      row.appendChild(createEmptyCell('column-gap'));

      // Column 2: Testing monitor (Name | Score | RTT)
      if (i < testingMonitors.length) {
        const monitor = testingMonitors[i]!;
        const monitorRow = createMonitorRow(monitor, true); // true for includeRtt
        // Extract cells from the created row and add to current row
        while (monitorRow.firstChild) {
          row.appendChild(monitorRow.firstChild);
        }
      } else {
        // Empty cells (Name | Score | RTT)
        row.appendChild(createEmptyCell());
        row.appendChild(createEmptyCell());
        row.appendChild(createEmptyCell());
      }

      tbody.appendChild(row);
    }
  } else {
    // Other statuses section: Process in the order from the original status groups
    // The statusGroups should already be ordered properly since we separated them
    // from the sortedStatuses array
    statuses.forEach(status => {
      const monitors = statusGroups[status] || [];
      const statusConfig = MONITOR_STATUS[status];

      if (!statusConfig || monitors.length === 0) return;

      // Add status header spanning all columns
      // Calculate colspan based on maximum monitors in any row (up to 3)
      const maxMonitorsInRow = Math.min(monitors.length, 3);
      const headerColspan = maxMonitorsInRow === 1 ? 2 :
        maxMonitorsInRow === 2 ? 5 : // Name|Score|Gap|Name|Score
          8; // Name|Score|Gap|Name|Score|Gap|Name|Score

      const headerRow = document.createElement('tr');
      const headerCell = document.createElement('th');
      headerCell.className = `status-header ${statusConfig.class}`;
      headerCell.textContent = statusConfig.label;
      headerCell.colSpan = headerColspan;
      headerCell.dataset['monitorStatus'] = status;
      headerRow.appendChild(headerCell);
      tbody.appendChild(headerRow);

      // Add monitors in three-column layout
      for (let i = 0; i < monitors.length; i += 3) {
        const row = document.createElement('tr');

        // Column 1: First monitor
        const monitor1 = monitors[i]!;
        const monitorRow1 = createMonitorRow(monitor1, false, true); // false for no RTT, true for 3-col
        while (monitorRow1.firstChild) {
          row.appendChild(monitorRow1.firstChild);
        }

        // Gap after first column
        row.appendChild(createEmptyCell('column-gap'));

        // Column 2: Second monitor (if exists)
        if (i + 1 < monitors.length) {
          const monitor2 = monitors[i + 1]!;
          const monitorRow2 = createMonitorRow(monitor2, false, true);
          while (monitorRow2.firstChild) {
            row.appendChild(monitorRow2.firstChild);
          }
        } else {
          // Empty cells if no second monitor
          row.appendChild(createEmptyCell());
          row.appendChild(createEmptyCell());
        }

        // Gap after second column (only if there's a third monitor)
        if (i + 2 < monitors.length) {
          row.appendChild(createEmptyCell('column-gap'));

          // Column 3: Third monitor
          const monitor3 = monitors[i + 2]!;
          const monitorRow3 = createMonitorRow(monitor3, false, true);
          while (monitorRow3.firstChild) {
            row.appendChild(monitorRow3.firstChild);
          }
        }

        tbody.appendChild(row);
      }
    });
  }
}

/**
 * Create a simple table cell with content and class
 */
function createCell(content: string, className: string): HTMLElement {
  const cell = document.createElement('td');
  cell.className = className;
  cell.textContent = content;
  return cell;
}

/**
 * Get display name for a monitor (handles special cases)
 */
function getMonitorDisplayName(monitor: Monitor): string {
  if (monitor.type === 'score') {
    if (monitor.name === 'recentmedian') {
      return 'overall';
    }
    if (monitor.name === 'every') {
      return 'legacy';
    }
    return `${monitor.name} score`;
  }
  return monitor.name;
}

/**
 * Create a complete monitor row (no event listeners - handled by delegation)
 */
function createMonitorRow(monitor: Monitor, includeRtt: boolean, threeColumn = false): HTMLElement {
  const row = document.createElement('tr');
  // Only set row-level monitor ID for single-monitor rows (like priority section)
  if (!threeColumn) {
    row.dataset['monitorId'] = monitor.id.toString();
  }

  const displayName = getMonitorDisplayName(monitor);
  const nameClass = threeColumn ? 'monitor-name-3col' : 'monitor-name';
  const scoreClass = threeColumn ? 'monitor-score-3col' : 'monitor-score';

  // Apply special formatting for score monitors
  let textClass = '';
  if (monitor.type === 'score' && monitor.name === 'recentmedian') {
    textClass = ' fw-bold';
  }

  // Add cells: Name | Score | RTT (if applicable)
  const nameCell = createCell(displayName, nameClass + textClass);
  const scoreCell = createCell(monitor.score.toString(), scoreClass + textClass);

  // Add monitor ID to individual cells for precise hover targeting
  nameCell.dataset['monitorId'] = monitor.id.toString();
  scoreCell.dataset['monitorId'] = monitor.id.toString();

  row.appendChild(nameCell);
  row.appendChild(scoreCell);

  if (includeRtt) {
    let rttContent = '';
    if ((monitor.status === 'active' || monitor.status === 'testing') && monitor.avg_rtt !== undefined) {
      rttContent = `${monitor.avg_rtt.toFixed(1)}ms`;
    }
    const rttCell = createCell(rttContent, 'monitor-rtt monitor-rtt-fallback');
    // Add monitor ID to RTT cell for precise hover targeting
    rttCell.dataset['monitorId'] = monitor.id.toString();
    row.appendChild(rttCell);
  }

  return row;
}


/**
 * Create an empty table cell
 */
function createEmptyCell(className?: string): HTMLElement {
  const cell = document.createElement('td');
  cell.className = `empty-cell ${className || ''}`;
  return cell;
}


/**
 * Fade monitors except the specified one or status group
 */
function fadeOtherMonitors(
  chartGroup: GSelection,
  targetIdentifier: number | string | null,
  opacity: number,
  filterType: 'monitor' | 'status' = 'monitor'
): void {
  const startTime = performance.now();
  const selection = chartGroup.selectAll<SVGElement, ServerHistoryPoint>('.monitor-data');
  const elementCount = selection.size();

  console.log('🎯 fadeOtherMonitors start:', {
    targetIdentifier,
    filterType,
    opacity,
    elementCount,
    timestamp: startTime
  });

  // Get monitor status map from chartGroup if available
  const monitorStatusMap = (chartGroup.node() as ChartGroupElement | null)?.__monitorStatusMap;

  // Apply opacity changes immediately without transitions
  selection.style('opacity', d => {
    if (targetIdentifier === null) return 1;

    if (filterType === 'status' && monitorStatusMap && d.monitor_id !== null) {
      // Status-based filtering using Map lookup
      const monitorStatus = monitorStatusMap.get(d.monitor_id);
      return monitorStatus === targetIdentifier ? 1 : opacity;
    } else if (filterType === 'monitor') {
      // Monitor ID-based filtering (existing logic)
      return d.monitor_id === targetIdentifier ? 1 : opacity;
    } else {
      // Fallback: data points without monitor_id or no status map
      return opacity;
    }
  });

  // For score points, also change color to gray when dimmed
  const scorePoints = chartGroup.selectAll<SVGElement, ServerHistoryPoint>('.scores.monitor-data');
  scorePoints.style('fill', d => {
    if (targetIdentifier === null) {
      // Restore original color
      return getScoreColor(d.step);
    }

    let isTarget = false;
    if (filterType === 'status' && monitorStatusMap && d.monitor_id !== null) {
      const monitorStatus = monitorStatusMap.get(d.monitor_id);
      isTarget = monitorStatus === targetIdentifier;
    } else if (filterType === 'monitor') {
      isTarget = d.monitor_id === targetIdentifier;
    }

    return isTarget ? getScoreColor(d.step) : '#888888';
  });

  // Log completion immediately since there's no transition
  const endTime = performance.now();
  console.log('🎯 fadeOtherMonitors end:', {
    targetIdentifier,
    filterType,
    elementCount,
    duration: endTime - startTime,
    timestamp: endTime
  });
}

/**
 * Simple global table cell highlighting for chart interactions
 * Only called by chart points, not by table event handlers
 */
function highlightTableCellsGlobally(monitorId: number | null, highlight: boolean): void {
  if (highlight && monitorId !== null) {
    const monitorCells = document.querySelectorAll(`[data-monitor-id="${monitorId}"]`);
    monitorCells.forEach(cell => cell.classList.add('monitor-cell-hover'));
  } else {
    const allHighlighted = document.querySelectorAll('.monitor-cell-hover');
    allHighlighted.forEach(cell => cell.classList.remove('monitor-cell-hover'));
  }
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
