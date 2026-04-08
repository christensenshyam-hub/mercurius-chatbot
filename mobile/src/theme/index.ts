import React, { createContext, useContext, useMemo } from 'react';
import { useColorScheme } from 'react-native';
import { lightColors, darkColors, ThemeColors } from './colors';
import { typography, spacing } from './typography';
import { useSettingsStore } from '../stores/useSettingsStore';

interface Theme {
  colors: ThemeColors;
  typography: typeof typography;
  spacing: typeof spacing;
  isDark: boolean;
}

const ThemeContext = createContext<Theme>({
  colors: darkColors,
  typography,
  spacing,
  isDark: true,
});

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const systemScheme = useColorScheme();
  const themeSetting = useSettingsStore((s) => s.theme);

  const isDark = useMemo(() => {
    if (themeSetting === 'system') return systemScheme === 'dark';
    return themeSetting === 'dark';
  }, [themeSetting, systemScheme]);

  const theme = useMemo<Theme>(
    () => ({
      colors: isDark ? darkColors : lightColors,
      typography,
      spacing,
      isDark,
    }),
    [isDark]
  );

  return React.createElement(ThemeContext.Provider, { value: theme }, children);
}

export function useTheme(): Theme {
  return useContext(ThemeContext);
}

export { typography, spacing };
