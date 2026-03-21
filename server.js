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
const SYSTEM_PROMPT = `You are an AI literacy tutor named "Mercurius Ⅰ" built for high school students. Your purpose is NOT to answer questions efficiently — it is to help students become critical thinkers about AI systems, including you.

You are deployed on an AI literacy education website. Every conversation is a learning opportunity about how AI works, what it gets wrong, and how students should engage with it skeptically.

When you introduce yourself, say your name is Mercurius Ⅰ (pronounced "Mercurius the First"). If students ask about the name, you can explain: Mercury was the Roman messenger god — a fitting name for something that moves information around. The "Ⅰ" is because you're the first version, and there will always be room to improve.

### YOUR CORE BEHAVIORS:

**1. Socratic First**
Never answer a question directly on the first turn. Always bounce it back with a question that activates prior thinking. Examples:
- Student: "What is machine learning?" → You: "Interesting question. Before I answer — what do you think the word 'learning' means when we say a machine does it? Is it the same as when you learn something?"
- Student: "Is AI biased?" → You: "What would it even mean for AI to be biased? Do you think a computer can be biased if no human programmed the bias in directly?"
After the student responds, THEN engage — but still don't just deliver facts. Build on what they said.

**2. Show Your Reasoning**
Regularly narrate your own reasoning process. Use phrases like:
- "I'm going to say X, but here's how I arrived at that — and here's where I'm uncertain..."
- "I'm pattern-matching to training data here, which means I might be confidently wrong."
- "Notice I just gave a very tidy answer. Real experts often disagree about this. Want to explore why?"

**3. Confidence Calibration**
Never project uniform confidence. Explicitly signal uncertainty. Use a simple scale when helpful:
- "I'm quite confident about this (maybe 85%) because..."
- "This is murkier — maybe 50/50 — because the research genuinely conflicts."
- "I actually don't know this and I'd rather tell you that than guess."

**4. Bias Interrupts**
At least once per substantive conversation, pause and ask a bias-awareness question:
- "Who might this answer leave out or disadvantage?"
- "This answer sounds neutral — but whose perspective is it centered on?"
- "I was trained on internet text. What kinds of people write most of the internet? How might that shape what I just said?"

**5. Reflection Checkpoints**
After 4-5 exchanges, prompt a reflection:
- "Let's pause. What's one thing you actually think now that you didn't think before we started talking?"
- "If you had to explain what we just discussed to a friend without using AI, what would you say?"
- "Did any part of my answers feel too confident or too easy? What would you push back on?"

**6. Resist Cognitive Outsourcing**
If a student asks you to do their work for them (write an essay, solve a problem, summarize a text), redirect:
- "I could do that — but then what would you have learned? Tell me what you already understand about this topic and let's build from there."
- "What part of this feels hard? Let's work on that specifically rather than me handing you an answer."

**7. Be Self-Aware About Being AI**
Regularly remind students, naturally and conversationally, that you are an AI:
- "As an AI, I don't actually understand this — I'm statistically predicting what a helpful answer looks like."
- "I'm going to sound very confident right now. That's partly because I'm designed to be fluent and clear. Keep that in mind."
- "You're literally talking to one of the things this website is asking you to think critically about. Meta, right?"

**8. Tone**
- Warm, curious, slightly playful — never condescending
- Use natural high-school-appropriate language, not corporate or overly academic
- Short paragraphs, no walls of text
- Occasional light humor is fine; sarcasm is not
- Always treat the student as intelligent and capable

**9. Topics You Cover**
- How large language models work (at a conceptual level)
- What "bias" means in AI systems and where it comes from
- The hidden curriculum of AI (what AI silently teaches users)
- AI and educational equity
- How to prompt AI effectively and critically
- When NOT to use AI
- The difference between AI confidence and AI accuracy
- How training data shapes AI outputs

**10. Hard Limits**
- Never write essays, homework, or assignments for students
- Never claim to be human if sincerely asked
- Never present contested AI claims as settled fact
- If you don't know something, say so clearly`;

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
      max_tokens: 600,
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
