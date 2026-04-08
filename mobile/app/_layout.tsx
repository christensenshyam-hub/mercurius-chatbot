import { useEffect, useState } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import * as SplashScreen from 'expo-splash-screen';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { ThemeProvider, useTheme } from '../src/theme';
import { AchievementToastProvider } from '../src/components/ui/AchievementToast';
import { zustandStorage } from '../src/services/storage';

SplashScreen.preventAutoHideAsync();

function RootLayoutInner() {
  const { colors, isDark } = useTheme();
  const [hasOnboarded, setHasOnboarded] = useState<boolean | null>(null);

  useEffect(() => {
    const val = zustandStorage.getItem('hasOnboarded');
    setHasOnboarded(val === 'true');
    SplashScreen.hideAsync();
  }, []);

  if (hasOnboarded === null) return null;

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: colors.background }}>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      <AchievementToastProvider>
        <Stack screenOptions={{ headerShown: false }} initialRouteName={hasOnboarded ? '(tabs)' : 'onboarding'}>
          <Stack.Screen name="onboarding" />
          <Stack.Screen name="(tabs)" />
        </Stack>
      </AchievementToastProvider>
    </GestureHandlerRootView>
  );
}

export default function RootLayout() {
  return (
    <ThemeProvider>
      <RootLayoutInner />
    </ThemeProvider>
  );
}
