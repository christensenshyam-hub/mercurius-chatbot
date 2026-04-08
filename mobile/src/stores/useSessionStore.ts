import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { zustandStorage } from '../services/storage';

function generateId(): string {
  return 'xxxx-xxxx-xxxx'.replace(/x/g, () =>
    Math.floor(Math.random() * 16).toString(16)
  );
}

interface SessionState {
  sessionId: string;
  mode: string;
  unlocked: boolean;
  streak: number;
  difficulty: number;
  messageCount: number;
  setMode: (mode: string) => void;
  setUnlocked: (unlocked: boolean) => void;
  setStreak: (streak: number) => void;
  setDifficulty: (difficulty: number) => void;
  incrementMessageCount: () => void;
  resetSession: () => void;
}

export const useSessionStore = create<SessionState>()(
  persist(
    (set, get) => ({
      sessionId: generateId(),
      mode: 'socratic',
      unlocked: false,
      streak: 0,
      difficulty: 1,
      messageCount: 0,
      setMode: (mode) => set({ mode }),
      setUnlocked: (unlocked) => set({ unlocked }),
      setStreak: (streak) => set({ streak }),
      setDifficulty: (difficulty) => set({ difficulty }),
      incrementMessageCount: () => set({ messageCount: get().messageCount + 1 }),
      resetSession: () =>
        set({
          sessionId: generateId(),
          mode: 'socratic',
          unlocked: false,
          streak: 0,
          difficulty: 1,
          messageCount: 0,
        }),
    }),
    {
      name: 'session-store',
      storage: createJSONStorage(() => zustandStorage),
    }
  )
);
