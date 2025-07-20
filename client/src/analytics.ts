/**
 * Plausible Analytics Integration
 * Uses the upstream plausible script
 */

import { init, track } from './plausible.js'

// Read configuration from meta tags
const domainMeta = document.querySelector('meta[name="plausible-domain"]')
const apiHostMeta = document.querySelector('meta[name="plausible-api-host"]')
const propsMeta = document.querySelector('meta[name="plausible-props"]')

// Default to current host, allow override
const apiHostValue = apiHostMeta?.getAttribute('content') || (window.location.protocol + '//' + window.location.host)
const endpoint = apiHostValue + '/api/event'

// Parse custom properties from meta tag
let customProperties = {}
try {
  const propsContent = propsMeta?.getAttribute('content')
  if (propsContent) {
    customProperties = JSON.parse(propsContent)
  }
} catch (e) {
  console.warn('Failed to parse plausible-props meta tag:', e)
}

// Initialize plausible
init({
  domain: domainMeta?.getAttribute('content') || window.location.hostname,
  endpoint: endpoint,
  autoCapturePageviews: true,
  outboundLinks: true,
  fileDownloads: true,
  customProperties: customProperties,
})

console.log('Plausible analytics initialized for domain:', domainMeta?.getAttribute('content') || window.location.hostname)

// Export track function for manual usage if needed
export { track }
export default { track }
