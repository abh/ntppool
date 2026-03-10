/**
 * WebForm.dev integration for help form submissions
 * The embed.js script automatically handles forms with the "webform-embed" class
 * This module just loads the required assets and sets up event listeners
 */

/**
 * Initialize WebForm.dev integration
 * Loads CSS/JS assets and sets up event listeners for webform events
 */
export function initializeWebForm(): void {
  // Only initialize if we're on a page with a webform-embed form
  const webformEmbedForm = document.querySelector('.webform-embed');
  if (!webformEmbedForm) {
    return;
  }

  // Load WebForm.dev assets
  Promise.all([loadWebFormCSS(), loadWebFormScript()]).then(() => {
    console.log('WebForm.dev assets loaded successfully');
    setupEventListeners();
  }).catch(error => {
    console.error('Failed to load WebForm.dev assets:', error);
  });
}

/**
 * Set up event listeners for webform events
 */
function setupEventListeners(): void {
  // Listen for webform success events
  document.addEventListener('webform:success', (event: any) => {
    const { form: _form, message } = event.detail;
    console.log('Form submitted successfully:', message);

    // Optional: Add any custom success handling here
    // The embed.js script already handles the UI updates based on data attributes
  });

  // Listen for webform error events
  document.addEventListener('webform:error', (event: any) => {
    const { form: _form, message, category } = event.detail;
    console.error('Form submission error:', message, 'Category:', category);

    // Optional: Add any custom error handling here
    // The embed.js script already handles the UI updates based on data attributes
  });

  // Listen for webform submission start
  document.addEventListener('webform:submit', (event: any) => {
    const { form: _form } = event.detail;
    console.log('Form submission started');

    // Optional: Add any custom loading state handling here
  });

  // Listen for submission completion (success or error)
  document.addEventListener('webform:complete', (event: any) => {
    const { form: _form } = event.detail;
    console.log('Form submission completed');

    // Optional: Add any cleanup or analytics tracking here
  });
}

/**
 * Dynamically load the WebForm.dev embed CSS
 */
function loadWebFormCSS(): Promise<void> {
  return new Promise((resolve, reject) => {
    // Check if CSS is already loaded
    if (document.querySelector('link[href="https://send.webform.dev/css/embed.css"]')) {
      resolve();
      return;
    }

    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = 'https://send.webform.dev/css/embed.css';
    link.onload = () => resolve();
    link.onerror = () => reject(new Error('Failed to load WebForm.dev CSS'));
    document.head.appendChild(link);
  });
}

/**
 * Dynamically load the WebForm.dev embed script
 */
function loadWebFormScript(): Promise<void> {
  return new Promise((resolve, reject) => {
    // Check if script is already loaded
    if (document.querySelector('script[src="https://send.webform.dev/js/embed.js"]')) {
      resolve();
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://send.webform.dev/js/embed.js';
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Failed to load WebForm.dev script'));
    document.head.appendChild(script);
  });
}
