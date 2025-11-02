# Status-Based Hover Enhancement Plan

## Problem Statement

Currently in `client/src/charts/server-chart.ts`, the monitor legend table has two issues with status header hover behavior:

1. **Incorrect Status Header Styling**: When hovering over status header cells (e.g., "Active", "Testing"), the background turns white and affects neighbor cells in the same row
2. **Limited Dimming System**: The chart dimming functionality (`fadeOtherMonitors`) only works with individual monitor IDs, not with monitor status groups

## Current Architecture Analysis

### Existing Hover System
- **Function**: `fadeOtherMonitors(chartGroup, monitorId, opacity)` - server-chart.ts:946
- **Parameters**: Takes single `monitorId` number, applies opacity to non-matching monitors
- **Event Handling**: Uses debounced event system with `sharedLegendDebouncer`
- **CSS Classes**: `.monitor-cell-hover` for table highlighting, defined in _components.scss:1342

### Status Configuration
- **Source**: `MONITOR_STATUS` object in utils/dom-utils.ts:69
- **Statuses**: active, testing, candidate, pending, paused, deleted
- **Properties**: Each has `order`, `class` (Bootstrap table color), `label`

### Current Event Listeners
- **Location**: `addTableEventListeners()` in server-chart.ts:662
- **Target**: Individual monitor cells with `data-monitor-id` attributes
- **Scope**: Only handles single monitor highlighting

## Implementation Plan

### Phase 1: Fix Status Header Hover Styling

**Goal**: Status headers should intensify their existing background color on hover, not turn white

**Changes Required**:

1. **CSS Updates** in `client/src/styles/_components.scss`:
   ```scss
   .status-header {
       text-align: left;

       &:hover {
           // Intensify existing Bootstrap table colors
           &.table-success { background-color: rgba(25, 135, 84, 0.25) !important; }
           &.table-info { background-color: rgba(13, 202, 240, 0.25) !important; }
           &.table-secondary { background-color: rgba(108, 117, 125, 0.25) !important; }
           &.table-danger { background-color: rgba(220, 53, 69, 0.25) !important; }
       }
   }
   ```

2. **Row Hover Override**: Ensure status header hover doesn't trigger row-level hover effects:
   ```scss
   tbody tr:has(.status-header:hover) td:not(.status-header) {
       background-color: transparent !important;
   }
   ```

**Test Criteria**:
- Hover over "Active" header → green background intensifies
- Hover over "Testing" header → blue background intensifies
- Neighbor cells remain unchanged during status header hover

### Phase 2: Extend Dimming System for Status Groups (Memory-Optimized)

**Goal**: Allow chart dimming based on monitor status using efficient numeric status IDs

**Changes Required**:

1. **Status ID Constants** in server-chart.ts or utils/chart-utils.ts:
   ```typescript
   const STATUS_IDS = {
     'active': 0,
     'testing': 1,
     'candidate': 2,
     'pending': 3,
     'paused': 4,
     'deleted': 5
   } as const;

   type StatusId = typeof STATUS_IDS[keyof typeof STATUS_IDS];
   ```

2. **Augment Chart Data** in `processChartData()`:
   ```typescript
   function processChartData(
     history: ServerHistoryPoint[],
     monitors: Monitor[]
   ): ProcessedChartData {
     // Create efficient monitor ID to status ID mapping
     const monitorStatusIdMap = new Map(
       monitors.map(m => [m.id, STATUS_IDS[m.status] ?? 999])
     );

     const scorePoints: (ServerHistoryPoint & { status_id: number })[] = [];
     const offsetPoints: (ServerHistoryPoint & { status_id: number })[] = [];
     const totalScorePoints: ServerHistoryPoint[] = [];

     for (const point of history) {
       if (point.monitor_id === null) {
         totalScorePoints.push(point);
       } else {
         const enrichedPoint = {
           ...point,
           status_id: monitorStatusIdMap.get(point.monitor_id) ?? 999
         };
         scorePoints.push(enrichedPoint);
         if (point.offset != null) {
           offsetPoints.push(enrichedPoint);
         }
       }
     }

     return { scorePoints, offsetPoints, totalScorePoints };
   }
   ```

3. **Update Function Signature** for `fadeOtherMonitors()`:
   ```typescript
   function fadeOtherMonitors(
     chartGroup: GSelection,
     targetIdentifier: number | null, // Can be monitorId or statusId
     opacity: number,
     filterType: 'monitor' | 'status' = 'monitor'
   ): void {
     const selection = chartGroup.selectAll<SVGElement, ServerHistoryPoint>('.monitor-data');

     selection.style('opacity', d => {
       if (targetIdentifier === null) return 1;

       if (filterType === 'status') {
         // Ultra-fast numeric comparison for status filtering
         return (d as any).status_id === targetIdentifier ? 1 : opacity;
       } else {
         // Existing monitor ID logic
         return d.monitor_id === targetIdentifier ? 1 : opacity;
       }
     });

     // Update score point colors
     const scorePoints = chartGroup.selectAll<SVGElement, ServerHistoryPoint>('.scores.monitor-data');
     scorePoints.style('fill', d => {
       if (targetIdentifier === null) {
         return getScoreColor(d.step);
       }

       const isTarget = filterType === 'status'
         ? (d as any).status_id === targetIdentifier
         : d.monitor_id === targetIdentifier;

       return isTarget ? getScoreColor(d.step) : '#888888';
     });
   }
   ```

4. **Update TypeScript Interfaces** to reflect enriched data:
   ```typescript
   interface EnrichedServerHistoryPoint extends ServerHistoryPoint {
     status_id: number;
   }

   interface ProcessedChartData {
     scorePoints: EnrichedServerHistoryPoint[];
     offsetPoints: EnrichedServerHistoryPoint[];
     totalScorePoints: ServerHistoryPoint[];
   }
   ```

**Performance Benefits**:
- **Memory**: ~4-8x reduction in status data size (4 bytes vs 32+ bytes per point)
- **Speed**: Numeric comparison vs string comparison for filtering
- **Scalability**: Efficient for charts with thousands of data points

**Test Criteria**:
- Memory usage doesn't increase significantly with status data
- Chart rendering performance remains smooth
- Status-based filtering works correctly

### Phase 3: Integrate Status Header Event Handling

**Goal**: Add event listeners to status headers using existing debounced system

**Changes Required**:

1. **Data Attributes**: Add status identification to headers in server-chart.ts:
   ```typescript
   // In createTableSection() around lines 732, 744, 810
   activeHeader.dataset['monitorStatus'] = 'active';
   testingHeader.dataset['monitorStatus'] = 'testing';
   headerCell.dataset['monitorStatus'] = status;
   ```

2. **Event Listener Updates** in `addTableEventListeners()`:
   ```typescript
   table.addEventListener('mouseenter', function (e) {
     const target = e.target as HTMLElement;

     // Check for status header hover
     if (target.classList.contains('status-header') && target.dataset['monitorStatus']) {
       const status = target.dataset['monitorStatus'];
       const statusId = STATUS_IDS[status as keyof typeof STATUS_IDS];

       if (statusId !== undefined) {
         sharedDebouncer.debounce(() => {
           fadeOtherMonitors(chartGroup, statusId, 0.15, 'status');
           highlightTableCellsByStatus(table, status, true);
           globalHoverState.setHover(`status-${status}`, 'status-header');
         }, `status-${status}`);
       }
     }

     // Existing monitor cell logic for individual cells...
     else if (target.dataset['monitorId']) {
       const monitorId = parseInt(target.dataset['monitorId'], 10);
       sharedDebouncer.debounce(() => {
         setTargetMonitor(monitorId, chartGroup, table);
       }, monitorId);
     }
   }, true);

   table.addEventListener('mouseleave', function (e) {
     const target = e.target as HTMLElement;

     if (target.classList.contains('status-header') || target.dataset['monitorId']) {
       sharedDebouncer.debounce(() => {
         setTargetMonitor(null, chartGroup, table);
       }, null);
     }
   }, true);
   ```

3. **New Helper Function** for status-based table highlighting:
   ```typescript
   function highlightTableCellsByStatus(table: HTMLTableElement, status: string, highlight: boolean): void {
     // Find all monitor cells and check their status
     const monitorCells = table.querySelectorAll('[data-monitor-id]');

     monitorCells.forEach(cell => {
       const monitorId = parseInt((cell as HTMLElement).dataset['monitorId']!, 10);
       const monitor = monitors.find(m => m.id === monitorId);

       if (monitor && monitor.status === status) {
         if (highlight) {
           cell.classList.add('monitor-cell-hover');
         } else {
           cell.classList.remove('monitor-cell-hover');
         }
       }
     });
   }
   ```

4. **Update createLegend() signature** to pass monitors data:
   ```typescript
   function createLegend(
     legendContainer: Element,
     monitors: Monitor[],
     chartGroup: GSelection,
     showOnlyActiveTesting = false
   ): void {
     // Store monitors reference for status-based operations
     (chartGroup.node() as any).__monitors = monitors;

     // Rest of existing function...
   }
   ```

**Test Criteria**:
- Status header hover triggers debounced dimming effect
- All monitors of hovered status remain visible/highlighted
- Table cells of matching status get highlighted
- Smooth interaction with existing monitor hover system
- No conflicts between status and monitor hover states

## Technical Considerations

### Memory Optimization
- **Status IDs**: Using numeric IDs (0-5) instead of strings saves significant memory
- **Data Augmentation**: One-time cost during chart creation vs repeated lookups
- **Type Safety**: TypeScript interfaces ensure correct usage of enriched data

### Performance
- **Numeric Comparisons**: Much faster than string comparisons for filtering
- **Memory Locality**: Numeric status IDs improve cache performance
- **Minimal Overhead**: Only 4 bytes per data point vs 32+ bytes for strings

### Compatibility
- **Existing Functionality**: Individual monitor hover continues to work unchanged
- **Global State**: Extend hover state to handle status-based states
- **CSP Compliance**: All styling changes use external CSS only

### Testing Strategy
- **Unit Testing**: Test each phase independently with small datasets
- **Performance Testing**: Verify memory usage and render speed with large datasets
- **Integration Testing**: Verify both monitor and status hover work together
- **Playwright Testing**: Automated browser testing for hover interactions

## Implementation Order

1. **Phase 1**: CSS-only changes for status header styling
2. **Phase 2**: Core data structure and dimming functionality
3. **Phase 3**: Event integration and full system testing

Each phase builds incrementally and can be tested independently to ensure system stability throughout implementation.

## Memory Profiling Strategy

**Baseline Measurement**:
- **When**: Before Phase 1 implementation (establish current memory usage)
- **Method**: Playwright test measuring JavaScript heap size during typical chart interactions
- **Purpose**: Establish baseline for memory usage with current 6,500 data points

**Phase Validation**:
- **After Phase 1**: Verify CSS-only changes don't impact memory
- **After Phase 2**: Measure impact of status data augmentation (primary memory concern)
- **After Phase 3**: Final integration testing with all features enabled

**Scaling Validation**:
- **Method**: Change limit from 6500 to 20000 in `client/src/components/server-chart.ts:130`
- **Location**: Update `&limit=6500` to `&limit=20000` in `getDataUrl()` method
- **Thresholds**: Memory increase should be proportional and reasonable (target: <1MB total increase)

**Documentation**:
- **Results Logging**: All memory profiling results will be logged in this plan file after each test
- **Format**: Include baseline measurements, phase-by-phase changes, and scaling validation results
- **Purpose**: Track memory usage trends and validate optimization claims

## Memory Usage Comparison

**Before (string status)**:
- 10,000 data points × ~32 bytes per status string = ~320KB additional memory

**After (numeric status)**:
- 10,000 data points × 4 bytes per status ID = ~40KB additional memory
- **Savings**: ~280KB per chart (87% reduction)

## Memory Profiling Results

*Results will be logged here after each profiling session*

### Baseline Results
- **Status**: ✅ Complete
- **Test Date**: 2025-08-02 23:56:51 UTC
- **Measurement**: Comprehensive baseline established

**Single Chart (216.239.35.4):**
- Initial Memory: 10.99 MB (after page load)
- After Hover Interactions: 16.03 MB (after hover triggers)
- Memory Increase: ~5 MB during interaction
- Data Points: 7,040 SVG elements
- Monitor Cells: 34
- Status Headers: 3

**Multiple Charts (9 servers - fancytime account):**
- Memory Usage: 78.83 MB (after all charts loaded)
- Total Data Points: 87,168 SVG elements
- Total SVG Elements: 19 charts
- Monitor Cells: 240
- Status Headers: 18
- Hover Processing: 10,860 elements processed during fade effect

**Key Findings:**
- Memory scales roughly linearly with chart count (~8.8 MB per chart)
- Hover interactions cause temporary memory spikes but no permanent leaks
- Current debouncing system processes 10K+ elements efficiently (6.5ms duration)
- Baseline establishes ~80MB for 9 charts as acceptable performance threshold

### Phase 1 Results (CSS Changes)
- **Status**: ✅ Complete
- **Test Date**: 2025-08-03 00:06:26 UTC
- **Git Commit**: `6050560c` - fix(charts): prevent status header hover affecting other cells
- **Memory Impact**: No impact (CSS-only changes)

**Implementation Summary:**
- Added status color variables in `_variables.scss` with base/hover variants
- Updated Bootstrap table overrides to use consistent status variables
- Fixed legend table hover behavior with specific status header rules
- Eliminated cross-hover bug where hovering one header affected others
- Used consistent variable references throughout for maintainability

**Testing Results:**
- ✅ Active header: Rich green background on hover (no white background)
- ✅ Testing header: Rich blue background on hover (no white background)
- ✅ Candidate header: Rich gray background on hover
- ✅ No cross-contamination between status headers during hover
- ✅ Bootstrap hover effects properly overridden for legend tables
- ✅ Behavior verified on development site (web.askdev.grundclock.com)

**Files Modified:**
- `client/src/styles/_variables.scss`: Added status color variables
- `client/src/styles/_components.scss`: Updated table overrides and hover behavior

### Phase 2 Results (Status Data Augmentation)
- **Status**: Pending
- **Test Date**: TBD
- **Memory Impact**: TBD

### Phase 3 Results (Event Integration)
- **Status**: Pending
- **Test Date**: TBD
- **Memory Impact**: TBD

### Scaling Results (20,000 Data Points)
- **Status**: Pending
- **Test Date**: TBD
- **Memory Impact**: TBD
