#!/usr/bin/env node
// Checks the homepage lesson replay (#demo) in headless Chrome over the
// DevTools protocol — same approach as the club site's tools/shoot.mjs.
//
// usage: node scripts/check-demo.mjs [url]
//   url defaults to http://127.0.0.1:8160/index.html (any static server
//   over marketing/ works: `cd marketing && python3 -m http.server 8160`)
// env: CHROME=<path to a Chrome binary>
//
// Checks:
//   - the page section matches the generator (build-demo-replay.mjs --check);
//   - with JS off the whole replay is there and readable;
//   - with JS: the step-through order, keyboard-operable options, grading of
//     every option of every check, the recorded-pick notes, focus moving to
//     each new turn, "Show the whole lesson", "Start over", the live region,
//     reduced motion, and no network requests from the demo;
//   - no horizontal overflow at 360 and 390 px;
//   - every Mercurius reply on the page, with the page's own labels removed,
//     equals the source JSON with its markup rendered away (and each student
//     bubble equals the recorded student turn).
// Exits 1 on any failure.
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const URL_ = process.argv[2] || 'http://127.0.0.1:8160/index.html';
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// ---------------------------------------------------------------------------
// Expected content, straight from the capture (independent of the generator)
// ---------------------------------------------------------------------------
const capture = JSON.parse(readFileSync(path.join(ROOT, 'docs/evals/pacing-demo-capture-lesson1.json'), 'utf8'));
const convo = capture.perRun[1].results.find((r) => r.id === 'curriculum-blocks-1');
const TURNS = 3;
const source = convo.replies.slice(0, TURNS);
const norm = (s) => String(s).replace(/\s+/g, ' ').trim();
/** The reply as a reader sees it: markup gone, words untouched. */
const rendered = (raw) => norm(raw
  .replace(/^ANS:.*$/gm, ' ')
  .replace(/\[\/?(?:EX|KEY|Q|CHECK)\]/g, ' ')
  .replace(/^---$/gm, ' ')
  .replace(/\*\*([^*\n]+?)\*\*/g, '$1')
  .replace(/\*([^*\n]+?)\*/g, '$1'));
const answers = source.map((t) => /^ANS: ([A-D])$/m.exec(t.raw)[1]);
const optionCounts = source.map((t) => (/\[Q\]([\s\S]*?)\[\/Q\]/.exec(t.raw)[1].match(/^[A-D]\) /gm) || []).length);
// What the scripted student tapped on check t = the next turn's "I picked X)".
const recorded = source.map((_, t) => (t + 1 < TURNS ? /^I picked ([A-D])\)/.exec(convo.replies[t + 1].user)[1] : null));
const L = (i) => String.fromCharCode(65 + i);

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------
let failures = 0;
let passes = 0;
function check(name, cond, detail = '') {
  if (cond) { passes++; console.log(`ok   ${name}`); }
  else { failures++; console.log(`FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
  return cond;
}
const eq = (name, actual, expected) =>
  check(name, JSON.stringify(actual) === JSON.stringify(expected),
    `got ${JSON.stringify(actual)}, expected ${JSON.stringify(expected)}`);

// ---------------------------------------------------------------------------
// Chrome over CDP
// ---------------------------------------------------------------------------
const port = 9300 + Math.floor(Math.random() * 600);
const profile = mkdtempSync(path.join(os.tmpdir(), 'check-demo-'));
const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--no-first-run', '--no-default-browser-check', '--hide-scrollbars', '--disable-gpu', 'about:blank'],
{ stdio: 'ignore', detached: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function pageSocket() {
  for (let i = 0; i < 100; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page) return page.webSocketDebuggerUrl;
    } catch { /* not up yet */ }
    await sleep(150);
  }
  throw new Error('Chrome did not start');
}

let ws;
let nextId = 1;
const pending = new Map();
const listeners = [];
const requests = [];
function send(method, params = {}) {
  const id = nextId++;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}
function once(method, timeoutMs = 15000) {
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve(null), timeoutMs);
    listeners.push({ method, fn: (p) => { clearTimeout(t); resolve(p); } });
  });
}
async function js(expression) {
  const { result, exceptionDetails } = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (exceptionDetails) throw new Error(`page error: ${exceptionDetails.exception?.description || exceptionDetails.text}`);
  return result.value;
}

async function load({ scripts = true, width = 1280, height = 900, reduceMotion = false, query = '' } = {}) {
  const mobile = width < 768;
  await send('Emulation.setScriptExecutionDisabled', { value: !scripts });
  await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile });
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: reduceMotion ? 'reduce' : 'no-preference' }] });
  const loaded = once('Page.loadEventFired');
  await send('Page.navigate', { url: URL_ + query });
  await loaded;
  // Fonts settle layout; with scripts off, poll instead of awaiting a promise.
  await sleep(scripts ? 0 : 400);
  if (scripts) await js('document.fonts.ready.then(() => true)');
  await sleep(150);
}

const KEYS = {
  Tab: { code: 'Tab', vk: 9 },
  Enter: { code: 'Enter', vk: 13, text: '\r' },
  ' ': { code: 'Space', vk: 32, text: ' ' },
  ArrowDown: { code: 'ArrowDown', vk: 40 },
  ArrowUp: { code: 'ArrowUp', vk: 38 },
  ArrowRight: { code: 'ArrowRight', vk: 39 },
  ArrowLeft: { code: 'ArrowLeft', vk: 37 },
  Home: { code: 'Home', vk: 36 },
  End: { code: 'End', vk: 35 },
};
async function press(key, { shift = false } = {}) {
  const k = KEYS[key];
  const base = { key, code: k.code, windowsVirtualKeyCode: k.vk, nativeVirtualKeyCode: k.vk, modifiers: shift ? 8 : 0 };
  await send('Input.dispatchKeyEvent', { type: 'keyDown', ...base, ...(k.text ? { text: k.text, unmodifiedText: k.text } : {}) });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', ...base });
  await sleep(40);
}

// ---------------------------------------------------------------------------
// In-page probes
// ---------------------------------------------------------------------------
const PROBE = `(() => {
  const root = document.querySelector('[data-demo]');
  const shown = (el) => !!el && !el.closest('[hidden]') && el.getClientRects().length > 0;
  const turns = [...root.querySelectorAll('[data-demo-turn]')];
  // Text a reader gets from a node, minus everything the page adds itself
  // (data-demo-chrome): block elements become spaces, inline ones join.
  const textOf = (el) => {
    const c = el.cloneNode(true);
    c.querySelectorAll('[data-demo-chrome]').forEach((x) => x.remove());
    c.querySelectorAll('p,div,li,ol,ul,hr,button,br').forEach((b) => { b.before(' '); b.after(' '); });
    return c.textContent.replace(/\\s+/g, ' ').trim();
  };
  const active = document.activeElement;
  return {
    turnsShown: turns.map(shown),
    replies: [...root.querySelectorAll('[data-demo-reply]')].map(textOf),
    repliesShown: [...root.querySelectorAll('[data-demo-reply]')].map(shown),
    students: [...root.querySelectorAll('[data-demo-student]')].map((s) => textOf(s.querySelector('.demo-bubble'))),
    studentsShown: [...root.querySelectorAll('[data-demo-student]')].map(shown),
    endShown: shown(root.querySelector('[data-demo-end]')),
    progress: (root.querySelector('[data-demo-progress]') || {}).textContent,
    wholeShown: shown(root.querySelector('[data-demo-action="whole"]')),
    wholeDisabled: root.querySelector('[data-demo-action="whole"]').disabled,
    restartShown: shown(root.querySelector('[data-demo-action="restart"]')),
    restartDisabled: root.querySelector('[data-demo-action="restart"]').disabled,
    live: (root.querySelector('[data-demo-live]') || {}).textContent,
    liveRole: root.querySelector('[data-demo-live]').getAttribute('role'),
    livePolite: root.querySelector('[data-demo-live]').getAttribute('aria-live'),
    howtoShown: shown(document.querySelector('[data-demo-howto]')),
    checks: turns.map((turn) => {
      const card = turn.querySelector('[data-demo-check]');
      const list = card.querySelector('.demo-options');
      const items = [...list.querySelectorAll('.demo-option')];
      const note = turn.querySelector('[data-demo-note]');
      const fb = note.querySelector('[data-demo-feedback]');
      const rec = note.querySelector('[data-demo-recorded]');
      const cont = note.querySelector('[data-demo-action="continue"]');
      const answerEl = note.querySelector('[data-demo-static-answer]');
      return {
        groupRole: list.getAttribute('role'),
        labelled: !!document.getElementById(list.getAttribute('aria-labelledby') || '-'),
        radios: items.map((li) => li.querySelector('[role="radio"]')).filter(Boolean).length,
        options: items.length,
        tabbable: items.map((li) => { const b = li.querySelector('[role="radio"]'); return b ? b.tabIndex : null; }),
        checked: items.map((li) => { const b = li.querySelector('[role="radio"]'); return b ? b.getAttribute('aria-checked') : null; }),
        classes: items.map((li) => (li.classList.contains('is-answer') ? 'answer' : li.classList.contains('is-wrong') ? 'wrong' : '')),
        tags: items.map((li) => shown(li.querySelector('[data-demo-pick-tag]'))),
        heights: items.map((li) => Math.round((li.querySelector('[role="radio"]') || li).getBoundingClientRect().height)),
        noteShown: shown(note),
        feedback: shown(fb) ? fb.textContent : null,
        recorded: shown(rec) ? rec.textContent : null,
        contShown: shown(cont),
        staticAnswer: shown(answerEl),
      };
    }),
    active: active ? {
      tag: active.tagName,
      role: active.getAttribute('role'),
      student: active.getAttribute('data-demo-student'),
      reply: active.getAttribute('data-demo-reply'),
      endTitle: active.hasAttribute('data-demo-end-title'),
      action: active.getAttribute('data-demo-action'),
      turn: active.closest('[data-demo-turn]') ? active.closest('[data-demo-turn]').getAttribute('data-demo-turn') : null,
      isTurnFirst: !!active.closest('[data-demo-turn]') && active.closest('[data-demo-turn]').firstElementChild === active,
      option: active.closest('[data-demo-option]') ? active.closest('[data-demo-option]').getAttribute('data-demo-option') : null,
      outline: getComputedStyle(active).outlineStyle,
    } : null,
  };
})()`;
const probe = () => js(PROBE);
const click = (sel) => js(`(() => { const el = document.querySelector(${JSON.stringify(sel)}); if (!el) throw new Error('no ' + ${JSON.stringify(sel)}); el.click(); return true; })()`);
const focus = (sel) => js(`(() => { const el = document.querySelector(${JSON.stringify(sel)}); if (!el) throw new Error('no ' + ${JSON.stringify(sel)}); el.focus(); return true; })()`);
const turnSel = (t) => `[data-demo-turn="${t + 1}"]`;
const tabbableRadio = (t) => `${turnSel(t)} [role="radio"][tabindex="0"]`;
const continueSel = (t) => `${turnSel(t)} [data-demo-action="continue"]`;
const overflow = () => js(`(() => {
  const vw = document.documentElement.clientWidth;
  let worst = 0;
  document.querySelectorAll('#demo *').forEach((el) => {
    const r = el.getBoundingClientRect();
    if (r.width && r.right - vw > worst && !el.closest('.demo-sr')) worst = r.right - vw;
  });
  return { page: document.documentElement.scrollWidth - vw, element: Math.ceil(worst) };
})()`);

/** Pick option k on check t with the keyboard: arrive on the group, arrow, Enter/Space. */
async function keyboardPick(t, k, activate = 'Enter') {
  await focus(tabbableRadio(t));
  await press('Home');
  for (let i = 0; i < k; i++) await press('ArrowDown');
  await press(activate);
  await sleep(150);
}
/** From a fresh page, reach check t by answering earlier checks and continuing. */
async function reach(t) {
  for (let i = 0; i < t; i++) {
    await keyboardPick(i, 0);
    await click(continueSel(i));
  }
  await sleep(100);
}

// ---------------------------------------------------------------------------
// The checks
// ---------------------------------------------------------------------------
async function textChecks(label, p) {
  eq(`${label}: ${TURNS} Mercurius replies on the page`, p.replies.length, TURNS);
  p.replies.forEach((text, t) => {
    const want = rendered(source[t].raw);
    const same = text === want;
    let detail = '';
    if (!same) {
      let i = 0;
      while (i < text.length && text[i] === want[i]) i++;
      detail = `first difference at char ${i}: page "${text.slice(i, i + 50)}" vs source "${want.slice(i, i + 50)}"`;
    }
    check(`${label}: reply ${t + 1} text equals the source JSON (markup rendered, nothing edited)`, same, detail);
  });
  eq(`${label}: student bubbles equal the recorded student turns`, p.students, source.slice(1).map((s) => norm(s.user)));
}

async function main() {
  ws = new WebSocket(await pageSocket());
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const p = pending.get(msg.id); pending.delete(msg.id);
      msg.error ? p.reject(new Error(msg.error.message)) : p.resolve(msg.result);
    } else if (msg.method) {
      // data: URIs (the inline icon masks) never touch the network.
      if (msg.method === 'Network.requestWillBeSent' && !msg.params.request.url.startsWith('data:')) requests.push(msg.params.request.url);
      for (let i = listeners.length - 1; i >= 0; i--) {
        if (listeners[i].method === msg.method) { listeners[i].fn(msg.params); listeners.splice(i, 1); }
      }
    }
  };
  await send('Page.enable');
  await send('Runtime.enable');

  // 0. The page is exactly what the generator writes from the capture.
  const gen = spawnSync(process.execPath, [path.join(ROOT, 'scripts/build-demo-replay.mjs'), '--check'], { encoding: 'utf8' });
  check('generator: index.html section reproduces exactly from the capture', gen.status === 0, (gen.stderr || gen.stdout).trim());

  // 1. JS off: the whole replay is plain, complete HTML.
  for (const width of [1280, 360]) {
    await load({ scripts: false, width });
    const p = await probe();
    const label = `no-JS ${width}px`;
    eq(`${label}: all three turns shown`, p.turnsShown, [true, true, true]);
    eq(`${label}: all replies + student turns shown`, [...p.repliesShown, ...p.studentsShown], [true, true, true, true, true]);
    check(`${label}: end panel shown`, p.endShown);
    check(`${label}: JS-only controls stay hidden`, !p.wholeShown && !p.restartShown && !p.howtoShown
      && p.checks.every((c) => !c.contShown));
    eq(`${label}: options per check`, p.checks.map((c) => c.options), optionCounts);
    eq(`${label}: recorded-pick notes`, p.checks.map((c) => c.recorded),
      recorded.map((r) => (r ? `In this session, the student picked ${r}.` : null)));
    eq(`${label}: answered checks show the recorded grading`, p.checks.map((c) => c.classes),
      answers.map((a, t) => [0, 1, 2].map((k) => (recorded[t] === null ? ''
        : L(k) === a ? 'answer' : L(k) === recorded[t] ? 'wrong' : ''))));
    check(`${label}: last check offers "Show the answer"`, p.checks[TURNS - 1].staticAnswer);
    await textChecks(label, p);
    if (width === 360) {
      const o = await overflow();
      check(`${label}: no horizontal overflow`, o.page <= 0 && o.element <= 0, JSON.stringify(o));
    }
    const facts = await js(`(() => {
      const t = document.querySelector('#demo').textContent.replace(/\\s+/g, ' ');
      const a = document.querySelector('#demo .demo-end a');
      return { t, href: a && a.href, badge: a && a.querySelector('img') && a.querySelector('img').getAttribute('src'),
        h2: !!document.querySelector('#demo h2#demo-heading'), h3: document.querySelectorAll('#demo h3').length,
        afterHero: document.querySelector('section.hero').nextElementSibling === document.querySelector('#demo'),
        defer: (document.querySelector('script[src^="/demo.js"]') || {}).defer };
    })()`);
    if (width === 1280) {
      check('honesty: says it is a real lesson, replayed', /real Mercurius lesson, replayed/.test(facts.t));
      check('honesty: names the lesson and its real title', /Unit 1, Lesson 1, “What happens when you type a prompt,”/.test(facts.t));
      check('honesty: gives the recording date', /October 7, 2026/.test(facts.t));
      check('honesty: student taps scripted, replies unedited', /scripted the student’s taps/.test(facts.t) && /replies are unedited/.test(facts.t));
      check('end: App Store link + self-hosted badge', facts.href === 'https://apps.apple.com/app/id6773192313' && facts.badge === '/assets/app-store-badge.svg');
      check('end: says the full lesson continues in the app', /full lesson continues in the app/.test(facts.t));
      check('turns 4+ are left out', !/Here's your exercise|For the exercise, concretely/.test(facts.t));
      check('outline: h2 section heading, h3 lesson + end headings', facts.h2 && facts.h3 === 2);
      check('placement: directly under the hero', facts.afterHero);
      check('demo.js loads with defer', facts.defer === true);
    }
  }

  // 2. JS on: initial state.
  await load();
  await send('Network.enable');
  requests.length = 0;
  let p = await probe();
  eq('JS: only turn 1 shown at first', p.turnsShown, [true, false, false]);
  check('JS: end panel hidden at first', !p.endShown);
  check('JS: no notes or grading before an answer', p.checks.every((c) => !c.noteShown && c.classes.every((x) => !x) && c.tags.every((x) => !x)));
  eq('JS: progress reads turn 1 of 3', p.progress, 'Turn 1 of 3');
  check('JS: controls shown; "Start over" disabled until something changes', p.wholeShown && !p.wholeDisabled && p.restartShown && p.restartDisabled);
  check('JS: how-to line shown', p.howtoShown);
  check('JS: options are radios in a labelled radiogroup', p.checks.every((c, t) => c.groupRole === 'radiogroup' && c.labelled && c.radios === optionCounts[t]));
  check('JS: one tab stop per group (roving tabindex)', p.checks.every((c) => c.tabbable.filter((x) => x === 0).length === 1));
  check('JS: options are at least 44px tall', p.checks[0].heights.every((h) => h >= 44), JSON.stringify(p.checks[0].heights));
  eq('live region is role=status, aria-live=polite', [p.liveRole, p.livePolite], ['status', 'polite']);

  // Keyboard path: Tab into the group, arrows move without grading.
  await focus('[data-demo-action="whole"]');
  await press('Tab');
  p = await probe();
  check('keyboard: Tab from the toolbar lands on check 1, option A', p.active && p.active.role === 'radio' && p.active.option === 'A', JSON.stringify(p.active));
  check('keyboard: focus is visible on the option', p.active && p.active.outline !== 'none', p.active && p.active.outline);
  await press('ArrowDown');
  p = await probe();
  check('keyboard: ArrowDown moves to B', p.active && p.active.option === 'B');
  check('keyboard: moving does not grade', p.checks[0].checked.every((x) => x === 'false') && !p.checks[0].noteShown);
  await press('End'); p = await probe(); check('keyboard: End moves to the last option', p.active && p.active.option === L(optionCounts[0] - 1));
  await press('Home'); p = await probe(); check('keyboard: Home moves to A', p.active && p.active.option === 'A');
  await press('ArrowUp'); p = await probe(); check('keyboard: ArrowUp wraps to the last option', p.active && p.active.option === L(optionCounts[0] - 1));
  await press('ArrowRight'); p = await probe(); check('keyboard: ArrowRight wraps to A', p.active && p.active.option === 'A');
  await press('ArrowDown');
  await press(' ');
  await sleep(150);
  p = await probe();
  check('keyboard: Space picks the focused option', p.checks[0].checked[1] === 'true');
  check('order: turn 2 stays hidden until Continue', !p.turnsShown[1]);
  await press('Tab');
  p = await probe();
  check('keyboard: Tab from the answered group reaches Continue', p.active && p.active.action === 'continue' && p.active.turn === '1', JSON.stringify(p.active));
  await press('Enter');
  await sleep(200);
  p = await probe();
  eq('order: Continue reveals turn 2', p.turnsShown, [true, true, false]);
  check('focus: moves to turn 2’s first element (the student’s pick)', p.active && p.active.student === '2' && p.active.isTurnFirst, JSON.stringify(p.active));
  check('live: announces turn 2', /Turn 2 of 3/.test(p.live), p.live);
  eq('progress reads turn 2 of 3', p.progress, 'Turn 2 of 3');
  check('Start over is enabled after progress', !p.restartDisabled);

  // Turn 2 → 3 → end, by keyboard.
  await keyboardPick(1, 0, 'Enter');
  p = await probe();
  check('live: announces the grade and the recorded pick', p.live === `Not quite. The answer is ${answers[1]}. In this session, the student picked ${recorded[1]}.`, p.live);
  await focus(continueSel(1));
  await press('Enter');
  await sleep(200);
  p = await probe();
  eq('order: Continue reveals turn 3', p.turnsShown, [true, true, true]);
  check('focus: moves to turn 3’s first element', p.active && p.active.student === '3' && p.active.isTurnFirst, JSON.stringify(p.active));
  check('end panel still hidden before the last check', !p.endShown);
  await keyboardPick(2, 1, ' ');
  p = await probe();
  check('last check: graded, no recorded pick (turn 4 is left out)', p.checks[2].feedback !== null && p.checks[2].recorded === null);
  check('last check: Continue offered', p.checks[2].contShown);
  await click(continueSel(2));
  await sleep(200);
  p = await probe();
  check('end: Continue on the last check shows the end panel', p.endShown);
  check('focus: moves to the end panel heading', p.active && p.active.endTitle, JSON.stringify(p.active));
  check('live: announces the end', /End of the replay/.test(p.live), p.live);
  check('end: "Show the whole lesson" disabled, "Start over" enabled', p.wholeDisabled && !p.restartDisabled);
  check('no network requests while using the demo', requests.length === 0, requests.join(', '));
  await send('Network.disable');

  // 3. Grading of every option of every check, picked with the keyboard.
  for (let t = 0; t < TURNS; t++) {
    for (let k = 0; k < optionCounts[t]; k++) {
      await click('[data-demo-action="restart"]');
      await reach(t);
      await keyboardPick(t, k, k % 2 ? ' ' : 'Enter');
      p = await probe();
      const c = p.checks[t];
      const right = L(k) === answers[t];
      const tag = `check ${t + 1}, pick ${L(k)}`;
      const ok = [
        c.checked.every((x, i) => x === (i === k ? 'true' : 'false')),
        c.classes.every((x, i) => x === (L(i) === answers[t] ? 'answer' : i === k ? 'wrong' : '')),
        c.feedback === `${right ? 'Correct.' : 'Not quite.'} The answer is ${answers[t]}.`,
        c.recorded === (recorded[t] ? `In this session, the student picked ${recorded[t]}.` : null),
        c.tags.every((x, i) => x === (L(i) === recorded[t])),
        c.contShown,
        p.turnsShown[t + 1] !== true,
        p.live.startsWith(c.feedback || '???'),
      ];
      check(`grading: ${tag} → ${right ? 'correct' : 'not correct'}, recorded note ${recorded[t] || 'none'}`, ok.every(Boolean),
        `flags ${JSON.stringify(ok)} ${JSON.stringify(c)} live="${p.live}"`);
      // A second pick is ignored once graded.
      await focus(`${turnSel(t)} [data-demo-option="${L((k + 1) % optionCounts[t])}"] [role="radio"]`);
      await press('Enter');
      p = await probe();
      check(`grading: ${tag} is final`, p.checks[t].checked[k] === 'true');
    }
  }

  // 4. "Show the whole lesson" + "Start over".
  await click('[data-demo-action="restart"]');
  await sleep(100);
  await focus('[data-demo-action="whole"]');
  await press('Enter');
  await sleep(200);
  p = await probe();
  eq('whole: all turns shown', p.turnsShown, [true, true, true]);
  check('whole: end panel shown', p.endShown);
  eq('whole: recorded-pick notes shown', p.checks.map((c) => c.recorded),
    recorded.map((r) => (r ? `In this session, the student picked ${r}.` : null)));
  eq('whole: answered checks show the recorded grading', p.checks.map((c) => c.classes),
    answers.map((a, t) => [0, 1, 2].map((k) => (recorded[t] === null ? ''
      : L(k) === a ? 'answer' : L(k) === recorded[t] ? 'wrong' : ''))));
  check('whole: focus moves to the first newly shown turn', p.active && p.active.student === '2', JSON.stringify(p.active));
  check('whole: announced', /whole replay/.test(p.live), p.live);
  check('whole: no Continue buttons', p.checks.every((c) => !c.contShown));
  check('whole: "Show the whole lesson" disabled', p.wholeDisabled);
  await textChecks('JS whole lesson', p);
  await keyboardPick(2, 0);
  p = await probe();
  check('whole: the last check can still be tried', p.checks[2].feedback === `Not quite. The answer is ${answers[2]}.` && !p.checks[2].contShown);
  await focus('[data-demo-action="restart"]');
  await press('Enter');
  await sleep(200);
  p = await probe();
  eq('start over: back to turn 1 only', p.turnsShown, [true, false, false]);
  check('start over: picks, notes and end panel cleared', p.checks.every((c) => !c.noteShown && c.checked.every((x) => x === 'false') && c.classes.every((x) => !x)) && !p.endShown);
  check('start over: focus on turn 1', p.active && p.active.reply === '1' && p.active.isTurnFirst, JSON.stringify(p.active));
  check('start over: announced', /restarted/.test(p.live), p.live);
  check('start over: "Start over" disabled again, "Show the whole lesson" enabled', p.restartDisabled && !p.wholeDisabled);

  // 5. Reduced motion: reveals are instant.
  await load({ reduceMotion: true });
  await keyboardPick(0, 1);
  await click(continueSel(0));
  await sleep(50);
  const anim = await js(`getComputedStyle(document.querySelector('[data-demo-turn="2"]')).animationName`);
  eq('reduced motion: no reveal animation', anim, 'none');

  // 6. Debug hook is read-only and does what it says.
  await load({ query: '?demo-step=answered2' });
  p = await probe();
  check('?demo-step=answered2 opens at turn 2, answered', p.turnsShown.join() === 'true,true,false' && p.checks[1].feedback !== null && p.checks[1].contShown);

  // 7. demo.js adds no layout shift on load: CLS with it equals CLS without it
  //    (fonts and the hero may shift the page on their own; that isn't ours).
  for (const width of [1440, 1024, 768, 390]) {
    const cls = async (block) => {
      await send('Network.enable');
      await send('Network.setBlockedURLs', { urls: block ? ['*/demo.js*'] : [] });
      await load({ width, height: width < 768 ? 844 : 900 });
      await sleep(600);
      const v = await js(`new Promise((resolve) => {
        let sum = 0;
        new PerformanceObserver((list) => {
          for (const e of list.getEntries()) if (!e.hadRecentInput) sum += e.value;
        }).observe({ type: 'layout-shift', buffered: true });
        setTimeout(() => resolve(Math.round(sum * 10000) / 10000), 100);
      })`);
      await send('Network.setBlockedURLs', { urls: [] });
      await send('Network.disable');
      return v;
    };
    const without = await cls(true);
    const withDemo = await cls(false);
    check(`${width}px: demo.js adds no layout shift (CLS ${withDemo} with, ${without} without)`, withDemo <= without + 0.001);
  }

  // 8. Phones: no overflow at 360 and 390, before and after showing everything.
  for (const width of [360, 390]) {
    await load({ width, height: 844 });
    let o = await overflow();
    check(`${width}px: no horizontal overflow (turn 1)`, o.page <= 0 && o.element <= 0, JSON.stringify(o));
    await keyboardPick(0, 2);
    await click('[data-demo-action="whole"]');
    await sleep(200);
    o = await overflow();
    check(`${width}px: no horizontal overflow (whole lesson, graded)`, o.page <= 0 && o.element <= 0, JSON.stringify(o));
    const h = await js(`Math.min(...[...document.querySelectorAll('#demo [role="radio"]')].map((b) => b.getBoundingClientRect().height))`);
    check(`${width}px: options at least 44px tall`, h >= 44, String(h));
  }
}

try {
  await main();
} catch (err) {
  failures++;
  console.log(`FAIL crashed — ${err.stack || err}`);
} finally {
  try { ws && ws.close(); } catch { /* ignore */ }
  try { process.kill(-chrome.pid, 'SIGKILL'); } catch { /* ignore */ }
  rmSync(profile, { recursive: true, force: true });
}
console.log(`\n${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
