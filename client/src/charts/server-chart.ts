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
    showOnlyActiveTesting: false,
    ...options
  } as Required<ServerChartOptions>;

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
  drawGrid(g, xScale, yOffsetScale, yScoreScale, innerWidth, innerHeight, yOffsetMax, yOffsetMin);
  drawDataPoints(g, processedData, xScale, yOffsetScale, yScoreScale);
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
    createLegend(config.legend, data.monitors, g, config.showOnlyActiveTesting);
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
  // Reduce tick count to prevent overlapping when showing longer timestamps
  const domain = xScale.domain();
  const timeRange = (domain[0] && domain[1]) ? domain[1].getTime() - domain[0].getTime() : 24 * 60 * 60 * 1000;
  const oneDay = 24 * 60 * 60 * 1000;
  const xTicks = timeRange <= oneDay ? 8 : 6; // Fewer ticks for longer ranges

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
    .attr('font-size', '11px')
    // .attr('transform', d => `rotate(-45, ${xScale(d)}, ${height + 3})`)
    .text(d => {
      if (timeRange <= oneDay) {
        // For time ranges within a day, show time in 24-hour UTC format
        return d3.utcFormat('%H:%M')(d);
      } else {
        // For longer ranges, show date and time in 24-hour UTC format
        return d3.utcFormat('%b %d %H:%M')(d);
      }
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
  yScoreScale: PowerScale
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
      fadeOtherMonitors(g, d.monitor_id, 0.2);
      highlightTableCells(d.monitor_id, true);
    })
    .on('mouseout', function () {
      fadeOtherMonitors(g, null, 1);
      highlightTableCells(null, false);
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
      fadeOtherMonitors(g, d.monitor_id, 0.25);
      highlightTableCells(d.monitor_id, true);
    })
    .on('mouseout', function () {
      fadeOtherMonitors(g, null, 1);
      highlightTableCells(null, false);
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
  showOnlyActiveTesting = false
): void {
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
  createSingleTableLegend(legendContainer, statusGroups, chartGroup);
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
  chartGroup: GSelection
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
    addTableEventListeners(priorityTable, chartGroup);
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
    addTableEventListeners(otherTable, chartGroup);
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
 * Add event delegation listeners to a table
 */
function addTableEventListeners(table: HTMLTableElement, chartGroup: GSelection): void {
  table.addEventListener('mouseenter', function(e) {
    const target = e.target as Element;

    // Check if we're hovering over a monitor cell (has data-monitor-id)
    if (target instanceof HTMLElement && target.dataset['monitorId']) {
      const monitorId = parseInt(target.dataset['monitorId'], 10);

      // Find ALL cells in the table with the same monitor ID
      const monitorCells = table.querySelectorAll(`[data-monitor-id="${monitorId}"]`);
      monitorCells.forEach(cell => cell.classList.add('monitor-cell-hover'));

      // Fade other monitors in the chart
      fadeOtherMonitors(chartGroup, monitorId, 0.25);
    }
  }, true);

  table.addEventListener('mouseleave', function(e) {
    const target = e.target as Element;

    // Check if we're leaving a monitor cell
    if (target instanceof HTMLElement && target.dataset['monitorId']) {
      // Remove highlight from all monitor cells in the table
      const allCells = table.querySelectorAll('.monitor-cell-hover');
      allCells.forEach(cell => cell.classList.remove('monitor-cell-hover'));

      // Reset chart highlighting
      fadeOtherMonitors(chartGroup, null, 1);
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

/**
 * Highlight table cells for the specified monitor
 */
function highlightTableCells(monitorId: number | null, highlight: boolean): void {
  if (highlight && monitorId !== null) {
    // Find all table cells with matching monitor ID
    const monitorCells = document.querySelectorAll(`[data-monitor-id="${monitorId}"]`);
    monitorCells.forEach(cell => cell.classList.add('monitor-cell-hover'));
  } else {
    // Remove highlight from all table cells
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
