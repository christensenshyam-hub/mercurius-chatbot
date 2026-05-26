/**
 * Mercurius AI — marketing site
 *
 * Deliberately minimal. The page works without JS — the mode tabs
 * stay on "Socratic" (the default panel is the only one not hidden).
 * This script just wires up the tab switching + a tiny dynamic year
 * in the footer.
 *
 * No frameworks, no dependencies, ~30 lines. Loaded `defer` so it
 * never blocks parse.
 */

(() => {
  'use strict';

  // ---- Mode tabs (Socratic / Direct / Debate / Discussion) ----
  //
  // Tabs and panels are decoupled via `data-mode-panel`. Any element on
  // the page that wants to react to a mode change (the description
  // panel, the "Mode by intent" stage, anything we add later) tags
  // itself with `data-mode-panel="<mode>"` and gets toggled in one pass.
  const tabs = Array.from(document.querySelectorAll('.mode-pill[data-mode]'));
  const panels = Array.from(document.querySelectorAll('[data-mode-panel]'));

  if (tabs.length && panels.length) {
    const activate = (mode) => {
      tabs.forEach((t) => {
        const on = t.dataset.mode === mode;
        t.classList.toggle('is-active', on);
        t.setAttribute('aria-selected', on ? 'true' : 'false');
      });
      panels.forEach((p) => {
        const on = p.dataset.modePanel === mode;
        p.hidden = !on;
        p.classList.toggle('is-active', on);
      });
    };

    tabs.forEach((tab) => {
      tab.addEventListener('click', () => activate(tab.dataset.mode));
      // Arrow-key navigation between tabs (a11y nicety, matches WAI-ARIA
      // tablist pattern — keeps focus order intuitive).
      tab.addEventListener('keydown', (e) => {
        const i = tabs.indexOf(tab);
        if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
          e.preventDefault();
          const next = e.key === 'ArrowRight'
            ? tabs[(i + 1) % tabs.length]
            : tabs[(i - 1 + tabs.length) % tabs.length];
          next.focus();
          activate(next.dataset.mode);
        }
      });
    });
  }

  // ---- Dynamic year ----
  const year = document.getElementById('year');
  if (year) year.textContent = String(new Date().getFullYear());
})();
