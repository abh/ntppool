# NTP Pool Frontend - TypeScript Charts

Modern TypeScript implementation of NTP Pool chart visualizations using D3.js v7.

## Architecture

This project uses a modern TypeScript architecture with comprehensive type safety:

```
client/
├── src/
│   ├── types/          # TypeScript type definitions
│   │   ├── api.ts      # API response types
│   │   ├── charts.ts   # Chart component types
│   │   └── index.ts    # Type re-exports
│   ├── utils/          # Shared utilities
│   │   └── chart-utils.ts  # Chart helper functions
│   ├── charts/         # Chart implementations
│   │   ├── server-chart.ts # Server offset/score charts
│   │   ├── zone-chart.ts   # Zone server count charts
│   │   └── index.ts        # Chart re-exports
│   └── main.ts         # Main entry point
├── package.json        # Dependencies and scripts
├── tsconfig.json       # TypeScript configuration
├── vite.config.ts      # Development build config
└── vite.config.production.ts  # Production build config
```

## Features

- **Full Type Safety**: Comprehensive TypeScript types for all APIs and chart components
- **Modern ES2022**: Using latest JavaScript features with proper browser support
- **D3.js v7**: Latest version with proper TypeScript integration
- **Responsive Design**: Charts automatically adapt to container sizes
- **Accessibility**: ARIA labels, screen reader support, keyboard navigation
- **Code Splitting**: D3.js and utilities are split into separate chunks for optimal caching
- **Legacy Support**: Automatic polyfills for older browsers via Vite Legacy plugin

## Development

### Prerequisites

- Node.js 18+
- npm 9+

### Setup

```bash
cd client
npm install
```

### Scripts

```bash
# Type checking
npm run type-check

# Development server with hot reload
npm run dev

# Build for development (with source maps, no minification)
npm run build:dev

# Build for production (minified, optimized)
npm run build

# Watch mode for production builds
npm run watch

# Clean build artifacts
npm run clean
```

### From Project Root

```bash
# Install dependencies
make js-deps

# Type check
make js-type-check

# Build for production
make js-build

# Development server
make js-dev

# Clean build artifacts
make js-clean
```

## API Integration

The charts integrate with these NTP Pool APIs:

### Server Score History
- **Endpoint**: `/api/server/scores/{server}/json`
- **Type**: `ServerScoreHistoryResponse`
- **Charts**: Server offset and score visualization

### Zone Counts
- **Endpoint**: `/api/zone/counts/{zone_name}`
- **Type**: `ZoneCountsResponse`
- **Charts**: Zone server count trends

## Type Safety

All API responses and chart configurations are fully typed:

```typescript
// Server chart with type safety
const result = await fetchChartData<ServerScoreHistoryResponse>(url);
if (result.success && result.data) {
  createServerChart(container, result.data, {
    legend: legendElement,
    showTooltips: true,
    responsive: true
  });
}
```

## Build Output

Production builds generate:

- `graphs.bundle.js` - Main application bundle
- `graphs.bundle-legacy.js` - Legacy browser support
- `chunks/d3-vendor-[hash].js` - D3.js library chunk
- `*.map` files - Source maps for debugging

Output location: `../docs/shared/static/js/`

## Browser Support

### Modern Bundle (ES2022)
- Chrome >= 87 (2020)
- Firefox >= 78 (2020)
- Safari >= 14 (2020)
- Edge >= 88 (2021)

### Legacy Bundle (Polyfilled)
- Chrome >= 63
- Firefox >= 67
- Safari >= 12
- Edge >= 79

## Configuration

### TypeScript (`tsconfig.json`)
- Strict mode enabled
- ES2022 target
- Modern module resolution
- Path mapping for clean imports

### Vite Development (`vite.config.ts`)
- ES2022 target
- Source maps enabled
- Console logs preserved
- Hot module replacement

### Vite Production (`vite.config.production.ts`)
- Optimized builds
- Console logs removed
- Legacy browser support
- Chunk splitting for optimal caching

## Backwards Compatibility

The TypeScript implementation maintains compatibility with existing templates:

```html
<!-- Static group usage (recommended) -->
[% page.js.push("module:graphs.bundle.js") %]

<!-- Global function access (legacy) -->
<script>
  // These still work for backwards compatibility
  window.zone_chart(container, data, options);
  window.server_chart(container, data, options);
  window.Pool.Graphs.SetupGraphs();
</script>
```

## Migration from JavaScript

The original JavaScript files have been moved to `client/src/` and converted to TypeScript:

- `graphs.js` → `src/main.ts`
- `graphs.server.js` → `src/charts/server-chart.ts`
- `graphs.zone.js` → `src/charts/zone-chart.ts`
- `chart-utils.js` → `src/utils/chart-utils.ts`

Build output goes to `docs/shared/static/js/` maintaining the same file locations for the web application.

## Performance

TypeScript compilation adds minimal overhead:
- Type checking: ~1-2 seconds
- Build time: Similar to JavaScript version
- Bundle size: Identical (types are erased)
- Runtime performance: Unchanged

The benefits of type safety, better tooling, and maintainability far outweigh the small compilation cost.
