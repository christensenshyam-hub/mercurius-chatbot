import { ChatResponse, EventData, BlogPost } from '../types';

const PRODUCTION_URL = 'https://mercurius-chatbot-production.up.railway.app';
const REQUEST_TIMEOUT_MS = 30000;

function getBaseUrl(): string {
  return PRODUCTION_URL;
}

/**
 * Fetch wrapper with timeout and structured error handling.
 * All API calls go through this to ensure consistent behavior.
 */
async function apiFetch(
  path: string,
  options: RequestInit = {}
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const res = await fetch(`${getBaseUrl()}${path}`, {
      ...options,
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        ...(options.headers || {}),
      },
    });
    return res;
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Parse a JSON response, throwing a descriptive error on failure.
 */
async function parseJsonResponse<T>(res: Response, context: string): Promise<T> {
  if (!res.ok) {
    let detail = '';
    try {
      const body = await res.json();
      detail = body.reply || body.error || body.message || '';
    } catch {}
    throw new Error(detail || `${context}: server returned ${res.status}`);
  }
  return res.json();
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

export async function sendChatMessage(
  messages: Array<{ role: string; content: string }>,
  sessionId: string
): Promise<ChatResponse> {
  const res = await apiFetch('/api/chat', {
    method: 'POST',
    body: JSON.stringify({ messages, sessionId }),
  });
  return parseJsonResponse<ChatResponse>(res, 'Chat');
}

// ---------------------------------------------------------------------------
// Mode switching
// ---------------------------------------------------------------------------

export async function changeMode(
  sessionId: string,
  mode: string
): Promise<{ mode: string; unlocked: boolean; error?: string }> {
  try {
    const res = await apiFetch('/api/mode', {
      method: 'POST',
      body: JSON.stringify({ sessionId, mode }),
    });
    const data = await res.json();
    if (!res.ok) {
      return { mode: 'socratic', unlocked: false, error: data.error || data.message };
    }
    return data;
  } catch (e: any) {
    return { mode, unlocked: false, error: e.name === 'AbortError' ? 'Request timed out' : 'Network error' };
  }
}

// ---------------------------------------------------------------------------
// Tools: Quiz, Report Card, Leaderboard
// ---------------------------------------------------------------------------

export async function fetchQuiz(
  sessionId: string,
  messages: Array<{ role: string; content: string }>
): Promise<string> {
  const res = await apiFetch('/api/quiz', {
    method: 'POST',
    body: JSON.stringify({ sessionId, messages }),
  });
  const data = await parseJsonResponse<{ quiz?: string; reply?: string }>(res, 'Quiz');
  return data.quiz || data.reply || '';
}

export async function fetchReportCard(
  sessionId: string,
  messages: Array<{ role: string; content: string }>
): Promise<string> {
  const res = await apiFetch('/api/report-card', {
    method: 'POST',
    body: JSON.stringify({ sessionId, messages }),
  });
  const data = await parseJsonResponse<{ report?: string; reply?: string }>(res, 'Report card');
  return data.report || data.reply || '';
}

export async function fetchLeaderboard(): Promise<any[]> {
  const res = await apiFetch('/api/leaderboard');
  const data = await parseJsonResponse<{ leaderboard?: any[] }>(res, 'Leaderboard');
  return data.leaderboard || [];
}

// ---------------------------------------------------------------------------
// Club data (static JSON from Netlify — no auth needed)
// ---------------------------------------------------------------------------

export async function fetchEvents(): Promise<EventData | null> {
  try {
    const res = await fetch('https://mayoailiteracy.com/events-data.json');
    if (!res.ok) return null;
    return res.json();
  } catch {
    return null;
  }
}

export async function fetchBlogPosts(): Promise<BlogPost[]> {
  try {
    const res = await fetch('https://mayoailiteracy.com/blog-content.json');
    if (!res.ok) return [];
    return res.json();
  } catch {
    return [];
  }
}

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------

export async function checkHealth(): Promise<boolean> {
  try {
    const res = await apiFetch('/api/health');
    return res.ok;
  } catch {
    return false;
  }
}
