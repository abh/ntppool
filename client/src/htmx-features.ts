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

  // Check if this element already has a countdown to prevent duplicates
  if (element.querySelector('#countdown')) {
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
 * Monitor configuration and deletion error handler for HTMX responses
 * Handles both response errors and network errors
 * Migrated from legacy showMonitorConfigError function
 */
export function initializeMonitorErrorHandler(): void {
  // Handle HTTP response errors (4xx, 5xx status codes)
  document.addEventListener('htmx:responseError', (event: Event) => {
    const customEvent = event as HTMXEvent;

    // Only handle monitor-related errors
    if (!isMonitorError(customEvent)) {
      return;
    }

    handleMonitorConfigError(customEvent);
  });

  // Handle network errors (connection issues, timeouts, etc.)
  document.addEventListener('htmx:sendError', (event: Event) => {
    const customEvent = event as HTMXEvent;

    // Only handle monitor-related errors
    if (!isMonitorError(customEvent)) {
      return;
    }

    handleMonitorNetworkError(customEvent);
  });
}

/**
 * Check if the error is related to monitor operations (configuration, deletion, etc.)
 */
function isMonitorError(event: HTMXEvent): boolean {
  const element = event.detail.elt;

  // Check if the element or its parent has monitor-related attributes
  return !!(
    element.hasAttribute('data-monitor-config') ||
    element.hasAttribute('data-monitor-delete') ||
    element.closest('[data-monitor-config]') ||
    element.closest('[data-monitor-delete]') ||
    element.matches('form[action*="monitor"]') ||
    element.closest('form[action*="monitor"]') ||
    // Any HTMX request targeting monitor endpoints
    (element.getAttribute('hx-get') || element.getAttribute('hx-post') || '').includes('monitor')
  );
}

/**
 * Handle monitor configuration and deletion errors with comprehensive logging
 */
function handleMonitorConfigError(event: HTMXEvent): void {
  const xhr = event.detail.xhr;
  const element = event.detail.elt;

  console.log('Monitor config/delete error handler called', event);
  console.log('XHR object:', xhr);
  console.log('XHR status:', xhr.status);
  console.log('XHR response:', xhr.responseText);
  console.log('All response headers:', xhr.getAllResponseHeaders());

  // Check if this is a monitor deletion form
  const isDeleteForm = element.hasAttribute('data-monitor-delete') ||
                       element.closest('[data-monitor-delete]');

  // Check if this is a modal loading error
  const isModalError = element.getAttribute('hx-target') === '#modal-container';

  if (isDeleteForm) {
    handleMonitorDeletionError(xhr);
  } else if (isModalError) {
    handleMonitorModalError(xhr);
  } else {
    handleLegacyMonitorConfigError(xhr);
  }
}

/**
 * Handle modal loading errors (e.g., confirm-delete modal)
 */
function handleMonitorModalError(xhr: XMLHttpRequest): void {
  const modalContainer = document.getElementById('modal-container');

  if (!modalContainer) {
    console.error('Modal container element (#modal-container) not found');
    return;
  }

  // Extract error message and trace ID
  const { message, traceid } = extractErrorDetails(xhr);

  // Create error display HTML
  let errorHtml = `<div class="alert alert-danger" role="alert">
    <strong>Error:</strong> Unable to load confirmation dialog. ${escapeHtml(message)}`;

  if (traceid && traceid !== 'Not available') {
    errorHtml += `<br><small>Trace ID: ${escapeHtml(traceid)} (please include this if contacting support)</small>`;
  }

  errorHtml += `<br><small>Please try again or contact support if the problem persists.</small>`;
  errorHtml += '</div>';

  // Display error in the modal container
  modalContainer.innerHTML = errorHtml;

  // Log for debugging
  console.log('Modal loading error handled:', { message, traceid });
}

/**
 * Handle monitor deletion errors using the delete-result target
 */
function handleMonitorDeletionError(xhr: XMLHttpRequest): void {
  const deleteResultDiv = document.getElementById('delete-result');

  if (!deleteResultDiv) {
    console.error('Delete result element (#delete-result) not found');
    return;
  }

  // Extract error message and trace ID
  const { message, traceid } = extractErrorDetails(xhr);

  // Create error display HTML
  let errorHtml = `<div class="alert alert-danger" role="alert">
    <strong>Error:</strong> ${escapeHtml(message)}`;

  if (traceid && traceid !== 'Not available') {
    errorHtml += `<br><small>Trace ID: ${escapeHtml(traceid)} (please include this if contacting support)</small>`;
  }

  errorHtml += '</div>';

  // Display error in the delete-result div
  deleteResultDiv.innerHTML = errorHtml;

  // Log for debugging
  console.log('Monitor deletion error handled:', { message, traceid });
}

/**
 * Handle legacy monitor config errors using the original elements
 */
function handleLegacyMonitorConfigError(xhr: XMLHttpRequest): void {
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
 * Handle monitor network errors (connection failures, timeouts)
 */
function handleMonitorNetworkError(event: HTMXEvent): void {
  const element = event.detail.elt;

  console.log('Monitor network error handler called', event);

  // Check if this is a monitor deletion form
  const isDeleteForm = element.hasAttribute('data-monitor-delete') ||
                       element.closest('[data-monitor-delete]');

  // Check if this is a modal loading error
  const isModalError = element.getAttribute('hx-target') === '#modal-container';

  if (isDeleteForm) {
    handleMonitorDeletionNetworkError();
  } else if (isModalError) {
    handleMonitorModalNetworkError();
  } else {
    handleLegacyMonitorNetworkError();
  }
}

/**
 * Handle network errors for modal loading
 */
function handleMonitorModalNetworkError(): void {
  const modalContainer = document.getElementById('modal-container');

  if (!modalContainer) {
    console.error('Modal container element (#modal-container) not found');
    return;
  }

  // Create network error display HTML
  const errorHtml = `<div class="alert alert-warning" role="alert">
    <strong>Service Error:</strong> Unable to load confirmation dialog. Please try again or contact support if the problem persists.
  </div>`;

  // Display error in the modal container
  modalContainer.innerHTML = errorHtml;

  // Log for debugging
  console.log('Modal loading network error handled');
}

/**
 * Handle network errors for monitor deletion
 */
function handleMonitorDeletionNetworkError(): void {
  const deleteResultDiv = document.getElementById('delete-result');

  if (!deleteResultDiv) {
    console.error('Delete result element (#delete-result) not found');
    return;
  }

  // Create network error display HTML
  const errorHtml = `<div class="alert alert-danger" role="alert">
    <strong>Network Error:</strong> Unable to connect to the server. Please check your internet connection and try again.
  </div>`;

  // Display error in the delete-result div
  deleteResultDiv.innerHTML = errorHtml;

  // Log for debugging
  console.log('Monitor deletion network error handled');
}

/**
 * Handle network errors for legacy monitor config
 */
function handleLegacyMonitorNetworkError(): void {
  // Find error display elements
  const errorDiv = document.getElementById('monitor-config-error');
  const messageSpan = document.getElementById('monitor-config-error-message');
  const traceidSpan = document.getElementById('monitor-config-error-traceid');

  if (!errorDiv || !messageSpan || !traceidSpan) {
    console.error('Monitor config error elements not found');
    return;
  }

  // Display network error
  messageSpan.textContent = 'Network error - please check your connection and try again';
  traceidSpan.textContent = 'N/A';
  errorDiv.classList.remove('d-none');

  // Scroll to error message
  errorDiv.scrollIntoView({ behavior: 'smooth', block: 'nearest' });

  // Log for debugging
  console.log('Monitor config network error handled');
}

/**
 * HTML escaping utility using standard DOM APIs
 */
function escapeHtml(unsafe: string): string {
  const div = document.createElement('div');
  div.textContent = unsafe;
  return div.innerHTML;
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
