import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTheme } from '../../theme';

interface Props {
  level: 'high' | 'medium' | 'low';
}

export function ConfidenceMeter({ level }: Props) {
  const { colors, typography: typo } = useTheme();

  const levelConfig = {
    high: { color: colors.success, label: 'High Confidence', width: '90%' },
    medium: { color: colors.warning, label: 'Medium Confidence', width: '60%' },
    low: { color: colors.error, label: 'Low Confidence', width: '30%' },
  };

  const config = levelConfig[level];

  return (
    <View style={[styles.container, { backgroundColor: colors.surfaceElevated }]}>
      <Text style={[styles.label, { color: colors.textSecondary, ...typo.caption }]}>
        {config.label}
      </Text>
      <View style={[styles.track, { backgroundColor: colors.border }]}>
        <View
          style={[styles.fill, { backgroundColor: config.color, width: config.width as any }]}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    marginHorizontal: 16,
    marginBottom: 8,
  },
  label: {
    marginBottom: 4,
  },
  track: {
    height: 4,
    borderRadius: 2,
    overflow: 'hidden',
  },
  fill: {
    height: '100%',
    borderRadius: 2,
  },
});
