import React, { useCallback, useState } from 'react';
import { View, Text, Pressable, StyleSheet, Alert } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';
import { useSessionStore } from '../../stores/useSessionStore';
import { changeMode } from '../../services/api';

const MODES = [
  {
    id: 'socratic',
    label: 'Socratic',
    icon: 'help-circle',
    locked: false,
    desc: 'Questions before answers',
  },
  {
    id: 'debate',
    label: 'Debate',
    icon: 'flame',
    locked: false,
    desc: 'Challenge and argue ideas',
  },
  {
    id: 'discussion',
    label: 'Discussion',
    icon: 'chatbubbles',
    locked: false,
    desc: 'Scored reasoning evaluation',
  },
  {
    id: 'direct',
    label: 'Direct',
    icon: 'flash',
    locked: true,
    desc: 'Unlock by passing the test',
  },
];

export function ModeSelector() {
  const { colors, typography: typo } = useTheme();
  const mode = useSessionStore((s) => s.mode);
  const unlocked = useSessionStore((s) => s.unlocked);
  const sessionId = useSessionStore((s) => s.sessionId);
  const setMode = useSessionStore((s) => s.setMode);
  const setUnlocked = useSessionStore((s) => s.setUnlocked);
  const messageCount = useSessionStore((s) => s.messageCount);
  const [switching, setSwitching] = useState(false);

  const handleModeChange = useCallback(async (modeId: string, isLocked: boolean) => {
    if (modeId === mode) return;
    if (switching) return;

    if (isLocked && !unlocked) {
      const remaining = Math.max(0, 6 - messageCount);
      if (remaining > 0) {
        Alert.alert(
          'Direct Mode Locked',
          `Send ${remaining} more message${remaining === 1 ? '' : 's'} in Socratic mode to trigger the comprehension test. Pass it to unlock Direct mode.`
        );
      } else {
        Alert.alert(
          'Direct Mode Locked',
          'Keep chatting in Socratic mode. Mercurius will test your critical thinking soon. Pass the test to unlock Direct mode.'
        );
      }
      return;
    }

    setSwitching(true);
    try {
      const result = await changeMode(sessionId, modeId, unlocked);
      if (result.error === 'locked') {
        Alert.alert('Mode Locked', 'Complete the comprehension check to unlock Direct mode.');
      } else {
        setMode(modeId);
        if (result.unlocked) setUnlocked(true);
      }
    } catch {
      // Offline fallback — change locally
      setMode(modeId);
    }
    setSwitching(false);
  }, [mode, unlocked, sessionId, messageCount, switching, setMode, setUnlocked]);

  return (
    <View style={[styles.container, { borderBottomColor: colors.border }]}>
      {MODES.map((m) => {
        const isActive = mode === m.id;
        const isLocked = m.locked && !unlocked;

        return (
          <Pressable
            key={m.id}
            onPress={() => handleModeChange(m.id, m.locked)}
            disabled={switching}
            style={({ pressed }) => [
              styles.pill,
              {
                backgroundColor: isActive ? colors.accent : 'transparent',
                borderColor: isActive ? colors.accent : colors.border,
                opacity: isLocked ? 0.4 : (pressed ? 0.8 : 1),
              },
            ]}
          >
            <Icon
              name={isLocked ? 'lock-closed' : m.icon}
              size={13}
              color={isActive ? '#fff' : colors.textSecondary}
            />
            <View>
              <Text
                style={[
                  styles.label,
                  {
                    color: isActive ? '#fff' : colors.text,
                    fontWeight: isActive ? '600' : '500',
                  },
                ]}
              >
                {m.label}
              </Text>
              {isActive && (
                <Text style={[styles.desc, { color: isActive ? 'rgba(255,255,255,0.7)' : colors.textSecondary }]}>
                  {isLocked ? 'Locked' : m.desc}
                </Text>
              )}
            </View>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    paddingHorizontal: 12,
    paddingVertical: 8,
    gap: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 20,
    borderWidth: 1,
    gap: 6,
  },
  label: {
    fontSize: 13,
  },
  desc: {
    fontSize: 10,
    marginTop: 1,
  },
});
