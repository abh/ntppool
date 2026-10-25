/**
 * Show a `.modal[data-htmx-modal]` after htmx swaps it in, then dispose and
 * remove it on hide. Replaces the inline <script> such fragments carried.
 */

import { loadBootstrapBundle } from './bootstrap-loader';
import { showErrorAlert } from './htmx-features';
import type { HTMXEvent } from './types/htmx';

const MODAL_ERROR = 'Could not open the dialog. Please reload the page.';

async function showModal(el: HTMLElement, container: HTMLElement): Promise<void> {
  if (!window.bootstrap?.Modal) {
    await loadBootstrapBundle();
  }
  const Modal = window.bootstrap?.Modal;
  if (!Modal) {
    // Prod builds strip console output, so the page shows the failure too.
    console.error('Bootstrap Modal is not available; cannot show', el);
    showErrorAlert(container, MODAL_ERROR);
    return;
  }

  // A later swap can replace the fragment while the bundle loads; showing a
  // detached element would leave its backdrop on screen.
  if (!el.isConnected) {
    return;
  }

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
  document.addEventListener('htmx:afterSwap', (event: Event) => {
    const target = (event as HTMXEvent).target;
    target.querySelectorAll<HTMLElement>('.modal[data-htmx-modal]').forEach(el => {
      showModal(el, target).catch(error => {
        console.error('Failed to show htmx modal:', error);
        showErrorAlert(target, MODAL_ERROR);
      });
    });
  });
}
