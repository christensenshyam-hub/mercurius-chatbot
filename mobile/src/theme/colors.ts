export const lightColors = {
  background: '#f5f8f6',
  surface: '#ffffff',
  surfaceElevated: '#edf4ef',
  primary: '#122e1e',
  accent: '#C9922A',
  accentLight: '#E8B84B',
  accentDim: 'rgba(201, 146, 42, 0.15)',
  userBubble: '#122e1e',
  userBubbleText: '#ffffff',
  aiBubble: '#edf4ef',
  aiBubbleText: '#1a1714',
  text: '#1a1714',
  textSecondary: '#6b7a6e',
  border: '#d4ddd7',
  error: '#ef4444',
  success: '#22c55e',
  warning: '#eab308',
  gray: '#94a3b8',
  tabBar: '#ffffff',
  tabBarBorder: '#d4ddd7',
};

export const darkColors = {
  background: '#080f0b',
  surface: '#101e16',
  surfaceElevated: '#182c22',
  primary: '#edf4ef',
  accent: '#E8B84B',
  accentLight: '#f0c75e',
  accentDim: 'rgba(232, 184, 75, 0.15)',
  userBubble: '#C9922A',
  userBubbleText: '#ffffff',
  aiBubble: '#162a1f',
  aiBubbleText: '#e8ede9',
  text: '#e8ede9',
  textSecondary: '#8a9e90',
  border: '#1c3828',
  error: '#ff6b6b',
  success: '#22c55e',
  warning: '#eab308',
  gray: '#6b7a6e',
  tabBar: '#0a1610',
  tabBarBorder: '#162a1f',
};

export type ThemeColors = typeof lightColors;

export const gradients = {
  light: {
    primary: ['#122e1e', '#1a4a30'] as [string, string],
    accent: ['#C9922A', '#E8B84B'] as [string, string],
    card: ['#ffffff', '#f5f8f6'] as [string, string],
    background: ['#f5f8f6', '#edf4ef'] as [string, string],
    send: ['#C9922A', '#daa740'] as [string, string],
  },
  dark: {
    primary: ['#122e1e', '#1a4a30'] as [string, string],
    accent: ['#C9922A', '#E8B84B'] as [string, string],
    card: ['#1a3d2a', '#224b35'] as [string, string],
    background: ['#0a1610', '#0f2118'] as [string, string],
    send: ['#C9922A', '#E8B84B'] as [string, string],
  },
};

export const shadows = {
  small: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  medium: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 8,
    elevation: 4,
  },
  glow: (color: string) => ({
    shadowColor: color,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.3,
    shadowRadius: 12,
    elevation: 6,
  }),
};
