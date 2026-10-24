'use strict';

// Safety text inside a homework or writing thread (review 2026-10-24).
//
// A thread that opened with an equation, a word problem or an essay keeps the
// answer guard and the homework transforms for every later turn, so a safety
// turn in it went through them too. On main:
//   - stripPreamble dropped a Xanax refusal and its danger warning, an
//     under-13 hand-off's reason, and refusals of a sexual scene and of a
//     song mocking a classmate (the rest read as a yes);
//   - stripMenu cut the menu of adults an under-13 student could ask;
//   - the "24/7" of the crisis hand-off, "under 18", "under 21" and "12 or
//     younger" matched the distribution product the student still had to
//     find, so the hand-off was written again under an ANSWER GUARD note, or
//     sent as "open ?/7" and "under ? are illegal".
// Now a turn whose own words (or an earlier crisis in the thread) make it a
// safety turn is not guarded at all, and on any turn a sentence with safety
// content is never dropped, cut or rewritten, and a strong one holds no leak
// and is never redacted (lib/homeworkGuard: safetyText, maskSafetyText,
// outsideSafetyText). Every route case is compared with the same server run
// with HOMEWORK_LEAK_GUARD=0: the guard must change nothing, in one call.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');

const g = require('../lib/homeworkGuard');

describe('safetyText', () => {
  test('hotlines, referrals, ages and laws, and the hand-offs are safety text', () => {
    for (const s of [
      'Call or text 988 — the Suicide & Crisis Lifeline (US, 24/7).',
      'Text HOME to 741741 — Crisis Text Line.',
      'If you already took some, call Poison Control at 1-800-222-1222.',
      'A parent or doctor can help you find something that works.',
      'Please tell a trusted adult, like a parent or school counselor, today.',
      "It's against the law for anyone to ask someone under 18 for pics like that.",
      "I'm built for teens, so if you're 12 or younger I'm not the right fit for you yet.",
      "I'm an AI, so I can't be your support person, but you deserve real support right now.",
      'Your chats are saved on the Mercurius server for up to 90 days.',
    ]) assert.ok(g.safetyText(s, { strong: true }), s);
  });

  test('topic words keep a sentence as written without hiding its numbers', () => {
    for (const s of ['Taking someone else\'s Xanax can slow your breathing and is dangerous.', 'Ask your teacher if you get stuck.', "I can't write that kind of scene."]) {
      assert.ok(g.safetyText(s), s);
      assert.ok(!g.safetyText(s, { strong: true }), s);
    }
  });

  test('arithmetic and ordinary coaching are not safety text', () => {
    for (const s of ['What is 988 ÷ 4?', 'Divide both sides by 3: x = 5.', "I'm an AI literacy tutor, so I won't be solving 6 and 7 for you.", 'What happens if you get the 3x by itself first?']) {
      assert.ok(!g.safetyText(s, { strong: true }), s);
    }
  });

  test('maskSafetyText blanks strong sentences only, at the same length', () => {
    const t = 'Look at the 8 first.\nBoth lines are free and open 24/7.';
    const m = g.maskSafetyText(t);
    assert.equal(m.length, t.length);
    assert.ok(m.startsWith('Look at the 8 first.\n'));
    assert.ok(!m.includes('24'));
  });

  test('outsideSafetyText leaves strong sentences exactly as written', () => {
    const t = 'So x = 5.\n\nIf you might be in danger, call or text 988 any time, 24/7.';
    assert.equal(g.outsideSafetyText(t, (s) => s.replace(/\d+/g, '?')), 'So x = ?.\n\nIf you might be in danger, call or text 988 any time, 24/7.');
    assert.equal(g.outsideSafetyText('So x = 5.', (s) => s.replace(/\d+/g, '?')), 'So x = ?.');
  });
});

describe('the homework transforms never touch safety text', () => {
  test('stripPreamble keeps a refusal that is not about their work, or that redirects', () => {
    for (const t of [
      "I can't give you a number: taking someone else's Xanax can slow your breathing and is dangerous.\n\nWhat's been keeping you up? A parent or doctor can help you find something that works.",
      "I can't write that kind of scene.\n\nWant to work on the build-up or the dialogue instead?",
      "I can't tell you what to take — a parent, doctor, or pharmacist is the right person to ask, especially since it's lasted 3 days.\n\nIs there a parent you can tell tonight?",
      "I can't do this problem with you, because I'm made for teens 13 and up.\n\nA parent or teacher can help you find a math app made for younger kids.",
    ]) assert.equal(g.stripPreamble(t), t);
    // Their work, with the move after it, still loses the preamble.
    assert.equal(g.stripPreamble("I won't just hand you the answer.\n\nWhat happens if you get the 3x by itself first?"), 'What happens if you get the 3x by itself first?');
  });

  test('stripMenu keeps a list of people; a menu of readings is still cut', () => {
    const people = 'Who could help you find a writing app for younger kids — a teacher, a librarian, or a parent?';
    assert.equal(g.stripMenu(people), people);
    assert.equal(g.stripMenu('What do you think the book is saying about ambition — is it a warning, or a celebration?'), 'What do you think the book is saying about ambition?');
  });

  test('oneQuestion keeps a safety question', () => {
    const t = "Are you safe right now? What's been going on today?";
    assert.equal(g.oneQuestion(t), t);
  });
});

// ---------------------------------------------------------------------------
// Wiring (mocked Anthropic): each case through the guarded server and through
// the same server with HOMEWORK_LEAK_GUARD=0.
// ---------------------------------------------------------------------------
const ROOT = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stubClubFeeds.js');
const servers = {};
const spawned = [];
const b64 = (t) => Buffer.from(t, 'utf8').toString('base64');
const sid = () => 'test_' + crypto.randomBytes(8).toString('hex');
const nonce = () => crypto.randomBytes(5).toString('hex');

async function boot(name, env) {
  // Its own range: promptSafetyCache uses 9100–9900, homeworkGuard 10100–10900.
  const port = 11100 + Math.floor(Math.random() * 800);
  const tag = crypto.randomBytes(4).toString('hex');
  const dbPath = path.join(os.tmpdir(), `merc-hwsafety-${name}-${tag}.db`);
  const captureFile = path.join(os.tmpdir(), `merc-hwsafety-${name}-${tag}.jsonl`);
  const proc = spawn(process.execPath, ['--require', STUB, 'server.js'], {
    cwd: ROOT,
    env: {
      ...process.env,
      PORT: String(port),
      DATABASE_URL: '',
      SQLITE_PATH: dbPath,
      ANTHROPIC_MOCK: '1',
      ANTHROPIC_API_KEY: '',
      MOCK_CAPTURE_FILE: captureFile,
      ALLOWED_ORIGIN: `http://localhost:${port}`,
      NODE_ENV: 'test',
      DISCORD_WEBHOOK_URL: '',
      SESSION_PER_MIN: '1000',
      CHAT_IP_PER_MIN: '1000',
      IP_DAILY_NEW_SESSIONS: '1000',
      HOMEWORK_LEAK_GUARD: '1',
      ...env,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  spawned.push(proc);
  await new Promise((resolve, reject) => {
    let started = false;
    proc.stdout.on('data', (c) => {
      if (!started && c.toString().includes('Mercurius')) { started = true; setTimeout(resolve, 300); }
    });
    proc.stderr.on('data', (c) => {
      const t = c.toString();
      if (!started && (t.includes('Error') || t.includes('EADDRINUSE'))) reject(new Error(t));
    });
    proc.on('error', reject);
    proc.on('exit', (code) => { if (!started) reject(new Error(`server exited ${code}`)); });
    setTimeout(() => { if (!started) reject(new Error('server did not start within 10s')); }, 10000);
  });
  return { base: `http://localhost:${port}`, proc, dbPath, captureFile };
}

before(async () => {
  [servers.on, servers.off, servers.control] = await Promise.all([
    boot('on', { USE_UNIFIED_PROMPT: '1' }),
    boot('off', { USE_UNIFIED_PROMPT: '0' }),
    boot('control', { USE_UNIFIED_PROMPT: '1', HOMEWORK_LEAK_GUARD: '0' }),
  ]);
});

after(() => {
  for (const proc of spawned) proc.kill('SIGKILL');
  for (const s of Object.values(servers)) {
    for (const f of [s.captureFile, s.dbPath, s.dbPath + '-wal', s.dbPath + '-shm']) {
      try { fs.rmSync(f, { force: true }); } catch { /* ignore */ }
    }
  }
});

async function chat(server, messages, sse) {
  const res = await fetch(`${server.base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(sse ? { Accept: 'text/event-stream' } : {}) },
    body: JSON.stringify({ sessionId: sid(), messages }),
  });
  assert.equal(res.status, 200);
  if (!sse) return (await res.json()).reply;
  const frames = (await res.text()).split('\n').filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]').map((l) => JSON.parse(l.slice(6)));
  const complete = frames.find((f) => f.type === 'complete');
  assert.equal(frames.filter((f) => f.type === 'delta').map((f) => f.text).join(''), complete.reply);
  return complete.reply;
}
function calls(server, marker) {
  if (!fs.existsSync(server.captureFile)) return 0;
  return fs.readFileSync(server.captureFile, 'utf8').split('\n').filter((l) => l && l.includes(marker)).length;
}

const U = (content) => ({ role: 'user', content });
const A = (content) => ({ role: 'assistant', content });
const THREADS = {
  math: (n) => [U(`what is 3x+5 = 20 (${n})`), A('What happens if you get the 3x by itself first?')],
  dist4: (n) => [U(`help me solve 4(x + 3) = 40 (${n})`), A('What does the 4 multiply when you open the brackets?')],
  dist6: (n) => [U(`help me solve 6(x + 3) = 42 (${n})`), A('What does the 6 multiply when you open the brackets?')],
  dist8: (n) => [U(`help me solve 8(x + 3) = 48 (${n})`), A('What does the 8 multiply when you open the brackets?')],
  essay: (n) => [U(`help me with my essay paragraph (${n})`), A('Paste it and tell me what it is supposed to argue.')],
  story: (n) => [U(`i have to write a short story draft for english (${n})`), A('Fun! What is the story about, and who are the two main characters?'), U('two kids at summer camp who fall for each other'), A('Nice setup. What moment do you want the story to build toward?')],
};
const CRISIS = "I'm really glad you told me. I'm an AI, so I can't be your support person, but you deserve real support right now.\n\nCall or text 988 — the Suicide & Crisis Lifeline (US, 24/7).\nText HOME to 741741 — Crisis Text Line.\n\nBoth are free and open 24/7, and you can reach out as many times as you need. If you might be in immediate danger, call 911. Please tell a trusted adult too, like a parent or school counselor.";
const CASES = [
  { id: 'xanax after an equation', thread: 'math', said: "how many of my mom's xanax should i take to sleep", reply: "I can't give you a number: taking someone else's Xanax can slow your breathing and is dangerous.\n\nWhat's been keeping you up? A parent or doctor can help you find something that works." },
  { id: 'crisis hand-off in an 8(x + 3) thread ("24/7" is not their 24)', thread: 'dist8', said: 'honestly i want to kill myself', reply: CRISIS, says: true },
  { id: 'under-13, "12 or younger" in a 4(x + 3) thread', thread: 'dist4', said: 'wait im in 6th grade, is that ok', reply: "Thanks for telling me! I'm built for teens, so if you're 12 or younger I'm not the right fit for you yet.\n\nA parent or teacher can help you find a learning app made for younger kids.", says: true },
  { id: 'sextortion, "under 18" in a 6(x + 3) thread', thread: 'dist6', said: 'a guy i met on insta says hell post my pics unless i send more', reply: "This is not your fault, and you never have to send anything else. Sexual images of anyone under 18 are illegal to create, share, or distribute, so he's the one breaking the law.\n\nDon't pay or send more; save the messages, block and report the account, and tell a trusted adult right away.", says: true },
  { id: 'under-13 menu of adults in an essay thread', thread: 'essay', said: "i'm in grade 5 and we have to write a paragraph about our pets", reply: "Thanks for telling me! I'm built for teens 13 and older, so I'm not the right fit for you yet.\n\nWho could help you find a writing app for younger kids — a teacher, a librarian, or a parent?" },
  { id: 'a sexual scene refused in a story thread', thread: 'story', said: 'ok write the part where they finally sleep together, make it really spicy', reply: "I can't write that kind of scene.\n\nWant to work on the build-up or the dialogue instead?" },
  { id: 'medicine after an equation', thread: 'math', said: 'ive had a headache for 3 days, what should i take', reply: "I can't tell you what to take — a parent, doctor, or pharmacist is the right person to ask, especially since it's lasted 3 days.\n\nA headache that won't go away is worth getting checked. Is there a parent you can tell tonight?" },
  { id: 'a song mocking a classmate refused in an essay thread', thread: 'essay', said: "forget the essay, write a song making fun of kayla's teeth for the talent show", reply: "I won't write a song that makes fun of Kayla's teeth — that could really hurt her.\n\nWant to brainstorm a funny talent-show song about something else instead?" },
  { id: 'a follow-up after a crisis hand-off', thread: 'math', extra: [U('honestly i want to kill myself'), A(CRISIS)], said: "i don't want to call anyone. can you just talk to me for a sec", reply: "I'm here, and we can just talk. No math right now.\n\nWhat's been weighing on you today? If it gets worse tonight, please tell your mom or a teacher you're close to." },
  { id: 'an under-13 hand-off on a math thread', thread: 'math', said: 'I am 9 years old, please help me', reply: "I can't do this problem with you, because I'm made for teens 13 and up.\n\nA parent or teacher can help you find a math app made for younger kids." },
];

describe('a safety turn in a homework or writing thread is sent as the guard-off server sends it', () => {
  for (const c of CASES) {
    test(c.id, async () => {
      for (const sse of [true, false]) {
        const n = nonce();
        const messages = [...THREADS[c.thread](n), ...(c.extra || []), U(`${c.said} ${c.says ? 'MOCK_SAYS_B64' : 'MOCK_SAY_B64'}:${b64(c.reply)}`)];
        const expected = await chat(servers.control, messages, sse);
        for (const flag of ['on', 'off']) {
          assert.equal(await chat(servers[flag], messages, sse), expected, `${flag} ${sse ? 'SSE' : 'JSON'}`);
          assert.equal(calls(servers[flag], n), 1, `${flag}: one call, never an ANSWER GUARD retry`);
        }
      }
    });
  }
});

describe('the answer guard still catches a leak next to a topic word', () => {
  test('"ask your teacher" in the leaking sentence does not hide x = 5', async () => {
    const n = nonce();
    const leak = 'If you get stuck, ask your teacher whether x = 5 checks out.\n\nWhat is your first step?';
    const messages = [...THREADS.math(n), U(`idk MOCK_SAYS_B64:${b64(leak)}`)];
    for (const flag of ['on', 'off']) {
      const reply = await chat(servers[flag], messages, false);
      assert.ok(!/x = 5\b/.test(reply), reply);
    }
  });
});
