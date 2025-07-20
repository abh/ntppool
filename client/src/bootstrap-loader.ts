/**
 * Optimized Bootstrap component loader with tree-shaking
 *
 * - Only loads Bootstrap JS components when needed DOM elements are present
 * - Uses individual component imports for minimal bundle size
 * - Loads components in parallel for better performance
 * - Supports: Dropdown, Alert, Modal, Tooltip, Popover
 *
 * Instead of loading the full 90KB Bootstrap bundle, this loader:
 * - Dropdown: ~5KB
 * - Alert: ~2KB
 * - Modal: ~8KB
 * - Tooltip: ~6KB
 * - Popover: ~7KB
 */

// Type imports for individual Bootstrap components
type Alert = any; // Will be properly typed when imported
type Dropdown = any; // Will be properly typed when imported
type Modal = any; // Will be properly typed when imported
type Tooltip = any; // Will be properly typed when imported
type Popover = any; // Will be properly typed when imported

export interface BootstrapComponents {
  Dropdown?: typeof Dropdown;
  Alert?: typeof Alert;
  Modal?: typeof Modal;
  Tooltip?: typeof Tooltip;
  Popover?: typeof Popover;
}

/**
 * Check if Bootstrap dropdown components are present in the DOM
 */
function hasDropdownComponents(): boolean {
  return document.querySelector('[data-bs-toggle="dropdown"]') !== null;
}

/**
 * Check if Bootstrap alert components are present in the DOM
 * Handles both Bootstrap 4 (data-dismiss) and Bootstrap 5 (data-bs-dismiss) syntax
 */
function hasAlertComponents(): boolean {
  return document.querySelector('.alert-dismissible [data-dismiss="alert"], .alert-dismissible [data-bs-dismiss="alert"], .alert-dismissible .btn-close') !== null;
}

/**
 * Check if Bootstrap modal components are present in the DOM
 */
function hasModalComponents(): boolean {
  return document.querySelector('[data-bs-toggle="modal"], .modal') !== null;
}

/**
 * Check if Bootstrap tooltip components are present in the DOM
 */
function hasTooltipComponents(): boolean {
  return document.querySelector('[data-bs-toggle="tooltip"], [title]:not([title=""])') !== null;
}

/**
 * Check if Bootstrap popover components are present in the DOM
 */
function hasPopoverComponents(): boolean {
  return document.querySelector('[data-bs-toggle="popover"]') !== null;
}

/**
 * Initialize Bootstrap dropdown components
 */
function initializeDropdowns(DropdownClass: typeof Dropdown): void {
  const dropdownElements = document.querySelectorAll('[data-bs-toggle="dropdown"]');
  dropdownElements.forEach(element => {
    new DropdownClass(element as Element);
  });
  console.log(`Initialized ${dropdownElements.length} Bootstrap dropdown(s)`);
}

/**
 * Initialize Bootstrap alert components
 * Also handles migration from Bootstrap 4 to Bootstrap 5 data attributes
 */
function initializeAlerts(AlertClass: typeof Alert): void {
  const alertElements = document.querySelectorAll('.alert-dismissible');

  alertElements.forEach(element => {
    // Migrate Bootstrap 4 data-dismiss to Bootstrap 5 data-bs-dismiss
    const dismissButtons = element.querySelectorAll('[data-dismiss="alert"]');
    dismissButtons.forEach(button => {
      button.setAttribute('data-bs-dismiss', 'alert');
      button.removeAttribute('data-dismiss');
    });

    new AlertClass(element as Element);
  });
  console.log(`Initialized ${alertElements.length} Bootstrap alert(s)`);
}

/**
 * Initialize Bootstrap modal components
 */
function initializeModals(ModalClass: typeof Modal): void {
  const modalElements = document.querySelectorAll('.modal');
  modalElements.forEach(element => {
    new ModalClass(element as Element);
  });
  console.log(`Initialized ${modalElements.length} Bootstrap modal(s)`);
}

/**
 * Initialize Bootstrap tooltip components
 */
function initializeTooltips(TooltipClass: typeof Tooltip): void {
  const tooltipElements = document.querySelectorAll('[data-bs-toggle="tooltip"], [title]:not([title=""])');
  tooltipElements.forEach(element => {
    // Migrate title to data-bs-title for Bootstrap 5
    const title = element.getAttribute('title');
    if (title && !element.getAttribute('data-bs-toggle')) {
      element.setAttribute('data-bs-toggle', 'tooltip');
      element.setAttribute('data-bs-title', title);
      element.setAttribute('title', ''); // Clear original title to avoid browser tooltip
    }
    new TooltipClass(element as Element);
  });
  console.log(`Initialized ${tooltipElements.length} Bootstrap tooltip(s)`);
}

/**
 * Initialize Bootstrap popover components
 */
function initializePopovers(PopoverClass: typeof Popover): void {
  const popoverElements = document.querySelectorAll('[data-bs-toggle="popover"]');
  popoverElements.forEach(element => {
    new PopoverClass(element as Element);
  });
  console.log(`Initialized ${popoverElements.length} Bootstrap popover(s)`);
}

/**
 * Conditionally load and initialize Bootstrap components
 * Only loads components that are actually used on the page
 */
export async function loadBootstrapComponents(): Promise<BootstrapComponents> {
  const components: BootstrapComponents = {};
  const needsDropdown = hasDropdownComponents();
  const needsAlert = hasAlertComponents();
  const needsModal = hasModalComponents();
  const needsTooltip = hasTooltipComponents();
  const needsPopover = hasPopoverComponents();

  // Exit early if no Bootstrap components are needed
  if (!needsDropdown && !needsAlert && !needsModal && !needsTooltip && !needsPopover) {
    console.log('No Bootstrap JS components detected, skipping load');
    return components;
  }

  try {
    // Dynamic import - only import what we need
    const imports: string[] = [];
    if (needsDropdown) imports.push('Dropdown');
    if (needsAlert) imports.push('Alert');
    if (needsModal) imports.push('Modal');
    if (needsTooltip) imports.push('Tooltip');
    if (needsPopover) imports.push('Popover');

    console.log(`Loading Bootstrap components: ${imports.join(', ')}`);

    // Import only the specific components we need for optimal tree-shaking
    const importPromises: Promise<any>[] = [];

    if (needsDropdown) {
      importPromises.push(
        import('bootstrap/js/src/dropdown').then(module => ({
          type: 'Dropdown',
          class: module.default
        }))
      );
    }

    if (needsAlert) {
      importPromises.push(
        import('bootstrap/js/src/alert').then(module => ({
          type: 'Alert',
          class: module.default
        }))
      );
    }

    if (needsModal) {
      importPromises.push(
        import('bootstrap/js/src/modal').then(module => ({
          type: 'Modal',
          class: module.default
        }))
      );
    }

    if (needsTooltip) {
      importPromises.push(
        import('bootstrap/js/src/tooltip').then(module => ({
          type: 'Tooltip',
          class: module.default
        }))
      );
    }

    if (needsPopover) {
      importPromises.push(
        import('bootstrap/js/src/popover').then(module => ({
          type: 'Popover',
          class: module.default
        }))
      );
    }

    // Load components in parallel
    const loadedComponents = await Promise.all(importPromises);

    // Initialize each loaded component
    loadedComponents.forEach(({ type, class: ComponentClass }) => {
      switch (type) {
        case 'Dropdown':
          components.Dropdown = ComponentClass;
          initializeDropdowns(ComponentClass);
          break;
        case 'Alert':
          components.Alert = ComponentClass;
          initializeAlerts(ComponentClass);
          break;
        case 'Modal':
          components.Modal = ComponentClass;
          initializeModals(ComponentClass);
          break;
        case 'Tooltip':
          components.Tooltip = ComponentClass;
          initializeTooltips(ComponentClass);
          break;
        case 'Popover':
          components.Popover = ComponentClass;
          initializePopovers(ComponentClass);
          break;
      }
    });

    console.log('Bootstrap components loaded and initialized successfully');

    // Dispatch event to notify that Bootstrap is ready
    document.dispatchEvent(new CustomEvent('bootstrap-ready', {
      detail: { components: imports }
    }));

    return components;

  } catch (error) {
    console.error('Failed to load Bootstrap components:', error);

    // Dispatch error event
    document.dispatchEvent(new CustomEvent('bootstrap-error', {
      detail: { error }
    }));

    throw error;
  }
}

/**
 * Auto-initialize Bootstrap components when DOM is ready
 * This is called from main.ts
 */
export function initializeBootstrap(): void {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      loadBootstrapComponents().catch(error => {
        console.error('Bootstrap auto-initialization failed:', error);
      });
    });
  } else {
    // DOM is already ready
    loadBootstrapComponents().catch(error => {
      console.error('Bootstrap auto-initialization failed:', error);
    });
  }
}
