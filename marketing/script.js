/**
 * Mercurius AI — marketing site
 *
 * Deliberately minimal. The page works without JS — the mode tabs
 * stay on "Socratic" (the default panel is the only one not hidden)
 * and the phone menu is a native <details>. This script wires up the
 * tab switching, a few menu niceties, and a tiny dynamic year in the
 * footer. (Reel players live in ads.js, the lesson replay in demo.js.)
 *
 * No frameworks, no dependencies. Loaded `defer` so it never blocks
 * parse.
 */

(() => {
  'use strict';

  // ---- Mode tabs (Socratic / Debate / Discussion) ----
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

  // ---- Phone/tablet menu ----
  //
  // The menu is a native <details>, so it opens and closes without JS.
  // This only adds the expected extras: Escape closes it (and returns
  // focus to "Menu"), and so do a click outside it or on one of its links,
  // and Tabbing out of it.
  document.querySelectorAll('[data-nav-menu]').forEach((menu) => {
    const summary = menu.querySelector('summary');
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && menu.open) {
        menu.open = false;
        if (summary) summary.focus();
      }
    });
    document.addEventListener('click', (e) => {
      if (menu.open && !menu.contains(e.target)) menu.open = false;
    });
    menu.addEventListener('click', (e) => {
      if (e.target.closest('a')) menu.open = false;
    });
    // Close it when keyboard focus leaves it, so the open panel never
    // covers the next focused link (WCAG 2.4.7).
    menu.addEventListener('focusout', (e) => {
      if (menu.open && e.relatedTarget && !menu.contains(e.relatedTarget)) menu.open = false;
    });
  });

  // ---- Dynamic year ----
  const year = document.getElementById('year');
  if (year) year.textContent = String(new Date().getFullYear());
})();
