# CLEAR Equity Navigator - Learnings

## Project Overview
This is a single-page static app for navigating startup equity offer letters. Originally a Ruby on Rails application with HAML templates, CoffeeScript, and Backbone.js, it has been converted to a standalone static HTML file.

## Key Technical Decisions

### Architecture
- **Single HTML file**: All HTML, CSS, and JavaScript are bundled into one `index.html` file for maximum portability
- **CDN dependencies**: jQuery, Underscore, Backbone, and Google Charts loaded from CDNs
- **No build step required**: The app works by simply opening the HTML file or serving it from any static host

### URL State Management
- All form state is encoded as base64 JSON in the URL query string
- Uses `btoa()/atob()` for encoding/decoding
- Enables sharing offers via URL without any server-side storage
- State is restored on page load from URL

### Form Binding
- Custom two-way binding between Backbone model and form inputs
- Uses `data-model-attribute` attributes to map inputs to model properties
- Computed fields (like equity %) are automatically synced

## Conversion Notes (2026-01-14)

### What Was Converted
1. HAML templates → Static HTML with inline styles
2. CoffeeScript with RequireJS → Vanilla ES6 JavaScript
3. Ruby presenter classes → CSS classes directly in HTML
4. Server-side routing → Single page with hash anchors

### What Was Omitted (for MVP)
- PDF generation (jsPDF integration) - can be added later
- Comparison data charts (salary/equity benchmarks) - requires data source
- Mixpanel analytics tracking
- Some validation features

### Known Patterns
- `.js-*` classes are JavaScript hooks for DOM manipulation
- `.u-hidden` class toggles visibility for conditional content
- Presets (clear1, clear2) lock certain form fields with CLEAR-recommended values
- Charts use Google Visualization API

## Strategic Dimensions
(To be defined - these guide tradeoff decisions)

1. **Simplicity even over features** - A single static file that just works
2. **Privacy even over convenience** - No server storage, all data in URL
3. **Education even over precision** - Help users understand equity, not replace lawyers
