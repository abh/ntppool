# Server Chart Legend Refactoring Plan

## Current State Analysis

The legend creation system in `src/charts/server-chart.ts` spans ~400 lines across multiple functions with high complexity:

### Main Functions Involved:
- `createLegend()` - Entry point (33 lines)
- `createSingleTableLegend()` - Layout orchestrator (50 lines)
- `createTableSection()` - Complex row creation (148 lines) **← MOST COMPLEX**
- `createMonitorRow()` - Individual monitor row creation (40 lines)
- `addTableEventListeners()` - Event delegation (30 lines)
- Supporting utilities: `createTable()`, `createCell()`, `createEmptyCell()`, `getMonitorDisplayName()` (25 lines total)

### Complexity Issues:
1. **Monolithic `createTableSection()` function** - Handles both priority (2-column) and other (3-column) layouts in one function
2. **Mixed responsibilities** - Layout logic, DOM creation, data processing, and styling all intertwined
3. **Deeply nested conditionals** - Multiple branching paths for different table types
4. **Repetitive DOM manipulation** - Similar cell creation patterns repeated throughout
5. **Hard to test** - Large functions with multiple side effects

## Refactoring Strategy

### Phase 1: Extract Table Layout Strategies

**Goal**: Separate layout logic from DOM creation

#### 1.1 Create Layout Strategy Interface
```typescript
interface TableLayoutStrategy {
  createHeaders(tbody: HTMLElement, statusGroups: Record<string, Monitor[]>): void;
  createRows(tbody: HTMLElement, statusGroups: Record<string, Monitor[]>): void;
  calculateMaxColumns(statusGroups: Record<string, Monitor[]>): number;
}
```

#### 1.2 Implement Concrete Strategies
- **`PriorityTableLayout`** - Handles Active/Testing 2-column layout with RTT
- **`StandardTableLayout`** - Handles 3-column layout for other statuses

#### 1.3 Benefits
- Single Responsibility Principle - each strategy handles one layout type
- Open/Closed Principle - easy to add new layouts without modifying existing code
- Eliminates the massive conditional logic in `createTableSection()`

### Phase 2: Create Specialized Row Builders

**Goal**: Standardize and simplify row creation patterns

#### 2.1 Row Builder Hierarchy
```typescript
abstract class RowBuilder {
  abstract createRow(monitor: Monitor, context: RowContext): HTMLElement;
  protected createCell(content: string, className: string): HTMLElement;
  protected addMonitorId(element: HTMLElement, monitorId: number): void;
}

class PriorityRowBuilder extends RowBuilder // Name | Score | RTT
class StandardRowBuilder extends RowBuilder // Name | Score only
class EmptyRowBuilder extends RowBuilder     // Empty cells with gaps
```

#### 2.2 Row Context Object
```typescript
interface RowContext {
  includeRtt: boolean;
  columnStyle: 'priority' | 'standard' | 'three-column';
  monitorDisplayRules: MonitorDisplayRules;
}
```

#### 2.3 Benefits
- Eliminates repetitive cell creation code
- Consistent monitor ID assignment
- Easy to modify cell creation logic in one place

### Phase 3: Extract Monitor Display Logic

**Goal**: Centralize monitor name formatting and styling rules

#### 3.1 Monitor Display Service
```typescript
class MonitorDisplayService {
  getDisplayName(monitor: Monitor): string;
  getStyleClasses(monitor: Monitor, context: DisplayContext): string[];
  shouldShowRtt(monitor: Monitor): boolean;
  formatRttValue(monitor: Monitor): string;
}
```

#### 3.2 Display Rules Configuration
```typescript
interface MonitorDisplayRules {
  specialNames: Record<string, string>; // 'recentmedian' → 'overall'
  styleRules: Array<{
    condition: (monitor: Monitor) => boolean;
    classes: string[];
  }>;
  rttFormatting: {
    precision: number;
    showForStatuses: string[];
  };
}
```

#### 3.3 Benefits
- Centralized display logic
- Easy to modify monitor name rules
- Configurable styling without code changes

### Phase 4: Simplify Event Handling

**Goal**: Create cleaner, more maintainable event system

#### 4.1 Event Handler Factory
```typescript
class LegendEventHandler {
  constructor(private chartGroup: GSelection) {}

  createTableEventListeners(): {
    onMouseEnter: (event: Event) => void;
    onMouseLeave: (event: Event) => void;
  };

  private handleMonitorHover(monitorId: number, isEntering: boolean): void;
  private findMonitorCells(monitorId: number, table: HTMLElement): NodeListOf<Element>;
}
```

#### 4.2 Benefits
- Separated event handling from DOM creation
- Reusable across different table types
- Easier to test event logic

### Phase 5: Create Legend Factory

**Goal**: Provide clean, simple API for legend creation

#### 5.1 Main Factory Class
```typescript
class ServerChartLegendFactory {
  constructor(
    private layoutStrategies: Map<string, TableLayoutStrategy>,
    private rowBuilders: Map<string, RowBuilder>,
    private displayService: MonitorDisplayService,
    private eventHandler: LegendEventHandler
  ) {}

  createLegend(config: LegendConfiguration): void {
    const processor = new LegendProcessor(config, this.dependencies);
    processor.process();
  }
}

interface LegendConfiguration {
  container: Element;
  monitors: Monitor[];
  chartGroup: GSelection;
  showOnlyActiveTesting: boolean;
  layoutPreferences?: LegendLayoutPreferences;
}
```

#### 5.2 Benefits
- Single entry point with clear interface
- Dependency injection for testability
- Configuration-driven behavior

## Implementation Plan

### Step 1: Create Base Interfaces and Types (2-3 hours)
- Define all interfaces (`TableLayoutStrategy`, `RowBuilder`, etc.)
- Create type definitions for configuration objects
- Add comprehensive JSDoc documentation

### Step 2: Extract Monitor Display Service (1-2 hours)
- Move `getMonitorDisplayName()` logic into service
- Add display rules configuration
- Create tests for display logic

### Step 3: Implement Row Builders (2-3 hours)
- Create abstract `RowBuilder` class
- Implement `PriorityRowBuilder` and `StandardRowBuilder`
- Extract common cell creation patterns

### Step 4: Create Layout Strategies (3-4 hours)
- Implement `PriorityTableLayout` strategy
- Implement `StandardTableLayout` strategy
- Extract and test header creation logic

### Step 5: Build Event Handler (1-2 hours)
- Extract event handling from existing code
- Create reusable event handler class
- Maintain existing hover functionality

### Step 6: Create Factory and Integration (2-3 hours)
- Build `ServerChartLegendFactory`
- Integrate all components
- Update `createLegend()` function to use factory

### Step 7: Testing and Validation (2-3 hours)
- Create unit tests for each component
- Integration tests for full legend creation
- Visual regression testing for layout consistency

### Step 8: Documentation and Cleanup (1 hour)
- Update JSDoc comments
- Create usage examples
- Remove old code and add deprecation notices

**Total Estimated Time: 14-21 hours**

## Benefits After Refactoring

### Code Quality
- **Reduced complexity**: Largest function drops from 148 to ~20 lines
- **Better testability**: Each component can be unit tested independently
- **Clearer responsibilities**: Each class has a single, well-defined purpose
- **Easier maintenance**: Changes to layout, styling, or behavior are localized

### Performance
- **Same runtime performance**: No performance degradation
- **Improved development speed**: Easier to make changes and fix bugs
- **Better debugging**: Smaller functions with clear purposes

### Extensibility
- **New layouts**: Easy to add without modifying existing code
- **Custom styling**: Display rules can be configured externally
- **Event customization**: Event handling can be modified or extended

### Maintainability
- **Reduced cognitive load**: Developers can focus on one aspect at a time
- **Better documentation**: Each component can be documented independently
- **Easier onboarding**: New developers can understand individual components

## Risk Mitigation

### Visual Regression Testing
- Screenshot comparison of existing legend layouts
- Manual testing of all monitor status combinations
- Hover behavior verification

### Feature Parity Checklist
- [ ] Priority table layout (Active | Testing with RTT)
- [ ] Standard table layout (3-column for other statuses)
- [ ] Empty cell handling and gaps
- [ ] Monitor hover highlighting
- [ ] Chart interaction synchronization
- [ ] CSS class assignments
- [ ] Monitor ID data attributes
- [ ] Special monitor name handling ('recentmedian' → 'overall')
- [ ] RTT display for active/testing monitors
- [ ] Responsive layout preservation

### Rollback Strategy
- Keep existing functions in place with deprecation warnings
- Implement feature flag to switch between old and new implementations
- Gradual migration with fallback capabilities

## Success Metrics

- **Code Complexity**: Reduce cyclomatic complexity from ~25 to <10 per function
- **Test Coverage**: Achieve >90% test coverage for legend creation
- **Maintainability**: New legend layouts can be added in <2 hours
- **Bug Reduction**: Eliminate existing layout inconsistencies
- **Developer Experience**: New team members can understand and modify legend logic within 1 day

## Future Enhancements (Post-Refactoring)

1. **Configuration-Driven Layouts**: Allow external configuration of column arrangements
2. **Accessibility Improvements**: Better ARIA labels and keyboard navigation
3. **Mobile Optimization**: Responsive layouts for different screen sizes
4. **Animation Support**: Smooth transitions for hover effects
5. **Export Functionality**: Allow saving legend data to CSV/JSON
