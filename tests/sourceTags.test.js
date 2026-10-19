'use strict';

// AUD-38 (audit 2026-10): iOS showed "[SOURCE: label — domain/path]" as raw
// bracket text, sometimes with an invented URL path. lib/sourceTags.js
// rewrites each tag for blocks_v1 clients as plain text with the label and
// the domain only.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  createSourceRewriter, rewriteSources, parseSourceTag, formatSource, contextOf,
  REWRITTEN_SOURCE_RE, ENDS_WITH_REWRITTEN_SOURCE_RE, MAX_TAG_CHARS,
} = require('../lib/sourceTags');

// Every distinct real tag in the audit transcripts and docs/evals, with
// what a student now reads when it stands on its own line.
const REAL_TAGS = [
  ['White House Executive Order on AI — whitehouse.gov/briefing-room/presidential-actions/2023/10/30/executive-order-on-the-safe-secure-and-trustworthy-development-and-use-of-artificial-intelligence',
    'Source: White House Executive Order on AI (whitehouse.gov)'],
  ["Stanford's 2023 honor code revision explicitly acknowledged AI didn't *create* academic dishonesty, it just made existing behavior more visible — hai.stanford.edu/research/ai-education",
    "Source: Stanford's 2023 honor code revision explicitly acknowledged AI didn't *create* academic dishonesty, it just made existing behavior more visible (hai.stanford.edu)"],
  ['Mata v. Avianca — the case behind AI hallucination in law — courtlistener.com/docket/67219/mata-v-avianca-inc',
    'Source: Mata v. Avianca — the case behind AI hallucination in law (courtlistener.com)'],
  ['Mata v. Avianca — the case behind the lawyers story: courtlistener.com/docket/16708263/mata-v-avianca-inc',
    'Source: Mata v. Avianca — the case behind the lawyers story (courtlistener.com)'],
  ['ProPublica "Machine Bias" — propublica.org/article/machine-bias-risk-assessments-in-criminal-sentencing',
    'Source: ProPublica "Machine Bias" (propublica.org)'],
  ['NIST Face Recognition Vendor Testing — nist.gov/programs-projects/face-recognition-vendor-testing-frvt',
    'Source: NIST Face Recognition Vendor Testing (nist.gov)'],
  ['Reuters reporting — reuters.com/article/us-amazon-com-jobs-automation-insight-idUSKCN1MK08G',
    'Source: Reuters reporting (reuters.com)'],
  ['"Lost in the Middle: How Language Models Use Long Contexts" — arxiv.org/abs/2307.03172',
    'Source: "Lost in the Middle: How Language Models Use Long Contexts" (arxiv.org)'],
  ['"On the Dangers of Stochastic Parrots" — dl.acm.org/doi/10.1145/3442188.3445922',
    'Source: "On the Dangers of Stochastic Parrots" (dl.acm.org)'],
  ['MIT Technology Review — technologyreview.com/topic/artificial-intelligence',
    'Source: MIT Technology Review (technologyreview.com)'],
  ['OpenAI Help Center — help.openai.com/en/articles/7730893', 'Source: OpenAI Help Center (help.openai.com)'],
  ['Attention Is All You Need — arxiv.org/abs/1706.03762', 'Source: Attention Is All You Need (arxiv.org)'],
  ['AI Now Institute annual reports — ainowinstitute.org', 'Source: AI Now Institute annual reports (ainowinstitute.org)'],
  ['Elements of AI (free course) — elementsofai.com', 'Source: Elements of AI (free course) (elementsofai.com)'],
  ['Stanford HAI AI Index — aiindex.stanford.edu', 'Source: Stanford HAI AI Index (aiindex.stanford.edu)'],
  ['Chalkbeat NYC coverage — chalkbeat.org', 'Source: Chalkbeat NYC coverage (chalkbeat.org)'],
  ['Algorithmic Justice League — ajl.org', 'Source: Algorithmic Justice League (ajl.org)'],
  ['Gender Shades — gendershades.org', 'Source: Gender Shades (gendershades.org)'],
];

function streamed(text, sizes) {
  const r = createSourceRewriter();
  let out = '';
  let i = 0;
  let k = 0;
  while (i < text.length) {
    const n = sizes[k % sizes.length];
    out += r.push(text.slice(i, i + n));
    i += n;
    k += 1;
  }
  return out + r.flush();
}

describe('sourceTags: the rewrite (AUD-38)', () => {
  test('every real tag from the audit corpus: label kept, path dropped', () => {
    for (const [inner, expected] of REAL_TAGS) {
      const out = rewriteSources(`Intro sentence here.\n\n[SOURCE: ${inner}]\n\nNext?`);
      assert.equal(out, `Intro sentence here.\n\n${expected}\n\nNext?`);
      assert.ok(!/\[SOURCE/.test(out));
      const domain = /\(([^()]+)\)$/.exec(expected)[1];
      assert.ok(!out.includes(`${domain}/`), `no URL path after ${domain}`);
    }
  });

  test('the invented docket numbers from the hallucination lesson never reach the student', () => {
    const out = rewriteSources("That's exactly the skill this lesson is about.\n\n[SOURCE: Mata v. Avianca — the case behind the lawyers story: courtlistener.com/docket/16708263/mata-v-avianca-inc]");
    assert.ok(!/16708263|docket/.test(out), out);
    assert.ok(out.endsWith('Source: Mata v. Avianca — the case behind the lawyers story (courtlistener.com)'));
  });

  test('the form follows where the tag sits', () => {
    const cases = [
      // own line
      ['[SOURCE: Gender Shades — gendershades.org]', 'Source: Gender Shades (gendershades.org)'],
      // after a sentence
      ['Error rates were 34% higher. [SOURCE: Gender Shades — gendershades.org]', 'Error rates were 34% higher. Source: Gender Shades (gendershades.org)'],
      ['He said "it works." [SOURCE: Gender Shades — gendershades.org]', 'He said "it works." Source: Gender Shades (gendershades.org)'],
      // mid-sentence
      ['Regulators approved COMPAS [SOURCE: Machine Bias — propublica.org/article/x] while its bias problems were known.',
        'Regulators approved COMPAS (Source: Machine Bias, propublica.org) while its bias problems were known.'],
      ['more than 34% — [SOURCE: Gender Shades — gendershades.org].', 'more than 34% — (Source: Gender Shades, gendershades.org).'],
      // inside the model's own parentheses
      ["I'll grant the bias ([SOURCE: NIST FRVT — nist.gov/programs-projects/frvt]), and then",
        "I'll grant the bias (Source: NIST FRVT, nist.gov), and then"],
      // after a label or a block marker
      ['**Impact:** [SOURCE: Stanford HAI — hai.stanford.edu]', '**Impact:** Source: Stanford HAI (hai.stanford.edu)'],
      ['[EX][SOURCE: Gender Shades — gendershades.org] shows the gap.[/EX]', '[EX]Source: Gender Shades (gendershades.org) shows the gap.[/EX]'],
      // two in a row
      ['[SOURCE: A — a.org] [SOURCE: B — b.org]', 'Source: A (a.org) (Source: B, b.org)'],
    ];
    for (const [input, expected] of cases) assert.equal(rewriteSources(input), expected, input);
  });

  test('tags without a domain keep the label; an empty tag is dropped', () => {
    assert.equal(rewriteSources('ProPublica found bias. [SOURCE: propublica-2016] What follows?'), 'ProPublica found bias. Source: propublica-2016 What follows?');
    assert.equal(rewriteSources('Fact [SOURCE: NIST 2024] here.'), 'Fact (Source: NIST 2024) here.');
    assert.equal(rewriteSources('Fact. [SOURCE: ]'), 'Fact. ');
    assert.equal(rewriteSources('Fact. [SOURCE:]'), 'Fact. ');
  });

  test('parseSourceTag: separators, schemes, www, a bare domain', () => {
    assert.deepEqual(parseSourceTag('Learn Prompting - learnprompting.org'), { label: 'Learn Prompting', domain: 'learnprompting.org' });
    assert.deepEqual(parseSourceTag('Nature, https://www.nature.com/articles/s41586'), { label: 'Nature', domain: 'nature.com' });
    assert.deepEqual(parseSourceTag('Gender Shades (gendershades.org)'), { label: 'Gender Shades', domain: 'gendershades.org' });
    assert.deepEqual(parseSourceTag('UNESCO | unesco.org/en/x'), { label: 'UNESCO', domain: 'unesco.org' });
    assert.deepEqual(parseSourceTag('read it at ajl.org/about'), { label: 'read it at', domain: 'ajl.org' });
    assert.deepEqual(parseSourceTag('gendershades.org'), { label: '', domain: 'gendershades.org' });
    // Not an address: "U.S." and "v." stay in the label.
    assert.deepEqual(parseSourceTag('U.S. Copyright Office report'), { label: 'U.S. Copyright Office report', domain: '' });
    assert.deepEqual(parseSourceTag('Mata v. Avianca'), { label: 'Mata v. Avianca', domain: '' });
  });

  test('formatSource and contextOf', () => {
    assert.equal(formatSource('Gender Shades — gendershades.org', 'line'), 'Source: Gender Shades (gendershades.org)');
    assert.equal(formatSource('Gender Shades — gendershades.org', 'inline'), '(Source: Gender Shades, gendershades.org)');
    assert.equal(formatSource('Gender Shades — gendershades.org', 'paren'), 'Source: Gender Shades, gendershades.org');
    assert.equal(contextOf(''), 'line');
    assert.equal(contextOf('end.\n'), 'line');
    assert.equal(contextOf('end.)  '), 'line');
    assert.equal(contextOf('see ('), 'paren');
    assert.equal(contextOf('[KEY]'), 'line');
    assert.equal(contextOf('approved COMPAS '), 'inline');
  });
});

describe('sourceTags: what passes through', () => {
  test('text that only looks like a tag is untouched', () => {
    for (const text of [
      'A [SOURCE: broken\nacross lines] tag',
      'A [SOURCE: nested [x] — x.org] tag',
      '[SOURCES] and [Source: lower — x.org] and [SOURCE without colon]',
      `Runaway [SOURCE: ${'x'.repeat(MAX_TAG_CHARS)}] tag`,
      'Ends mid-tag [SOURCE: Gender Sha',
      'Ends on a bracket [',
      'Ends on [SOURCE',
    ]) {
      assert.equal(rewriteSources(text), text, JSON.stringify(text.slice(0, 60)));
      assert.equal(streamed(text, [1]), text);
      assert.equal(streamed(text, [3, 7]), text);
    }
  });

  test('a real tag after a runaway one is still rewritten', () => {
    const text = `Runaway [SOURCE: ${'x'.repeat(MAX_TAG_CHARS)}\n\nFact. [SOURCE: Gender Shades — gendershades.org]`;
    const out = rewriteSources(text);
    assert.ok(out.endsWith('Fact. Source: Gender Shades (gendershades.org)'));
    assert.equal(streamed(text, [1]), out);
    assert.equal(streamed(text, [MAX_TAG_CHARS - 2, 5]), out);
  });
});

describe('sourceTags: chunk boundaries', () => {
  const REPLY = 'Facial analysis erred far more on darker-skinned women. [SOURCE: Gender Shades — gendershades.org]\n\n' +
    'Regulators approved COMPAS [SOURCE: Machine Bias — propublica.org/article/machine-bias-risk-assessments-in-criminal-sentencing] while its bias problems were known ' +
    '([SOURCE: NIST FRVT — nist.gov/programs-projects/face-recognition-vendor-testing-frvt]).\n\n[SOURCE: Algorithmic Justice League — ajl.org]\n\nWho checks the checker?';

  test('every two-way split equals the one-shot result', () => {
    const oneShot = rewriteSources(REPLY);
    assert.ok(!oneShot.includes('[SOURCE'));
    for (let cut = 0; cut <= REPLY.length; cut += 1) {
      const r = createSourceRewriter();
      assert.equal(r.push(REPLY.slice(0, cut)) + r.push(REPLY.slice(cut)) + r.flush(), oneShot, `cut at ${cut}`);
    }
  });

  test('random chunkings (fuzz) equal the one-shot result; no raw tag text is ever emitted', () => {
    const oneShot = rewriteSources(REPLY);
    let seed = 7;
    const rand = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
    for (let run = 0; run < 300; run += 1) {
      const r = createSourceRewriter();
      let out = '';
      let i = 0;
      while (i < REPLY.length) {
        const n = 1 + Math.floor(rand() * 25);
        out += r.push(REPLY.slice(i, i + n));
        i += n;
        assert.ok(!out.includes('[S'), `run ${run}: raw tag text emitted`);
      }
      out += r.flush();
      assert.equal(out, oneShot, `run ${run}`);
    }
  });
});

describe('sourceTags: the eval metrics read the rewritten forms', () => {
  test('REWRITTEN_SOURCE_RE matches every form the rewrite writes, and nothing else in the reply', () => {
    const out = rewriteSources('One. [SOURCE: Elements of AI (free course) — elementsofai.com]\n\nTwo [SOURCE: Machine Bias — propublica.org/x] three.\n\n[SOURCE: Gender Shades — gendershades.org]');
    const stripped = out.replace(REWRITTEN_SOURCE_RE, '#');
    assert.equal(stripped, 'One. #\n\nTwo # three.\n\n#');
  });

  test('ENDS_WITH_REWRITTEN_SOURCE_RE: a reply that ends on a source ended on purpose', () => {
    for (const ending of ['[SOURCE: Gender Shades — gendershades.org]', 'Fact. [SOURCE: Gender Shades — gendershades.org]',
      'A fact [SOURCE: Gender Shades — gendershades.org]', 'Fact.\n[SOURCE: NIST 2024]']) {
      assert.ok(ENDS_WITH_REWRITTEN_SOURCE_RE.test(rewriteSources(ending)), ending);
    }
    assert.ok(!ENDS_WITH_REWRITTEN_SOURCE_RE.test('The Source: of the Nile is'));
  });
});
