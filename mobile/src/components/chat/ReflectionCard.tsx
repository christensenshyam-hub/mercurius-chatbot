import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';

const PROMPTS = [
  'What surprised you most in this conversation so far?',
  'Did anything Mercurius said challenge your assumptions?',
  'What would you want to verify independently?',
  'How confident are you in what you learned today?',
  'What question do you wish you had asked?',
  'Did you notice any gaps in the AI\'s reasoning?',
  'How would you explain this topic to a friend?',
  'What\'s one thing you want to explore further?',
];

interface Props {
  messageCount: number;
  onDismiss: () => void;
}

export function ReflectionCard({ messageCount, onDismiss }: Props) {
  const { colors, typography: typo, spacing } = useTheme();
  const prompt = PROMPTS[Math.floor(messageCount / 5) % PROMPTS.length];

  return (
    <View style={[styles.container, { backgroundColor: colors.accentDim, borderColor: colors.accent }]}>
      <View style={styles.header}>
        <Icon name="bulb" size={18} color={colors.accent} />
        <Text style={[styles.headerText, { color: colors.accent, ...typo.caption }]}>
          Reflection Moment
        </Text>
        <Pressable onPress={onDismiss} style={styles.dismiss}>
          <Icon name="close" size={16} color={colors.textSecondary} />
        </Pressable>
      </View>
      <Text style={[styles.prompt, { color: colors.text, ...typo.body }]}>
        {prompt}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginHorizontal: 16,
    marginVertical: 8,
    padding: 14,
    borderRadius: 12,
    borderWidth: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginBottom: 8,
  },
  headerText: {
    fontWeight: '600',
    flex: 1,
  },
  dismiss: {
    padding: 4,
  },
  prompt: {
    fontStyle: 'italic',
  },
});
