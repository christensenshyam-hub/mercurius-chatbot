import { create } from 'zustand';
import { Message } from '../types';
import * as db from '../services/database';

function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

interface ChatState {
  messages: Message[];
  isLoading: boolean;
  streamingContent: string;
  streamingMessageId: string | null;
  conversationId: string;
  pendingMessage: string | null;
  _cache: Record<string, Message[]>;

  setConversationId: (id: string) => void;
  loadMessages: (conversationId: string) => void;
  addUserMessage: (content: string) => Message;
  startStreaming: () => string;
  appendStreamDelta: (text: string) => void;
  finalizeStream: (fullContent: string) => void;
  setError: (messageId: string, error: string) => void;
  setLoading: (loading: boolean) => void;
  clearMessages: () => void;
  setPendingMessage: (msg: string | null) => void;
  switchConversation: (id: string) => void;
  newConversation: (id: string) => void;
}

export const useChatStore = create<ChatState>()((set, get) => ({
  messages: [],
  isLoading: false,
  streamingContent: '',
  streamingMessageId: null,
  conversationId: '',
  pendingMessage: null,
  _cache: {},

  setConversationId: (id) => set({ conversationId: id }),
  setPendingMessage: (msg) => set({ pendingMessage: msg }),

  // Save current messages to cache, then load target conversation
  switchConversation: (id) => {
    const state = get();
    const newCache = { ...state._cache };

    // Save current conversation to cache (if it has messages)
    if (state.conversationId && state.messages.length > 0) {
      newCache[state.conversationId] = [...state.messages];
    }

    // Load target: cache first, then SQLite
    let targetMessages = newCache[id];
    if (!targetMessages) {
      try {
        targetMessages = db.getMessages(id);
      } catch {
        targetMessages = [];
      }
    }
    newCache[id] = targetMessages;

    set({
      conversationId: id,
      messages: targetMessages,
      _cache: newCache,
      streamingMessageId: null,
      streamingContent: '',
      isLoading: false,
    });
  },

  // Create a brand new conversation — saves current first
  newConversation: (id) => {
    const state = get();
    const newCache = { ...state._cache };

    // Save current conversation to cache
    if (state.conversationId && state.messages.length > 0) {
      newCache[state.conversationId] = [...state.messages];
    }

    // New conversation starts empty
    newCache[id] = [];

    set({
      conversationId: id,
      messages: [],
      _cache: newCache,
      streamingMessageId: null,
      streamingContent: '',
      isLoading: false,
    });
  },

  loadMessages: (conversationId) => {
    const cached = get()._cache[conversationId];
    if (cached && cached.length > 0) {
      set({ messages: cached, conversationId });
      return;
    }
    try {
      const msgs = db.getMessages(conversationId);
      set((s) => ({
        messages: msgs,
        conversationId,
        _cache: { ...s._cache, [conversationId]: msgs },
      }));
    } catch {
      set({ messages: [], conversationId });
    }
  },

  addUserMessage: (content) => {
    const msg: Message = {
      id: generateId(),
      role: 'user',
      content,
      timestamp: Date.now(),
    };
    set((state) => {
      const newMessages = [...state.messages, msg];
      return {
        messages: newMessages,
        _cache: { ...state._cache, [state.conversationId]: newMessages },
      };
    });
    const { conversationId } = get();
    if (conversationId) {
      try { db.insertMessage(conversationId, msg); } catch {}
    }
    return msg;
  },

  startStreaming: () => {
    const id = generateId();
    const msg: Message = {
      id,
      role: 'assistant',
      content: '',
      timestamp: Date.now(),
      isStreaming: true,
    };
    set((state) => {
      const newMessages = [...state.messages, msg];
      return {
        messages: newMessages,
        streamingMessageId: id,
        streamingContent: '',
        isLoading: true,
        _cache: { ...state._cache, [state.conversationId]: newMessages },
      };
    });
    return id;
  },

  appendStreamDelta: (text) => {
    set((state) => {
      const newContent = state.streamingContent + text;
      const idx = state.messages.findIndex((m) => m.id === state.streamingMessageId);
      if (idx === -1) return { streamingContent: newContent };
      const updated = [...state.messages];
      updated[idx] = { ...updated[idx], content: newContent };
      // Skip _cache update during streaming for performance — cache syncs on finalizeStream
      return { messages: updated, streamingContent: newContent };
    });
  },

  finalizeStream: (fullContent) => {
    set((state) => {
      const messages = state.messages.map((m) =>
        m.id === state.streamingMessageId
          ? { ...m, content: fullContent, isStreaming: false }
          : m
      );
      const finalMsg = messages.find((m) => m.id === state.streamingMessageId);
      if (finalMsg && state.conversationId) {
        try { db.insertMessage(state.conversationId, { ...finalMsg, isStreaming: false }); } catch {}
      }
      return {
        messages,
        streamingMessageId: null,
        streamingContent: '',
        isLoading: false,
        _cache: { ...state._cache, [state.conversationId]: messages },
      };
    });
  },

  setError: (messageId, error) => {
    set((state) => {
      const messages = state.messages.map((m) =>
        m.id === messageId ? { ...m, content: error, isStreaming: false } : m
      );
      return {
        messages,
        streamingMessageId: null,
        streamingContent: '',
        isLoading: false,
        _cache: { ...state._cache, [state.conversationId]: messages },
      };
    });
  },

  setLoading: (loading) => set({ isLoading: loading }),

  clearMessages: () =>
    set((state) => ({
      messages: [],
      streamingMessageId: null,
      streamingContent: '',
      isLoading: false,
    })),
}));
