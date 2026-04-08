import React from 'react';
import {
  ScrollView,
  View,
  Text,
  TextInput,
  Switch,
  Pressable,
  StyleSheet,
  Alert,
} from 'react-native';
import { Icon } from '../../src/components/ui/Icon';
import { useTheme } from '../../src/theme';
import { useSettingsStore } from '../../src/stores/useSettingsStore';
import { useSessionStore } from '../../src/stores/useSessionStore';
import { checkHealth } from '../../src/services/api';

export default function SettingsScreen() {
  const { colors, typography: typo } = useTheme();
  const settings = useSettingsStore();
  const session = useSessionStore();

  const testConnection = async () => {
    const ok = await checkHealth();
    Alert.alert(
      ok ? 'Connected' : 'Connection Failed',
      ok
        ? `Server at ${settings.serverUrl} is running.`
        : `Could not reach ${settings.serverUrl}. Check URL and ensure the server is running.`
    );
  };

  const themeOptions: Array<{ value: 'light' | 'dark' | 'system'; label: string }> = [
    { value: 'dark', label: 'Dark' },
    { value: 'light', label: 'Light' },
    { value: 'system', label: 'System' },
  ];

  return (
    <ScrollView
      style={{ backgroundColor: colors.background }}
      contentContainerStyle={styles.content}
    >
      {/* Profile */}
      <Text style={[styles.sectionTitle, { color: colors.textSecondary, ...typo.caption }]}>
        PROFILE
      </Text>
      <View style={[styles.card, { backgroundColor: colors.surface, borderColor: colors.border }]}>
        <View style={styles.row}>
          <Text style={[styles.label, { color: colors.text, ...typo.body }]}>Name</Text>
          <TextInput
            style={[styles.input, { color: colors.text, borderColor: colors.border, backgroundColor: colors.surfaceElevated }]}
            value={settings.studentName}
            onChangeText={settings.setStudentName}
            placeholder="Your name"
            placeholderTextColor={colors.textSecondary}
          />
        </View>
        <View style={styles.row}>
          <Text style={[styles.label, { color: colors.text, ...typo.body }]}>Session</Text>
          <Text style={[styles.value, { color: colors.textSecondary, ...typo.caption }]}>
            {session.sessionId}
          </Text>
        </View>
        <View style={styles.row}>
          <Text style={[styles.label, { color: colors.text, ...typo.body }]}>Streak</Text>
          <Text style={[styles.value, { color: colors.accent, ...typo.bodyMedium }]}>
            {session.streak} days
          </Text>
        </View>
        <View style={styles.row}>
          <Text style={[styles.label, { color: colors.text, ...typo.body }]}>Mode</Text>
          <Text style={[styles.value, { color: colors.textSecondary, ...typo.caption }]}>
            {session.mode} {session.unlocked ? '(unlocked)' : ''}
          </Text>
        </View>
      </View>

      {/* Appearance */}
      <Text style={[styles.sectionTitle, { color: colors.textSecondary, ...typo.caption }]}>
        APPEARANCE
      </Text>
      <View style={[styles.card, { backgroundColor: colors.surface, borderColor: colors.border }]}>
        <View style={styles.row}>
          <Text style={[styles.label, { color: colors.text, ...typo.body }]}>Theme</Text>
          <View style={styles.segmented}>
            {themeOptions.map((opt) => (
              <Pressable
                key={opt.value}
                onPress={() => settings.setTheme(opt.value)}
                style={[
                  styles.segment,
                  {
                    backgroundColor: settings.theme === opt.value ? colors.accent : colors.surfaceElevated,
                    borderColor: colors.border,
                  },
                ]}
              >
                <Text
                  style={{
                    color: settings.theme === opt.value ? '#fff' : colors.text,
                    fontSize: 13,
                    fontWeight: '600',
                  }}
                >
                  {opt.label}
                </Text>
              </Pressable>
            ))}
          </View>
        </View>
        <View style={styles.row}>
          <Text style={[styles.label, { color: colors.text, ...typo.body }]}>Haptic Feedback</Text>
          <Switch
            value={settings.hapticFeedback}
            onValueChange={settings.setHapticFeedback}
            trackColor={{ false: colors.border, true: colors.accent }}
          />
        </View>
      </View>

      {/* Server */}
      <Text style={[styles.sectionTitle, { color: colors.textSecondary, ...typo.caption }]}>
        SERVER
      </Text>
      <View style={[styles.card, { backgroundColor: colors.surface, borderColor: colors.border }]}>
        <View style={styles.row}>
          <Text style={[styles.label, { color: colors.text, ...typo.body }]}>URL</Text>
          <TextInput
            style={[styles.input, { color: colors.text, borderColor: colors.border, backgroundColor: colors.surfaceElevated, flex: 1 }]}
            value={settings.serverUrl}
            onChangeText={settings.setServerUrl}
            placeholder="http://localhost:3000"
            placeholderTextColor={colors.textSecondary}
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="url"
          />
        </View>
        <Pressable
          onPress={testConnection}
          style={({ pressed }) => [
            styles.button,
            { backgroundColor: colors.accent, opacity: pressed ? 0.8 : 1 },
          ]}
        >
          <Icon name="pulse" size={16} color="#fff" />
          <Text style={styles.buttonText}>Test Connection</Text>
        </Pressable>
      </View>

      {/* About */}
      <Text style={[styles.sectionTitle, { color: colors.textSecondary, ...typo.caption }]}>
        ABOUT
      </Text>
      <View style={[styles.card, { backgroundColor: colors.surface, borderColor: colors.border }]}>
        <View style={styles.row}>
          <Text style={[styles.label, { color: colors.text, ...typo.body }]}>App</Text>
          <Text style={[styles.value, { color: colors.textSecondary, ...typo.caption }]}>
            Mercurius Mobile v1.0.0
          </Text>
        </View>
        <View style={styles.row}>
          <Text style={[styles.label, { color: colors.text, ...typo.body }]}>Club</Text>
          <Text style={[styles.value, { color: colors.textSecondary, ...typo.caption }]}>
            Mayo AI Literacy Club
          </Text>
        </View>
      </View>

      <Pressable
        onPress={() =>
          Alert.alert(
            'Reset Session',
            'This will start a fresh session. Your chat history will be preserved but the server will treat you as a new student.',
            [
              { text: 'Cancel', style: 'cancel' },
              { text: 'Reset', style: 'destructive', onPress: session.resetSession },
            ]
          )
        }
        style={({ pressed }) => [
          styles.resetButton,
          { borderColor: colors.error, opacity: pressed ? 0.7 : 1 },
        ]}
      >
        <Text style={[styles.resetText, { color: colors.error, ...typo.body }]}>
          Reset Session
        </Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingTop: 16,
    paddingBottom: 40,
  },
  sectionTitle: {
    fontWeight: '600',
    letterSpacing: 1,
    marginHorizontal: 16,
    marginBottom: 8,
    marginTop: 16,
  },
  card: {
    marginHorizontal: 16,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 14,
    gap: 14,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  label: {
    minWidth: 70,
  },
  value: {},
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    fontSize: 14,
    minWidth: 160,
  },
  segmented: {
    flexDirection: 'row',
    gap: 4,
  },
  segment: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingVertical: 10,
    borderRadius: 8,
  },
  buttonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
  resetButton: {
    marginHorizontal: 16,
    marginTop: 24,
    paddingVertical: 12,
    borderRadius: 10,
    borderWidth: 1,
    alignItems: 'center',
  },
  resetText: {
    fontWeight: '600',
  },
});
