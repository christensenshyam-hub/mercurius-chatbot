import { useSettingsStore } from '../stores/useSettingsStore';
import { ChatResponse, EventData, BlogPost } from '../types';

function getBaseUrl(): string {
  return useSettingsStore.getState().serverUrl;
}

export async function changeMode(
  sessionId: string,
  mode: string,
  clientUnlocked: boolean
): Promise<{ mode: string; unlocked: boolean; error?: string }> {
  try {
    const res = await fetch(`${getBaseUrl()}/api/mode`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId, mode, clientUnlocked }),
    });
    const data = await res.json();
    if (!res.ok) {
      return { mode: 'socratic', unlocked: false, error: data.error || data.message };
    }
    return data;
  } catch {
    return { mode, unlocked: clientUnlocked, error: 'Network error' };
  }
}

export async function sendChatMessage(
  messages: Array<{ role: string; content: string }>,
  sessionId: string
): Promise<ChatResponse> {
  const res = await fetch(`${getBaseUrl()}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ messages, sessionId }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.reply || err.error || `Server error ${res.status}`);
  }
  return res.json();
}

export async function sendChatMessageStreaming(
  messages: Array<{ role: string; content: string }>,
  sessionId: string,
  onDelta: (text: string) => void,
  onComplete: (data: ChatResponse) => void,
  onError: (error: string) => void,
  signal?: AbortSignal
): Promise<void> {
  try {
    // Never request streaming — use regular JSON for maximum compatibility
    const res = await fetch(`${getBaseUrl()}/api/chat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ messages, sessionId }),
      signal,
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      onError(err.reply || err.error || `Server error ${res.status}`);
      return;
    }

    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('text/event-stream') && res.body) {
      // SSE streaming via ReadableStream
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let gotComplete = false;

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop() || '';

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const data = line.slice(6);
              if (data === '[DONE]') continue;
              try {
                const parsed = JSON.parse(data);
                if (parsed.type === 'delta') {
                  onDelta(parsed.text);
                } else if (parsed.type === 'complete') {
                  onComplete(parsed);
                  gotComplete = true;
                } else if (parsed.type === 'error') {
                  onError(parsed.error);
                  return;
                }
              } catch {
                // Non-JSON SSE line, skip
              }
            }
          }
        }
      } catch (readErr: any) {
        if (readErr.name !== 'AbortError' && !gotComplete) {
          onError(readErr.message || 'Stream read error');
        }
      }
    } else {
      // Non-streaming JSON response — immediate
      const data: ChatResponse = await res.json();
      onComplete(data);
    }
  } catch (err: any) {
    if (err.name !== 'AbortError') {
      onError(err.message || 'Network error');
    }
  }
}

export async function fetchQuiz(sessionId: string, messages: Array<{ role: string; content: string }>): Promise<string> {
  const res = await fetch(`${getBaseUrl()}/api/quiz`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, messages }),
  });
  const data = await res.json();
  return data.quiz || data.reply || '';
}

export async function fetchReportCard(sessionId: string, messages: Array<{ role: string; content: string }>): Promise<string> {
  const res = await fetch(`${getBaseUrl()}/api/report-card`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, messages }),
  });
  const data = await res.json();
  return data.report || data.reply || '';
}

export async function fetchLeaderboard(): Promise<any[]> {
  const res = await fetch(`${getBaseUrl()}/api/leaderboard`);
  const data = await res.json();
  return data.leaderboard || [];
}

export async function fetchEvents(): Promise<EventData | null> {
  try {
    const res = await fetch('https://mayoailiteracy.com/events-data.json');
    if (res.ok) return res.json();
  } catch {}
  return null;
}

export async function fetchBlogPosts(): Promise<BlogPost[]> {
  try {
    const res = await fetch('https://mayoailiteracy.com/blog-content.json');
    if (res.ok) return res.json();
  } catch {}
  return [];
}

export async function checkHealth(): Promise<boolean> {
  try {
    const res = await fetch(`${getBaseUrl()}/api/health`);
    return res.ok;
  } catch {
    return false;
  }
}
