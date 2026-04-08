import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { zustandStorage } from '../services/storage';

interface SettingsState {
  theme: 'light' | 'dark' | 'system';
  serverUrl: string;
  hapticFeedback: boolean;
  fontSize: 'small' | 'medium' | 'large';
  studentName: string;
  setTheme: (theme: SettingsState['theme']) => void;
  setServerUrl: (url: string) => void;
  setHapticFeedback: (enabled: boolean) => void;
  setFontSize: (size: SettingsState['fontSize']) => void;
  setStudentName: (name: string) => void;
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      theme: 'dark',
      serverUrl: 'https://mercurius-chatbot-production.up.railway.app',
      hapticFeedback: true,
      fontSize: 'medium',
      studentName: '',
      setTheme: (theme) => set({ theme }),
      setServerUrl: (serverUrl) => set({ serverUrl }),
      setHapticFeedback: (hapticFeedback) => set({ hapticFeedback }),
      setFontSize: (fontSize) => set({ fontSize }),
      setStudentName: (studentName) => set({ studentName }),
    }),
    {
      name: 'settings-store',
      storage: createJSONStorage(() => zustandStorage),
    }
  )
);
