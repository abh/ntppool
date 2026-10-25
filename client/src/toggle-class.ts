/**
 * data-toggle-class="<class>" data-toggle-target="<selector>": a click toggles
 * the class on every match. Replaces inline onclick/hx-on handlers; delegated
 * on document so htmx-swapped content works too.
 */

export function initializeToggleClass(): void {
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
