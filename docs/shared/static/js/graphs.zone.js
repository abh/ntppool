/* Copyright 2012-2025 Ask Bjørn Hansen, Develooper LLC & NTP Pool Project */

/**
 * Zone chart module for displaying server counts over time
 * Modern ES6+ implementation with D3.js v7
 */

import {
    getElementDimensions,
    parseTimestamp,
    CHART_DEFAULTS,
    COLORS,
    createSvgContainer,
    addAccessibilityLabels,
    formatNumber
} from './chart-utils.js';

/**
 * Create a zone chart showing server counts over time
 * @param {Element} container - Container element for the chart
 * @param {Object} data - Chart data with history array
 * @param {Object} options - Chart options
 */
export function createZoneChart(container, data, options = {}) {
    // Set default options
    const config = {
        ipVersion: options.ipVersion || 'v4',
        name: options.name || 'Zone',
        showBothVersions: options.showBothVersions !== false,
        ...options
    };

    // Process history data
    const history = data.history.map(d => ({
        ...d,
        date: parseTimestamp(d.ts)
    }));

    // Calculate dimensions
    const dimensions = getElementDimensions(container, {
        defaultWidth: 480,
        defaultHeight: 246
    });

    const padding = {
        horizontal: 40,
        vertical: 19
    };

    const innerWidth = dimensions.width - (padding.horizontal * 2);
    const innerHeight = dimensions.height - (padding.vertical * 2);

    // Calculate Y-axis domain
    const yMax = calculateYMax(history);
    const yMin = 0;

    // Create scales
    const yScale = d3.scaleLinear()
        .domain([yMax, yMin])
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
        `Server counts for ${config.name}`,
        `Time series chart showing registered, active, and inactive server counts for ${config.name} zone`
    );

    // Draw grid lines and axes
    drawGrid(g, xScale, yScale, innerWidth, innerHeight, yMax);

    // Draw background rect
    g.append("rect")
        .attr("width", innerWidth)
        .attr("height", innerHeight)
        .attr("fill", "none")
        .attr("stroke", COLORS.grid);

    // Define line generators
    const lineGenerator = d3.line()
        .x(d => xScale(d.date))
        .y(d => yScale(d.value))
        .curve(d3.curveMonotoneX);

    // Draw lines for each IP version
    const ipVersions = config.showBothVersions ? ['v4', 'v6'] : [config.ipVersion];

    ipVersions.forEach(ipVersion => {
        drawVersionLines(g, history, ipVersion, lineGenerator, xScale, yScale);
    });

    // Add chart title
    g.append("text")
        .attr("x", 2)
        .attr("y", -5)
        .attr("font-weight", "bold")
        .attr("font-size", "14px")
        .text(`Server counts for ${config.name}`);

    // Add legend if showing both versions
    if (config.showBothVersions) {
        addLegend(g, innerWidth, innerHeight);
    }
}

/**
 * Calculate appropriate Y-axis maximum
 * @param {Array} history - History data
 * @returns {number}
 */
function calculateYMax(history) {
    let yMax = d3.max(history, d => d.rc) || 0;

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
function drawGrid(g, xScale, yScale, width, height, yMax) {
    // X-axis grid lines and labels
    const xTicks = xScale.ticks(CHART_DEFAULTS.ticks.x);
    const xAxisGroup = g.selectAll("g.x-axis")
        .data(xTicks)
        .enter().append("g")
        .attr("class", "x-axis");

    xAxisGroup.append("line")
        .attr("x1", d => xScale(d))
        .attr("x2", d => xScale(d))
        .attr("y1", 0)
        .attr("y2", height)
        .attr("stroke", COLORS.grid)
        .attr("stroke-dasharray", "2,2");

    xAxisGroup.append("text")
        .attr("x", d => xScale(d))
        .attr("y", height + 3)
        .attr("dy", ".71em")
        .attr("text-anchor", "middle")
        .attr("font-size", "12px")
        .text(d => d3.timeFormat("%b %d")(d));

    // Y-axis grid lines and labels
    const yTicks = yMax > 8 ? 8 : yMax;
    const yTickValues = yScale.ticks(yTicks);
    const yAxisGroup = g.selectAll("g.y-axis")
        .data(yTickValues)
        .enter().append("g")
        .attr("class", "y-axis");

    yAxisGroup.append("line")
        .attr("x1", 0)
        .attr("x2", width)
        .attr("y1", d => yScale(d))
        .attr("y2", d => yScale(d))
        .attr("stroke", COLORS.grid)
        .attr("stroke-dasharray", "2,2");

    yAxisGroup.append("text")
        .attr("x", -3)
        .attr("y", d => yScale(d))
        .attr("dy", ".35em")
        .attr("text-anchor", "end")
        .attr("font-size", "12px")
        .text(d => formatNumber(d));
}

/**
 * Draw lines for a specific IP version
 */
function drawVersionLines(g, history, ipVersion, lineGenerator, xScale, yScale) {
    // Filter data for this IP version
    const versionData = history.filter(d => d.iv === ipVersion);

    if (versionData.length === 0) return;

    // Define line styles
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
    };

    // Draw registered count line
    g.append("path")
        .datum(versionData.map(d => ({ date: d.date, value: d.rc })))
        .attr("class", `line registered_count ${ipVersion}`)
        .attr("fill", "none")
        .attr("stroke", lineStyles.registered_count.color)
        .attr("stroke-width", lineStyles.registered_count.width)
        .attr("stroke-dasharray", lineStyles.registered_count.dasharray)
        .attr("d", lineGenerator);

    // Draw active count line
    g.append("path")
        .datum(versionData.map(d => ({ date: d.date, value: d.ac })))
        .attr("class", `line active_count ${ipVersion}`)
        .attr("fill", "none")
        .attr("stroke", lineStyles.active_count.color)
        .attr("stroke-width", lineStyles.active_count.width)
        .attr("stroke-dasharray", lineStyles.active_count.dasharray)
        .attr("d", lineGenerator);

    // Draw inactive count line (registered - active)
    g.append("path")
        .datum(versionData.map(d => ({ date: d.date, value: d.rc - d.ac })))
        .attr("class", `line inactive_count ${ipVersion}`)
        .attr("fill", "none")
        .attr("stroke", lineStyles.inactive_count.color)
        .attr("stroke-width", lineStyles.inactive_count.width)
        .attr("stroke-dasharray", lineStyles.inactive_count.dasharray)
        .attr("d", lineGenerator);
}

/**
 * Add legend to the chart
 */
function addLegend(g, width, height) {
    const legendItems = [
        { label: 'Registered', class: 'registered_count', color: COLORS.lines.registered },
        { label: 'Active', class: 'active_count', color: COLORS.lines.active },
        { label: 'Inactive', class: 'inactive_count', color: COLORS.lines.inactive }
    ];

    const legend = g.append("g")
        .attr("class", "legend")
        .attr("transform", `translate(${width - 100}, 20)`);

    const legendItem = legend.selectAll(".legend-item")
        .data(legendItems)
        .enter().append("g")
        .attr("class", "legend-item")
        .attr("transform", (d, i) => `translate(0, ${i * 20})`);

    legendItem.append("line")
        .attr("x1", 0)
        .attr("x2", 20)
        .attr("y1", 0)
        .attr("y2", 0)
        .attr("stroke", d => d.color)
        .attr("stroke-width", 2);

    legendItem.append("text")
        .attr("x", 25)
        .attr("y", 0)
        .attr("dy", ".35em")
        .attr("font-size", "12px")
        .text(d => d.label);
}

// Export for backward compatibility with global function
if (typeof window !== 'undefined') {
    window.zone_chart = createZoneChart;
}
