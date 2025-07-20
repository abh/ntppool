/**
 * Custom Bootstrap Bundle - Only includes components we actually use
 * This reduces bundle size from 90KB to ~7KB
 */

// Import only the components we need
import Dropdown from 'bootstrap/js/src/dropdown';
import Alert from 'bootstrap/js/src/alert';

// Export for potential programmatic use
export { Dropdown, Alert };

/**
 * Initialize Bootstrap components when DOM is ready
 */
function initializeComponents() {
  // Initialize all dropdowns
  const dropdowns = document.querySelectorAll('[data-bs-toggle="dropdown"]');
  dropdowns.forEach(element => new Dropdown(element));

  if (dropdowns.length > 0) {
    console.log(`Initialized ${dropdowns.length} Bootstrap dropdown(s)`);
  }

  // Initialize all dismissible alerts
  const alerts = document.querySelectorAll('.alert-dismissible');
  alerts.forEach(element => new Alert(element));

  if (alerts.length > 0) {
    console.log(`Initialized ${alerts.length} Bootstrap alert(s)`);
  }

  // Handle Bootstrap 4 → 5 migration for alerts
  const oldAlerts = document.querySelectorAll('[data-dismiss="alert"]');
  oldAlerts.forEach(element => {
    element.setAttribute('data-bs-dismiss', 'alert');
    element.removeAttribute('data-dismiss');
    // Initialize the parent alert element
    const alertElement = element.closest('.alert');
    if (alertElement) {
      new Alert(alertElement);
    }
  });

  if (oldAlerts.length > 0) {
    console.log(`Migrated ${oldAlerts.length} Bootstrap 4 alert(s) to Bootstrap 5`);
  }
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeComponents);
} else {
  // DOM is already loaded
  initializeComponents();
}

// Re-initialize on HTMX content updates
document.addEventListener('htmx:afterSwap', (event) => {
  // Only initialize within the swapped content
  const target = event.detail.target;
  if (target) {
    // Initialize dropdowns in new content
    target.querySelectorAll('[data-bs-toggle="dropdown"]')
      .forEach(element => new Dropdown(element));

    // Initialize alerts in new content
    target.querySelectorAll('.alert-dismissible')
      .forEach(element => new Alert(element));

    // Handle Bootstrap 4 alerts in new content
    target.querySelectorAll('[data-dismiss="alert"]')
      .forEach(element => {
        element.setAttribute('data-bs-dismiss', 'alert');
        element.removeAttribute('data-dismiss');
        const alertElement = element.closest('.alert');
        if (alertElement) {
          new Alert(alertElement);
        }
      });
  }
});
