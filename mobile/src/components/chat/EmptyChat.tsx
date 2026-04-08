import React from 'react';
import { View, Text, Image, Pressable, StyleSheet } from 'react-native';
import { useTheme } from '../../theme';

const logoSource = require('../../../assets/logo-watermark.png');

interface Props {
  onSuggestion: (text: string) => void;
}

const SUGGESTIONS = [
  'What is AI literacy and why does it matter?',
  'Explain how LLMs actually work',
  'What is algorithmic bias?',
  'How should I think critically about AI?',
];

export function EmptyChat({ onSuggestion }: Props) {
  const { colors, typography: typo, isDark } = useTheme();

  return (
    <View style={styles.container}>
      <Image
        source={logoSource}
        style={[styles.logo, { opacity: isDark ? 0.35 : 0.28 }]}
        resizeMode="contain"
      />
      <Text style={[styles.title, { color: colors.text, ...typo.heading }]}>
        Mercurius
      </Text>
      <Text style={[styles.subtitle, { color: colors.textSecondary, ...typo.caption }]}>
        AI Literacy Tutor
      </Text>
      <Text style={[styles.tagline, { color: colors.textSecondary }]}>
        Here to help you think, not think for you.
      </Text>

      <View style={styles.suggestions}>
        {SUGGESTIONS.map((suggestion, i) => (
          <Pressable
            key={i}
            onPress={() => onSuggestion(suggestion)}
            style={({ pressed }) => [
              styles.chip,
              {
                backgroundColor: pressed ? colors.surfaceElevated : 'transparent',
                borderColor: colors.border,
                borderLeftColor: colors.accent,
                borderLeftWidth: 3,
              },
            ]}
          >
            <Text style={[styles.chipText, { color: colors.textSecondary, ...typo.caption }]}>
              {suggestion}
            </Text>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingBottom: 40,
  },
  logo: {
    width: 120,
    height: 120,
    marginBottom: 14,
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
    marginBottom: 2,
  },
  subtitle: {
    marginBottom: 6,
  },
  tagline: {
    fontSize: 14,
    fontStyle: 'italic',
    marginBottom: 28,
  },
  suggestions: {
    width: '100%',
    gap: 10,
  },
  chip: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 12,
    borderWidth: 1,
  },
  chipText: {
    textAlign: 'left',
    fontSize: 15,
  },
});
