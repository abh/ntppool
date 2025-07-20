/**
 * Simple Bootstrap loader - loads custom bundle with only Alert and Dropdown
 *
 * This replaces the complex component detection logic with a simple,
 * maintainable approach that loads a pre-configured bundle.
 */

/**
 * Check if Bootstrap components are needed on the page
 */
function hasBootstrapComponents(): boolean {
  return !!(
    document.querySelector('[data-bs-toggle="dropdown"]') ||
    document.querySelector('.alert-dismissible') ||
    document.querySelector('[data-dismiss="alert"]') ||
    document.querySelector('.dropdown-toggle') ||
    document.querySelector('.dropdown-menu')
  );
}

/**
 * Initialize Bootstrap if needed
 */
export async function initializeBootstrap(): Promise<void> {
  if (!hasBootstrapComponents()) {
    console.log('No Bootstrap components detected, skipping load');
    return;
  }

  try {
    // Load our custom bundle (only ~7KB with Dropdown + Alert)
    // @ts-ignore - This is a plain JS file with our custom Bootstrap bundle
    await import('./bootstrap-bundle.js');
    console.log('Bootstrap custom bundle loaded successfully');

    // Dispatch event for any code that needs to know Bootstrap is ready
    document.dispatchEvent(new CustomEvent('bootstrap-ready'));
  } catch (error) {
    console.error('Failed to load Bootstrap bundle:', error);

    // Dispatch error event
    document.dispatchEvent(new CustomEvent('bootstrap-error', {
      detail: { error }
    }));
  }
}
