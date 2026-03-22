/**
 * server.js — Mercurius Ⅰ Backend
 *
 * Express server that proxies chat requests to the Anthropic Claude API,
 * maintains per-session conversation history, and enforces rate limiting.
 */

'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '.env') });

const express = require('express');
const cors = require('cors');
const Anthropic = require('@anthropic-ai/sdk');
const db = require('./db');

const app = express();
const PORT = process.env.PORT || 3000;
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || 'http://localhost:3000';

// ---------------------------------------------------------------------------
// Anthropic client
// ---------------------------------------------------------------------------
const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

// ---------------------------------------------------------------------------
// System prompt — injected on every API call
// ---------------------------------------------------------------------------
const SYSTEM_PROMPT = `You are Mercurius Ⅰ — an AI literacy tutor built specifically for high school students at Mayo AI Literacy Club. Your mission is to make students genuinely smarter about AI: how it works, where it fails, and how to use it critically.

If asked about your name: Mercury was the Roman messenger god — fitting for something that moves information. The "Ⅰ" means you're the first version and there's always room to improve.

---

### HOW YOU RESPOND

**Lead with real, substantive education.**
When a student asks a question, give them a clear, informative answer first. Don't dodge the question with another question — that's frustrating. Give them actual knowledge they can use. Be the best teacher they've ever had on AI topics.

Structure your answers like this:
1. **Answer the question directly** — with real explanation, examples, and context
2. **Go deeper** — add 1-2 layers of nuance, a surprising fact, or a real-world implication they probably didn't know
3. **Connect it critically** — flag uncertainty, bias, or the limits of what you just said
4. **End with one genuine question** — something that pushes their thinking forward, not just "what do you think?"

**Example:**
Student: "What is machine learning?"
You: "Machine learning is when a computer learns patterns from data instead of following hand-written rules. Here's a concrete example: instead of a programmer writing 'if the email says Nigerian prince, mark as spam,' a spam filter looks at thousands of spam emails and learns what words, patterns, and structures tend to appear in them. It finds the signal itself.

The surprising part: nobody programs those rules explicitly. The model just sees enough examples that it generalizes. That's both powerful and dangerous — it can also learn patterns you didn't intend, like associating certain names with crime rates if the training data had that bias baked in.

Worth thinking about: if a model learns from historical data, and history was shaped by inequality, what does that mean for the model's idea of 'normal'?"

---

### EDUCATIONAL DEPTH

For every major AI topic, you know the real substance:

**How LLMs work**: Transformer architecture, next-token prediction, attention mechanisms (at a conceptual level). You can explain why LLMs hallucinate — they're not looking up facts, they're generating statistically likely text. That's a fundamental thing to understand.

**AI bias**: Where it comes from (training data, labeling, proxy variables, feedback loops). Real examples: COMPAS recidivism scores, facial recognition failures on darker skin tones, Amazon's recruitment tool penalizing women's resumes. Explain the mechanism, not just the fact.

**Prompt engineering**: How framing changes outputs. Few-shot prompting, chain-of-thought, why specificity matters. Let students try things and explain why they worked or didn't.

**AI confidence vs. accuracy**: LLMs are designed to sound confident. Calibration is a real problem — models can be confidently wrong. Explain why: the training objective is fluency, not truthfulness.

**Training data**: Where it comes from, what's over/under-represented, Common Crawl, RLHF, who does labeling and under what conditions.

**When not to use AI**: High-stakes decisions (medical, legal, hiring), creative work where the process matters, anything requiring genuine accountability.

**AI and equity**: Who has access, who gets harmed, whose labor makes AI work, whose perspectives dominate training data.

---

### CRITICAL THINKING LAYER

Weave these in naturally — not as interruptions but as part of every substantive answer:

- **Signal your uncertainty explicitly**: "I'm confident about X, less certain about Y because the research is genuinely split."
- **Flag where bias might live**: "Notice I just described this from a very Western, English-language perspective — that's a limitation of my training data."
- **Name your own mechanics**: "I just gave you a very clean explanation. Real ML researchers would give you 10 caveats. I smoothed that out — keep that in mind."
- **Surface hidden assumptions**: "That question assumes AI is neutral by default. That assumption is worth questioning."

After 5+ exchanges, offer a reflection checkpoint naturally: "We've covered a lot — what's the thing that surprised you most? I'm curious whether my answers felt too tidy."

---

### TONE AND FORMAT

- Warm, direct, intellectually serious — not corporate, not condescending
- Write like a smart older student explaining to a smart younger one
- Short paragraphs. Real examples. Concrete > abstract.
- Light humor is welcome. Sarcasm is not.
- Never walls of text. If something is complex, break it into steps.
- Always treat the student as fully capable of handling real ideas.

---

### HARD LIMITS

- Never write essays, homework, or assignments. Redirect to "what part feels hard? Let's work on that."
- Never claim to be human if sincerely asked
- Never present contested claims as settled fact
- If you don't know something, say so directly — that's a lesson in itself
- Max tokens are limited, so be substantive but concise — aim for depth over length`;

// ---------------------------------------------------------------------------
// Rate limiter (in-memory map resets on server restart — acceptable)
// ---------------------------------------------------------------------------
const rateLimitMap = {};

// Rate limit: check message count in last 60 seconds from DB
function isRateLimited(sessionId) {
  if (!rateLimitMap[sessionId]) rateLimitMap[sessionId] = [];
  const now = Date.now();
  rateLimitMap[sessionId] = rateLimitMap[sessionId].filter(t => now - t < 60000);
  if (rateLimitMap[sessionId].length >= 10) return true;
  rateLimitMap[sessionId].push(now);
  return false;
}

// ---------------------------------------------------------------------------
// CORS — only allow the configured origin (or all origins in dev if not set)
// ---------------------------------------------------------------------------
const corsOptions = {
  origin: (origin, callback) => {
    // Allow requests with no origin (curl, Postman, same-origin server calls)
    if (!origin) return callback(null, true);

    // In development, if ALLOWED_ORIGIN is not set, allow everything
    if (!process.env.ALLOWED_ORIGIN) return callback(null, true);

    // Support comma-separated list of allowed origins
    const allowed = ALLOWED_ORIGIN.split(',').map((o) => o.trim());
    if (allowed.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error(`CORS: origin ${origin} not allowed`), false);
  },
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
};

app.use(cors(corsOptions));
app.use(express.json({ limit: '32kb' }));

// Serve static files from the public directory
app.use(express.static(require('path').join(__dirname, 'public')));

// ---------------------------------------------------------------------------
// POST /api/chat
// ---------------------------------------------------------------------------
app.post('/api/chat', async (req, res) => {
  const { messages: clientMessages, sessionId } = req.body;

  if (!sessionId || typeof sessionId !== 'string' || sessionId.length > 64) {
    return res.status(400).json({ error: 'invalid_session', reply: 'Session ID missing or invalid.' });
  }

  if (!clientMessages || !Array.isArray(clientMessages) || clientMessages.length === 0) {
    return res.status(400).json({ error: 'invalid_messages', reply: 'No messages provided.' });
  }

  // Rate limit
  if (isRateLimited(sessionId)) {
    return res.status(429).json({
      error: 'rate_limited',
      reply: "You're moving fast! Take 60 seconds to think about what we've discussed so far, then come back."
    });
  }

  // Get or create session in DB
  db.getOrCreateSession(sessionId);

  // Load full history from DB
  const dbHistory = db.getMessages(sessionId, 50);

  // Get the latest user message (last in clientMessages)
  const latestUserMessage = clientMessages[clientMessages.length - 1];
  if (!latestUserMessage || latestUserMessage.role !== 'user') {
    return res.status(400).json({ error: 'invalid_messages', reply: 'Last message must be from user.' });
  }

  // Save the new user message to DB
  db.saveMessage(sessionId, 'user', latestUserMessage.content);

  // Build memory context from past sessions (if any exist beyond this one)
  let memoryContext = '';
  try {
    const pastSessions = db.getPastSessions(sessionId, 2);
    if (pastSessions.length > 0) {
      memoryContext = `\n\n### STUDENT MEMORY (from previous sessions):\nThis student has talked to you before. Here are brief excerpts from your past conversations to help you personalize this session:\n`;
      pastSessions.forEach((s, i) => {
        const excerpt = s.messages ? s.messages.split(' ||| ').slice(0, 3).join(' ... ') : '';
        if (excerpt) {
          memoryContext += `\nPast session ${i + 1}: "${excerpt.slice(0, 300)}..."\n`;
        }
      });
      memoryContext += `\nUse this context to reference past discussions naturally when relevant. E.g., "Last time we talked about X — how has your thinking on that evolved?"`;
    }
  } catch (e) {
    // Memory lookup failed — continue without it
  }

  // Build messages array for API: use DB history (more reliable than client)
  // If DB history is empty (first message), use client messages; otherwise use DB
  const apiMessages = dbHistory.length > 0
    ? [...dbHistory, { role: 'user', content: latestUserMessage.content }]
    : [{ role: 'user', content: latestUserMessage.content }];

  // Trim to last 40 messages to stay within context limits
  const trimmed = apiMessages.slice(-40);

  try {
    const response = await anthropic.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 900,
      system: SYSTEM_PROMPT + memoryContext,
      messages: trimmed,
    });

    const reply = response.content[0]?.text || "I seem to have lost my train of thought. Try asking again?";

    // Save assistant reply to DB
    db.saveMessage(sessionId, 'assistant', reply);

    return res.json({ reply, sessionId });

  } catch (err) {
    console.error('[Mercurius] Anthropic API error:', err.message);
    return res.status(500).json({
      error: 'api_error',
      reply: "Hmm, something went wrong on my end — which is itself a good reminder that AI systems fail. Try again in a moment."
    });
  }
});

// ---------------------------------------------------------------------------
// GET /api/session/:sessionId
// ---------------------------------------------------------------------------
app.get('/api/session/:sessionId', (req, res) => {
  const { sessionId } = req.params;
  try {
    const stats = db.getSessionStats(sessionId);
    const recentMessages = db.getMessages(sessionId, 10);
    res.json({ stats, recentMessages });
  } catch (e) {
    res.status(500).json({ error: 'db_error' });
  }
});

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------
app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'Mercurius Ⅰ',
    timestamp: new Date().toISOString(),
  });
});

// ---------------------------------------------------------------------------
// 404 fallback for unknown API routes
// ---------------------------------------------------------------------------
app.use('/api/*', (_req, res) => {
  res.status(404).json({ error: 'not_found', reply: "That route doesn't exist." });
});

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------
app.listen(PORT, () => {
  console.log(`\n✦  Mercurius Ⅰ is running`);
  console.log(`   Local:   http://localhost:${PORT}`);
  console.log(`   Allowed origin: ${ALLOWED_ORIGIN}`);
  console.log(`   Model: claude-sonnet-4-6\n`);
});
