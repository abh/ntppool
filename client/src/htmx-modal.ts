/**
 * Show Bootstrap modals that htmx swaps in.
 *
 * A fragment marks its modal with data-htmx-modal. After the swap the modal
 * is shown, and once it's hidden its instance is disposed and the element
 * removed, so loading the fragment again starts clean. This replaces the
 * inline <script> such fragments used to carry, which the CSP blocks.
 */

import { loadBootstrapBundle } from './bootstrap-loader';
import type { HTMXEvent } from './types/htmx';

const MODAL_SELECTOR = '.modal[data-htmx-modal]';

let installed = false;

/**
 * Show the failure in the page: prod builds strip console output, so a
 * console message alone would leave the click doing nothing.
 */
function renderModalError(container: HTMLElement): void {
  const alert = document.createElement('div');
  alert.className = 'alert alert-danger';
  alert.setAttribute('role', 'alert');
  alert.textContent = 'Could not open the dialog. Please reload the page.';
  container.replaceChildren(alert);
}

async function showModal(el: HTMLElement, container: HTMLElement): Promise<void> {
  if (!window.bootstrap?.Modal) {
    await loadBootstrapBundle();
  }
  const Modal = window.bootstrap?.Modal;
  if (!Modal) {
    console.error('Bootstrap Modal is not available; cannot show', el);
    renderModalError(container);
    return;
  }

  // A later swap can replace the fragment while the bundle loads; showing a
  // detached element would leave its backdrop on screen.
  if (!el.isConnected) {
    return;
  }

  Modal.getInstance(el)?.dispose();
  const modal = new Modal(el);
  el.addEventListener(
    'hidden.bs.modal',
    () => {
      modal.dispose();
      el.remove();
    },
    { once: true },
  );
  modal.show();
}

export function initializeHTMXModals(): void {
  if (installed) {
    return;
  }
  installed = true;

  document.addEventListener('htmx:afterSwap', (event: Event) => {
    const target = (event as HTMXEvent).target;
    const modals = Array.from(target.querySelectorAll<HTMLElement>(MODAL_SELECTOR));
    if (target.matches(MODAL_SELECTOR)) {
      modals.unshift(target);
    }

    modals.forEach(el => {
      // For an outerHTML swap the target is the modal itself, so an error
      // goes into its parent.
      const container = el === target ? target.parentElement : target;
      if (!container) {
        console.error('htmx modal has no container to report errors in', el);
        return;
      }
      showModal(el, container).catch(error => {
        console.error('Failed to show htmx modal:', error);
        renderModalError(container);
      });
    });
  });
}
