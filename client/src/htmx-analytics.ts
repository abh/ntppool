/**
 * HTMX Analytics Integration
 * Tracks essential HTMX events for user behavior insights
 */

import { track } from './analytics'

// Track HTMX form submissions and actions
document.addEventListener('htmx:beforeRequest', (event: Event) => {
  const customEvent = event as CustomEvent
  const element = customEvent.detail.elt as HTMLElement

  // Track form submissions
  if (element.tagName === 'FORM' || element.closest('form')) {
    const form = element.tagName === 'FORM' ? element : element.closest('form')
    const formName = form?.getAttribute('data-analytics-name') ||
                    form?.getAttribute('id') ||
                    'unknown-form'

    track('htmx_form_submit', {
      interactive: true,
      props: {
        form_name: formName,
        action: customEvent.detail.pathInfo?.requestPath || 'unknown',
        method: customEvent.detail.verb || 'GET'
      }
    })
  }

  // Track button/link interactions
  if (element.hasAttribute('data-analytics-action')) {
    track('htmx_action', {
      interactive: true,
      props: {
        action: element.getAttribute('data-analytics-action') || 'unknown',
        target: customEvent.detail.target?.id || 'unknown',
        trigger: element.tagName.toLowerCase()
      }
    })
  }
})

// Track HTTP errors (4xx, 5xx responses)
document.addEventListener('htmx:responseError', (event: Event) => {
  const customEvent = event as CustomEvent
  const element = customEvent.detail.elt as HTMLElement
  const context = element.closest('form')?.getAttribute('data-analytics-name') ||
                  element.getAttribute('data-analytics-action') ||
                  'unknown'

  track('htmx_response_error', {
    interactive: false,
    props: {
      context: context,
      status_code: customEvent.detail.xhr.status.toString(),
      path: customEvent.detail.pathInfo?.requestPath || 'unknown',
      method: customEvent.detail.pathInfo?.verb || 'unknown'
    }
  })
})

// Track form validation failures
document.addEventListener('htmx:validation:failed', (event: Event) => {
  const customEvent = event as CustomEvent
  const element = customEvent.detail.elt as HTMLElement
  const form = element.closest('form')

  // Cast to input/form element to access name and type properties
  const inputElement = element as HTMLInputElement

  track('htmx_validation_failed', {
    interactive: false,
    props: {
      form_name: form?.getAttribute('data-analytics-name') || form?.id || 'unknown',
      field_name: inputElement.name || element.id || 'unknown',
      field_type: inputElement.type || element.tagName.toLowerCase(),
      error_count: (customEvent.detail.errors?.length || 1).toString()
    }
  })
})

// Track user confirmation dialogs (only when confirmation is actually shown)
document.addEventListener('htmx:confirm', (event: Event) => {
  const customEvent = event as CustomEvent
  const element = customEvent.detail.elt as HTMLElement

  // Only track if there's actually a confirmation dialog
  const hasConfirm = element.getAttribute('hx-confirm') ||
                     element.getAttribute('data-confirm') ||
                     element.hasAttribute('hx-confirm')

  if (hasConfirm) {
    track('htmx_confirm_shown', {
      interactive: false,
      props: {
        action: element.getAttribute('data-analytics-action') ||
                element.closest('form')?.getAttribute('data-analytics-name') ||
                'unknown',
        trigger_type: element.tagName.toLowerCase(),
        confirm_text: element.getAttribute('hx-confirm') || 'true'
      }
    })
  }
})

console.log('HTMX analytics event tracking initialized')
