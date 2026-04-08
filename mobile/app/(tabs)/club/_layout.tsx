import { Stack } from 'expo-router';
import { useTheme } from '../../../src/theme';

export default function ClubLayout() {
  const { colors } = useTheme();

  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: colors.background },
        headerTintColor: colors.text,
        headerShadowVisible: false,
      }}
    >
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="[blogId]" />
    </Stack>
  );
}
