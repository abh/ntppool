/**
 * Plausible Analytics Integration
 * Uses the plausible-client NPM package
 */

import { Plausible, enableAutoPageviews, enableAutoOutboundTracking } from 'plausible-client'

// Read configuration from meta tags
const domainMeta = document.querySelector('meta[name="plausible-domain"]')
const apiHostMeta = document.querySelector('meta[name="plausible-api-host"]')

// Handle relative API paths by converting to full URL
const apiHostValue = apiHostMeta?.getAttribute('content') || '/api/event'
const apiHost = apiHostValue.startsWith('/')
  ? window.location.origin + apiHostValue
  : apiHostValue

const plausible = new Plausible({
  domain: domainMeta?.getAttribute('content') || window.location.hostname,
  apiHost: apiHost,
})

// Enable automatic page view tracking
enableAutoPageviews(plausible)

// Enable automatic outbound link tracking
enableAutoOutboundTracking(plausible)

console.log('Plausible analytics initialized for domain:', domainMeta?.getAttribute('content') || window.location.hostname)

// Export for manual usage if needed
export default plausible
