import { useRef, useCallback } from 'react';
import { Alert } from 'react-native';
import { useChatStore } from '../stores/useChatStore';
import { useSessionStore } from '../stores/useSessionStore';
import { sendChatMessage } from '../services/api';
import * as db from '../services/database';
import { Conversation } from '../types';

export function useChat() {
  const abortRef = useRef<AbortController | null>(null);
  const contentRef = useRef('');
  const rafRef = useRef<number | null>(null);
  const pendingDelta = useRef('');

  const sendMessage = useCallback(async (text: string) => {
    const store = useChatStore.getState();
    const session = useSessionStore.getState();

    if (!text.trim() || store.isLoading) return;

    store.addUserMessage(text.trim());
    session.incrementMessageCount();

    // Build history from current store state (fresh read, no stale closure)
    const currentMessages = useChatStore.getState().messages;
    const msgHistory = currentMessages.map((m) => ({ role: m.role, content: m.content }));

    const streamId = store.startStreaming();
    contentRef.current = '';
    pendingDelta.current = '';

    const abort = new AbortController();
    abortRef.current = abort;

    // Batched delta flush — max 60fps
    const flushDelta = () => {
      if (pendingDelta.current) {
        useChatStore.getState().appendStreamDelta(pendingDelta.current);
        pendingDelta.current = '';
      }
      rafRef.current = null;
    };

    const scheduleDeltaFlush = () => {
      if (!rafRef.current) {
        rafRef.current = requestAnimationFrame(flushDelta);
      }
    };

    try {
      const data = await sendChatMessage(msgHistory, session.sessionId);

      const finalContent = data.reply || '';
      useChatStore.getState().finalizeStream(finalContent);

      // Update session state
      if (data.streak !== undefined) session.setStreak(data.streak);
      if (data.difficulty !== undefined) session.setDifficulty(data.difficulty);
      if (data.mode) session.setMode(data.mode);
      if (data.unlocked) session.setUnlocked(true);

      // Notify user when they unlock Direct mode
      if (data.justUnlocked) {
        setTimeout(() => {
          Alert.alert(
            'Direct Mode Unlocked',
            'You passed the comprehension test. You can now switch to Direct mode for deeper, more detailed responses.'
          );
        }, 500);
      }

      // Persist conversation
      const convId = useChatStore.getState().conversationId;
      if (convId) {
        try {
          const msgs = useChatStore.getState().messages;
          db.upsertConversation({
            id: convId,
            sessionId: session.sessionId,
              title: msgs.length <= 2 ? text.trim().slice(0, 50) : '',
              lastMessage: finalContent.slice(0, 100),
              lastTimestamp: Date.now(),
              messageCount: msgs.length,
            } as Conversation);
          } catch {}
        }

        abortRef.current = null;
    } catch (error: any) {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
      useChatStore.getState().setError(streamId, `Error: ${error.message || error}`);
      abortRef.current = null;
    }
  }, []); // No dependencies — reads from store directly

  const cancelStream = useCallback(() => {
    abortRef.current?.abort();
    abortRef.current = null;
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
  }, []);

  // Subscribe to store for reactive values
  const messages = useChatStore((s) => s.messages);
  const isLoading = useChatStore((s) => s.isLoading);

  return { sendMessage, cancelStream, isLoading, messages };
}
