/**
 * Mercurius AI — homepage lesson replay (#demo)
 *
 * Progressive enhancement. scripts/build-demo-replay.mjs writes the whole
 * replay (three turns of a recorded lesson, fully rendered) into index.html,
 * so without JS it reads top to bottom. This script turns it into a
 * step-through:
 *   1. Only turn 1 shows. The visitor taps (or arrows + Enter/Space) an
 *      option of the check; it's graded here, from the card's data-answer.
 *      Nothing is sent anywhere.
 *   2. A note says what the student picked in the recorded session, and
 *      "Continue" reveals that pick and Mercurius's real reply to it. The
 *      reply answers the recorded pick, never the visitor's.
 *   3. And so on to turn 3's check, then the end panel.
 * "Show the whole lesson" reveals everything (unanswered checks show the
 * recorded pick, like the app re-renders an answered card); "Start over"
 * resets. New content is announced in a polite live region and focus moves
 * to the first element of what was revealed.
 *
 * Debug hook (screenshots and the check script only; read-only, no
 * network): ?demo-step=<step> opens the replay at a given point, with each
 * earlier check answered with the recorded pick (or the right answer where
 * none was recorded). Steps: turn1, answered1, turn2, answered2, turn3,
 * answered3, end, whole.
 *
 * No dependencies. Loaded with `defer`.
 */
(() => {
  'use strict';

  const root = document.querySelector('[data-demo]');
  if (!root) return;

  const all = (sel, el = root) => Array.from(el.querySelectorAll(sel));
  const one = (sel, el = root) => el.querySelector(sel);
  const letter = (i) => String.fromCharCode(65 + i);
  const indexOf = (l) => (l ? l.charCodeAt(0) - 65 : null);
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  const turns = all('[data-demo-turn]');
  const total = turns.length;
  const live = one('[data-demo-live]');
  const progress = one('[data-demo-progress]');
  const end = one('[data-demo-end]');
  const endTitle = one('[data-demo-end-title]');
  const wholeButton = one('[data-demo-action="whole"]');
  const restartButtons = all('[data-demo-action="restart"]');
  if (!total || !live || !end) return;

  // ---- Build the per-turn model + enhance the options into radios ----
  const checks = turns.map((turn, t) => {
    const card = one('[data-demo-check]', turn);
    const list = one('.demo-options', card);
    const note = one('[data-demo-note]', turn);
    const check = {
      turn,
      first: one('.demo-msg', turn),
      answer: indexOf(card.dataset.answer),
      recorded: card.dataset.recordedPick ? indexOf(card.dataset.recordedPick) : null,
      list,
      items: all('.demo-option', list),
      buttons: [],
      focusIndex: 0,
      feedback: one('[data-demo-feedback]', note),
      recordedNote: one('[data-demo-recorded]', note),
      note,
      cont: one('[data-demo-action="continue"]', note),
    };

    list.setAttribute('role', 'radiogroup');
    check.items.forEach((item, k) => {
      item.setAttribute('role', 'none');
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'demo-option-btn';
      button.setAttribute('role', 'radio');
      button.setAttribute('aria-checked', 'false');
      while (item.firstChild) button.appendChild(item.firstChild);
      item.appendChild(button);
      check.buttons.push(button);
      button.addEventListener('click', () => pick(t, k));
      button.addEventListener('focus', () => { check.focusIndex = k; roving(check); });
    });

    // Radio keyboard path: arrows/Home/End move focus; Enter or Space picks
    // (native button activation). Moving never grades, so a visitor can
    // read every option before choosing.
    list.addEventListener('keydown', (e) => {
      const at = check.buttons.indexOf(document.activeElement);
      if (at === -1) return;
      const n = check.buttons.length;
      const to = {
        ArrowDown: (at + 1) % n, ArrowRight: (at + 1) % n,
        ArrowUp: (at - 1 + n) % n, ArrowLeft: (at - 1 + n) % n,
        Home: 0, End: n - 1,
      }[e.key];
      if (to === undefined) return;
      e.preventDefault();
      check.buttons[to].focus();
    });

    // The no-JS "Show the answer" disclosure isn't needed once grading works.
    all('[data-demo-static-answer]', note).forEach((el) => el.remove());
    check.cont.addEventListener('click', () => advance(t));
    return check;
  });

  // ---- State ----
  const fresh = () => ({ shown: 1, picks: checks.map(() => null), whole: false, ended: false });
  let state = fresh();
  const isFresh = () => state.shown === 1 && !state.whole && !state.ended
    && state.picks.every((p) => p === null);

  function roving(check) {
    check.buttons.forEach((b, k) => { b.tabIndex = k === check.focusIndex ? 0 : -1; });
  }

  function render() {
    turns.forEach((turn, t) => { turn.hidden = !(state.whole || t < state.shown); });

    checks.forEach((c, t) => {
      const mine = state.picks[t];
      const showRecorded = c.recorded !== null && (mine !== null || state.whole);
      // Graded by the visitor's pick, or — in "whole lesson" view of an
      // unanswered check — by the recorded pick (the app's inert re-render).
      const graded = mine !== null ? mine : (showRecorded ? c.recorded : null);

      c.items.forEach((item, k) => {
        const button = c.buttons[k];
        const isAnswer = k === c.answer;
        item.classList.toggle('is-answer', graded !== null && isAnswer);
        item.classList.toggle('is-wrong', graded !== null && k === graded && !isAnswer);
        button.setAttribute('aria-checked', mine === k ? 'true' : 'false');
        if (graded !== null) button.setAttribute('aria-disabled', 'true');
        else button.removeAttribute('aria-disabled');

        const tag = one('[data-demo-pick-tag]', item);
        if (tag) tag.hidden = !(showRecorded && k === c.recorded);

        const parts = [];
        if (mine === k) parts.push('your pick');
        if (showRecorded && k === c.recorded) parts.push('the student’s pick');
        if (graded !== null && isAnswer) parts.push('correct answer');
        else if (parts.length) parts.push('not correct');
        one('[data-demo-option-state]', item).textContent = parts.length ? ` (${parts.join(', ')})` : '';
      });
      if (graded !== null) {
        c.list.setAttribute('aria-readonly', 'true');
        c.focusIndex = graded;
      } else {
        c.list.removeAttribute('aria-readonly');
      }
      roving(c);

      c.note.hidden = !(mine !== null || showRecorded);
      c.feedback.hidden = mine === null;
      if (mine !== null) {
        const right = mine === c.answer;
        c.feedback.textContent = `${right ? 'Correct.' : 'Not quite.'} The answer is ${letter(c.answer)}.`;
        c.feedback.classList.toggle('is-correct', right);
        c.feedback.classList.toggle('is-incorrect', !right);
      }
      if (c.recordedNote) c.recordedNote.hidden = !showRecorded;
      c.cont.hidden = !(mine !== null && !state.whole && t === state.shown - 1 && !state.ended);
    });

    end.hidden = !(state.whole || state.ended);
    progress.textContent = state.whole ? `All ${total} turns`
      : state.ended ? 'End of the replay'
        : `Turn ${state.shown} of ${total}`;
    wholeButton.disabled = state.whole || state.ended;
    restartButtons.forEach((b) => { b.disabled = isFresh(); });
  }

  // ---- Announcements + focus ----
  let announceTimer;
  function announce(message) {
    clearTimeout(announceTimer);
    live.textContent = '';
    // A fresh text node after a beat, so a repeated message is read again.
    announceTimer = setTimeout(() => { live.textContent = message; }, 60);
  }

  function reveal(el) {
    if (reduceMotion.matches) return;
    el.classList.remove('is-entering');
    void el.offsetWidth; // restart the fade
    el.classList.add('is-entering');
  }

  function focusOn(el) {
    if (!el.hasAttribute('tabindex')) el.setAttribute('tabindex', '-1');
    el.focus({ preventScroll: true });
    el.scrollIntoView({ block: 'start', behavior: reduceMotion.matches ? 'auto' : 'smooth' });
  }

  // ---- Actions ----
  function pick(t, k) {
    const c = checks[t];
    if (state.picks[t] !== null || (state.whole && c.recorded !== null)) return;
    state.picks[t] = k;
    c.focusIndex = k;
    render();
    const recorded = c.recorded !== null
      ? ` In this session, the student picked ${letter(c.recorded)}.`
      : '';
    announce(`${c.feedback.textContent}${recorded}`);
  }

  function advance(t) {
    if (t < total - 1) {
      state.shown = t + 2;
      render();
      const turn = turns[t + 1];
      reveal(turn);
      focusOn(checks[t + 1].first);
      announce(`Turn ${t + 2} of ${total}: the student’s pick from the recorded session, then Mercurius’s reply.`);
    } else {
      state.ended = true;
      render();
      reveal(end);
      focusOn(endTitle);
      announce('End of the replay. The full lesson continues in the app.');
    }
  }

  function showWhole() {
    const firstHidden = turns.findIndex((turn) => turn.hidden);
    state.whole = true;
    render();
    if (firstHidden !== -1) {
      turns.slice(firstHidden).forEach(reveal);
      reveal(end);
      focusOn(checks[firstHidden].first);
    } else {
      reveal(end);
      focusOn(endTitle);
    }
    announce(`Showing the whole replay: all ${total} turns, with the student’s recorded picks.`);
  }

  function restart() {
    state = fresh();
    checks.forEach((c) => { c.focusIndex = 0; });
    render();
    focusOn(checks[0].first);
    announce(`Replay restarted at turn 1 of ${total}.`);
  }

  wholeButton.addEventListener('click', showWhole);
  restartButtons.forEach((b) => b.addEventListener('click', restart));

  // ---- Debug hook: ?demo-step=… (see the header comment) ----
  function applyStep(step) {
    const auto = (t) => (checks[t].recorded !== null ? checks[t].recorded : checks[t].answer);
    if (step === 'whole') { state.whole = true; return; }
    if (step === 'end') {
      state.shown = total;
      state.picks = checks.map((_, t) => auto(t));
      state.ended = true;
      return;
    }
    const m = /^(turn|answered)(\d)$/.exec(step || '');
    if (!m) return;
    const n = Math.min(Math.max(Number(m[2]), 1), total);
    state.shown = n;
    for (let t = 0; t < n - 1; t++) state.picks[t] = auto(t);
    if (m[1] === 'answered') state.picks[n - 1] = auto(n - 1);
  }
  try {
    applyStep(new URLSearchParams(window.location.search).get('demo-step'));
  } catch (_) { /* no URLSearchParams: ignore the hook */ }

  // ---- Go ----
  all('[data-demo-howto]', document).forEach((el) => { el.hidden = false; });
  wholeButton.hidden = false;
  restartButtons.forEach((b) => { b.hidden = false; });
  root.classList.add('is-enhanced');
  render();
})();
