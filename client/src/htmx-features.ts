/**
 * Enhanced HTMX features including auto-redirect and monitor error handling
 * Migrated from legacy ntppool.js with improved TypeScript implementation
 */

import type { HTMXEvent, ErrorDetails, HTMXResponseError } from '@/types/htmx.js';

/**
 * Auto-redirect functionality for monitor acceptance success
 * Migrated from legacy autoRedirectOnSuccess function
 */
export function initializeAutoRedirect(): void {
  document.addEventListener('htmx:afterSwap', (event: Event) => {
    const customEvent = event as HTMXEvent;
    const redirectElements = customEvent.target.querySelectorAll<HTMLElement>('[data-redirect-url]');

    redirectElements.forEach((elem) => {
      handleAutoRedirect(elem);
    });
  });
}

/**
 * Handle individual auto-redirect element with countdown display
 */
function handleAutoRedirect(element: HTMLElement): void {
  const targetUrl = element.getAttribute('data-redirect-url');
  const delay = parseInt(element.getAttribute('data-delay') || '1500', 10);
  const countdown = Math.floor(delay / 1000);

  if (!targetUrl) {
    console.warn('Auto-redirect element missing data-redirect-url attribute');
    return;
  }

  // Create countdown display
  const countdownElement = createCountdownDisplay(countdown);
  element.appendChild(countdownElement);

  // Start countdown timer
  startCountdown(countdownElement, countdown, targetUrl);
}

/**
 * Create countdown display element
 */
function createCountdownDisplay(initialCountdown: number): HTMLParagraphElement {
  const countdownP = document.createElement('p');
  countdownP.innerHTML = `<small>Redirecting to monitor in <span id="countdown">${initialCountdown}</span> seconds...</small>`;
  return countdownP;
}

/**
 * Start countdown timer with visual feedback
 */
function startCountdown(countdownContainer: HTMLElement, countdown: number, targetUrl: string): void {
  const countdownElement = countdownContainer.querySelector('#countdown');

  if (!countdownElement) {
    console.error('Countdown element not found');
    return;
  }

  const timer = setInterval(() => {
    countdown--;
    countdownElement.textContent = countdown.toString();

    if (countdown <= 0) {
      clearInterval(timer);
      window.location.href = targetUrl;
    }
  }, 1000);
}

/**
 * Monitor configuration error handler for HTMX responses
 * Migrated from legacy showMonitorConfigError function
 */
export function initializeMonitorErrorHandler(): void {
  document.addEventListener('htmx:responseError', (event: Event) => {
    const customEvent = event as HTMXEvent;

    // Only handle monitor configuration errors
    if (!isMonitorConfigurationError(customEvent)) {
      return;
    }

    handleMonitorConfigError(customEvent);
  });
}

/**
 * Check if the error is related to monitor configuration
 */
function isMonitorConfigurationError(event: HTMXEvent): boolean {
  const element = event.detail.elt;

  // Check if the element or its parent has monitor-related attributes
  return !!(
    element.hasAttribute('data-monitor-config') ||
    element.closest('[data-monitor-config]') ||
    element.matches('form[action*="monitor"]') ||
    element.closest('form[action*="monitor"]')
  );
}

/**
 * Handle monitor configuration errors with comprehensive logging
 */
function handleMonitorConfigError(event: HTMXEvent): void {
  const xhr = event.detail.xhr;

  console.log('Monitor config error handler called', event);
  console.log('XHR object:', xhr);
  console.log('XHR status:', xhr.status);
  console.log('XHR response:', xhr.responseText);
  console.log('All response headers:', xhr.getAllResponseHeaders());

  // Find error display elements
  const errorDiv = document.getElementById('monitor-config-error');
  const messageSpan = document.getElementById('monitor-config-error-message');
  const traceidSpan = document.getElementById('monitor-config-error-traceid');

  if (!errorDiv || !messageSpan || !traceidSpan) {
    console.error('Monitor config error elements not found');
    return;
  }

  // Extract error message and trace ID
  const { message, traceid } = extractErrorDetails(xhr);

  // Display error
  messageSpan.textContent = message;
  traceidSpan.textContent = traceid;
  errorDiv.classList.remove('d-none');

  // Scroll to error message
  errorDiv.scrollIntoView({ behavior: 'smooth', block: 'nearest' });

  // Log for debugging
  console.log('Monitor config error handled:', { message, traceid });
}

/**
 * Extract error message and trace ID from XHR response
 */
function extractErrorDetails(xhr: XMLHttpRequest): ErrorDetails {
  // Extract trace ID from response headers (try multiple case variations)
  const traceid = xhr.getResponseHeader('TraceID') ||
                  xhr.getResponseHeader('traceid') ||
                  xhr.getResponseHeader('Traceid') ||
                  'Not available';

  console.log('Traceid extraction attempts:', {
    TraceID: xhr.getResponseHeader('TraceID'),
    traceid: xhr.getResponseHeader('traceid'),
    Traceid: xhr.getResponseHeader('Traceid')
  });

  // Default error message
  let message = 'Server error occurred';

  // Try to parse JSON response for more detailed error
  try {
    const response: HTMXResponseError = JSON.parse(xhr.responseText);
    if (response && response.error) {
      message = response.error;
    } else if (response && response.message) {
      message = response.message;
    }
  } catch (e) {
    // If not JSON, use status text or default message
    if (xhr.statusText) {
      message = xhr.statusText;
    }
  }

  return { message, traceid };
}

/**
 * Initialize all HTMX enhanced features
 */
export function initializeHTMXFeatures(): void {
  initializeAutoRedirect();
  initializeMonitorErrorHandler();

  console.log('HTMX enhanced features initialized');
}
