'use strict';

/**
 * homeworkGuard — deterministic backstops for Socratic homework coaching
 * (socratic homework review, 2026-10-22). The rules in
 * lib/responseQuality.js (HOMEWORK COACHING) say Merc never gives the final
 * answer to the student's own problem; the red team still found it leaking
 * through worked examples that land on the same answer, candidate values
 * ("Try 6 — does 2(6) + 9 = 21?"), arithmetic ("15 ÷ 3 = 5") and the Quiz-me
 * chip. Like lib/airyReflow (a formatting invariant), the common case gets a
 * transform instead of more prompt text. Pure; unit-tested in
 * tests/homeworkGuard.test.js.
 *
 *   linearEquations(text)      one-variable linear equations ("3x+5=20",
 *                              "5x + 12 = 2x − 3", "3(x − 4) + 5 = 2x + 9")
 *                              with their solution.
 *   studentProblems(messages)  the linear equations the student was given (typed
 *                              as a problem, or restated by Merc from their
 *                              photo) whose answer they haven't stated yet.
 *   findLeak(text, problems)   the first place a reply states one of those
 *                              answers, or null.
 *   redactLeaks(text, problems) the same text with each leaked value as "?".
 *   quizQuestionLeaks(q, problems)  a Quiz-me question on their equation or
 *                              whose correct option is their answer.
 *   looksLikeProblemWork(messages, { hasImage, broad })  the thread holds a
 *                              problem to work (an equation, a reaction, a
 *                              quantity with units, lettered options): the
 *                              chat handler turns adaptive thinking on for
 *                              it. `broad` (claude-sonnet-5-5's thinking
 *                              decision only) also counts calculus,
 *                              statistics, proofs and a bare "i got 12".
 *
 * Only what can be decided exactly is guarded: linear equations in one
 * variable. Everything else (quadratics, word problems, essays) relies on
 * the rules and the eval.
 */

/** Unicode minus/dashes, × · ÷ and markdown bold → plain ASCII math. Length-
 *  preserving (bold "**" becomes two spaces), so an index into the result is
 *  an index into the original text. */
function normalizeMath(text) {
  return String(text ?? '')
    .replace(/\*\*/g, '  ')
    // The em dash is prose ("Yes — 3x = 15"), never a minus sign.
    .replace(/[−–]/g, '-')
    .replace(/[×·⋅]/g, '*')
    .replace(/÷/g, '/');
}

const isLetter = (c) => Boolean(c) && /[a-z]/i.test(c);
/** A single standalone letter (the "x" in "3x+5", not the "s" in "is"). */
const isVarAt = (s, i) => isLetter(s[i]) && !isLetter(s[i - 1]) && !isLetter(s[i + 1]);
// '^', '²' and '³' are scanned so a quadratic is captured whole and rejected
// by the parser, never read as its linear tail.
const SCAN_CHAR = /[0-9.+\-*/()^²³ \t]/;

// ── A tiny parser for linear expressions in one variable ───────────────────
// Values are { k, c } meaning k·var + c. Implicit multiplication ("3x",
// "2(x − 4)", "(x+1)(2)") needs the two tokens to touch: "20 x" is two
// separate things, not 20x.

function tokenize(src) {
  const tokens = [];
  let i = 0;
  let spaced = false;
  while (i < src.length) {
    const c = src[i];
    if (c === ' ' || c === '\t') { spaced = true; i++; continue; }
    const num = /^\d+(?:\.\d+)?/.exec(src.slice(i));
    if (num) {
      tokens.push({ t: 'num', v: Number(num[0]), spaced });
      i += num[0].length;
    } else if (isLetter(c)) {
      tokens.push({ t: 'var', v: c.toLowerCase(), spaced });
      i++;
    } else if ('+-*/()'.includes(c)) {
      tokens.push({ t: c, spaced });
      i++;
    } else {
      return null; // '^', '²', '.' on its own …: not a linear expression
    }
    spaced = false;
  }
  return tokens;
}

function parseLinear(src) {
  const tokens = tokenize(src);
  if (!tokens || tokens.length === 0) return null;
  let pos = 0;
  let variable = null;
  const peek = () => tokens[pos];
  const fail = () => { throw new Error('parse'); };
  const mul = (a, b) => {
    if (a.k !== 0 && b.k !== 0) fail();
    return { k: a.k * b.c + b.k * a.c, c: a.c * b.c };
  };
  function factor() {
    const tk = peek();
    if (!tk) fail();
    if (tk.t === '-' || tk.t === '+') {
      pos++;
      const f = factor();
      return tk.t === '-' ? { k: -f.k, c: -f.c } : f;
    }
    if (tk.t === 'num') { pos++; return { k: 0, c: tk.v }; }
    if (tk.t === 'var') {
      if (variable && variable !== tk.v) fail();
      variable = tk.v;
      pos++;
      return { k: 1, c: 0 };
    }
    if (tk.t === '(') {
      pos++;
      const e = expr();
      if (!peek() || peek().t !== ')') fail();
      pos++;
      return e;
    }
    return fail();
  }
  function term() {
    let v = factor();
    for (;;) {
      const tk = peek();
      if (!tk) break;
      if (tk.t === '*') { pos++; v = mul(v, factor()); continue; }
      if (tk.t === '/') {
        pos++;
        const d = factor();
        if (d.k !== 0 || d.c === 0) fail();
        v = { k: v.k / d.c, c: v.c / d.c };
        continue;
      }
      // Implicit multiplication: "3x", "2(", ")(", ")x" — touching only.
      if (!tk.spaced && (tk.t === 'var' || tk.t === '(' || (tk.t === 'num' && tokens[pos - 1]?.t === ')'))) {
        v = mul(v, factor());
        continue;
      }
      break;
    }
    return v;
  }
  function expr() {
    let v = term();
    for (;;) {
      const tk = peek();
      if (!tk || (tk.t !== '+' && tk.t !== '-')) break;
      pos++;
      const r = term();
      v = tk.t === '+' ? { k: v.k + r.k, c: v.c + r.c } : { k: v.k - r.k, c: v.c - r.c };
    }
    return v;
  }
  try {
    const v = expr();
    if (pos !== tokens.length) return null;
    return { ...v, variable, tokens };
  } catch {
    return null;
  }
}

const round = (n) => Math.round(n * 1e9) / 1e9;
/** "5", "-3", "2.5"; null for an answer that isn't a short decimal. */
function formatAnswer(n) {
  const r = round(n);
  if (!Number.isFinite(r) || !Number.isInteger(round(r * 100))) return null;
  return String(r);
}

/**
 * Every one-variable linear equation in `text`, in order:
 * { text, variable, answer (number), value (string), A, D, numbers, assignment }.
 * A·var = D is the equation once both sides are collected (so the last step
 * is D ÷ A); `numbers` are the absolute values of every number in it and of
 * A and D; `assignment` marks a bare "x = 5" (an answer, not a problem); L
 * and R are each side as k·var + c. With `all`, an equation whose answer
 * isn't a short decimal ("3x = 25") is kept, with value null.
 */
function linearEquations(text, { all = false } = {}) {
  const s = normalizeMath(text);
  const out = [];
  for (let p = s.indexOf('='); p !== -1; p = s.indexOf('=', p + 1)) {
    let l = p;
    while (l > 0 && s[l - 1] !== '=' && (SCAN_CHAR.test(s[l - 1]) || isVarAt(s, l - 1))) l--;
    let r = p + 1;
    while (r < s.length && s[r] !== '=' && (SCAN_CHAR.test(s[r]) || isVarAt(s, r))) r++;
    const clean = (x) => x.replace(/^[\s.]+|[\s.]+$/g, '');
    const count = (x, c) => x.split(c).length - 1;
    // A bracket the scan caught from the words around it ("= 20 (pls)",
    // "(so 3x = 15") is cut off with what it opened.
    // A sign standing apart at the very start is a prose dash ("Yes – 3x = 15").
    let lhsSrc = clean(s.slice(l, p)).replace(/^[-+]\s+(?=\S)/, '');
    while (count(lhsSrc, ')') > count(lhsSrc, '(')) lhsSrc = clean(lhsSrc.slice(lhsSrc.indexOf(')') + 1));
    while (count(lhsSrc, '(') > count(lhsSrc, ')')) lhsSrc = clean(lhsSrc.slice(lhsSrc.indexOf('(') + 1));
    let rhsSrc = clean(s.slice(p + 1, r));
    while (count(rhsSrc, '(') > count(rhsSrc, ')')) rhsSrc = clean(rhsSrc.slice(0, rhsSrc.lastIndexOf('(')));
    while (count(rhsSrc, ')') > count(rhsSrc, '(')) rhsSrc = clean(rhsSrc.slice(0, rhsSrc.lastIndexOf(')')));
    // Words the scan took for variables ("= 20 (a b)") make a side fail to
    // parse: fall back to the longest piece next to the "=" that does.
    const firstParsed = (cands) => cands.map((c) => clean(c)).filter(Boolean).map((c) => [c, parseLinear(c)]).find(([, v]) => v) || [null, null];
    // Only words are cut off, never math: a dropped piece holding an
    // operator ("x^2 −", "x +", "m/s²") means the side really doesn't parse.
    const cut = (src, fromLeft) => {
      const out = [src];
      const at = [...src.matchAll(/\s+/g)].map((m) => m.index);
      const words = (piece) => !/[-+*/^²³]/.test(piece);
      // …and what's kept can't start (or end) on an operator: "x + y" is not "+ y".
      if (fromLeft) for (const i of at) { if (words(src.slice(0, i)) && !/^\s*[-+*/]/.test(src.slice(i))) out.push(src.slice(i)); }
      else for (const i of at.reverse()) { if (words(src.slice(i)) && !/[-+*/]\s*$/.test(src.slice(0, i))) out.push(src.slice(0, i)); }
      return out;
    };
    let L;
    let R;
    [lhsSrc, L] = firstParsed(cut(lhsSrc, true));
    [rhsSrc, R] = firstParsed(cut(rhsSrc, false));
    if (!L || !R) continue;
    if (L.variable && R.variable && L.variable !== R.variable) continue;
    const variable = L.variable || R.variable;
    if (!variable) continue;
    const A = round(L.k - R.k);
    const D = round(R.c - L.c);
    if (A === 0) continue;
    // Divide before rounding: x/3 has k = 0.333…, and a rounded 0.333333333
    // gave 15.000000015, so "x/3 + 2 = 7" was never guarded (red-team run on
    // b0940d8: an example landed on their x = 15).
    const answer = round((R.c - L.c) / (L.k - R.k));
    const value = formatAnswer(answer);
    if (value === null && !all) continue;
    const literals = [...new Set([...L.tokens, ...R.tokens].filter((t) => t.t === 'num').map((t) => round(Math.abs(t.v))))];
    const isBare = (side, other) => side.k === 1 && side.c === 0 && side.tokens.length === 1 && other.k === 0;
    out.push({
      text: `${lhsSrc} = ${rhsSrc}`,
      compact: `${lhsSrc}=${rhsSrc}`.replace(/\s+/g, '').toLowerCase(),
      variable,
      answer,
      value,
      A,
      D,
      numbers: [...new Set([...literals, Math.abs(A), Math.abs(D)].map(round))],
      literals,
      assignment: isBare(L, R) || isBare(R, L),
      lhs: lhsSrc,
      rhs: rhsSrc,
      L: { k: L.k, c: L.c },
      R: { k: R.k, c: R.c },
    });
  }
  return out;
}

const escapeRe = (x) => String(x).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** The answer as a pattern: "5", "-\s*3", "2\.5"; an integer may be written "7.0". */
const valueRe = (value) => {
  const neg = value.startsWith('-');
  const abs = escapeRe(neg ? value.slice(1) : value);
  const tail = /\./.test(value) ? '' : String.raw`(?:\.0+)?`;
  return `${neg ? String.raw`-\s*` : ''}${abs}${tail}`;
};
const END = String.raw`(?![\d.]*\d)`;

/** The answer stated by the student in their own words: "x = 5", "is it 5",
 *  "i got 5", "its 5", or a turn that is only the number. */
function statesAnswer(text, eq) {
  const t = normalizeMath(text).toLowerCase();
  const v = valueRe(eq.value);
  const x = escapeRe(eq.variable);
  const res = [
    String.raw`(?<![\w.])${x}\s*(?:=|is|equals|would be|should be)\s*${v}${END}`,
    String.raw`\b(?:is it|it['’]?s|its|it is|i got|i get|got|answer is|answer['’]?s|i think it['’]?s|i think|maybe|so)\s*${v}${END}`,
    String.raw`^\W*${v}\W*$`,
  ];
  return res.some((re) => new RegExp(re, 'i').test(t));
}

// A turn asks for help with the equation it holds: the thread's first turn
// always does; a later one only with one of these, otherwise the equation is
// the student's own step ("3x + 12 = -3"), not a new problem.
const REQUEST_RE = /\b(?:solve|what(?:['’]s| is| does)|whats|find|help|how (?:do|would|should|can) (?:i|you|we)|now|next|another|what about|how about|calculate|simplify|try this)\b/i;

/**
 * The linear equations the student typed AS A PROBLEM in this thread whose
 * answer no user turn has stated. `messages` is the client's thread
 * ({ role, content } with string content); assistant turns are never read
 * (they hold Merc's own worked examples).
 */
function studentProblems(messages) {
  const userTexts = (Array.isArray(messages) ? messages : [])
    .filter((m) => m && m.role === 'user' && typeof m.content === 'string')
    .map((m) => m.content);
  const problems = [];
  userTexts.forEach((text, i) => {
    const eq = linearEquations(text).find((e) => !e.assignment);
    if (eq && (i === 0 || REQUEST_RE.test(text))) problems.push(eq);
  });
  // After a photo the problem is only in Merc's restatement (givenProblem).
  if (problems.length === 0) {
    const restated = givenProblem(userTexts, messages);
    if (restated) problems.push(restated);
  }
  const unique = [];
  for (const p of problems) {
    if (!unique.some((u) => u.compact === p.compact)) unique.push(p);
  }
  // The line their own step in words gives ("add 9 to both sides" on
  // 2x + 9 = 21 gives 2x + 18 = 30) is the check of that step, never an
  // example on their answer (red-team run on 594cd6a, alg-wrong-op).
  const last = userTexts[userTexts.length - 1] || '';
  const verbal = linearEquations(last, { all: true }).length ? null : VERBAL_RE.exec(lower(last));
  // Every line the student typed is theirs to see again: "Yes, 2x − 15 = 7
  // is right" quotes their step, it is not an example on their answer (tuned
  // 5.5 run 2026-10-24, alg-1: the whole one-line reply was dropped as one).
  const typed = userTexts.flatMap((t) => linearEquations(t, { all: true }))
    .filter((e) => !e.assignment && e.L && e.R)
    .map((e) => ({ L: e.L, R: e.R }));
  return unique.filter((p) => !userTexts.some((t) => statesAnswer(t, p))).map((p) => {
    const withTyped = typed.length ? { ...p, typed } : p;
    if (!verbal || !p.L || p.R.k !== 0) return withTyped;
    const n = Number(verbal[2]);
    const v = verbal[1].toLowerCase();
    const shift = /^(?:subtract|minus|take)/.test(v) ? -n : /^(?:add|plus)/.test(v) ? n : null;
    if (shift === null) return withTyped;
    return { ...withTyped, allowed: [{ k: p.L.k, c: round(p.L.c + shift), r: round(p.R.c + shift) }] };
  });
}

/** Patterns that state `eq`'s answer, as [name, RegExp] (flags: i, g). */
function leakPatterns(eq) {
  const v = valueRe(eq.value);
  const x = escapeRe(eq.variable);
  const ops = String.raw`(\+|-|\*|/|x|times|plus|minus|divided by|over)`;
  const num = String.raw`(\d+(?:\.\d+)?)`;
  const is = String.raw`\s*(?:=|is|equals|gives(?: you)?|makes|leaves(?: you with)?)\s*`;
  const list = [
    // "x = 5", "x is 5", "y = 5" (any one-letter variable), "x = 7.0"
    ['assignment', String.raw`(?<![\w.])(?<![-+*/]\s*)(?:${x}\s*(?:=|is|equals|would be|should be|must be)|[a-z]\s*=)\s*${v}${END}(?![a-z(])`],
    // "x = 15/3 = 5", but not a value that starts a longer expression: "if
    // x = 11, then 5 − 2(11 + 3) = 5 − 28" checks their wrong x = 11 on
    // 5 − 2(x + 3) = −11, it doesn't say x = 5 (review 2026-10-24: a needless
    // retry, then the check redacted to "= ? − 2(14)", both models). "= 16
    // (done!)" and "= 11 - nice" still end on the answer.
    ['chain', String.raw`(?<![\w.])${x}\s*=[^=\n]{1,24}=\s*${v}${END}(?!\s*[-+*/]\s*[\d(])`],
    ['the answer', String.raw`\b(?:the |your )?(?:final )?answer(?: is|['’]s|:|=| would be| should be)\s*(?:${x}\s*=\s*)?${v}${END}`],
    // a substitution of the answer: "3(5) + 5", "2(6) + 9 = 21"
    ['substitution', String.raw`\(\s*${v}\s*\)`],
    ['you get', String.raw`\byou(?:['’]ll| will| would)? (?:get|end up with)\s*${v}${END}(?!\s*[a-z(*/+-])`],
    ['candidate', String.raw`\b(?:try|plug in|test|check|guess)\s+(?:${x}\s*=\s*)?${v}${END}`],
    // Code that solves it: "It prints `6.0`" (review 2026-10-22).
    ['printed', String.raw`\b(?:prints?|printed|outputs?|returns?)\b[^.?!\n]{0,24}?(?<![\d.])${v}${END}(?![a-z])`],
  ];
  // Arithmetic on their own numbers that lands on the answer ("15 ÷ 3 = 5",
  // "15 - 8 = 7") or shows it as a factor ("5 × 3 = 15", "What's 4 times 7?").
  list.push(['arithmetic', String.raw`(?<![\d.])${num}\s*${ops}\s*\(?\s*${num}\s*\)?${is}${v}${END}`]);
  // …or checks it against their numbers before they've said it ("7 + 8 = 15").
  list.push(['check', String.raw`(?<![\d.])(?:${v}\s*${ops}\s*${num}|${num}\s*${ops}\s*\(?\s*${v}\s*\)?)${is}${num}${END}`]);
  list.push(['factor', String.raw`(?<![\d.])(?:${num}\s*(?:\*|x|times)\s*\(?\s*${v}\s*\)?|${v}\s*(?:\*|x|times)\s*${num})${END}`]);
  return list.map(([name, src]) => [name, new RegExp(src, 'gi')]);
}

const OP = {
  '+': (a, b) => a + b, plus: (a, b) => a + b,
  '-': (a, b) => a - b, minus: (a, b) => a - b,
  '*': (a, b) => a * b, x: (a, b) => a * b, times: (a, b) => a * b,
  '/': (a, b) => a / b, 'divided by': (a, b) => a / b, over: (a, b) => a / b,
};

/** Every leak of `eq` in normalized text, as { name, index, match }. */
function leaksOf(s, eq) {
  const theirs = new Set(eq.numbers);
  const hits = [];
  for (const [name, re] of leakPatterns(eq)) {
    re.lastIndex = 0;
    for (const m of s.matchAll(re)) {
      if (name === 'arithmetic') {
        const [a, op, b] = [Number(m[1]), OP[m[2].toLowerCase()], Number(m[3])];
        // Only their own numbers, and only arithmetic that is actually true.
        if (!op || !theirs.has(round(a)) || !theirs.has(round(b)) || round(op(a, b)) !== eq.answer) continue;
      }
      if (name === 'check') {
        // Groups: v-first (op m[1], n m[2]) or n-first (n m[3], op m[4]); result m[5].
        const vFirst = m[1] !== undefined;
        const n = Number(vFirst ? m[2] : m[3]);
        const op = OP[String(vFirst ? m[1] : m[4]).toLowerCase()];
        const result = Number(m[5]);
        const value = vFirst ? op && op(eq.answer, n) : op && op(n, eq.answer);
        if (!op || !theirs.has(round(n)) || !theirs.has(round(result)) || round(value) !== round(result)) continue;
        // When the answer is also one of their own numbers (5 in 3x + 5 = 20),
        // "20 − 5 = 15" is the first step, not a check of the answer.
        if (eq.literals.includes(round(Math.abs(eq.answer)))) continue;
      }
      if (name === 'factor') {
        const n = Number(m[1] ?? m[2]);
        // "1 × 7" says nothing; the multiplier must be theirs.
        if (n === 1 || !theirs.has(round(n)) || Math.abs(eq.A) === 1) continue;
      }
      hits.push({ name, index: m.index, match: m[0] });
    }
  }
  // A worked example that lands on their answer: an equation in the reply
  // with their solution that is not one of their own lines (2x + 8 = 18 or
  // 3x + 7 = 22 for 3x + 5 = 20; their own lines are 3x + 5 = 20 and 3x = 15).
  const same = (e, L, R) => round(e.L.k - e.R.k) === round(L.k - R.k) && round(e.R.c - e.L.c) === round(R.c - L.c)
    && round(e.L.c) === round(L.c) && round(e.R.k) === round(R.k);
  const own = (e) => (eq.L && same(e, eq.L, eq.R)) || same(e, { k: eq.A, c: 0 }, { k: 0, c: eq.D })
    || (eq.typed || []).some((t) => same(e, t.L, t.R));
  const allowed = (e) => (eq.allowed || []).some((a) => round(e.L.k) === round(a.k) && round(e.L.c) === a.c && e.R.k === 0 && round(e.R.c) === a.r);
  // Their own problem one move on (4x − 4 = 20 or 7x = 3x + 24 for
  // 7x − 4 = 3x + 20: the x-terms or the numbers gathered on one side, the
  // rest of their line kept) is their next step written for them, not an
  // example on other numbers. Named apart so the retry note says so: told it
  // wrote "a worked example", 5.5 wrote the same line again (tuned run
  // 2026-10-24, take-home-test).
  const ownStep = (e) => Boolean(eq.L) && (
    (round(e.L.c) === round(eq.L.c) && round(e.R.c) === round(eq.R.c) && (e.L.k === 0 || e.R.k === 0))
    || (round(e.L.k) === round(eq.L.k) && round(e.R.k) === round(eq.R.k) && (e.L.c === 0 || e.R.c === 0)));
  for (const e of linearEquations(s)) {
    if (e.assignment || e.answer !== eq.answer || own(e) || allowed(e)) continue;
    hits.push({ name: ownStep(e) ? 'own step' : 'example', index: s.indexOf(e.lhs), match: e.text });
  }
  return hits.sort((a, b) => a.index - b.index);
}

// ── Quadratics with whole-number roots ──────────────────────────────────────
// Review 2026-10-22 (and the re-run): rung 2 factored the student's own
// x² − 5x + 6 = 0, a later reply named the pair "−2 and −3", and an example
// shared a root (x² − 7x + 12 = 0, roots 3 and 4). Monic or not, a quadratic
// with whole-number roots is guarded like a linear equation.
function polySide(src) {
  const t = normalizeMath(src).replace(/²/g, '^2').replace(/\s+/g, '');
  if (!t || /[^0-9a-z.+\-^]/i.test(t)) return null;
  const terms = t.replace(/-/g, '+-').split('+').filter(Boolean);
  const out = { a: 0, b: 0, c: 0, v: null };
  for (const term of terms) {
    const m = /^(-?)(\d*(?:\.\d+)?)([a-z])?(?:\^(\d))?$/i.exec(term);
    if (!m || (!m[2] && !m[3])) return null;
    const coef = (m[1] ? -1 : 1) * (m[2] ? Number(m[2]) : 1);
    if (m[3]) {
      if (out.v && out.v !== m[3].toLowerCase()) return null;
      out.v = m[3].toLowerCase();
      const pow = m[4] ? Number(m[4]) : 1;
      if (pow === 2) out.a += coef; else if (pow === 1) out.b += coef; else return null;
    } else if (m[4]) return null;
    else out.c += coef;
  }
  return out;
}
/** Quadratics in `text` with two whole-number roots: { text, variable, roots }. */
function quadraticEquations(text) {
  const s = normalizeMath(text).replace(/²/g, '^2');
  const out = [];
  const re = /([-+]?\s*\d*\s*[a-z]\s*\^\s*2(?:\s*[-+]\s*\d*\s*[a-z]?(?![a-z^]))*(?:\s*[-+]\s*\d+)?)\s*=\s*([-+]?\s*\d+(?:\s*[-+]\s*\d*\s*[a-z]?)*)/gi;
  for (const m of s.matchAll(re)) {
    const L = polySide(m[1]);
    const R = polySide(m[2]);
    if (!L || !R || (L.v && R.v && L.v !== R.v)) continue;
    const [a, b, c] = [L.a - R.a, L.b - R.b, L.c - R.c];
    const disc = b * b - 4 * a * c;
    if (a === 0 || disc < 0) continue;
    const sq = Math.sqrt(disc);
    if (!Number.isInteger(sq)) continue;
    const roots = [(-b + sq) / (2 * a), (-b - sq) / (2 * a)].map(round);
    if (!roots.every(Number.isInteger)) continue;
    out.push({ text: m[0].trim(), variable: L.v || R.v || 'x', roots: [...new Set(roots)] });
  }
  return out;
}
function quadraticProblems(messages) {
  const turns = userTurns(messages).map((m) => m.content);
  const problems = [];
  turns.forEach((t, i) => {
    const q = quadraticEquations(t)[0];
    if (q && (i === 0 || REQUEST_RE.test(t))) problems.push(q);
  });
  const stated = (q) => turns.some((t) => q.roots.some((r) => statesAnswer(t, { value: String(r), variable: q.variable })));
  return problems.filter((q) => !stated(q));
}
function findQuadraticLeak(text, problems) {
  const s = normalizeMath(text).replace(/²/g, '^2');
  for (const q of problems || []) {
    const x = escapeRe(q.variable);
    for (const r of q.roots) {
      const v = valueRe(String(r));
      const m = new RegExp(String.raw`(?<![\w.])${x}\s*(?:=|is)\s*${v}${END}(?![a-z(])`, 'i').exec(s);
      if (m) return { name: 'quadratic root', match: m[0], value: String(r) };
    }
    // Their factors: "(x − 2)(x − 3)", both of them.
    const factor = (r) => new RegExp(String.raw`\(\s*${x}\s*${r > 0 ? '-' : '\+'}\s*${Math.abs(r)}\s*\)`, 'i');
    if (q.roots.every((r) => r !== 0 && factor(r).test(s))) return { name: 'quadratic factors', match: q.roots.map((r) => `(${q.variable} ${r > 0 ? '-' : '+'} ${Math.abs(r)})`).join(''), value: String(q.roots[0]) };
    // The pair they are looking for, named together: "−2 and −3".
    if (q.roots.length === 2) {
      const [p1, p2] = q.roots.map((r) => valueRe(String(-r)));
      const pair = new RegExp(String.raw`(?<![\d.])(?:${p1}${END}\s*(?:and|&|,)\s*${p2}|${p2}${END}\s*(?:and|&|,)\s*${p1})${END}`, 'i').exec(s);
      if (pair) return { name: 'quadratic pair', match: pair[0], value: String(q.roots[0]) };
    }
    // An example that shares a root.
    for (const e of quadraticEquations(s)) {
      if (e.text.replace(/\s+/g, '') === q.text.replace(/\s+/g, '')) continue;
      const shared = e.roots.find((r) => q.roots.includes(r));
      if (shared !== undefined) return { name: 'quadratic example', match: e.text, value: String(shared) };
    }
  }
  return null;
}

// ── Two equations in two unknowns ──────────────────────────────────────────
// Red-team re-run (2026-10-22): "Adding your two equations gives 2x = 14, so
// x = 7", and an example whose y was the student's own y = 3.
function side2(src) {
  const t = normalizeMath(src).replace(/\s+/g, '');
  if (!t || /[^0-9a-z.+\-]/i.test(t)) return null;
  const out = { k: {}, c: 0 };
  for (const term of t.replace(/-/g, '+-').split('+').filter(Boolean)) {
    const m = /^(-?)(\d*(?:\.\d+)?)([a-z])?$/i.exec(term);
    if (!m || (!m[2] && !m[3])) return null;
    const coef = (m[1] ? -1 : 1) * (m[2] ? Number(m[2]) : 1);
    if (m[3]) out.k[m[3].toLowerCase()] = (out.k[m[3].toLowerCase()] || 0) + coef;
    else out.c += coef;
  }
  return out;
}
/** A 2×2 linear system in `text` ("x + y = 10 and x - y = 4"):
 *  { vars: ['x','y'], values: { x: 7, y: 3 } }, or null. */
function linearSystem(text) {
  const s = normalizeMath(text);
  const eqs = [...s.matchAll(/([-+]?\s*\d*\s*[a-z](?:\s*[-+]\s*\d*\s*[a-z]|\s*[-+]\s*\d+)*)\s*=\s*([-+]?\s*\d+(?:\.\d+)?)(?![\d.]*\d)/gi)]
    .map((m) => [side2(m[1]), side2(m[2])])
    .filter(([L, R]) => L && R && Object.keys(R.k).length === 0)
    .map(([L, R]) => ({ k: L.k, c: R.c - L.c }))
    .filter((e) => Object.keys(e.k).length === 2);
  if (eqs.length < 2) return null;
  const [e1, e2] = eqs;
  const vars = Object.keys(e1.k);
  if (vars.length !== 2 || !vars.every((v) => v in e2.k)) return null;
  const [u, w] = vars;
  const det = e1.k[u] * e2.k[w] - e1.k[w] * e2.k[u];
  if (det === 0) return null;
  const values = { [u]: round((e1.c * e2.k[w] - e1.k[w] * e2.c) / det), [w]: round((e1.k[u] * e2.c - e1.c * e2.k[u]) / det) };
  if (!Object.values(values).every((v) => formatAnswer(v) !== null)) return null;
  return { vars, values };
}
function systemProblems(messages) {
  const turns = userTurns(messages).map((m) => m.content);
  const sys = turns.map((t, i) => (i === 0 || REQUEST_RE.test(t) ? linearSystem(t) : null)).filter(Boolean).pop();
  if (!sys) return [];
  const stated = turns.some((t) => sys.vars.some((v) => statesAnswer(t, { variable: v, value: formatAnswer(sys.values[v]) })));
  return stated ? [] : [sys];
}
function findSystemLeak(text, systems) {
  const s = normalizeMath(text);
  for (const sys of systems || []) {
    for (const v of sys.vars) {
      // Not the tail of an expression ("x − y = 3" is an equation, not y = 3).
      const re = new RegExp(String.raw`(?<![\w.])(?<![-+*/]\s*)${escapeRe(v)}\s*(?:=|is)\s*\**\s*${valueRe(formatAnswer(sys.values[v]))}${END}(?![a-z(])`, 'i');
      const m = re.exec(s);
      if (m) return { name: 'system', match: m[0], value: formatAnswer(sys.values[v]) };
    }
  }
  return null;
}

/** The first place `text` states one of `problems`' answers, or null:
 *  { name, match, problem }. */
function findLeak(text, problems) {
  const s = normalizeMath(text);
  for (const problem of problems || []) {
    const [hit] = leaksOf(s, problem);
    if (hit) return { name: hit.name, match: hit.match.trim(), problem };
  }
  return null;
}

/** `text` with every leaked value replaced by "?" (the last resort when a
 *  regenerated reply still leaks). Everything else, bold and "−" included,
 *  is left exactly as written. */
function redactLeaks(text, problems) {
  let out = String(text ?? '');
  for (const problem of problems || []) {
    const v = new RegExp(`${valueRe(problem.value)}${END}`, 'g');
    // From the end, so earlier indexes stay valid (normalizeMath keeps them).
    for (const hit of leaksOf(normalizeMath(out), problem).reverse()) {
      const at = [...hit.match.matchAll(v)].pop();
      if (!at) continue;
      const start = hit.index + at.index;
      out = out.slice(0, start) + '?' + out.slice(start + at[0].length);
    }
  }
  return out;
}

/**
 * A Quiz-me question that is built on one of the student's own equations, or
 * whose correct option (or explanation) gives one of their answers.
 * `question` is { q, options, answer, explanation }.
 */
function quizQuestionLeaks(question, problems) {
  if (!question || typeof question !== 'object' || !Array.isArray(problems) || problems.length === 0) return false;
  const all = normalizeMath([question.q, ...(Array.isArray(question.options) ? question.options : []), question.explanation].join(' '))
    .replace(/\s+/g, '')
    .toLowerCase();
  if (problems.some((p) => all.includes(p.compact))) return true;
  const letter = String(question.answer || '').trim().toUpperCase();
  const correct = (Array.isArray(question.options) ? question.options : [])
    .find((o) => new RegExp(`^\\s*\\(?${escapeRe(letter)}[).:]`, 'i').test(String(o)));
  const correctValue = correct ? normalizeMath(String(correct).replace(/^\s*\(?[A-D][).:]\s*/i, '')).trim() : '';
  return problems.some((p) => {
    if (new RegExp(String.raw`^(?:[a-z]\s*=\s*)?${valueRe(p.value)}${END}\W*$`, 'i').test(correctValue)) return true;
    return Boolean(findLeak(`${question.q || ''}\n${correct || ''}\n${question.explanation || ''}`, [p]));
  });
}

// ── Which turns get adaptive thinking ──────────────────────────────────────
const EQUATION_RE = /(?:\d|(?<![a-z])[a-z](?![a-z])|\))\s*=\s*(?:-\s*)?(?:\d|(?<![a-z])[a-z](?![a-z])|\()/i;
const REACTION_RE = /[A-Z][a-z]?\d*\s*(?:\+\s*\d*\s*[A-Z][a-z]?\d*[A-Za-z\d]*\s*)*(?:->|→|⟶|=>)/;
const QUANTITY_RE = /\b\d+(?:\.\d+)?\s*(?:m\/s²?|m\/s\^?2|mph|km\/h|km|cm²?|mm|m|kg|g|mg|mol|moles|grams?|seconds?|sec|s|minutes?|hours?|°|degrees?|N|J|L|mL|liters?|meters?|miles?|feet|ft|in|inches)(?![A-Za-z])/;
const OPTIONS_RE = /(?:^|\s)\(?A\)\s*\S[\s\S]*?(?:^|\s)\(?B\)\s*\S/;
const PROBLEM_WORD_RE = /\b(?:solve|balance|calculate|compute|simplify|factor|evaluate|how many|how much|how fast|how far|how long|area|perimeter|volume|hypotenuse|angles?|slope|probability)\b/i;
// `broad` only (the chat handler passes it for claude-sonnet-5-5's thinking
// decision, never for the answer guard or the notes): calculus, statistics
// and proofs with some math in the message, and a bare "i got 12" or "i
// said 0.16". None of
// those matched above, so on Sonnet 5.5 they ran between_tools (no
// reasoning) at low effort: the A/B of 2026-10-24's wrong "12 would be right
// if …" on a definite integral, the endorsed n − 1 misconception and the
// integration-by-parts give-in were all such turns. Sonnet 4.6 never passes
// it, so its requests are unchanged.
const BROAD_WORD_RE = /\b(?:integra(?:l|ls|te|ting|tion)|antiderivatives?|derivatives?|differentiate|lim|limit as|prove|proofs?|induction|standard deviation|variance)\b|\bd\/dx\b/i;
const MATH_MARK_RE = /\d|[\^=+*/]|\bd[a-z]\b/;
const GOT_ANSWER_RE = /\bi (?:got|get|said|put|wrote)\s*-?\.?\d/i;

/** The thread holds a problem to work, so the turn gets adaptive thinking:
 *  judging a student's step needs the real answer, worked out first. */
function looksLikeProblemWork(messages, { hasImage = false, broad = false } = {}) {
  if (hasImage) return true;
  return (Array.isArray(messages) ? messages : []).some((m) => {
    if (!m || typeof m.content !== 'string') return false;
    const t = m.content.replace(/[−–]/g, '-');
    if (EQUATION_RE.test(t) && /\d/.test(t)) return true;
    if (REACTION_RE.test(t)) return true;
    if (m.role !== 'user') return false;
    if (QUANTITY_RE.test(t) || OPTIONS_RE.test(t) || (PROBLEM_WORD_RE.test(t) && /\d/.test(t))) return true;
    return broad && ((BROAD_WORD_RE.test(t) && MATH_MARK_RE.test(t)) || GOT_ANSWER_RE.test(t));
  });
}

// ── Moment notes: what the server can work out for THIS reply ──────────────
// The prompt rules plateaued on three things a model does in its head while
// it streams: judging a student's step, counting their asks, and not working
// a formula out in a check (review 2026-10-22). Each is decided here from the
// thread, every turn (no stored state), and handed to the model as a short
// note in the dynamic block, never the cached prefix.

const lower = (t) => String(t ?? '').toLowerCase().replace(/[’‘`]/g, "'");
/** "idk", "just tell me", "is it more than 6?", "????", "can u make it better"… */
const ASK_RE = /\b(?:idk|dunno|no idea|i (?:don'?t|dont|do not) (?:know|get it|get this|understand)|still (?:don'?t|dont|do not) get|i'?m (?:stuck|lost|confused)|just (?:tell|say|give|do|show|write)|tell me (?:the )?(?:answer|number|letter)|give me the (?:answer|number|letter)|can (?:u|you) (?:just )?(?:do|solve|tell|write|show)|what(?:'s| is) the answer|just the (?:answer|number|letter)|what would (?:x|it|the answer) be|hypothetically|what (?:would|does|will) it print|(?:is|would) (?:it|x|the answer) (?:be )?(?:more|less|bigger|smaller|greater|higher|lower) than|show me (?:an? )?(?:example|worked example)|make it better|sounds? better|is (?:that|this|it) good|c'?mon|cmon|not cheating|just (?:\d+|one|a|the) (?:sentence|option|line|example|thesis|answer|number|letter)s?|literally (?:one|1|just))\b|^\W*\?+\W*$|^\W*(?:huh|what|idk)\W*$/;
const WRITING_RE = /\b(?:essays?|thesis|theses|paragraphs?|sentences?|intro(?:duction)?|conclusion|hook|draft|rewrite)\b/;
const EXAMPLE_ASK_RE = /\b(?:example|sample|what a good one looks like|show me one)\b/;
const userTurns = (messages) => (Array.isArray(messages) ? messages : [])
  .filter((m) => m && m.role === 'user' && typeof m.content === 'string');

/** The equation the student was GIVEN: in the thread's first user turn, or in
 *  a turn that asks for help with it. A line of their own working is never
 *  the problem (a wrong translation would make a wrong answer look right). */
function givenProblem(turns, messages = []) {
  let problem = null;
  turns.forEach((t, i) => {
    const eq = linearEquations(t).find((e) => !e.assignment);
    if (eq && (i === 0 || REQUEST_RE.test(t))) problem = { ...eq, turn: i };
  });
  if (problem) return problem;
  // After a photo, the problem is only written down in Merc's first reply,
  // whose first line restates it (PHOTOS). A first user turn with no
  // equation and a first assistant line that is one: that line.
  const firstReply = (Array.isArray(messages) ? messages : []).find((m) => m && m.role === 'assistant' && typeof m.content === 'string');
  if (!firstReply || linearEquations(turns[0] || '').length) return null;
  const firstLine = firstReply.content.split('\n').find((l) => l.trim()) || '';
  const eqs = linearEquations(firstLine).filter((e) => !e.assignment);
  return eqs.length === 1 ? { ...eqs[0], turn: 0 } : null;
}

const fmt = (n) => formatAnswer(n);
const at = (side, v) => round(side.k * v + side.c);

// `calmTieIn` (claude-sonnet-5-5 only): the right-final-answer note orders
// the AI tie-in only when no turn of the thread pushed for the answer or
// was rushed, the rule's own "weren't frustrated or rushed". The unqualified
// order made a literal reader add it for a student on a timed test (A/B of
// 2026-10-24: take-home-test, multi-problem). "idk" is being stuck, not a
// push, so it doesn't count. Both patterns ask for the push or the clock
// itself, not a word that also turns up in calm work: "can you tell me if
// it's right", "a test catches 90%", "let me test x = 3", "60 km in 45
// minutes" and "i have a quiz friday so i want to practice" are calm.
const PUSH_RE = /\bjust (?:tell|say|give|do|show|write|solve)\b|\b(?:tell|give|show) me (?:the )?(?:answers?|number|letter)\b|\bcan (?:u|you) just\b|\b(?:do|solve|write) (?:it|this|that|mine|them|the rest) for me\b|\bwhat(?:'s| is) the answer\b|\bjust the (?:answers?|number|letter)\b|\b(?:answers?|numbers?) only\b|\bc'?mon\b|\bcmon\b/;
const RUSH_RE = /\b(?:hurry|asap|no time|(?:don'?t|dont|do not) have time)\b|\bdue (?:in|at|by|soon|today|tonight|tmrw|tomorrow)\b|\b\d+\s*(?:min|mins|minutes) (?:left|to go)\b|\bi (?:only )?have (?:like )?\d+\s*(?:min|mins|minutes)\b|\b(?:it'?s|its|this is) (?:a|my) (?:take[- ]home )?(?:test|exam|quiz)\b|\b(?:on|during|taking) (?:a|my|the) (?:take[- ]home )?(?:test|exam|quiz)\b|\btake[- ]home (?:test|exam|quiz)\b|\b(?:test|exam|quiz) (?:right )?now\b|\b(?:i(?:'ll| will)?|ill|i'?m|gonna) (?:\w+ )?fail(?:ing)?\b/;
const calmThread = (turns) => !turns.some((t) => PUSH_RE.test(lower(t)) || RUSH_RE.test(lower(t)));

/** The verdict note for the student's latest line on a given linear equation. */
function verdictNote(turns, messages, { calmTieIn = false } = {}) {
  const problem = givenProblem(turns, messages);
  if (!problem) return '';
  const last = turns.length - 1;
  const lines = linearEquations(turns[last], { all: true })
    .filter((e) => e.variable === problem.variable && e.compact !== problem.compact);
  if (lines.length === 0) return '';
  const line = lines[lines.length - 1];
  const holds = at(line.L, problem.answer) === at(line.R, problem.answer);
  const head = '## STEP CHECK (worked out by the server for this reply only; never mention it)';
  if (line.assignment) {
    if (holds) {
      const tieIn = !calmTieIn || calmThread(turns)
        ? ', and if no earlier reply in this thread has an AI line, add the one AI tie-in line'
        : '. No AI line in this reply: they were rushed or pushing for the answer';
      return `${head}\nTheir final answer ${line.text} is right: it holds in ${problem.text}. Confirm it with the visible check, say plainly that it's right${tieIn}.`;
    }
    const v = line.answer;
    const sides = problem.R.k === 0
      ? `${problem.lhs} is ${fmt(at(problem.L, v))}, not ${problem.rhs}`
      : `${problem.lhs} is ${fmt(at(problem.L, v))} but ${problem.rhs} is ${fmt(at(problem.R, v))}`;
    return `${head}\nTheir answer ${line.text} is wrong: at ${problem.variable} = ${fmt(v)}, ${sides}. Start with "Check it:" and that check with their number (Catch errors); don't give the right answer.`;
  }
  if (holds) {
    return `${head}\nTheir line ${line.text} is right: it holds at the real answer. Your first word is "Yes"; confirm it and move to the next step (Confirm and advance). Don't check it again, doubt it, or ask about it.`;
  }
  // The numbers of a check only for a line one step from the end ("−2x = 24"):
  // on an earlier line, where it breaks is clearer than what it would give.
  const implied = line.value !== null && line.L.c === 0 && line.R.k === 0 ? line.answer : null;
  const check = implied === null
    ? ''
    : ` Their line gives ${problem.variable} = ${line.value}, and at ${problem.variable} = ${line.value}, ${problem.lhs} is ${fmt(at(problem.L, implied))}, not ${fmt(at(problem.R, implied))}.`;
  return `${head}\nTheir line ${line.text} is wrong: it doesn't hold at the real answer.${check} Start with "Check it:" and ${check ? 'that check' : 'point at exactly where it breaks'} (Catch errors); never write the corrected line or the answer.`;
}

/** "subtract 5 from both sides?", "add 9", "divide by 3": a step in words,
 *  judged on the line the thread has reached (the latest written line of
 *  their problem that holds at the real answer, or the problem itself). */
const VERBAL_RE = /\b(subtract(?:ing)?|minus|take away|taking away|add(?:ing)?|plus|divid(?:e|ing)|multipl(?:y|ying))\b[^0-9\n]{0,24}?(\d+(?:\.\d+)?)/i;
function verbalStepNote(turns, messages) {
  const problem = givenProblem(turns, messages);
  const last = turns[turns.length - 1];
  if (!problem || linearEquations(last, { all: true }).length) return '';
  const m = VERBAL_RE.exec(lower(last));
  if (!m) return '';
  const holds = (e) => at(e.L, problem.answer) === at(e.R, problem.answer);
  const written = (Array.isArray(messages) ? messages : []).slice(0, -1)
    .filter((x) => x && typeof x.content === 'string')
    .flatMap((x) => linearEquations(x.content))
    .filter((e) => !e.assignment && e.variable === problem.variable && holds(e) && e.R.k === 0 && e.L.k !== 0);
  const line = written.length ? written[written.length - 1] : problem;
  if (line.R.k !== 0 || line.L.k === 0) return '';
  const [a, b, c] = [line.L.k, line.L.c, line.R.c];
  const n = Number(m[2]);
  const verb = m[1].toLowerCase();
  const v = problem.variable;
  const term = (k) => (k === 1 ? v : k === -1 ? `-${v}` : `${fmt(k)}${v}`);
  const side = (k, cst) => (cst === 0 ? term(k) : `${term(k)} ${cst < 0 ? '-' : '+'} ${fmt(Math.abs(cst))}`);
  let next;
  if (/^(?:subtract|minus|take)/.test(verb)) next = { k: a, c: b - n, r: c - n };
  else if (/^(?:add|plus)/.test(verb)) next = { k: a, c: b + n, r: c + n };
  else if (/^divid/.test(verb)) next = { k: a / n, c: b / n, r: c / n };
  else next = { k: a * n, c: b * n, r: c * n };
  [next.k, next.c, next.r] = [round(next.k), round(next.c), round(next.r)];
  const head = '## STEP CHECK (worked out by the server for this reply only; never mention it)';
  const said = `"${String(last).trim().slice(0, 60)}"`;
  const lastStep = next.c === 0 && Math.abs(next.k) === 1;
  if (next.c === 0 || (Math.abs(next.c) < Math.abs(b) && Math.abs(next.k) === Math.abs(a))) {
    return lastStep
      ? `${head}\nTheir step ${said} is right, and it is the last step: your first word is "Yes", and don't write what it gives; ask what they get.`
      : `${head}\nTheir step ${said} is right: your first word is "Yes"; if no earlier reply named it, name the idea in bold (**inverse operations**); write the line it gives, ${side(next.k, next.c)} = ${fmt(next.r)}, and ask about the next step.`;
  }
  if (/^divid/.test(verb) && Math.abs(n) === Math.abs(a)) {
    return `${head}\nTheir step ${said} works (dividing first is allowed), though it leaves fractions: say so plainly, and ask whether they'd rather undo the ${b < 0 ? '-' : '+'} ${fmt(Math.abs(b))} first.`;
  }
  return `${head}\nTheir step ${said} doesn't undo anything: it gives ${side(next.k, next.c)} = ${fmt(next.r)}, and the ${b < 0 ? '-' : '+'} ${fmt(Math.abs(b))} is still next to ${term(a)}. Start with "Check it:" and that line; don't give the right step.`;
}

/** The note for the student's number on a formula or word problem. */
const NUMBER_ANSWER_RE = /\b(?:i got|got|i get|is it|it'?s|its|it is|is|=)\s*(-?\d+(?:\.\d+)?)\b[^?.!\n]{0,30}?(?:\?|\bright\b|\bcorrect\b)|\b(?:i got|i get|got)\s*(-?\d+(?:\.\d+)?)\b/;
// `calcCheck` (claude-sonnet-5-5 only): on a calculus or statistics thread
// (BROAD_WORD_RE) "run it backwards; never work the formula out yourself"
// can't be done: a definite integral, f'(2), a limit or a standard deviation
// has no formula to run their number back through. A literal reader then
// invents a case where it would be right (A/B of 2026-10-24, calc-def: "12
// would be right if …"), against its model notes' own-working rule. Off, or
// on any other thread, the note is exactly today's. Calculus notation
// (f'(2), dy/dx, ∫) counts as well as the words.
const CALC_NOTATION_RE = /\b[a-z]'+\(|\bdy\/dx\b|∫/;
function formulaAnswerNote(turns, { calcCheck = false } = {}) {
  const t = lower(turns[turns.length - 1]);
  if (linearEquations(t, { all: true }).some((e) => !e.assignment)) return '';
  const m = NUMBER_ANSWER_RE.exec(t);
  if (!m) return '';
  if (calcCheck && turns.some((x) => BROAD_WORD_RE.test(x) || CALC_NOTATION_RE.test(lower(x)))) {
    return `## THEIR NUMBER (for this reply only; never mention it)\nThe student gave ${m[1] || m[2]} as their answer to a calculus or statistics problem, which can't be checked by putting their number back in. Work it out silently yourself. If their number matches, show the line of your working it matches and say plainly that it's right; if not, show a check that fails or name the first line of their work that breaks (or ask for their work), and never write your own result. Never describe a case where their number would be right.`;
  }
  return `## THEIR NUMBER (for this reply only; never mention it)\nThe student gave ${m[1] || m[2]} as their answer to a formula or word problem. Check it with THEIR number only: run it backwards through the formula, or name the step it skipped. Never work the formula out yourself or write its result, whether their number is right or wrong.`;
}

const ASK_MOVES = [
  '',
  'a nudge that points at exactly where the next move happens',
  'a bigger hint that names the operation (when only the last step is left, name it and ask for the bare arithmetic, once)',
  'the worked example now: the same kind of problem on new numbers with a different answer, solved step by step and written as statements, then theirs handed back from where it stands (ask for their next step or their answer itself, never arithmetic already asked in this thread)',
];

/** The note that counts the student's asks on the current problem. */
// Merc's own replies on this problem, read for which last-step moves are
// used up (the stall: the same "36 ÷ 18?" ask after ask).
const ARITH_RE = /(\d+(?:\.\d+)?)\s*(\/|÷|divided by|over|\*|×|·|times|-|−|–|minus|\+|plus)\s*(\d+(?:\.\d+)?)|\bdivide (\d+(?:\.\d+)?) by (\d+(?:\.\d+)?)/i;
const EXAMPLE_MOVE_RE = /\b(?:new numbers|different numbers|other numbers|like this|same kind|same idea|same setup|same move|same calculation|here(?:['’]s| is) one|worked example|worked out|similar (?:problem|one|equation|example)|one more example|another example)\b/i;
const SMALLER_MOVE_RE = /\btimes what\b|\bwhat (?:number )?(?:times|plus|minus)\b|\bwhat \w+ (?:makes|gives)\b/i;
const GUESS_MOVE_RE = /\bguess\b/i;
function lastStepMove(messages) {
  const replies = (Array.isArray(messages) ? messages : []).filter((m) => m && m.role === 'assistant' && typeof m.content === 'string').map((m) => m.content);
  const lastQ = (t) => ((t.match(/[^.!?\n]*\?/g) || []).pop() || '');
  // The first reply that ASKED them for arithmetic (in its closing line,
  // "Look at the division: 36 ÷ 18. What do you get?"): their own last
  // step, never a later worked example's line.
  const closing = (r) => r.split('\n').filter((l) => l.trim()).pop() || '';
  const asked = replies.map((r) => (lastQ(r) ? ARITH_RE.exec(closing(r)) : null)).filter(Boolean)[0];
  if (!asked) return null;
  const [n1, op, n2] = asked[4] ? [asked[4], '/', asked[5]] : [asked[1], asked[2], asked[3]];
  const used = (re) => replies.some((r) => re.test(r));
  if (!used(EXAMPLE_MOVE_RE)) return ASK_MOVES[3];
  if (!used(SMALLER_MOVE_RE)) {
    const smaller = /^(?:\/|÷|divided by|over)$/i.test(op)
      ? `"${n2} times what makes ${n1}?"`
      : /^(?:-|−|–|minus)$/i.test(op) ? `"What plus ${n2} makes ${n1}?"` : null;
    if (smaller) return `make it smaller with their own numbers: ${smaller}`;
  }
  if (!used(GUESS_MOVE_RE)) return '"Guess a number and we\'ll check it together: what\'s your guess?"';
  return 'another worked example of that one step on new numbers, then ask for their answer';
}

function askNote(turns, { writing, messages = [] }) {
  const isAsk = (t) => ASK_RE.test(lower(t)) && linearEquations(t, { all: true }).length === 0;
  const last = turns.length - 1;
  if (last < 1 || !isAsk(turns[last])) return '';
  let n = 0;
  for (let i = last; i >= 1 && isAsk(turns[i]); i--) n++;
  // Asks the student made earlier on the same problem count too, as long as
  // no turn of their own work (an equation or a number) came in between.
  for (let i = last - n; i >= 1 && !/\d/.test(turns[i]) && !looksLikeProblemWork([{ role: 'user', content: turns[i] }]); i--) {
    if (isAsk(turns[i])) n++;
  }
  // The count itself stays out of the note: "That's the second ask" reached a
  // student once the note named it (tuning 2026-10-22).
  const head = '## NEXT MOVE (worked out by the server for this reply only; never mention it)';
  if (writing) {
    const wantsExample = EXAMPLE_ASK_RE.test(lower(turns[last]));
    // A claim or draft of their own, typed in an earlier turn of this thread.
    const ownText = turns.slice(1, last).some((t) => !isAsk(t) && (t.match(/\S+/g) || []).length >= 5);
    const move = wantsExample || n >= 3
      ? 'the everyday lunch model from the writing ladder, word for word, then "Now write yours the same way. What\'s your claim?"'
      : ownText
        ? 'quote, in quotation marks, the one phrase of their own wording that most needs work, say why in one line, and ask one open question about it (no options, no "or")'
        : n === 1
          ? 'one short question about their own text, like "What\'s one moment or detail you remember from it?", and the reply ends with that question mark (no options, no "or")'
          : 'the frame with blanks and no content';
    return `${head}\nThe student is asking you to write it again. Make this move: ${move}. Start with the move itself, never with what you won't do or whose work it is, and end with one question.`;
  }
  // Once a reply has asked them for the bare arithmetic, the next moves are
  // fixed: the worked example, the smaller form, a guess, another example.
  const stalled = n >= 2 ? lastStepMove(messages) : null;
  const move = stalled || (n >= 4 ? 'a move no reply in this thread has made yet (HOMEWORK COACHING)' : ASK_MOVES[n]);
  return `${head}\nThe student is asking for the answer${n > 1 ? ' again' : ''}. Make this move: ${move}. Don't comment on their message (never call it "an ask"); start with the move itself. Never their final answer, in any form, and never a question you or they already asked in this thread. End with one question, and no other question mark.`;
}

/** A claim or draft the student just wrote, in a writing thread. */
function ownClaimNote(turns) {
  const last = turns[turns.length - 1];
  if (turns.length < 2 || ASK_RE.test(lower(last)) || (last.match(/\S+/g) || []).length < 4) return '';
  return '## THEIR WORDS (for this reply only; never mention it)\nThe student just wrote a claim or draft of their own. Work on their wording: quote the phrase that most needs work, say why in one line, and ask one open question about it. No options and no "or": never hand them readings, words or positions to pick from.';
}

/** The opener for a request to write their essay or paragraph. */
function writingOpenerNote(turns) {
  if (turns.length !== 1) return '';
  const t = lower(turns[0]);
  if (!WRITING_RE.test(t) || !/\b(?:write|rewrite|need|give me|make|fix|improve|better)\b/.test(t)) return '';
  // Their own pasted text: start from it.
  const pasted = t.split(/:\s*/).slice(1).join(': ');
  if ((pasted.match(/[.!?](?:\s|$)/g) || []).length >= 2) {
    return '## THEIR TEXT (for this reply only; never mention it)\nThe student pasted text they wrote. Your first sentence quotes the one phrase of theirs that most needs work, in quotation marks, and says why in one line; then one question asking them to rewrite it. Don\'t rewrite it, and don\'t offer options.';
  }
  if (EXAMPLE_ASK_RE.test(t)) {
    return '## WRITING (for this reply only; never mention it)\nThe student asked for an example on their own topic. Give the everyday lunch model from the writing ladder, word for word, then "Now write yours the same way. What\'s your claim?" No sentence about their book, topic or theme.';
  }
  return '## WRITING (for this reply only; never mention it)\nThe student asked you to write their work. Your whole reply is one short question asking what THEY think about their topic, like "What do you think the book is really saying about that?", and it ends right there: nothing after the topic, no dash, no "or", no readings or positions to pick from.';
}

// ── Balancing: count the atoms exactly ─────────────────────────────────────
// Review 2026-10-22: every chemistry opener asked about H in H₂ + O₂ → H₂O,
// which already matches, and correct coefficients ("is it 2 O₂?") were
// called wrong 6 of 6 times. Counting atoms is exact work for the server.
const SUB = { '₀': '0', '₁': '1', '₂': '2', '₃': '3', '₄': '4', '₅': '5', '₆': '6', '₇': '7', '₈': '8', '₉': '9' };
const ARROW_RE = /\s*(?:->|→|⟶|=>|⇒)\s*/;

/** Atoms in one formula ("Al2O3", "Ca(OH)2"), as { element: count }, or null. */
function parseFormula(src) {
  let i = 0;
  function group() {
    const counts = {};
    while (i < src.length && src[i] !== ')') {
      let part;
      if (src[i] === '(') {
        i++;
        part = group();
        if (src[i] !== ')') return null;
        i++;
      } else {
        const m = /^[A-Z][a-z]?/.exec(src.slice(i));
        if (!m) return null;
        i += m[0].length;
        part = { [m[0]]: 1 };
      }
      if (!part) return null;
      const n = /^\d+/.exec(src.slice(i));
      const mult = n ? Number(n[0]) : 1;
      if (n) i += n[0].length;
      for (const [el, c] of Object.entries(part)) counts[el] = (counts[el] || 0) + c * mult;
    }
    return counts;
  }
  const out = group();
  return out && i === src.length && Object.keys(out).length ? out : null;
}

/** "C3H8 + O2 -> 3CO2 + 4H2O" → { text, sides: [[{ coef, formula, atoms }]] }, or null. */
function parseReaction(line) {
  const t = String(line).replace(/[₀-₉]/g, (c) => SUB[c]);
  const m = /((?:\d*\s*[A-Z][A-Za-z0-9()]*\s*\+\s*)*\d*\s*[A-Z][A-Za-z0-9()]*)\s*(?:->|→|⟶|=>|⇒)\s*((?:\d*\s*[A-Z][A-Za-z0-9()]*\s*\+\s*)*\d*\s*[A-Z][A-Za-z0-9()]*)/.exec(t);
  if (!m) return null;
  const side = (src) => src.split('+').map((term) => {
    const tm = /^\s*(\d*)\s*([A-Z][A-Za-z0-9()]*)\s*$/.exec(term);
    if (!tm) return null;
    const atoms = parseFormula(tm[2]);
    return atoms ? { coef: tm[1] ? Number(tm[1]) : 1, formula: tm[2], atoms } : null;
  });
  const sides = [side(m[1]), side(m[2])];
  if (sides.some((x) => x.some((term) => !term))) return null;
  return { text: `${m[1].trim()} → ${m[2].trim()}`, sides };
}

function atomTotals(terms) {
  const out = {};
  for (const term of terms) for (const [el, c] of Object.entries(term.atoms)) out[el] = (out[el] || 0) + c * term.coef;
  return out;
}
function countLine(reaction) {
  const [l, r] = reaction.sides.map(atomTotals);
  const els = [...new Set([...Object.keys(l), ...Object.keys(r)])];
  const parts = els.map((el) => `${el} ${l[el] || 0} and ${r[el] || 0} (${(l[el] || 0) === (r[el] || 0) ? 'match' : 'differ'})`);
  return { text: parts.join(', '), balanced: els.every((el) => (l[el] || 0) === (r[el] || 0)) };
}

/** The atom-count note for the student's reaction as it stands, and for a
 *  coefficient they propose ("is it 5 O2?"). */
function atomNote(turns) {
  let reaction = null;
  let at = -1;
  turns.forEach((t, i) => { const r = parseReaction(t); if (r) { reaction = r; at = i; } });
  if (!reaction) return '';
  const head = '## ATOM COUNT (worked out by the server for this reply only; never mention it)';
  const now = countLine(reaction);
  const last = String(turns[turns.length - 1]).replace(/[₀-₉]/g, (c) => SUB[c]);
  const afterReaction = at === turns.length - 1 ? last.split(ARROW_RE).slice(1).join(' ').replace(/^[^.?!]*?(?=\b(?:is it|what about|how about|so)\b)/i, '') : last;
  const proposal = /\b(\d+)\s*([A-Z][A-Za-z0-9()]*)\s*\??\s*$/.exec(afterReaction.trim()) || /\b(?:is it|what about|how about|so)\s+(\d+)\s*([A-Z][A-Za-z0-9()]*)/i.exec(afterReaction);
  if (proposal) {
    const [n, formula] = [Number(proposal[1]), proposal[2]];
    const tried = { ...reaction, sides: reaction.sides.map((side) => side.map((term) => (term.formula === formula ? { ...term, coef: n } : term))) };
    if (tried.sides.some((side) => side.some((term) => term.formula === formula))) {
      const c = countLine(tried);
      return c.balanced
        ? `${head}\nWith ${n} ${formula}, their reaction balances: ${c.text}. Their proposal is right: your first word is "Yes", then show that count. Never doubt it, and never ask them to work it out again.`
        : `${head}\nWith ${n} ${formula}, their reaction doesn't balance yet: ${c.text}. Start with "Check it:" and that count; don't give the right coefficients.`;
    }
  }
  return `${head}\nAs their reaction stands (${reaction.text}): ${now.text}. Ask only about an element whose counts differ, never one that matches, and never give the coefficients.`;
}

/**
 * The note for this reply, or ''. `messages` is the client's thread. Never
 * for a turn that may be a crisis or a safety topic (`unsafe`), whose reply
 * follows the safety rules alone. `calmTieIn` (claude-sonnet-5-5 only; see
 * calmThread) keeps the AI tie-in out of a rushed or pushing thread's
 * right-answer note; `calcCheck` (claude-sonnet-5-5 only; see
 * formulaAnswerNote) has a calculus or statistics number checked against
 * the model's own working. Both off, every note is exactly today's.
 */
function homeworkMoment(messages, { unsafe = false, hasImage = false, deep = false, calmTieIn = false, calcCheck = false } = {}) {
  if (unsafe) return '';
  const turns = userTurns(messages).map((m) => m.content);
  if (turns.length === 0) return '';
  const all = lower(turns.join('\n'));
  const writing = WRITING_RE.test(all) && !linearEquations(all).length;
  if (writing && !hasImage) return writingOpenerNote(turns) || askNote(turns, { writing: true }) || ownClaimNote(turns);
  // A photo of schoolwork: the restatement comes first, and it is what keeps
  // the problem in the thread for the next turn (PHOTOS).
  if (hasImage) {
    return '## PHOTO (for this reply only; never mention it)\nThe student sent a photo. If it is schoolwork, your first line restates the exact problem you will work on, in one line, and the rest of the reply coaches it with one question at the end: no refusal and no comment on what you won\'t do. If they gave an answer of their own, check it (CHECK BEFORE ANY VERDICT).';
  }
  // Assistant turns count here: after a photo, Merc's restated problem is the
  // only place the problem is written down.
  if (!looksLikeProblemWork(messages)) return '';
  if (deep) {
    return '## EXPLAIN MORE (for this reply only; never mention it)\nThe student tapped "Explain more" on a problem they are solving. Go deeper on the idea behind the step they are on (why it works), with any example on other numbers, and never write a line of their own problem that the thread hasn\'t reached yet, nor its answer. End with one question.';
  }
  const atoms = atomNote(turns);
  const step = verdictNote(turns, messages, { calmTieIn }) || verbalStepNote(turns, messages) || (givenProblem(turns, messages) || atoms ? '' : formulaAnswerNote(turns, { calcCheck }));
  // A proposal ("is it 5 O2?") is its own verdict; the ask count still helps.
  const ask = step || /balances|doesn't balance/.test(atoms) ? '' : askNote(turns, { writing: false, messages });
  return [atoms, step, ask].filter(Boolean).join('\n\n');
}

/**
 * The stall, at the very end of a reply: a closing question that asks the
 * arithmetic the previous reply already asked ("What's 15 ÷ 3?" after "What's
 * 15 ÷ 3?", the 3rd ask's worked example included). The question is asked
 * for their answer instead. `previous` is Merc's last reply in the thread.
 */
function unrepeatQuestion(text, previous, variable = null) {
  const arith = (t) => new Set([...normalizeMath(t).replace(/[×·]/g, '*').matchAll(/(\d+(?:\.\d+)?)\s*(\/|divided by|over|\*|times|-|minus|\+|plus)\s*(\d+(?:\.\d+)?)/gi)]
    .map((m) => `${m[1]}${({ 'divided by': '/', over: '/', times: '*', minus: '-', plus: '+' })[m[2].toLowerCase()] || m[2]}${m[3]}`));
  const lastQ = (t) => ((String(t).match(/[^.!?\n]*\?/g) || []).pop() || '');
  const q = lastQ(text);
  if (!q || !previous || safetyText(q)) return text;
  const before = arith(previous);
  const prevQ = lastQ(previous).trim().toLowerCase();
  // The same arithmetic asked again, or the previous reply's closing question
  // word for word ("Divide 36 by 18. What do you get?" then a worked example
  // ending "…36 g ÷ 18 g/mol. What do you get?": final run on d1ec542).
  const repeated = [...arith(q)].some((a) => before.has(a))
    || (prevQ && q.trim().toLowerCase() === prevQ && EXAMPLE_MOVE_RE.test(String(text)));
  if (!repeated) return text;
  const at = String(text).lastIndexOf(q);
  const asks = [variable ? `What do you get for ${variable}?` : 'What do you get for yours?', "What's your answer for yours?"];
  // (Asked from here, never the previous reply's own question again.)
  const ask = asks.find((a) => a.toLowerCase() !== prevQ) || asks[1];
  return `${String(text).slice(0, at)}${/^\s/.test(q) ? ' ' : ''}${ask}${String(text).slice(at + q.length)}`;
}

/**
 * "Explain more" on a two-step equation must not write the line the
 * student's own first step produces (3x = 15 for 3x + 5 = 20) before the
 * thread has reached it (final run 2026-10-22, flag off, 2 of 3).
 */
function findPastStep(text, messages) {
  const previous = (Array.isArray(messages) ? messages : []).slice(0, -1)
    .filter((m) => m && typeof m.content === 'string').map((m) => normalizeMath(m.content)).join('\n');
  for (const p of studentProblems(messages)) {
    if (!p.L || p.L.c === 0 || p.R.k !== 0) continue;
    const coef = Math.abs(p.A) === 1 ? (p.A < 0 ? '-' : '') : fmt(p.A).replace(/^-/, '-\\s*');
    const re = new RegExp(String.raw`(?<![\w.])${coef}\s*${escapeRe(p.variable)}\s*=\s*${valueRe(fmt(p.D))}${END}`);
    if (re.test(previous)) continue;
    const m = re.exec(normalizeMath(text));
    if (m) return { name: 'past step', match: m[0], value: fmt(p.D) };
  }
  return null;
}

/** Their own wording, quoted: a quoted span of 3+ words found in a turn of theirs. */
function quotesStudent(text, messages) {
  const norm = (x) => String(x).toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
  const theirs = norm(userTurns(messages).map((m) => m.content).join(' '));
  return [...String(text ?? '').matchAll(/["“]([^"”\n]+)["”]/g)].some((m) => {
    const q = norm(m[1].replace(/…|\.\.\./g, ' '));
    return q.split(' ').length >= 3 && theirs.includes(q);
  });
}
/** A writing turn whose move is to quote their own wording: they pasted
 *  text, or they ask about a claim or draft they typed earlier. */
function needsQuote(messages) {
  const turns = userTurns(messages).map((m) => m.content);
  if (!writingThread(messages) || turns.length === 0) return false;
  const last = turns[turns.length - 1];
  if (turns.length === 1) return /THEIR TEXT/.test(writingOpenerNote(turns));
  const ask = ASK_RE.test(lower(last)) && !EXAMPLE_ASK_RE.test(lower(last));
  return ask && turns.slice(1, -1).some((t) => !ASK_RE.test(lower(t)) && (t.match(/\S+/g) || []).length >= 5);
}

/** A writing thread (an essay, a thesis, a paragraph), with no equation. */
function writingThread(messages) {
  const all = lower(userTurns(messages).map((m) => m.content).join('\n'));
  return WRITING_RE.test(all) && !linearEquations(all).length;
}

/**
 * Review 2026-10-22: in writing threads the closing question kept ending in a
 * menu of readings after a dash ("What do you think the book is saying about
 * ambition — is it a warning, or a celebration?"), whatever the rules and the
 * notes said. When the part before the dash is a whole question, the menu is
 * cut and the question ends there. Nothing else is touched. `asides`
 * (claude-sonnet-5-5 only; off, the text comes back as it is) adds
 * stripOrAside.
 */
const MENU_PEOPLE_RE = /\b(?:parents?|mom|dad|guardians?|adults?|grown-?ups?|teachers?|coach(?:es)?|counsel(?:l)?ors?|librarians?|doctors?|nurses?|pharmacists?|therapists?|friends?|someone|people)\b/i;
function stripMenu(text, { asides = false } = {}) {
  const lines = String(text ?? '').split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    if (!lines[i].trim()) continue;
    // The menu: "— is it A or B?", or a list, "— was it reckless, naive, something else?".
    const m = /^(.*\b(?:what|how|why|which|who|where|when|do|does|did|is|are|was|were|can|could|would)\b[^—–?]*?\S)\s*[—–]\s*([^—–?]*(?:\bor\b|,[^,?]*,)[^—–?]*)\?(["”’']?)\s*$/i.exec(lines[i]);
    // A list of people to go to is not a menu of readings, and safety text
    // keeps every word (review 2026-10-24: "— a teacher, a librarian, or a
    // parent?" was cut from an under-13 hand-off).
    if (m && !safetyText(lines[i]) && !MENU_PEOPLE_RE.test(m[2])) lines[i] = `${m[1]}?${m[3]}`;
    if (asides && !safetyText(lines[i])) lines[i] = stripOrAside(lines[i]);
    break;
  }
  return lines.join('\n');
}

/**
 * The second option inside the closing question, between commas, on
 * claude-sonnet-5-5 (stripMenu's `asides`). Sonnet 5.5 A/B and tuned runs
 * 2026-10-24: hw-essay-draft failed "no menu of readings" in 3 of 6 runs, on
 * the two writing turns after the student's draft, though both turns' notes
 * say "no options, no 'or'": "What exactly did the Friar's plan do, or fail
 * to do, that made the ending happen?", "What did his plan lead Romeo to
 * believe, or keep Romeo from knowing, in that final scene?", "What did the
 * Friar decide, in the plan or around it, that he could have chosen
 * differently?". stripMenu cut only a menu after a dash. 4.6: none.
 *
 * The aside goes and the question reads on ("What exactly did the Friar's
 * plan do that made the ending happen?"). Only in a closing what, how, why,
 * which, who or whose question that ends the reply's last line, and only an
 * aside that opens at the question's FIRST comma, starts with "or" (or with
 * a preposition and holds an "or"), and is followed by more of the question.
 * Verifiers 2026-10-24 refuted a looser pass: it read the last item of an
 * Oxford-comma list as the aside ("Which of Romeo, the Nurse, or the Friar,
 * made…" became "Which of Romeo, the Nurse made…", and "…the vendor that
 * built it, or the auditor who signed off, and why?" lost its auditor), took
 * the clause in "When you use something like Siri, ChatGPT, or…, what…?" for
 * the question, and cut "or would it help to talk through how to reach 988"
 * from a crisis reply. So: no "when" or "where" (a leading clause); never an
 * aside after another comma of the question, one in quotation marks (their
 * own words), or one in a yes/no question ("Was it his haste, or his
 * secrecy, that…?" is the menu itself); never an aside that starts a new
 * clause (", or would it help…,", ", or you could…,"), one of a chain (", or
 * fail to do, or ignore,"), or a length ("in one sentence or less"). The
 * server never runs it on a safety turn or a safety topic.
 */
const OR_ASIDE_RE = /,\s+(?:or\b(?!\s+(?:would|could|should|do|does|did|is|are|was|were|will|can|might|may|has|have|had|am|i|you|we|he|she|they|it|there)\b)|(?:in|on|at|by|with|before|after|during|around|inside|outside|within)\b[^,?—–"“”]*?\bor\b)(?!\s+(?:less|more|so|fewer|longer|shorter)\b)[^,?—–"“”]*,\s+(?!or\b)(?=\S)/i;
function stripOrAside(line) {
  const q = /(^|[.!?:]["”’']?\s+)([^.!?:]*\?)(["”’']?)\s*$/.exec(line);
  if (!q || !/^\W*(?:what|how|why|which|who|whose)\b/i.test(q[2])) return line;
  const m = OR_ASIDE_RE.exec(q[2]);
  if (!m) return line;
  const before = q[2].slice(0, m.index);
  if (before.includes(',') || (before.match(/["“”]/g) || []).length % 2) return line;
  return `${line.slice(0, q.index + q[1].length)}${before} ${q[2].slice(m.index + m[0].length)}${q[3]}`;
}

/**
 * A word problem's own numbers worked into a result that isn't one of them
 * ("150 ÷ 3 = 50 mph", "½ × 10 × 3² = 45 m"): a line holding two or more of
 * the numbers the student gave, then "= R" with R a number they never gave.
 * Armed only when the thread has no linear equation (the main guard covers
 * those) and no later turn of theirs proposes a number of its own (then a
 * check that confirms it is fine). `problem` is the student's first turn.
 */
function wordProblemNumbers(messages) {
  const turns = userTurns(messages).map((m) => m.content);
  if (turns.length === 0 || linearEquations(turns.join('\n')).length) return null;
  if (!looksLikeProblemWork([{ role: 'user', content: turns[0] }]) || OPTIONS_RE.test(turns[0])) return null;
  // Not a word problem: a quadratic ("x^2"), a system or a reaction, whose
  // own examples share small numbers with theirs (red-team re-run: a
  // quadratic example's "−4 + (−5) = −9" was redacted to "= ?").
  if (quadraticEquations(turns[0]).length || /\b[a-z]\s*(?:\^\s*2|²)\s*[-+=]/i.test(turns[0]) || linearSystem(turns[0]) || REACTION_RE.test(turns[0])) return null;
  const nums = (t) => [...normalizeMath(t).matchAll(/(?<![\w.])\d+(?:\.\d+)?(?![\w.]*\d)/g)].map((m) => Number(m[0]));
  const theirs = new Set(nums(turns[0]));
  if (theirs.size < 2) return null;
  if (turns.slice(1).some((t) => nums(t).some((n) => !theirs.has(n)))) return null;
  // An answer of their own in the problem turn ("i got 30 m", "is 3 moles
  // right?"): a line built from it is the check run backwards, not a leak.
  const claim = NUMBER_ANSWER_RE.exec(lower(turns[0]));
  theirs.proposed = new Set(claim ? [Number(claim[1] || claim[2])] : []);
  return theirs;
}
function findNumberLeak(text, theirs) {
  if (!theirs) return null;
  const proposed = theirs.proposed || new Set();
  // Merc confirming the answer they gave: nothing left to give away (a right
  // "i got 15" for the hypotenuse was redacted to "15² = ?" before this).
  if (proposed.size && /✓|✔|\b(?:that['’]s|it['’]s|is) (?:right|correct)\b/i.test(text)) return null;
  for (const line of normalizeMath(text).split(/\n|(?<=[.!?])\s+/)) {

    // "= 45", or the same in words: "½ × 10 × 3² gives 45, not 30" (red-team
    // run on 3d22459, flag off).
    const ops = [...line.matchAll(/=|\b(?:gives(?: you)?|equals|comes (?:out )?to|makes)\b/gi)];
    if (ops.length === 0) continue;
    const last = ops[ops.length - 1];
    const eq = last.index;
    const before = [...line.slice(0, eq).matchAll(/(?<![\w.])\d+(?:\.\d+)?(?![\w.]*\d)/g)].map((m) => Number(m[0]));
    // Only the numbers the problem GAVE count; the answer they proposed is
    // theirs to run backwards ("30 = ½ × 10 × t² gives t² = 6" uses one given
    // number), but naming it in passing doesn't excuse a worked result ("if
    // the ball fell 30 m, … ½ × 10 × 3² = 45": two given numbers).
    const given = before.filter((n) => theirs.has(n) && !proposed.has(n));
    const after = /^\s*\**\s*(-?\d+(?:\.\d+)?)/.exec(line.slice(eq + last[0].length));
    if (!after) continue;
    const r = Number(after[1]);
    if (theirs.has(r) || given.length < 2) continue;
    return { name: 'word problem', match: line.trim(), value: after[1] };
  }
  return null;
}

/** Distribution products the student's latest line got wrong: for
 *  3(x − 4) and their "3x − 4 + 5", the −12 they still have to find. */
function correctionValues(messages) {
  const turns = userTurns(messages).map((m) => m.content);
  const problem = givenProblem(turns, messages);
  if (!problem || turns.length < 2) return [];
  const latest = normalizeMath(turns[turns.length - 1]);
  const out = [];
  for (const m of normalizeMath(problem.text).matchAll(/(-?\d+(?:\.\d+)?)\s*\(([^()]+)\)/g)) {
    const k = Number(m[1]);
    const inner = parseLinear(m[2]);
    if (!inner || inner.c === 0) continue;
    const product = round(k * inner.c);
    if (!new RegExp(`(?<![\\d.])${escapeRe(String(Math.abs(product)))}(?![\\d.]*\\d)`).test(latest)) out.push(product);
  }
  return out;
}
/** `text` with a leaked value written as "?": after an "=" for a word
 *  problem's result, everywhere for a correction value. */
function redactValue(text, leak) {
  const v = escapeRe(String(Math.abs(Number(leak.value)))).replace(/^/, Number(leak.value) < 0 ? '[-−–]\\s*' : '');
  const re = leak.name === 'word problem'
    ? new RegExp(`((?:=|\\bgives(?: you)?|\\bequals|\\bcomes (?:out )?to|\\bmakes)\\s*\\**\\s*)${v}(?![\\d.]*\\d)`, 'gi')
    : new RegExp(`()${v}(?![\\d.]*\\d)`, 'g');
  return String(text).replace(re, '$1?');
}
/** `text` without the lines that hold a worked example landing on their
 *  answer, or their own next line (the last resort: replacing the value
 *  can't fix either). */
function dropExampleLines(text, problems) {
  return String(text ?? '').split('\n').filter((l) => {
    const leak = findLeak(l, problems);
    return !(leak && (leak.name === 'example' || leak.name === 'own step'));
  }).join('\n').replace(/\n{3,}/g, '\n\n').trim();
}
/** `text` without the lines holding a quadratic leak (the last resort). */
function dropLeakLines(text, problems) {
  return String(text ?? '').split('\n').filter((l) => !findQuadraticLeak(l, problems)).join('\n').replace(/\n{3,}/g, '\n\n').trim();
}
function findCorrectionLeak(text, values) {
  for (const v of values || []) {
    const re = new RegExp(`${v < 0 ? String.raw`-\s*` : String.raw`(?<![-\d.]\s?)`}${escapeRe(String(Math.abs(v)))}(?![\d.]*\d)`);
    const m = normalizeMath(text).match(re);
    if (m) return { name: 'correction', match: m[0], value: String(v) };
  }
  return null;
}

// ── Safety text ─────────────────────────────────────────────────────────────
// Review 2026-10-24: a homework or writing thread keeps its guard for every
// later turn, and the transforms here never asked what they were cutting.
// On main, inside a thread that opened with an equation or an essay, a Xanax
// refusal and its danger warning were dropped as a "preamble"; a menu of
// adults to ask ("a teacher, a librarian, or a parent?") was cut as a menu of
// readings; the "24/7" of the crisis hand-off was read as the 8 × 3 = 24 the
// student still had to find, so the hand-off was written again under an
// ANSWER GUARD note or sent as "open ?/7"; "under 18" became "under ?".
// A sentence with SAFETY_CORE content is never dropped, cut or rewritten, and
// a strong one is never redacted and holds no leak. Strong: hotlines,
// referrals to an adult or a professional, ages and laws, harm. Topic words
// (pills, alcohol, a dose, a teacher) only keep a sentence's wording: a dosage
// word problem's "250 × 4 = 1000 mg" is still a leak.
const ADULT = String.raw`(?:parents?|mom|dad|mother|father|guardians?|(?:an?|another|other|some|older) (?:adult|grown-?up)s?|adults?|(?:school )?counsel(?:l)?ors?|doctors?|nurses?|pharmacists?|therapists?|pediatricians?|psychologists?|social workers?|police)`;
const STRONG_SAFETY_RE = new RegExp([
  // Hotlines and services; a bare 988 or 911 in arithmetic is neither.
  String.raw`\b741741\b|\bpoison control\b|\b1-800-\d|\bhotline\b|\blifeline\b|\bcrisis (?:text )?line\b`,
  String.raw`\b(?:call|text|dial|reach|contact)(?:ing|ed|s)?\b[^.?!\n]{0,40}\b(?:988|911)\b|\b(?:988|911)\b[^.?!\n]{0,40}\b(?:suicide|crisis|lifeline|emergenc\w*|free|24\/7)\b`,
  // An adult or a professional to tell or ask.
  String.raw`\b(?:tell|talk(?:ing)? (?:to|with)|speak(?:ing)? (?:to|with)|reach(?:ing)? out to|ask|go to|turn to|check (?:in )?with|let)\b[^.?!\n]{0,30}\b${ADULT}\b`,
  String.raw`\b${ADULT}\b[^.?!\n]{0,40}\b(?:can|could|will|would|should|is the right person|are the right people|help)\b`,
  String.raw`\btrusted (?:adult|grown-?up|teacher)\b|\b(?:adult|teacher|someone|people) you trust\b`,
  // Ages and laws (rules 7 and 8), and the hand-off's hours.
  String.raw`\b(?:under|over|younger than|older than) (?:1\d|2[01])\b|\b1\d (?:or|and) (?:younger|under|older|up|over)\b|\b13\s*\+|\b13 and (?:up|older|over)\b|\byears? old\b|\b(?:in|only in) (?:\d|1[0-2])(?:st|nd|rd|th)? grade\b|\bgrade (?:\d|1[0-2])\b|\billegal\b|\bagainst the law\b|\b24\/7\b|\b24 hours a day\b`,
  // Crisis and exploitation; the rule-1 hand-off; rules 5 and 8.
  String.raw`\bnot your fault\b|\boverdos\w*|\bself[- ]?harm\b|\bsuicid\w*|\bkill (?:yourself|myself|themselves|himself|herself)\b|\bblackmail\w*|\bsextort\w*|\bnudes?\b`,
  String.raw`\bi['’]?m (?:just )?an ai\b(?![- ](?:literacy|tutor))|\bi am an ai\b(?![- ](?:literacy|tutor))|\bsaved on\b|\bmercurius server\b|\bdelete my data\b|\bpersonal (?:info|information|details)\b|\b(?:built|made|designed) for teens\b|\bthe right fit for you\b`,
].join('|'), 'i');
const SAFETY_TOPIC_RE = new RegExp([
  String.raw`\b(?:teachers?|coach(?:es)?|librarians?|friends?)\b[^.?!\n]{0,40}\b(?:can|could|help)\b|\b(?:tell|talk(?:ing)? to|ask)\b[^.?!\n]{0,30}\b(?:teachers?|coach(?:es)?|librarians?|friends?)\b`,
  // Harm, danger and pressure: words a lesson or a debate uses too.
  String.raw`\bdanger(?:ous)?\b|\bunsafe\b|\bemergenc\w*|\babus\w*|\bassault\w*|\bpressur\w*|\breal person\b|\bmak(?:e|es|ing) fun of\b`,
  String.raw`\bpills?\b|\bdrugs?\b|\balcohol\b|\bdrunk\b|\bdrink(?:ing)?\b|\bvap(?:e|es|ing)\b|\bnicotine\b|\bmedic(?:ine|ation)s?\b|\bprescri\w*|\bdos(?:e|es|age)\b|\bhurt(?:s|ing)?\b|\bpoison\w*|\bblock\b|\breport\b|\bsafe\b|\bsafety\b`,
  String.raw`\broast\w*|\bbull(?:y|ying|ied)\b|\bharass\w*|\bmean (?:to|about)\b|\bsexual\w*|\bthat kind of (?:scene|content|story|thing)\b`,
].join('|'), 'i');

/** True when the student's message asks for something aimed at a person or
 *  sexual content ("write a mean post about jake", "roast my friend", "make
 *  it spicy"): Merc's decline of it ("I won't write it for you, but…") reads
 *  like a homework preamble, so the guard stays off for that turn (review
 *  2026-10-24). */
const HARM_REQUEST_RE = /\b(?:mean|nasty|rude|cruel|savage|embarrassing|hateful)\s+(?:post|message|comment|text|tweet|caption|joke|song|rap|poem|story|things?|stuff|names?)\b|\b(?:roast|make fun of|making fun of|bully|harass|insult|humiliate|expose|cyberbully)\s+(?:him|her|them|my|this|that|a|an|the|our|some|[a-z]+ (?:from|in) )|\bdiss (?:track|song|post)\b|\b(?:sexy|spicy|steamy|sex scene|sleep together|hook(?:ing)? up|nudes?|send (?:me )?pics)\b/i;
function harmRequest(text) {
  return HARM_REQUEST_RE.test(lower(text));
}

/** Sentence spans of `text` as [start, end): a span ends after . ! or ? (and
 *  any closing quote or emphasis) before a space, or at a line break. */
function sentenceSpans(text) {
  const t = String(text ?? '');
  const spans = [];
  let start = 0;
  for (const m of t.matchAll(/[.!?]+["”’'*_)\]]*(?=\s|$)|\n/g)) {
    const end = m.index + m[0].length;
    if (end > start) spans.push([start, end]);
    start = end;
  }
  if (start < t.length) spans.push([start, t.length]);
  return spans;
}
/** True when `text` carries safety content that no transform may drop or
 *  rewrite. `{ strong: true }` asks only for the markers that also hold no
 *  leak and are never redacted. */
function safetyText(text, { strong = false } = {}) {
  const t = normalizeMath(String(text ?? ''));
  return STRONG_SAFETY_RE.test(t) || (!strong && SAFETY_TOPIC_RE.test(t));
}
/** `text` with every strong safety sentence blanked to spaces (same length,
 *  line breaks kept), for the leak checks: "open 24/7" is not their 24. */
function maskSafetyText(text) {
  const t = String(text ?? '');
  let out = '';
  let at = 0;
  for (const [s, e] of sentenceSpans(t)) {
    const span = t.slice(s, e);
    out += t.slice(at, s) + (safetyText(span, { strong: true }) ? span.replace(/[^\n]/g, ' ') : span);
    at = e;
  }
  return out + t.slice(at);
}
/** `fn` applied to each run of `text` between strong safety sentences, which
 *  are kept exactly (the last-resort redaction never reaches them). */
function outsideSafetyText(text, fn) {
  const t = String(text ?? '');
  const spans = sentenceSpans(t);
  if (!spans.some(([s, e]) => safetyText(t.slice(s, e), { strong: true }))) return fn(t);
  const parts = [];
  let run = '';
  const flush = () => {
    if (!run) return;
    // The run's own leading and trailing whitespace stays, so the kept
    // sentences are still separated however `fn` trims.
    const lead = run.match(/^\s*/)[0];
    const trail = run.slice(lead.length).match(/\s*$/)[0];
    const core = run.slice(lead.length, run.length - trail.length);
    const done = core ? String(fn(core)).trim() : '';
    if (done) parts.push(lead + done + trail);
    else parts.push(run.includes('\n') ? '\n\n' : ' ');
    run = '';
  };
  let at = 0;
  for (const [s, e] of spans) {
    const span = t.slice(s, e);
    if (safetyText(span, { strong: true })) {
      run += t.slice(at, s);
      flush();
      parts.push(span);
    } else {
      run += t.slice(at, e);
    }
    at = e;
  }
  run += t.slice(at);
  flush();
  return parts.join('').replace(/\n{3,}/g, '\n\n').trim();
}

/**
 * No preamble, on a held-back homework or writing reply: a first sentence
 * that only says what Merc won't do or whose work it is ("That's your job —
 * and you're closer than you think.", "Running it on their numbers would
 * hand you the answer") is dropped when the move itself follows it. The
 * legacy path kept writing these on pushback turns whatever the rules said
 * (gate 2026-10-22, flag off, 3 of 3 runs).
 */
const PREAMBLE_SENTENCE_RE = new RegExp([
  // What Merc won't do to THEIR work ("I won't just hand you the answer"),
  // never a refusal of something else ("I can't write that kind of scene",
  // "I can't tell you what to take": review 2026-10-24).
  String.raw`\bi(?:['’]m| am)?\s+(?:just\s+|really\s+)?(?:not going to|not gonna|won['’]t|will not|can['’]t|cannot|can not|shouldn['’]t|should not|don['’]t|do not)\s+(?:just\s+|simply\s+)?(?:solve|give|hand|write|rewrite|finish|do|tell)\s+(?:you\s+)?(?:over\s+|out\s+)?(?:(?:it|this|that|them|yours)\b(?!\s+(?:kind|sort|type) of)(?!\s+(?:about|to|making|that|which|where|with)\b)|(?:the|your|an|any|this|that)\s+(?:final\s+|whole\s+|full\s+)?(?:answers?|number|result|value|solution|problems?|equation|homework|work|essay|paragraph|thesis|draft|sentence|intro|conclusion|code|script|steps?|worksheet)\b|what (?:it|x|the answer|the script) (?:is|prints|outputs|returns)\b|x\b)`,
  String.raw`\bhaven['’]t (?:given|shared|sent|told|shown) (?:me )?(?:your|an|any|a)\b`,
  String.raw`\b(?:solv|do|writ|rewrit|finish|answer)\w* (?:it|this|that|them|yours|your \w+) for you\b|\banswers? for you\b`,
  String.raw`\b(?:rather than|instead of)\s+(?:me\s+)?(?:just\s+)?(?:giving|telling|handing|solving|doing|writing)\b`,
  String.raw`\bacademic integrity\b|\bcheat(?:ing)?\b|\bprompt injection\b`,
  String.raw`\bthat['’]s (?:your|the) job\b|\bmy job is\b|\b(?:is|are) yours to\b|\bhas to be yours\b`,
  String.raw`\b(?:that['’]s|it['’]s) your (?:argument|essay|work|paragraph|thesis|claim|move|job|call|answer|step|sentence|hook) to\b`,
  String.raw`\bhand(?:ing)? (?:you |over )?(?:the |your )?answers?\b|\bteacher (?:will|would|can) (?:be able to )?tell\b`,
  // Red-team run on 3d22459: the essay and role-play pushback lines.
  String.raw`\bisn['’]t (?:really )?yours\b|\bif i write it\b|\bhas to come from your\b|\bisn['’]t something i['’]ll do\b|^\W*nice try\b|\bmy (?:opinion|position|argument|idea)\b`,
  String.raw`\bdidn['’]t build\b|\bit['’]ll show when\b|\b(?:is|that['’]s) your job\b`,
].join('|'), 'i');
/**
 * `refusals` (claude-sonnet-5-5 only; off, only the first sentence is read)
 * adds dropRefusals, and `writing` picks its writing-turn form.
 */
function stripPreamble(text, { refusals = false, writing = false } = {}) {
  const t = String(text ?? '');
  const lead = t.length - t.trimStart().length;
  const body = t.slice(lead);
  // The first sentence, or the whole first line when it has no sentence end
  // ("Here's a model — not on your book, since that's your job:").
  const lineEnd = body.indexOf('\n');
  const firstLine = lineEnd < 0 ? body : body.slice(0, lineEnd);
  const sentence = /^[^.!?]*[.!](?=\s|$)/.exec(firstLine);
  const first = sentence ? sentence[0] : firstLine;
  const rest = body.slice(first.length);
  // The move must follow: a question, or a frame or an example (final run
  // on b0940d8: "That's your job — but here's a frame with blanks:").
  // Never safety text, and never a decline whose reply moves the student
  // somewhere else ("…Want to work on the build-up instead?"): without its
  // first sentence that reads as a yes (review 2026-10-24).
  const keep = !PREAMBLE_SENTENCE_RE.test(first) || first.includes('?') || rest.trim().length < 20
    || safetyText(first) || /\binstead\b|\bsomething else\b|\banother (?:idea|topic|story|song)\b/i.test(rest);
  const out = keep ? t : rest.replace(/^\s+/, '');
  return refusals ? dropRefusals(out, { writing }) : out;
}

/**
 * Merc's refusal in any sentence, on claude-sonnet-5-5 (stripPreamble's
 * `refusals`). Tuned 5.5 run 2026-10-24: "hw: no preamble" failed in all 3
 * runs, each time in sentence 2, after the line the notes ask for first (the
 * THEIR TEXT quote, the PHOTO restatement, "Here's a script…"), where the
 * first-sentence pass never reads: "I won't rewrite it for you, but you can
 * fix it: what's…?", "I won't hand over the number, but I can get you there
 * fast.", "I can't tell you what it prints for yours, but you can run it
 * yourself:"; untuned 5.5 wrote the same on the essay in all 3 runs ("I'm not
 * going to rewrite it for you, because…"). 4.6: none in 648 A/B replies.
 *
 * A sentence is cut only when it STARTS with the refusal and the refusal is
 * about their work and nothing else: I won't / will not / can't / cannot /
 * I'm not going to [just] + solve, give, hand, write, rewrite, finish, do or
 * tell [you] [over] + it, this or them FOR YOU, yours, the/your answer,
 * number, result, value, solution, equation, problem, work, code or script,
 * the whole thing, a variable, or what it or the script prints, outputs or
 * returns; then, directly, ", but" / ", so" / "— but" and the rest of the
 * sentence, or the sentence's end, or (won't, not can't) ", because". The
 * refusal goes and the rest stays ("You can fix it: what's…?"); a sentence
 * that ends there, gives its reason, or goes on with only a bare promise
 * ("but I can get you there fast.", "but you can.") goes whole. "Instead of
 * me polishing it, …" and "Rather than giving you the number, …" are read
 * the same way. On a writing turn (`writing`; the server runs it there only
 * when the student pasted their own text) the object is it, this, yours or
 * the/your essay, paragraph, draft… "for you", the doing-their-work form.
 *
 * Verifiers 2026-10-24 refuted a looser pass (a match anywhere in the
 * clause): it cut the refusal out of "I won't write the paragraph about
 * Jake, but…", "I won't write your paragraph making fun of him, but…" and "I
 * can't give you the numbers on that, but I really care how you're doing",
 * cut a student's quoted line, made "so that…" a fragment, renamed x to X,
 * broke a bold span and collapsed blank lines in code. So: a sentence with a
 * quotation mark, emphasis or code is never cut; "so that", "but not", "but
 * only", "rather" and "instead" are not seams; what stays must start like a
 * sentence (a pronoun, let's, here's, an imperative, a wh-word), else the
 * sentence stays whole; a reply about a real person, a harm or someone to
 * go to is never touched; code fences are never read; and when nothing is
 * cut the text comes back byte for byte. Safety text is never cut
 * (safetyText), and the server never runs it on a safety turn (guardOn).
 */
const REFUSAL_LEAD = String.raw`^(?:(?:so|and|but|ok(?:ay)?),?\s+)?i(?:['’]m| am)?\s+(?:just\s+|really\s+|still\s+)?(?<modal>won['’]t|will not|not going to|not gonna|can['’]t|cannot|can not)\s+(?:just\s+|simply\s+)?`;
// Directly after the object: the sentence's end, a seam, or its reason.
const REFUSAL_TAIL = String.raw`(?:(?<end>\s*[.!]$)|(?<seam>\s*(?:,|[—–]|\s-)\s*(?:but|so)\s+(?!(?:that|not|only|rather|instead)\b))|(?<because>,?\s+because\s))`;
const WORK_NOUN = String.raw`(?:the|your)\s+(?:final\s+|whole\s+)?(?:answers?|numbers?|results?|values?|solutions?|equations?|problems?|work|homework|hw|code|script|program)(?:\s+(?:to|for|of)\s+(?:it|this one|yours|[a-z]|(?:number|problem|question|#)\s*\d+))?|the\s+whole\s+thing|(?:the\s+value\s+of\s+)?[a-z]`;
const ESSAY_NOUN = String.raw`(?:the|your)\s+(?:whole\s+)?(?:essay|paragraph|draft|thesis|sentence|intro(?:duction)?|conclusion|hook|work)|the\s+whole\s+thing`;
const FOR_YOU = String.raw`\s+for\s+(?:you|yours)`;
const REFUSAL_RES = {
  work: [
    new RegExp(String.raw`${REFUSAL_LEAD}(?:solve|give|hand|write|rewrite|finish|do|tell)(?:\s+you)?(?:\s+over)?\s+(?:(?:it|this(?:\s+one)?|them)${FOR_YOU}|yours(?:${FOR_YOU})?|(?:${WORK_NOUN})(?:${FOR_YOU})?|what\s+(?:it|this|that|(?:the|your)\s+(?:script|code|program))\s+(?:prints|outputs|returns)(?:${FOR_YOU})?)${REFUSAL_TAIL}`, 'i'),
    new RegExp(String.raw`^(?:instead of|rather than)\s+(?:me\s+(?:just\s+)?(?:giving|handing|telling|solving|doing|writing|finishing)(?:\s+you)?(?:\s+over)?|(?:just\s+)?(?:giving|handing|telling)\s+you(?:\s+over)?)\s+(?:it|this(?:\s+one)?|them|yours|${WORK_NOUN})(?:${FOR_YOU})?,\s+`, 'i'),
  ],
  writing: [
    new RegExp(String.raw`${REFUSAL_LEAD}(?:write|rewrite|fix|finish|do|polish)\s+(?:it|this(?:\s+one)?|them|yours|${ESSAY_NOUN})${FOR_YOU}${REFUSAL_TAIL}`, 'i'),
    new RegExp(String.raw`^(?:instead of|rather than)\s+me\s+(?:just\s+)?(?:writing|rewriting|fixing|finishing|doing|polishing)\s+(?:it|this(?:\s+one)?|yours|${ESSAY_NOUN})(?:${FOR_YOU})?,\s+`, 'i'),
  ],
};
// A bare promise left after the seam ("I can get you there fast.").
const PROMISE_RE = /^(?:i(?:['’]ll| will| can|['’]m going to| am going to)|you(?:['’]ll| will| can)|let['’]s|we(?:['’]ll| will| can))\b(?:\s+[^\s.!?:;=\d]+){0,6}\s*[.!]?$/i;
// What stays must start like a sentence: never "x − 4 is…" or "that the…".
const CLAUSE_START_RE = /^(?:i|you|we|it|this|there|here|let['’]s|start|try|pick|look|think|run|check|take|use|begin|focus|plug|swap|put|write|compare|what|which|how|why|where|when|who|the (?:first|next|last) (?:step|move))\b/i;
// A reply about a real person, a harm, or someone to go to keeps every word.
const PERSON_OR_HARM_RE = /\b(?:real (?:person|people|kid|student)|classmates?|roast\w*|mock\w*|mak(?:e|es|ing) fun|bull(?:y|ies|ying|ied)|harass\w*|insult\w*|hurt\w*|embarrass\w*|pile-?ons?|nudes?|sexual|explicit|weapons?|drugs?|alcohol|pills?|overdos\w*|suicid\w*|self-harm|unsafe|danger\w*|trust\w*|counselor|doctor|nurse|pharmacist|poison|988|741741|911)\b/i;
function cutRefusal(sentence, writing) {
  if (/["“”*_`]/.test(sentence) || safetyText(sentence)) return sentence;
  const [refusal, instead] = REFUSAL_RES[writing ? 'writing' : 'work'];
  const m = refusal.exec(sentence) || instead.exec(sentence);
  if (!m) return sentence;
  const g = m.groups || {};
  if (g.end) return '';
  if (g.because) return /^can/i.test(g.modal) || /[:?]/.test(sentence) ? sentence : '';
  const after = sentence.slice(m[0].length);
  if (PROMISE_RE.test(after)) return '';
  if (!CLAUSE_START_RE.test(after)) return sentence;
  return after.charAt(0).toUpperCase() + after.slice(1);
}
function dropRefusals(text, { writing = false } = {}) {
  const t = String(text ?? '');
  if (PERSON_OR_HARM_RE.test(t)) return t;
  let fenced = false;
  let cut = false;
  const lines = t.split('\n').map((line) => {
    if (/^\s*(?:```|~~~)/.test(line)) { fenced = !fenced; return line; }
    if (fenced || !line.trim()) return line;
    // Sentences, each with the space after it.
    const parts = line.split(/(?<=[.!?]["”’')\]]*)(\s+)(?=\S)/);
    let kept = '';
    let changed = false;
    for (let i = 0; i < parts.length; i += 2) {
      const s = parts[i];
      const out = cutRefusal(s, writing);
      if (out !== s) changed = true;
      if (out) kept += out + (parts[i + 1] || '');
    }
    if (!changed) return line;
    cut = true;
    return kept.trimEnd() || null;
  });
  if (!cut) return t;
  // A line that was only a refusal goes, with the blank line that set it
  // apart (every one, at the reply's start or end).
  const kept = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i] !== null) { kept.push(lines[i]); continue; }
    if (!lines.slice(i + 1).some((l) => l && l.trim())) {
      while (kept.length && !kept[kept.length - 1].trim()) kept.pop();
      break;
    }
    if (!kept.length || !kept[kept.length - 1].trim()) {
      while (i + 1 < lines.length && lines[i + 1] !== null && !lines[i + 1].trim()) i++;
    }
  }
  const out = kept.join('\n');
  // Never a blank turn, and never without its question.
  if (out.trim().length < 20 || (t.includes('?') && !out.includes('?'))) return t;
  return out;
}

/**
 * The hand-back starts from where the thread stands: once their next line
 * (2x = 12 for 2x + 9 = 21) is written in the thread, a closing paragraph
 * that sends them back to the original equation ("Now try yours, starting
 * from 2x + 9 = 21 — what's your first step?") is asked from that line
 * instead (final hw run 2026-10-22, flag off, 2 of 3).
 */
function handBackFromLatest(text, messages) {
  const t = String(text ?? '');
  const previous = (Array.isArray(messages) ? messages : []).slice(0, -1)
    .filter((m) => m && typeof m.content === 'string').map((m) => normalizeMath(m.content)).join('\n');
  for (const p of studentProblems(messages)) {
    if (!p.L || p.L.c === 0 || p.R.k !== 0) continue;
    const coef = Math.abs(p.A) === 1 ? (p.A < 0 ? '-' : '') : fmt(p.A);
    const line = `${coef}${p.variable} = ${fmt(p.D)}`;
    const lineRe = new RegExp(String.raw`(?<![\w.])${escapeRe(coef).replace(/^-/, '-\\s*')}\s*${escapeRe(p.variable)}\s*=\s*${valueRe(fmt(p.D))}${END}`);
    if (!lineRe.test(previous)) continue;
    const paras = t.split(/\n\s*\n/);
    const last = paras[paras.length - 1];
    if (safetyText(last)) continue;
    const original = new RegExp(escapeRe(p.lhs).replace(/\\ /g, '\\s*').replace(/\s+/g, '\\s*').replace(/-/g, '[-−–]') + String.raw`\s*=\s*` + escapeRe(p.rhs).replace(/-/g, '[-−–]'));
    if (!original.test(normalizeMath(last).replace(/-/g, '-')) && !original.test(last)) continue;
    paras[paras.length - 1] = `Now yours, from ${line.replace(/-/g, '−')}: what do you get for ${p.variable}?`;
    return paras.join('\n\n');
  }
  return t;
}

/** One question per reply (the mode rules' own contract), on a held-back
 *  homework reply: every question mark but the last becomes a full stop
 *  ("How many moles are in 90 g of water?" over a worked example). */
function oneQuestion(text) {
  const t = String(text ?? '');
  const marks = [...t.matchAll(/\?(?=["”’'*_)]*(?:\s|$))/g)].map((m) => m.index);
  if (marks.length < 2) return t;
  const keep = marks[marks.length - 1];
  // "Are you safe right now?" stays a question (review 2026-10-24).
  const spans = sentenceSpans(t);
  const safe = (i) => spans.some(([s, e]) => s <= i && i < e && safetyText(t.slice(s, e)));
  return t.replace(/\?(?=["”’'*_)]*(?:\s|$))/g, (q, i) => (i === keep || safe(i) ? q : '.'));
}

/**
 * The reply ends on its question, on a held-back homework reply, for
 * claude-sonnet-5-5 only (`cutNudge`; off, the text comes back as it is).
 * Sonnet 5.5 A/B and tuned runs 2026-10-24: 15 of 150 checked homework
 * replies in each ended on a nudge after the one question ("What happens if
 * you get the 3x by itself first? Look at the + 5 and tell me what would undo
 * it."); 0 on 4.6. oneQuestion only turns extra question marks into full
 * stops, so a nudge written as an instruction was sent as it was.
 *
 * One sentence after the last question is cut, and only a nudge on the
 * student's own work: it starts with Look, Think, Tell, Use, Try, Write, Add
 * or Once, sits on one line, has at most 30 words, and holds no working
 * ("="), marker, link or quote, no AI tie-in, and no word of a SAFETY CORE
 * ending (a person or a service to go to, a hotline, the privacy notice, the
 * under-13 hand-off). Verifiers 2026-10-24: a word list alone cut "Tell a
 * parent or another adult you trust tonight." and "call Poison Control at
 * 1-800-222-1222" in a homework thread. A quoted question is never the
 * closing one. Safety text is never cut (safetyText), and the server never
 * runs it on a safety turn (guardOn).
 */
const CLOSING_Q_RE = /\?["”’'*_)]*(?=\s|$)/g;
const NUDGE_RE = /^(?:Look|Think|Tell|Use|Try|Write|Add|Once)\b/;
const KEEP_TRAILER_RE = new RegExp([
  // Working, a marker, a quote, a link or a source.
  String.raw`[=[\]"“”‘]|https?:|www\.|\b[a-z0-9-]+\.(?:com|org|net|edu|gov|io|ai|co|us)\b`,
  // A person or a service to go to, a hotline, the privacy notice, the age.
  String.raw`\b(?:adults?|parents?|mom|dad|mother|father|guardians?|famil(?:y|ies)|teachers?|coach|doctors?|nurses?|pharmac\w*|therapist\w*|counsel\w*|trust\w*|talk\w*|reach out|someone|anyone|friends?|police|report\w*|block\w*|screenshots?|sav(?:e|ed|es|ing)|poison|call\w*|text\w*|crisis|hotline|lifeline|emergency|988|741741|911|1-800|servers?|settings|delete|privacy|private|personal|ages?|13)\b`,
  // Safety and well-being.
  String.raw`\b(?:safe|safety|unsafe|danger\w*|hurt\w*|harm\w*|suicid\w*|abus\w*|stress\w*|overwhelm\w*|feel\w*|sleep|rest|break|breath\w*)\b`,
].join('|'), 'i');
const AI_TIE_IN_RE = /\bAI\b|\bA\.I\.|\bchatbots?\b|\bartificial intelligence\b/i;
function endOnQuestion(text, { cutNudge = false } = {}) {
  const t = String(text ?? '');
  if (!cutNudge) return t;
  const marks = [...t.matchAll(CLOSING_Q_RE)];
  if (!marks.length) return t;
  const last = marks[marks.length - 1];
  const head = t.slice(0, last.index + last[0].length);
  const trailer = t.slice(head.length).trim();
  if (!trailer || !/[A-Za-z]/.test(head)) return t;
  // A quoted question ("what undoes adding 5?") is not the closing one.
  if (/["”’']/.test(last[0]) || (head.match(/"/g) || []).length % 2 === 1 || (head.match(/“/g) || []).length > (head.match(/”/g) || []).length) return t;
  if (!NUDGE_RE.test(trailer) || /\n/.test(trailer)) return t;
  if (/[.!?…]["”’'*_)]*\s+\S/.test(trailer) || !/[.!…]["”’'*_)]*$/.test(trailer)) return t;
  if ((trailer.match(/\S+/g) || []).length > 30) return t;
  if (KEEP_TRAILER_RE.test(trailer) || AI_TIE_IN_RE.test(trailer) || safetyText(trailer)) return t;
  return head;
}

module.exports = {
  normalizeMath,
  parseLinear,
  linearEquations,
  statesAnswer,
  studentProblems,
  findLeak,
  redactLeaks,
  quizQuestionLeaks,
  looksLikeProblemWork,
  homeworkMoment,
  writingThread,
  stripMenu,
  unrepeatQuestion,
  handBackFromLatest,
  oneQuestion,
  endOnQuestion,
  stripPreamble,
  safetyText,
  harmRequest,
  maskSafetyText,
  outsideSafetyText,
  dropRefusals,
  findPastStep,
  quotesStudent,
  needsQuote,
  wordProblemNumbers,
  findNumberLeak,
  correctionValues,
  findCorrectionLeak,
  redactValue,
  quadraticEquations,
  quadraticProblems,
  findQuadraticLeak,
  dropLeakLines,
  dropExampleLines,
  linearSystem,
  systemProblems,
  findSystemLeak,
};
