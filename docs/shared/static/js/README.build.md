# JavaScript Build System

This directory contains the source JavaScript files for the NTP Pool charts.

## Build Process

The JavaScript files are built using Vite for:
- Bundling ES modules
- Minification and optimization
- Legacy browser support
- Tree-shaking unused code

### Development

```bash
# Install dependencies
make js-deps

# Run development server with hot reload
make js-dev

# Build for production
make js-build
```

### Production Build

The production build creates:
- `graphs.bundle.js` - Main bundle with modern ES modules
- `graphs.bundle-legacy.js` - Legacy bundle for older browsers
- `chunks/` - Code-split chunks (D3.js, utilities)
- Source maps for debugging

### Integration

To use the bundled files in templates, use:

```
[% page.js.push("module:graphs.bundle.js") %]
```

The build system automatically handles:
- D3.js bundling (no need for separate CDN)
- Chart utilities bundling
- Legacy browser polyfills
- Optimal code splitting

### Static Groups

The Combust framework's static groups should be updated to use the bundled versions:

```perl
# In combust.conf or similar
StaticGroup graphs.js => [
    "graphs.bundle.js",
    # Legacy support handled automatically by Vite
]
```
