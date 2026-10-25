/**
 * Class toggle for elements marked with
 * data-toggle-class="<class>" data-toggle-target="<selector>".
 *
 * A click on the element (or inside it) toggles the class on every element
 * matching the selector. It replaces inline onclick and hx-on handlers, which
 * the CSP blocks. One delegated listener on document also covers content
 * that htmx swaps in later.
 */

let installed = false;

export function initializeToggleClass(): void {
  if (installed) {
    return;
  }
  installed = true;

  document.addEventListener('click', event => {
    if (!(event.target instanceof Element)) {
      return;
    }
    const trigger = event.target.closest<HTMLElement>('[data-toggle-class]');
    if (!trigger) {
      return;
    }

    const className = trigger.dataset['toggleClass'];
    const selector = trigger.dataset['toggleTarget'];
    if (!className || !selector) {
      console.error('data-toggle-class needs a class and a data-toggle-target selector', trigger);
      return;
    }

    const targets = document.querySelectorAll(selector);
    if (targets.length === 0) {
      console.error(`data-toggle-target "${selector}" matched nothing`, trigger);
      return;
    }
    targets.forEach(target => target.classList.toggle(className));
  });
}
