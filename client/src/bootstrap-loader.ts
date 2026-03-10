/**
 * Simple Bootstrap loader - loads custom bundle with Alert, Dropdown, and Collapse
 *
 * This replaces the complex component detection logic with a simple,
 * maintainable approach that loads a pre-configured bundle.
 */

// Extend Window interface to include bootstrap
declare global {
  interface Window {
    bootstrap?: {
      Dropdown?: any;
      Alert?: any;
      Collapse?: any;
      Popover?: any;
      Modal?: any;
    };
  }
}

/**
 * Check if Bootstrap components are needed on the page
 */
function hasBootstrapComponents(): boolean {
  return !!(
    document.querySelector('[data-bs-toggle="dropdown"]') ||
    document.querySelector('[data-bs-toggle="collapse"]') ||
    document.querySelector('[data-bs-toggle="popover"]') ||
    document.querySelector('.alert-dismissible') ||
    document.querySelector('[data-dismiss="alert"]') ||
    document.querySelector('.dropdown-toggle') ||
    document.querySelector('.dropdown-menu') ||
    document.querySelector('.collapse')
  );
}

/**
 * Initialize Bootstrap if needed
 */
export async function initializeBootstrap(): Promise<void> {
  if (!hasBootstrapComponents()) {
    console.log('No Bootstrap components detected, skipping load');

    // Listen for dynamic popover creation from charts
    document.addEventListener('chart-popovers-created', async (event: Event) => {
      const customEvent = event as CustomEvent;
      console.log('Chart popovers created, loading Bootstrap bundle', customEvent.detail);
      await loadBootstrapBundle();

      // After Bootstrap loads, manually initialize the specific popovers
      if (customEvent.detail && customEvent.detail.popovers) {
        await initializeSpecificPopovers(customEvent.detail.popovers);
      }
    });

    return;
  }

  await loadBootstrapBundle();
}

/**
 * Load and initialize Bootstrap bundle
 */
async function loadBootstrapBundle(): Promise<void> {
  try {
    // Load our custom bundle (includes Dropdown + Alert + Collapse + Popover)
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

/**
 * Initialize specific popover elements after Bootstrap is loaded
 */
async function initializeSpecificPopovers(elements: Element[]): Promise<void> {
  // Wait a bit to ensure Bootstrap is fully initialized
  await new Promise(resolve => setTimeout(resolve, 100));

  try {
    // Use globally available Bootstrap.Popover
    if (typeof window !== 'undefined' && window.bootstrap && window.bootstrap.Popover) {
      elements.forEach(element => {
        try {
          // Create popover instance using global Bootstrap
          new window.bootstrap.Popover(element);
          console.log('Manually initialized popover for element:', element.textContent);
        } catch (error) {
          console.error('Failed to initialize individual popover:', error);
        }
      });

      console.log(`Manually initialized ${elements.length} specific popover(s)`);
    } else {
      console.error('Bootstrap.Popover not available globally');
    }
  } catch (error) {
    console.error('Failed to initialize specific popovers:', error);
  }
}
