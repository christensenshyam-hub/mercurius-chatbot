'use strict';

/**
 * In-process stand-in for the Anthropic SDK client (ops/safety-rails).
 *
 * With ANTHROPIC_MOCK=1 the server can be booted and integration-tested with
 * NO API key and NO network: every route that talks to Claude gets a
 * deterministic, request-shaped reply, and the failure modes the safety rails
 * exist for (5xx, 529 overloaded, credit exhaustion, a stalled stream) can be
 * forced from the environment instead of waited for in production.
 *
 * The mock mirrors exactly the SDK surface server.js uses (v0.39):
 *
 *   client.messages.create(params)            → Promise<Message>
 *   client.messages.stream(params, { signal }) → MockMessageStream
 *
 * MockMessageStream reproduces lib/MessageStream.js: the event ORDER
 *   'streamEvent'(message_start) → 'streamEvent'(content_block_start)
 *   → ['streamEvent'(content_block_delta), 'text'] × N
 *   → 'streamEvent'(content_block_stop), 'contentBlock'
 *   → 'streamEvent'(message_delta)  ← carries usage.output_tokens
 *   → 'streamEvent'(message_stop), 'message'
 *   → 'finalMessage' → 'end'
 * the flags (`ended` / `errored` / `aborted` — on an abort the SDK sets BOTH
 * errored and aborted, and so does this), `abort()`, `done()`,
 * `finalMessage()`, `finalText()`, `emitted()`, async iteration, and the SDK's
 * "'end' follows 'error' AND 'abort'" rule that server.js's end-handler relies
 * on. Errors are real SDK APIError instances (err.status, err.error = the wire
 * body `{ type:'error', error:{ type, message } }`) when the SDK is installed.
 *
 * Usage semantics follow the real API: `input_tokens` counts only the
 * UNCACHED input; a system block carrying `cache_control` is billed to
 * `cache_creation_input_tokens` the first time this process sees that exact
 * text and to `cache_read_input_tokens` on every later call. All counts are
 * chars / 3.8 (image blocks count as a fixed 1200 tokens).
 *
 * Reply shaping (deterministic — no randomness anywhere):
 *   - curriculum ('[CURRICULUM' in the system prompt, or the last user turn
 *     starts with '[CURRICULUM:') → two short paragraphs + a [CHECK]…[/CHECK]
 *     line; from the 5th user turn on, a trailing [LESSON_COMPLETE].
 *   - JSON routes ('JSON' in the system prompt, or in the user turn when there
 *     is no system prompt — memory extraction) → a payload the matching
 *     server.js parser accepts: quiz / report-card / concept-map / unit-test
 *     grade / factcheck / analyze / pre-briefing / memory array. Unknown JSON
 *     prompts get the quiz shape.
 *   - anything else → a 2–3 sentence Socratic reply ending in one question.
 *
 * Env:
 *   ANTHROPIC_MOCK=1           → isMockEnabled() (the integration step swaps
 *                                the real client for createMockClient()).
 *   MOCK_SCENARIO              → 'ok' (default) | 'error' | 'overloaded' |
 *                                'slow' | 'hang' | 'credit'
 *   MOCK_STREAM_DELAY_MS       → ms between streamed text deltas (default 5;
 *                                'slow' multiplies by 20)
 *   MOCK_TIMEOUT_MS            → how long a 'hang' create() waits before it
 *                                fails like the SDK's client timeout would
 *                                (default 30000, the server's client timeout)
 */

const { EventEmitter } = require('node:events');
const crypto = require('node:crypto');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const SCENARIOS = Object.freeze(['ok', 'error', 'overloaded', 'slow', 'hang', 'credit']);
const CHARS_PER_TOKEN = 3.8;
const IMAGE_BLOCK_TOKENS = 1200;   // rough real-API cost of a ~1000px image
const CHUNK_CHARS = 12;
const SLOW_MULTIPLIER = 20;
const DEFAULT_DELAY_MS = 5;
const DEFAULT_TIMEOUT_MS = 30000;
const LESSON_COMPLETE_AFTER_USER_TURNS = 5;

const CREDIT_MESSAGE =
  'Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.';

// The real SDK is a dependency, so its error classes are normally available;
// the fallback keeps the mock usable if it ever is not (same public fields).
let SdkErrors = null;
try {
  SdkErrors = require('@anthropic-ai/sdk');
} catch {
  SdkErrors = null;
}

// ---------------------------------------------------------------------------
// Env + helpers
// ---------------------------------------------------------------------------
function isMockEnabled() {
  return process.env.ANTHROPIC_MOCK === '1';
}

function tokens(chars) {
  return Math.max(1, Math.round(chars / CHARS_PER_TOKEN));
}

function sha(text) {
  return crypto.createHash('sha256').update(String(text)).digest('hex');
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Text of a system prompt (string or array of {type:'text', text}) — the
// shape server.js sends under USE_UNIFIED_PROMPT (two blocks, first cached).
function systemBlocks(system) {
  if (!system) return [];
  if (typeof system === 'string') return [{ type: 'text', text: system }];
  if (Array.isArray(system)) return system.filter((b) => b && b.type === 'text' && typeof b.text === 'string');
  return [];
}

function systemText(system) {
  return systemBlocks(system).map((b) => b.text).join('\n');
}

// Text of a message's content (string, or an array of content blocks — the
// vision path sends [{type:'image'}, {type:'text'}] on the current turn).
function contentText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .filter((b) => b && b.type === 'text' && typeof b.text === 'string')
    .map((b) => b.text)
    .join('\n');
}

function contentChars(content) {
  if (typeof content === 'string') return content.length;
  if (!Array.isArray(content)) return 0;
  let chars = 0;
  for (const b of content) {
    if (!b) continue;
    if (b.type === 'text' && typeof b.text === 'string') chars += b.text.length;
    else if (b.type === 'image') chars += IMAGE_BLOCK_TOKENS * CHARS_PER_TOKEN;
  }
  return chars;
}

// ---------------------------------------------------------------------------
// Errors — real SDK classes when available (err.status, err.error, headers)
// ---------------------------------------------------------------------------
class FallbackAPIError extends Error {
  constructor(status, error, message, headers) {
    super(status ? `${status} ${JSON.stringify(error)}` : message);
    this.name = 'APIError';
    this.status = status;
    this.error = error;
    this.headers = headers;
    this.request_id = headers ? headers['request-id'] : undefined;
  }
}

function requestId(seed) {
  return 'req_mock_' + sha(seed).slice(0, 16);
}

// Build an API error exactly as the SDK would from an HTTP error response:
// `error` is the wire body { type:'error', error:{ type, message } }.
function apiError(status, type, message, seed = '') {
  const body = { type: 'error', error: { type, message } };
  const headers = { 'request-id': requestId(seed + status) };
  if (SdkErrors && SdkErrors.APIError && typeof SdkErrors.APIError.generate === 'function') {
    return SdkErrors.APIError.generate(status, body, undefined, headers);
  }
  return new FallbackAPIError(status, body, undefined, headers);
}

function abortError() {
  if (SdkErrors && SdkErrors.APIUserAbortError) return new SdkErrors.APIUserAbortError();
  const err = new FallbackAPIError(undefined, undefined, 'Request was aborted.', undefined);
  err.name = 'APIUserAbortError';
  return err;
}

function timeoutError() {
  if (SdkErrors && SdkErrors.APIConnectionTimeoutError) return new SdkErrors.APIConnectionTimeoutError();
  const err = new FallbackAPIError(undefined, undefined, 'Request timed out.', undefined);
  err.name = 'APIConnectionTimeoutError';
  return err;
}

function scenarioError(scenario, seed) {
  switch (scenario) {
    case 'error':
      return apiError(500, 'api_error', 'Internal server error', seed);
    case 'overloaded':
      return apiError(529, 'overloaded_error', 'Overloaded', seed);
    case 'credit':
      return apiError(400, 'invalid_request_error', CREDIT_MESSAGE, seed);
    default:
      return null;
  }
}

// Minimal mirror of the API's request validation — the two 400s server.js
// has actually been bitten by (see its comments around messages[0].role).
function validateParams(params, seed) {
  if (!params || typeof params !== 'object') {
    return apiError(400, 'invalid_request_error', 'messages: Field required', seed);
  }
  if (!Array.isArray(params.messages) || params.messages.length === 0) {
    return apiError(400, 'invalid_request_error', 'messages: at least one message is required', seed);
  }
  if (params.messages[0].role !== 'user') {
    return apiError(400, 'invalid_request_error', 'messages: first message must use the "user" role', seed);
  }
  if (!Number.isInteger(params.max_tokens) || params.max_tokens < 1) {
    return apiError(400, 'invalid_request_error', 'max_tokens: Input should be greater than or equal to 1', seed);
  }
  if (params.timeout !== undefined) {
    return apiError(400, 'invalid_request_error', 'timeout: Extra inputs are not permitted', seed);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Prompt-cache accounting — module-level, one Set per process
// ---------------------------------------------------------------------------
const seenCachedBlocks = new Set();

function computeUsage(params, replyText) {
  let uncachedChars = 0;
  let creation = 0;
  let read = 0;
  for (const block of systemBlocks(params.system)) {
    if (block.cache_control) {
      const key = sha(block.text);
      const t = tokens(block.text.length);
      if (seenCachedBlocks.has(key)) {
        read += t;
      } else {
        seenCachedBlocks.add(key);
        creation += t;
      }
    } else {
      uncachedChars += block.text.length;
    }
  }
  for (const m of params.messages || []) uncachedChars += contentChars(m.content);
  return {
    input_tokens: tokens(uncachedChars),
    cache_creation_input_tokens: creation,
    cache_read_input_tokens: read,
    output_tokens: tokens(replyText.length),
  };
}

// ---------------------------------------------------------------------------
// Reply generation — shaped by the request, deterministic
// ---------------------------------------------------------------------------
function userMessages(params) {
  return (params.messages || []).filter((m) => m && m.role === 'user');
}

function lastUserText(params) {
  const users = userMessages(params);
  return users.length ? contentText(users[users.length - 1].content) : '';
}

// Leading filler that never names a topic ("tell me about", "what is a").
const TOPIC_STOPWORDS = new Set([
  'a', 'an', 'the', 'about', 'and', 'can', 'could', 'do', 'does', 'explain', 'give', 'help', 'how', 'i', 'is', 'are',
  'learn', 'me', 'my', 'of', 'please', 'should', 'so', 'teach', 'tell', 'to', 'us', 'want', 'what', 'whats', 'why',
  'with', 'would', 'you',
]);

// A short, stable "topic" lifted from the first user turn (used to make the
// quiz / map / report look like they came from THIS conversation).
function topicOf(params) {
  const users = userMessages(params);
  const first = users.length ? contentText(users[0].content) : '';
  const words = first
    .replace(/^\[CURRICULUM:[^\]]*\]\s*/, '')
    .replace(/[^A-Za-z0-9 ]+/g, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  while (words.length && TOPIC_STOPWORDS.has(words[0].toLowerCase())) words.shift();
  const topic = words.slice(0, 3);
  return topic.length ? topic.join(' ') : 'AI Literacy';
}

// Echoed fragment of what the student said — terminal punctuation dropped so
// the reply still contains exactly one question mark (its own).
function snippet(text, max = 60) {
  const clean = String(text).replace(/\s+/g, ' ').trim().replace(/[.?!]+$/, '');
  if (clean.length <= max) return clean;
  return clean.slice(0, max - 1).trimEnd() + '…';
}

function isCurriculum(params) {
  return systemText(params.system).includes('[CURRICULUM') || lastUserText(params).startsWith('[CURRICULUM:');
}

function wantsJson(params) {
  const sys = systemText(params.system);
  if (sys) return sys.includes('JSON');
  // No system prompt at all → the instruction lives in the user turn
  // (server.js's background memory extraction).
  return lastUserText(params).includes('JSON');
}

function curriculumTag(params) {
  for (const m of userMessages(params)) {
    const match = contentText(m.content).match(/^\[CURRICULUM:\s*([^\]]+)\]/);
    if (match) return match[1].trim();
  }
  return 'this lesson';
}

const CHECK_QUESTIONS = [
  'What is the one assumption this idea depends on?',
  'Where would this break if the input data changed?',
  'How would you explain this to someone who has never used an AI tool?',
  'What evidence would make you doubt this claim?',
];

function curriculumReply(params) {
  const turn = userMessages(params).length;
  const tag = curriculumTag(params);
  const check = CHECK_QUESTIONS[(turn - 1) % CHECK_QUESTIONS.length];
  const lines = [
    `Good — that moves us forward in ${tag}. Here is the next idea: a model does not look answers up, it predicts what comes next from patterns in its training data.`,
    `Concrete example: given "The cat sat on the", the model assigns a high probability to "mat" because that sequence was common in its training text, not because it knows anything about cats.`,
    `[CHECK]${check}[/CHECK]`,
  ];
  if (turn >= LESSON_COMPLETE_AFTER_USER_TURNS) lines.push('[LESSON_COMPLETE]');
  return lines.join('\n\n');
}

const SOCRATIC_QUESTIONS = [
  'What would have to be true for that to hold in every case?',
  'Where do you think that claim came from — evidence, or a pattern you noticed?',
  'What is one example that might push back on it?',
];

function socraticReply(params) {
  const turn = userMessages(params).length;
  const said = snippet(lastUserText(params));
  const question = SOCRATIC_QUESTIONS[(turn - 1) % SOCRATIC_QUESTIONS.length];
  const opener = said
    ? `You said "${said}" — let's slow that down before we go further.`
    : "Let's start by pinning down what we actually mean here.";
  return `${opener} The interesting part is the assumption underneath it, not the conclusion. ${question}`;
}

// --- JSON routes -----------------------------------------------------------

function quizJson(params) {
  const topic = topicOf(params);
  return {
    title: `${topic} Quiz`,
    questions: [
      {
        q: 'What does a language model actually do when it answers?',
        options: ['A) Predicts likely next tokens', 'B) Searches a database', 'C) Runs a fixed script', 'D) Asks a human'],
        answer: 'A',
        explanation: 'It predicts the next token from patterns in training data.',
      },
      {
        q: 'Why can a confident answer still be wrong?',
        options: ['A) Confidence is random', 'B) Fluency is not accuracy', 'C) Models never err', 'D) It is always right'],
        answer: 'B',
        explanation: 'Fluent text is generated whether or not the facts are correct.',
      },
      {
        q: 'What is training data?',
        options: ['A) Live internet access', 'B) The model weights', 'C) Text the model learned patterns from', 'D) User settings'],
        answer: 'C',
        explanation: 'Training data is the corpus the model learned its patterns from.',
      },
      {
        q: 'Which habit best evaluates an AI claim?',
        options: ['A) Trust the tone', 'B) Count the words', 'C) Share it quickly', 'D) Ask for a checkable source'],
        answer: 'D',
        explanation: 'Checkable sources let you verify instead of trusting fluency.',
      },
    ],
  };
}

function reportCardJson(params) {
  const topic = topicOf(params);
  const turns = userMessages(params).length;
  return {
    overallGrade: turns >= 4 ? 'B+' : 'B',
    summary: `Explored ${topic} with steady engagement`,
    strengths: ['Asked clarifying questions', 'Used concrete examples'],
    areasToRevisit: ['Training data vs retrieval'],
    conceptsCovered: ['Next-token prediction', 'Training data', 'Confidence vs accuracy'],
    criticalThinkingScore: 72,
    curiosityScore: 85,
    misconceptionsAddressed: [],
    nextSessionSuggestion: 'Explore how models are evaluated',
  };
}

function conceptMapJson(params) {
  return {
    central: topicOf(params),
    nodes: [
      { id: 'n1', label: 'Next-token prediction', group: 'core' },
      { id: 'n2', label: 'Training data', group: 'core' },
      { id: 'n3', label: 'Hallucination', group: 'related' },
      { id: 'n4', label: 'Autocomplete', group: 'example' },
    ],
    edges: [
      { from: 'central', to: 'n1', label: 'includes' },
      { from: 'n2', to: 'n1', label: 'shapes' },
      { from: 'n1', to: 'n3', label: 'can cause' },
      { from: 'n1', to: 'n4', label: 'resembles' },
    ],
  };
}

function unitTestGradeJson(params) {
  const text = lastUserText(params);
  const match = text.match(/<student_answer>\s*([\s\S]*?)\s*<\/student_answer>/);
  const answer = (match ? match[1] : text).trim();
  // Short or empty answers fail (the grader prompt's own rule); anything with
  // real substance passes with a B so both client paths are reachable.
  const pass = answer.length >= 40;
  return pass
    ? { grade: 'B', pass: true, feedback: 'Clear reasoning that engages the question; add one concrete example to reach an A.' }
    : { grade: 'D', pass: false, feedback: 'The answer is too brief to show understanding — explain your reasoning in a few sentences.' };
}

function factcheckJson(params) {
  const claim = snippet(lastUserText(params).replace(/^Fact-check this claim:\s*/, ''), 50);
  return {
    verdict: 'nuanced',
    verdictLabel: 'Nuanced',
    summary: 'Partly true but oversimplified — the details matter',
    breakdown: [
      { claim: claim || 'The submitted claim', status: 'partial', explanation: 'True in some cases, missing key context' },
    ],
    nuances: 'Claims about AI often generalize from one system to all of them.',
    literacyLesson: 'Ask which system, which data, and which evidence before accepting a claim.',
  };
}

function analyzeJson() {
  return {
    overallAssessment: 'decent',
    summary: 'Fluent and organized but asserts more certainty than it earns',
    issues: [
      { type: 'overconfidence', description: 'States a contested point as settled', quote: null },
      { type: 'missing_context', description: 'No sources or dates for its claims', quote: null },
      { type: 'good', description: 'Clear structure and plain language', quote: null },
    ],
    confidenceFlags: 'The response sounds most certain exactly where it offers no evidence.',
    missingPerspectives: 'The people affected by the decision are not represented.',
    literacyLesson: 'Fluent prose is not the same as verified fact — check the claims, not the tone.',
  };
}

function preBriefingJson() {
  return {
    meetingTitle: 'Mock Club Meeting',
    date: 'Thursday, March 26',
    bullets: [
      { heading: 'Background you need', body: 'Review how language models generate text and why fluency differs from accuracy. Bring one example of an AI claim you have seen this week.' },
      { heading: 'The key debate', body: 'Should schools treat AI tools as calculators or as ghostwriters? Both sides have real evidence — be ready to argue either.' },
      { heading: 'What to watch for', body: 'Notice when a claim about AI generalizes from one system to all of them. That pattern drives most of the hype.' },
    ],
    keyQuestion: 'What evidence would change your mind about AI in school?',
    suggestedTopicToDiscuss: 'How to check an AI claim in under five minutes',
  };
}

function memoryJson(params) {
  const text = lastUserText(params);
  const match = text.match(/Student message:\s*"([\s\S]*?)"\s*\n/);
  const said = snippet(match ? match[1] : '', 40);
  return said
    ? [{ type: 'topic', content: said }]
    : [];
}

function jsonReply(params) {
  const sys = systemText(params.system);
  const user = lastUserText(params);
  let payload;
  if (!sys && (user.includes('memory objects') || user.includes('JSON array'))) payload = memoryJson(params);
  else if (sys.includes('"overallGrade"') || sys.includes('report card')) payload = reportCardJson(params);
  else if (sys.includes('"nodes"') || sys.includes('concept map')) payload = conceptMapJson(params);
  else if (sys.includes('"grade"') || sys.includes('"defense"')) payload = unitTestGradeJson(params);
  else if (sys.includes('"verdict"') || sys.includes('fact-checking')) payload = factcheckJson(params);
  else if (sys.includes('"overallAssessment"')) payload = analyzeJson();
  else if (sys.includes('"meetingTitle"') || sys.includes('pre-meeting briefing')) payload = preBriefingJson();
  else payload = quizJson(params);   // default JSON shape
  return JSON.stringify(payload);
}

function buildReply(params) {
  if (isCurriculum(params)) return curriculumReply(params);
  if (wantsJson(params)) return jsonReply(params);
  return socraticReply(params);
}

function buildMessage(params) {
  const text = buildReply(params);
  const seed = JSON.stringify({ s: params.system, m: params.messages });
  return {
    id: 'msg_mock_' + sha(seed).slice(0, 24),
    type: 'message',
    role: 'assistant',
    model: params.model,
    content: [{ type: 'text', text, citations: null }],
    stop_reason: 'end_turn',
    stop_sequence: null,
    usage: computeUsage(params, text),
  };
}

// ---------------------------------------------------------------------------
// MockMessageStream — the SDK's MessageStream surface on an EventEmitter
// ---------------------------------------------------------------------------
class MockMessageStream extends EventEmitter {
  constructor() {
    super();
    this.messages = [];
    this.receivedMessages = [];
    this.controller = new AbortController();
    this._ended = false;
    this._errored = false;
    this._aborted = false;
    this._catching = false;
    this._snapshot = undefined;
    this._timer = null;
    this._queue = [];
    this._endPromise = new Promise((resolve, reject) => {
      this._resolveEnd = resolve;
      this._rejectEnd = reject;
    });
    // As in the SDK: never let the end promise itself surface as unhandled.
    this._endPromise.catch(() => {});
    this.controller.signal.addEventListener('abort', () => this._onAbort());
  }

  get ended() { return this._ended; }
  get errored() { return this._errored; }
  get aborted() { return this._aborted; }
  get currentMessage() { return this._snapshot; }

  abort() {
    this.controller.abort();
  }

  async done() {
    this._catching = true;
    await this._endPromise;
  }

  async finalMessage() {
    await this.done();
    if (this.receivedMessages.length === 0) {
      throw new Error('stream ended without producing a Message with role=assistant');
    }
    return this.receivedMessages[this.receivedMessages.length - 1];
  }

  async finalText() {
    const message = await this.finalMessage();
    const blocks = message.content.filter((b) => b.type === 'text').map((b) => b.text);
    if (blocks.length === 0) throw new Error('stream ended without producing a content block with type=text');
    return blocks.join(' ');
  }

  emitted(event) {
    return new Promise((resolve, reject) => {
      this._catching = true;
      if (event !== 'error') this.once('error', reject);
      this.once(event, resolve);
    });
  }

  // Async iteration over streamEvents, as in the SDK (return() aborts).
  [Symbol.asyncIterator]() {
    const pushQueue = [];
    const readQueue = [];
    let done = false;
    this.on('streamEvent', (event) => {
      const reader = readQueue.shift();
      if (reader) reader.resolve(event);
      else pushQueue.push(event);
    });
    const finish = (err) => {
      done = true;
      for (const reader of readQueue) (err ? reader.reject(err) : reader.resolve(undefined));
      readQueue.length = 0;
    };
    this.on('end', () => finish());
    this.on('abort', (err) => finish(err));
    this.on('error', (err) => finish(err));
    return {
      next: async () => {
        if (!pushQueue.length) {
          if (done) return { value: undefined, done: true };
          return new Promise((resolve, reject) => readQueue.push({ resolve, reject }))
            .then((chunk) => (chunk ? { value: chunk, done: false } : { value: undefined, done: true }));
        }
        return { value: pushQueue.shift(), done: false };
      },
      return: async () => {
        this.abort();
        return { value: undefined, done: true };
      },
    };
  }

  // -- internals -----------------------------------------------------------

  // SDK _emit semantics: nothing after 'end'; 'abort'/'error' reject the end
  // promise, trigger an unhandled rejection when nobody is listening, and are
  // always followed by 'end'.
  _emit(event, ...args) {
    if (this._ended) return;
    if (event === 'end') {
      this._ended = true;
      this._resolveEnd();
    }
    const hasListeners = this.listenerCount(event) > 0;
    if (hasListeners) super.emit(event, ...args);
    if (event === 'abort' || event === 'error') {
      const err = args[0];
      if (!this._catching && !hasListeners) Promise.reject(err);
      this._rejectEnd(err);
      this._emit('end');
    }
  }

  // Terminal failure. The SDK flags an abort as errored AND aborted, then
  // emits 'abort' (never 'error') for it — server.js keys off both flags.
  _fail(err, { abort = false } = {}) {
    if (this._ended) return;
    this._clearTimer();
    this._queue = [];
    this._errored = true;
    if (abort) {
      this._aborted = true;
      this._emit('abort', err);
      return;
    }
    this._emit('error', err);
  }

  _onAbort() {
    if (this._ended) return;
    this._clearTimer();
    this._queue = [];
    // The real abort surfaces asynchronously (the fetch rejects on a later
    // tick), so the caller's synchronous code after abort() runs first.
    queueMicrotask(() => this._fail(abortError(), { abort: true }));
  }

  _clearTimer() {
    if (this._timer) {
      clearTimeout(this._timer);
      this._timer = null;
    }
  }

  // Run queued steps; a step with a delay is scheduled, the rest fire in turn.
  _pump() {
    this._timer = null;
    while (this._queue.length && !this._ended) {
      const step = this._queue.shift();
      if (step.delay > 0) {
        this._timer = setTimeout(() => {
          this._timer = null;
          step.fn();
          this._pump();
        }, step.delay);
        return;
      }
      step.fn();
    }
  }

  _streamEvent(event) {
    if (this._ended) return;
    const snapshot = this._accumulate(event);
    this._emit('streamEvent', event, snapshot);
    switch (event.type) {
      case 'content_block_delta': {
        const block = snapshot.content[snapshot.content.length - 1];
        if (event.delta.type === 'text_delta' && block.type === 'text') {
          this._emit('text', event.delta.text, block.text || '');
        }
        break;
      }
      case 'content_block_stop':
        this._emit('contentBlock', snapshot.content[snapshot.content.length - 1]);
        break;
      case 'message_stop':
        this.messages.push(snapshot);
        this.receivedMessages.push(snapshot);
        this._emit('message', snapshot);
        break;
      default:
        break;
    }
  }

  _accumulate(event) {
    if (event.type === 'message_start') {
      this._snapshot = event.message;
      return this._snapshot;
    }
    const snapshot = this._snapshot;
    switch (event.type) {
      case 'message_delta':
        snapshot.stop_reason = event.delta.stop_reason;
        snapshot.stop_sequence = event.delta.stop_sequence;
        snapshot.usage.output_tokens = event.usage.output_tokens;
        return snapshot;
      case 'content_block_start':
        snapshot.content.push(event.content_block);
        return snapshot;
      case 'content_block_delta': {
        const block = snapshot.content[event.index];
        if (block && block.type === 'text' && event.delta.type === 'text_delta') block.text += event.delta.text;
        return snapshot;
      }
      default:
        return snapshot;
    }
  }

  _finish() {
    if (this._ended) return;
    const final = this.receivedMessages[this.receivedMessages.length - 1];
    if (final) this._emit('finalMessage', final);
    this._emit('end');
  }

  // Plan the whole stream up front from the finished message, then pump.
  _run({ params, options, scenario, delayMs, message, error }) {
    for (const m of (params && params.messages) || []) this.messages.push(m);

    const signal = options && options.signal;
    if (signal) {
      if (signal.aborted) this.controller.abort();
      else signal.addEventListener('abort', () => this.controller.abort());
    }
    // Already aborted → the queued microtask emits 'abort' + 'end'; no work.
    if (this.controller.signal.aborted) return;

    const q = this._queue;
    if (error) {
      q.push({ delay: delayMs, fn: () => this._fail(error) });
      this._pump();
      return;
    }

    const full = message.content[0].text;
    const chunks = [];
    for (let i = 0; i < full.length; i += CHUNK_CHARS) chunks.push(full.slice(i, i + CHUNK_CHARS));
    const hang = scenario === 'hang';

    // Time-to-first-token, then the snapshot the SDK would build.
    q.push({
      delay: delayMs,
      fn: () => this._streamEvent({
        type: 'message_start',
        message: {
          id: message.id,
          type: 'message',
          role: 'assistant',
          model: message.model,
          content: [],
          stop_reason: null,
          stop_sequence: null,
          usage: { ...message.usage, output_tokens: 1 },
        },
      }),
    });
    q.push({
      delay: 0,
      fn: () => this._streamEvent({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '', citations: null } }),
    });
    chunks.forEach((text, i) => {
      // A stalled upstream: one chunk arrives, then nothing until abort().
      if (hang && i > 0) return;
      q.push({
        delay: i === 0 ? 0 : delayMs,
        fn: () => this._streamEvent({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text } }),
      });
    });
    if (hang) {
      this._pump();
      return;
    }
    q.push({ delay: 0, fn: () => this._streamEvent({ type: 'content_block_stop', index: 0 }) });
    q.push({
      delay: 0,
      fn: () => this._streamEvent({
        type: 'message_delta',
        delta: { stop_reason: 'end_turn', stop_sequence: null },
        usage: { output_tokens: message.usage.output_tokens },
      }),
    });
    q.push({ delay: 0, fn: () => this._streamEvent({ type: 'message_stop' }) });
    q.push({ delay: 0, fn: () => this._finish() });
    this._pump();
  }
}

// ---------------------------------------------------------------------------
// Client factory
// ---------------------------------------------------------------------------
function resolveScenario(raw) {
  const s = String(raw || 'ok').toLowerCase();
  return SCENARIOS.includes(s) ? s : 'ok';
}

function createMockClient({
  scenario = process.env.MOCK_SCENARIO || 'ok',
  delayMs = Number(process.env.MOCK_STREAM_DELAY_MS) || DEFAULT_DELAY_MS,
  timeoutMs = Number(process.env.MOCK_TIMEOUT_MS) || DEFAULT_TIMEOUT_MS,
} = {}) {
  const active = resolveScenario(scenario);
  const step = active === 'slow' ? delayMs * SLOW_MULTIPLIER : delayMs;

  async function create(params) {
    const seed = JSON.stringify(params && params.messages);
    const invalid = validateParams(params, seed);
    if (invalid) throw invalid;
    const failure = scenarioError(active, seed);
    await delay(step);
    if (failure) throw failure;
    if (active === 'hang') {
      // Headers never arrive → the SDK's client timeout fires.
      await delay(Math.max(0, timeoutMs - step));
      throw timeoutError();
    }
    return buildMessage(params);
  }

  function stream(params, options) {
    const s = new MockMessageStream();
    const seed = JSON.stringify(params && params.messages);
    const error = validateParams(params, seed) || scenarioError(active, seed);
    const message = error ? null : buildMessage(params);
    s._run({ params, options, scenario: active, delayMs: step, message, error });
    return s;
  }

  return {
    mock: true,
    scenario: active,
    messages: { create, stream },
  };
}

// Test-only: forget which cached system blocks this process has "created".
function __resetForTest() {
  seenCachedBlocks.clear();
}

module.exports = {
  createMockClient,
  isMockEnabled,
  MockMessageStream,
  SCENARIOS,
  buildReply,
  __resetForTest,
};
