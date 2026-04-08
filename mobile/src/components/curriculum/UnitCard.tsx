import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';
import { shadows } from '../../theme/colors';
import { CurriculumUnit } from '../../types';
import { useCurriculumStore } from '../../stores/useCurriculumStore';

interface Props {
  unit: CurriculumUnit;
  onPress: () => void;
}

export function UnitCard({ unit, onPress }: Props) {
  const { colors, typography: typo, spacing } = useTheme();
  const getProgress = useCurriculumStore((s) => s.getUnitProgress);
  const lessonIds = unit.lessons.map((l) => l.id);
  const { completed, total } = getProgress(lessonIds);
  const isComplete = completed === total;
  const progress = total > 0 ? completed / total : 0;

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.card,
        shadows.small,
        {
          backgroundColor: colors.surface,
          borderColor: isComplete ? colors.accent : colors.border,
          opacity: pressed ? 0.85 : 1,
        },
      ]}
    >
      <View style={[styles.numberBadge, { backgroundColor: isComplete ? colors.accent : colors.surfaceElevated }]}>
        <Text style={[styles.number, { color: isComplete ? '#fff' : colors.textSecondary, ...typo.heading }]}>
          {unit.number}
        </Text>
      </View>
      <View style={styles.content}>
        <Text style={[styles.title, { color: colors.text, ...typo.bodyMedium }]} numberOfLines={1}>
          {unit.title}
        </Text>
        <Text style={[styles.desc, { color: colors.textSecondary, ...typo.caption }]} numberOfLines={2}>
          {unit.description}
        </Text>
        <View style={styles.progressRow}>
          <View style={[styles.progressTrack, { backgroundColor: colors.border }]}>
            <View style={[styles.progressFill, { width: `${progress * 100}%`, backgroundColor: colors.accent }]} />
          </View>
          <Text style={[styles.progressText, { color: colors.textSecondary, ...typo.caption }]}>
            {completed}/{total}
          </Text>
        </View>
      </View>
      <Icon name="chevron-forward" size={18} color={colors.textSecondary} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
    marginHorizontal: 16,
    marginBottom: 12,
    gap: 14,
  },
  numberBadge: {
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
  },
  number: {
    fontSize: 16,
  },
  content: {
    flex: 1,
  },
  title: {
    marginBottom: 2,
  },
  desc: {
    marginBottom: 8,
  },
  progressRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  progressTrack: {
    flex: 1,
    height: 4,
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 2,
  },
  progressText: {
    minWidth: 28,
  },
});
