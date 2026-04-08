import { Platform } from 'react-native';
import { StateStorage } from 'zustand/middleware';

let mmkvInstance: any = null;

function getMMKV() {
  if (mmkvInstance) return mmkvInstance;
  if (Platform.OS !== 'web') {
    try {
      const { createMMKV } = require('react-native-mmkv');
      mmkvInstance = createMMKV({ id: 'mercurius-store' });
      return mmkvInstance;
    } catch {}
  }
  return null;
}

export const zustandStorage: StateStorage = {
  getItem: (name: string) => {
    const mmkv = getMMKV();
    if (mmkv) return mmkv.getString(name) ?? null;
    // Web fallback
    try { return localStorage.getItem(name); } catch { return null; }
  },
  setItem: (name: string, value: string) => {
    const mmkv = getMMKV();
    if (mmkv) { mmkv.set(name, value); return; }
    try { localStorage.setItem(name, value); } catch {}
  },
  removeItem: (name: string) => {
    const mmkv = getMMKV();
    if (mmkv) { mmkv.remove(name); return; }
    try { localStorage.removeItem(name); } catch {}
  },
};
