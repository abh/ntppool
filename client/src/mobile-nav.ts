/**
 * Simple Mobile Navigation Toggle
 * CSP-compliant mobile navigation for NTP Pool
 */

function initializeMobileNavigation(): void {
  const toggleButton = document.querySelector('.mobile-nav-toggle') as HTMLButtonElement;
  const closeButton = document.querySelector('.mobile-nav-close') as HTMLButtonElement;
  const overlay = document.querySelector('.mobile-nav-overlay') as HTMLElement;

  if (!toggleButton || !closeButton || !overlay) {
    return;
  }

  let isOpen = false;
  let lastFocusedElement: HTMLElement | null = null;

  function openMenu(): void {
    if (isOpen) return;

    isOpen = true;
    lastFocusedElement = document.activeElement as HTMLElement;

    toggleButton.classList.add('active');
    toggleButton.setAttribute('aria-expanded', 'true');
    overlay.classList.add('active');
    document.body.classList.add('mobile-nav-open');

    // Focus close button after animation (or immediately if reduced motion)
    const delay = window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : 300;
    setTimeout(() => closeButton.focus(), delay);
  }

  function closeMenu(): void {
    if (!isOpen) return;

    isOpen = false;

    toggleButton.classList.remove('active');
    toggleButton.setAttribute('aria-expanded', 'false');
    overlay.classList.remove('active');
    document.body.classList.remove('mobile-nav-open');

    // Restore focus
    if (lastFocusedElement) {
      lastFocusedElement.focus();
    }
  }

  function toggleMenu(): void {
    if (isOpen) {
      closeMenu();
    } else {
      openMenu();
    }
  }

  // Event listeners
  toggleButton.addEventListener('click', toggleMenu);
  closeButton.addEventListener('click', closeMenu);

  // Close on overlay click (outside menu content)
  overlay.addEventListener('click', (e) => {
    if (e.target === overlay) {
      closeMenu();
    }
  });

  // Keyboard support
  document.addEventListener('keydown', (e) => {
    if (isOpen && e.key === 'Escape') {
      e.preventDefault();
      closeMenu();
    }
  });

  // Close menu when window becomes desktop size
  window.addEventListener('resize', () => {
    if (window.innerWidth >= 768 && isOpen) {
      closeMenu();
    }
  });
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeMobileNavigation);
} else {
  initializeMobileNavigation();
}
