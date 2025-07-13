/* Copyright 2012-2025 Ask Bjørn Hansen, Develooper LLC & NTP Pool Project */

/**
 * Server chart module for displaying offset and score data
 * Modern ES6+ implementation with D3.js v7
 */

import {
    getElementDimensions,
    parseTimestamp,
    CHART_DEFAULTS,
    COLORS,
    THRESHOLDS,
    createSvgContainer,
    addAccessibilityLabels,
    formatNumber,
    MONITOR_STATUS,
    sortMonitors
} from './chart-utils.js';

/**
 * Create a server chart showing offset and score over time
 * @param {Element} container - Container element for the chart
 * @param {Object} data - Chart data with history and monitors
 * @param {Object} options - Chart options
 */
export function createServerChart(container, data, options = {}) {
    const config = {
        legend: options.legend || null,
        ...options
    };

    // Process history data
    const history = data.history.map(d => ({
        ...d,
        date: parseTimestamp(d.ts),
        offset: parseFloat(d.offset)
    }));

    // Calculate offset bounds
    let yOffsetMax = d3.max(history, d => d.offset) || 0;
    let yOffsetMin = d3.min(history, d => d.offset) || 0;

    // Clamp offset values to reasonable bounds
    if (yOffsetMax > THRESHOLDS.offset.max) yOffsetMax = THRESHOLDS.offset.max;
    if (yOffsetMin < THRESHOLDS.offset.min) yOffsetMin = THRESHOLDS.offset.min;

    // Show graph description if element exists
    const graphDesc = document.querySelector('.graph_desc');
    if (graphDesc) graphDesc.style.display = 'block';

    // Calculate dimensions
    const dimensions = getElementDimensions(container);
    const padding = { horizontal: 45, vertical: 19 };
    const innerWidth = dimensions.width - (padding.horizontal * 2);
    const innerHeight = dimensions.height - (padding.vertical * 2);

    // Create scales
    const yOffsetScale = d3.scalePow()
        .exponent(0.5)
        .domain([yOffsetMax, yOffsetMin])
        .range([0, innerHeight])
        .clamp(true);

    const yScoreScale = d3.scaleSqrt()
        .domain([THRESHOLDS.score.max, THRESHOLDS.score.min])
        .range([0, innerHeight]);

    const xScale = d3.scaleUtc()
        .domain(d3.extent(history, d => d.date))
        .range([0, innerWidth]);

    // Create SVG container
    const { svg, g } = createSvgContainer(container, {
        width: dimensions.width,
        height: dimensions.height,
        padding
    });

    // Add accessibility labels
    addAccessibilityLabels(
        svg.node(),
        `Offset and scores for ${data.server.ip}`,
        `Time series chart showing NTP server offset and score measurements over time`
    );

    // Draw X-axis grid and labels
    const xTicks = CHART_DEFAULTS.ticks.x;
    const xAxisGroup = g.selectAll("g.x-axis")
        .data(xScale.ticks(xTicks))
        .enter().append("g")
        .attr("class", "x-axis");

    xAxisGroup.append("line")
        .attr("x1", d => xScale(d))
        .attr("x2", d => xScale(d))
        .attr("y1", 0)
        .attr("y2", innerHeight)
        .attr("stroke", COLORS.grid)
        .attr("stroke-dasharray", "2,2");

    xAxisGroup.append("text")
        .attr("x", d => xScale(d))
        .attr("y", innerHeight + 3)
        .attr("dy", ".71em")
        .attr("text-anchor", "middle")
        .attr("font-size", "12px")
        .text(d => d3.timeFormat("%b %d")(d));

    // Draw Y-axis grid and labels for offset
    const yOffsetTicks = yOffsetScale.ticks(8);
    const yOffsetGroup = g.selectAll("g.y-offset")
        .data(yOffsetTicks)
        .enter().append("g")
        .attr("class", "y-offset");

    yOffsetGroup.append("line")
        .attr("x1", 0)
        .attr("x2", innerWidth)
        .attr("y1", d => yOffsetScale(d))
        .attr("y2", d => yOffsetScale(d))
        .attr("stroke", COLORS.grid)
        .attr("stroke-dasharray", "2,2");

    // Format for offset values
    const offsetFormat = d3.format(
        (yOffsetMax * 1000 < 3 && yOffsetMin * 1000 > -3) ? "0.1f" : "0.0f"
    );

    yOffsetGroup.append("text")
        .attr("x", -4)
        .attr("y", d => yOffsetScale(d))
        .attr("dy", ".35em")
        .attr("text-anchor", "end")
        .attr("font-size", "12px")
        .text((d, i) => {
            const ms = d * 1000;
            const formatted = offsetFormat(ms);
            return i === 0 ? "ms" : formatted;
        })
        .attr("font-weight", (d, i) => i === 0 ? "bold" : "normal");

    // Draw Y-axis labels for score
    const scoreValues = [20, 0, -20, -50, -100];
    const yScoreGroup = g.selectAll("g.y-score")
        .data(scoreValues)
        .enter().append("g")
        .attr("class", "y-score");

    yScoreGroup.append("line")
        .attr("x1", 0)
        .attr("x2", innerWidth)
        .attr("y1", d => yScoreScale(d))
        .attr("y2", d => yScoreScale(d))
        .attr("stroke", COLORS.grid)
        .attr("stroke-dasharray", "1,3")
        .attr("opacity", 0.5);

    yScoreGroup.append("text")
        .attr("x", innerWidth + 30)
        .attr("y", d => yScoreScale(d))
        .attr("dy", ".35em")
        .attr("text-anchor", "end")
        .attr("font-size", "11px")
        .attr("fill", "#666")
        .text(d => d);


    // Draw zero offset line
    g.append("line")
        .attr("class", "zero-offset")
        .attr("x1", 0)
        .attr("x2", innerWidth)
        .attr("y1", yOffsetScale(0))
        .attr("y2", yOffsetScale(0))
        .attr("stroke", COLORS.zeroLine)
        .attr("stroke-width", 2);

    // Draw chart border
    g.append("rect")
        .attr("width", innerWidth)
        .attr("height", innerHeight)
        .attr("fill", "none")
        .attr("stroke", COLORS.grid);

    // Draw score points
    const scorePoints = g.selectAll("circle.scores")
        .data(history.filter(d => d.monitor_id))
        .enter().append("circle")
        .attr("class", "scores monitor-data")
        .attr("r", 2)
        .attr("cx", d => xScale(d.date))
        .attr("cy", d => yScoreScale(d.score))
        .attr("fill", d => {
            if (d.step < -1) return COLORS.score.error;
            if (d.step < 0) return COLORS.score.warning;
            return COLORS.score.good;
        })
        .on('mouseover', function(event, d) {
            fadeOtherMonitors(g, d.monitor_id, 0.2);
        })
        .on('mouseout', function() {
            fadeOtherMonitors(g, null, 1);
        });

    // Draw offset points
    const offsetPoints = g.selectAll("circle.offsets")
        .data(history.filter(d => d.monitor_id))
        .enter().append("circle")
        .attr("class", "offsets monitor-data")
        .attr("r", history.length > 250 ? 1.5 : 2)
        .attr("cx", d => xScale(d.date))
        .attr("cy", d => yOffsetScale(d.offset))
        .attr("fill", d => {
            const absOffset = Math.abs(d.offset);
            if (absOffset < THRESHOLDS.offset.good) return COLORS.offset.good;
            if (absOffset < THRESHOLDS.offset.warning) return COLORS.offset.warning;
            return COLORS.offset.error;
        })
        .on('mouseover', function(event, d) {
            fadeOtherMonitors(g, d.monitor_id, 0.25);
        })
        .on('mouseout', function() {
            fadeOtherMonitors(g, null, 1);
        });

    // Draw total score line
    const totalScoreData = history.filter(d => !d.monitor_id);

    if (totalScoreData.length > 0) {
        g.append("path")
            .datum(totalScoreData)
            .attr("class", "line total-score")
            .attr("fill", "none")
            .attr("stroke", COLORS.lines.totalScore)
            .attr("stroke-width", 2)
            .attr("d", d3.line()
                .x(d => xScale(d.date))
                .y(d => yScoreScale(d.score))
                .curve(d3.curveMonotoneX)
            );
    }

    // Add chart title
    g.append("text")
        .attr("x", 0)
        .attr("y", -5)
        .attr("font-weight", "bold")
        .attr("font-size", "14px")
        .text(`Offset and scores for ${data.server.ip}`);

    // Create legend if specified
    if (config.legend) {
        createLegend(config.legend, data.monitors || [], g, padding.horizontal);
    }
}

/**
 * Create interactive legend table
 * @param {Element} legendContainer - Container for the legend
 * @param {Array} monitors - Monitor data
 * @param {Object} chartGroup - D3 selection of chart group
 * @param {number} leftMargin - Left margin to align with chart
 */
function createLegend(legendContainer, monitors, chartGroup, leftMargin) {
    // Apply styles to container
    legendContainer.style.marginLeft = `${leftMargin}px`;
    legendContainer.style.width = '50%';

    // Sort monitors
    const sortedMonitors = sortMonitors(monitors);


    // Create table
    const table = document.createElement('table');
    table.className = 'table table-striped table-hover table-sm small border-bottom';

    const tbody = document.createElement('tbody');
    let currentStatus = '';

    sortedMonitors.forEach(monitor => {
        // Add status header row if status changed
        if (currentStatus !== monitor.status && monitor.type !== 'score') {
            const statusConfig = MONITOR_STATUS[monitor.status] || {};
            const headerRow = document.createElement('tr');
            headerRow.className = statusConfig.class || '';

            const headerCell = document.createElement('th');
            headerCell.textContent = statusConfig.label || monitor.status;
            headerRow.appendChild(headerCell);

            const scoreCell = document.createElement('td');
            scoreCell.textContent = 'Score';
            headerRow.appendChild(scoreCell);

            tbody.appendChild(headerRow);
            currentStatus = monitor.status;
        }

        // Add monitor row
        const row = document.createElement('tr');
        row.dataset.monitorId = monitor.id;

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
        scoreCell.textContent = monitor.score;
        scoreCell.className = textClass;
        row.appendChild(scoreCell);

        tbody.appendChild(row);
    });

    table.appendChild(tbody);

    // Add hover interactions
    const rows = table.querySelectorAll('tr[data-monitor-id]');
    rows.forEach(row => {
        row.addEventListener('mouseenter', function() {
            const monitorId = this.dataset.monitorId;
            if (monitorId) {
                fadeOtherMonitors(chartGroup, monitorId, 0.25);
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
 * @param {Object} chartGroup - D3 selection of chart group
 * @param {string} monitorId - ID of monitor to keep opaque
 * @param {number} opacity - Opacity for other monitors
 */
function fadeOtherMonitors(chartGroup, monitorId, opacity) {
    chartGroup.selectAll('.monitor-data')
        .transition()
        .duration(200)
        .style('opacity', d => {
            if (!monitorId) return 1;
            return d.monitor_id === monitorId ? 1 : opacity;
        });
}

// Export for backward compatibility with global function
if (typeof window !== 'undefined') {
    window.server_chart = createServerChart;
}
