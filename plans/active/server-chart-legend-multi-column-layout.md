# Server Chart Legend Multi-Column Layout Specification

## Overview

This specification defines the multi-column layout design for the monitor legend in the server chart component (`src/charts/server-chart.ts`). The new layout optimizes space utilization while maintaining clear visual grouping of monitors by status.

## Current Implementation

The existing legend displays monitors in a single vertical table grouped by status:

```
Active
- monitor 1
- monitor 2
- monitor 3
Testing
- monitor 4
- monitor 5
- ...
- monitor 10
Candidate
- monitor 11
- monitor 12
- ...
```

## New Multi-Column Layout Design

### Layout Structure

The new design uses a two-section approach:

#### Section 1: Two-Column Layout (Active | Testing)
- **Active** and **Testing** statuses get dedicated columns (50% width each)
- These are the most important statuses and benefit from clear separation
- Monitors within each status are listed vertically

#### Section 2: Three-Column Layout (All Other Statuses)
- All remaining statuses use a space-optimized 3-column layout
- Statuses are packed efficiently to minimize vertical space
- Each status gets exactly one header at its starting position

### Visual Example

```
┌─────────────────┬─────────────────┐
│ Active          │ Testing         │
│ - monitor 1     │ - monitor 4     │
│ - monitor 2     │ - monitor 5     │
│ - monitor 3     │ - monitor 6     │
│                 │ - monitor 7     │
│                 │ - monitor 8     │
│                 │ - monitor 9     │
│                 │ - monitor 10    │
├─────────────────┼─────────────────┤
│ Candidate       │ Candidate       │ Candidate
│ - monitor 11    │ - monitor 15    │ - monitor 19
│ - monitor 12    │ - monitor 16    │ - monitor 20
│ - monitor 13    │ - monitor 17    │
│ - monitor 14    │ - monitor 18    │
│                 │                 │
│ Paused          │ Deleted         │
│ - monitor 21    │ - monitor 23    │
│ - monitor 22    │                 │
└─────────────────┴─────────────────┘
```

## Technical Specifications

### Monitor Status Classification

#### Priority Statuses (Dedicated Columns)
- **Active**: Gets left column in section 1
- **Testing**: Gets right column in section 1

#### Multi-Column Statuses (Space-Optimized)
- **Candidate**: Large groups flow across all 3 columns
- **Paused**: Small groups can share rows with other statuses
- **Deleted**: Small groups can share rows with other statuses
- **Inactive**: Small groups can share rows with other statuses
- Any other status: Follows the same packing rules

### Packing Algorithm

#### Large Status Groups (6+ monitors)
- Get their own row in the 3-column section
- Monitors flow left-to-right across all 3 columns
- Header appears in column 1

#### Small Status Groups (1-5 monitors)
- Can be packed together in shared rows
- Each status gets exactly one header at its starting position
- Monitors stay grouped under their respective headers

#### Distribution Logic
1. Calculate monitors per status
2. For large groups: allocate full row, distribute monitors evenly across 3 columns
3. For small groups: pack multiple statuses per row to minimize height
4. Headers only appear once per status at the first monitor position

### HTML Structure

#### Section 1: Active/Testing
```html
<div class="row">
  <div class="col-6">
    <h6 class="text-success">Active</h6>
    <ul class="list-unstyled">
      <!-- Active monitors -->
    </ul>
  </div>
  <div class="col-6">
    <h6 class="text-info">Testing</h6>
    <ul class="list-unstyled">
      <!-- Testing monitors -->
    </ul>
  </div>
</div>
```

#### Section 2: Multi-Column Layout
```html
<div class="row">
  <div class="col-4">
    <h6 class="text-warning">Candidate</h6>
    <ul class="list-unstyled">
      <!-- First group of candidate monitors -->
    </ul>
    <h6 class="text-secondary mt-3">Paused</h6>
    <ul class="list-unstyled">
      <!-- Paused monitors -->
    </ul>
  </div>
  <div class="col-4">
    <ul class="list-unstyled" style="margin-top: 2rem;">
      <!-- Continuation of candidate monitors -->
    </ul>
    <h6 class="text-danger mt-3">Deleted</h6>
    <ul class="list-unstyled">
      <!-- Deleted monitors -->
    </ul>
  </div>
  <div class="col-4">
    <ul class="list-unstyled" style="margin-top: 2rem;">
      <!-- Overflow monitors if needed -->
    </ul>
  </div>
</div>
```

### CSS Classes and Styling

#### Bootstrap Classes
- `row`: Bootstrap grid row
- `col-6`: 50% width columns for Active/Testing
- `col-4`: 33% width columns for multi-column section
- `list-unstyled`: Remove default list styling
- `mt-3`: Top margin for status headers

#### Status-Specific Classes
- `text-success`: Green for Active status
- `text-info`: Blue for Testing status
- `text-warning`: Orange for Candidate status
- `text-secondary`: Gray for Paused status
- `text-danger`: Red for Deleted status

#### Layout Classes
- Container maintains existing `width: 50%` and `marginLeft: ${CHART_DEFAULTS.padding.horizontal}px`
- Headers use existing font weight and sizing
- Monitor items maintain hover interactions

## Interaction Requirements

### Hover Effects
- Maintain existing hover interactions that highlight corresponding chart data
- Monitor hover should fade other monitors in the chart
- Legend row hover should highlight corresponding monitor data points

### Responsive Behavior
- Layout should work with existing responsive chart sizing
- Columns should stack vertically on smaller screens (Bootstrap default behavior)
- Text should remain readable at all supported screen sizes

## Edge Cases and Considerations

### Empty Status Groups
- If a status has no monitors, it should not appear in the legend
- Empty columns should be handled gracefully

### Single Monitor Statuses
- Single monitors can share rows with other small status groups
- Headers still required for clarity

### Large Numbers of Monitors
- Algorithm should handle any number of monitors per status
- Very large candidate groups may need scrolling or truncation

### Dynamic Status Addition
- New status types should automatically use the multi-column packing logic
- No hardcoding of specific status names beyond Active/Testing

## Implementation Notes

### Backward Compatibility
- Maintain existing `createLegend()` function signature
- Preserve all existing monitor data properties and sorting
- Keep existing event listener patterns for hover effects

### Performance Considerations
- Minimize DOM manipulations during legend creation
- Reuse existing monitor sorting and filtering logic
- Maintain efficient hover event delegation

### Testing Requirements
- Test with various combinations of monitor statuses and counts
- Verify responsive behavior across screen sizes
- Validate hover interactions work correctly
- Test edge cases (empty statuses, single monitors, large groups)

## Future Enhancements

### Potential Improvements
- Configurable column counts for different sections
- Collapsible status groups for very large lists
- Sorting options within status groups
- Status-specific color coding for monitor items

### Extensibility
- Design allows for easy addition of new status types
- Packing algorithm can be refined for better space utilization
- Layout can be adapted for different chart contexts

## Version History

- **v1.0** (2025-07-25): Initial specification for multi-column legend layout
- Replaces single-column table layout with space-optimized multi-column design
- Introduces dedicated columns for Active/Testing and efficient packing for other statuses
