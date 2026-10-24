/**
 * Submit-once guard for forms marked with data-submit-once="<busy text>".
 *
 * A second submit while the first is in flight is cancelled. The submit
 * buttons are not disabled: a disabled submitter is left out of the form
 * data, and the confirm button (name="yes") has to be sent.
 */

const SUBMITTING_ATTR = 'data-submitting';

type SubmitControl = HTMLInputElement | HTMLButtonElement;

function submitButtons(form: HTMLFormElement): SubmitControl[] {
  return Array.from(
    form.querySelectorAll<SubmitControl>('input[type="submit"], button[type="submit"], button:not([type])')
  );
}

function setLabel(control: SubmitControl, text: string): void {
  if (control instanceof HTMLInputElement) {
    control.value = text;
  } else {
    control.textContent = text;
  }
}

function getLabel(control: SubmitControl): string {
  return control instanceof HTMLInputElement ? control.value : (control.textContent ?? '');
}

export function initializeSubmitOnce(): void {
  const forms = document.querySelectorAll<HTMLFormElement>('form[data-submit-once]');

  forms.forEach(form => {
    const busyText = form.dataset['submitOnce'] ?? '';
    const originals = new Map<SubmitControl, string>();

    form.addEventListener('submit', event => {
      if (form.hasAttribute(SUBMITTING_ATTR)) {
        event.preventDefault();
        return;
      }

      form.setAttribute(SUBMITTING_ATTR, 'true');
      submitButtons(form).forEach(button => {
        originals.set(button, getLabel(button));
        if (busyText) {
          setLabel(button, busyText);
        }
        button.setAttribute('aria-disabled', 'true');
      });
    });

    // Back/forward cache restores the page in its submitting state.
    window.addEventListener('pageshow', event => {
      if (!event.persisted || !form.hasAttribute(SUBMITTING_ATTR)) {
        return;
      }
      form.removeAttribute(SUBMITTING_ATTR);
      originals.forEach((label, button) => {
        setLabel(button, label);
        button.removeAttribute('aria-disabled');
      });
      originals.clear();
    });
  });
}
