import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';
import { CurriculumLesson } from '../../types';
import { useCurriculumStore } from '../../stores/useCurriculumStore';

interface Props {
  lesson: CurriculumLesson;
  index: number;
  onPress: () => void;
}

export function LessonItem({ lesson, index, onPress }: Props) {
  const { colors, typography: typo } = useTheme();
  const isComplete = useCurriculumStore((s) => s.isLessonComplete)(lesson.id);

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.item,
        {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          opacity: pressed ? 0.8 : 1,
        },
      ]}
    >
      <View
        style={[
          styles.indexBadge,
          { backgroundColor: isComplete ? colors.accent : colors.surfaceElevated },
        ]}
      >
        {isComplete ? (
          <Icon name="checkmark" size={16} color="#fff" />
        ) : (
          <Text style={[styles.index, { color: colors.textSecondary }]}>
            {index + 1}
          </Text>
        )}
      </View>
      <View style={styles.content}>
        <Text style={[styles.title, { color: colors.text, ...typo.body }]}>
          {lesson.title}
        </Text>
        <Text style={[styles.objective, { color: colors.textSecondary, ...typo.caption }]} numberOfLines={1}>
          {lesson.objective}
        </Text>
      </View>
      <Icon name="play-circle" size={24} color={colors.accent} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  item: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 14,
    borderRadius: 10,
    borderWidth: StyleSheet.hairlineWidth,
    marginBottom: 8,
    gap: 12,
  },
  indexBadge: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
  },
  index: {
    fontSize: 14,
    fontWeight: '600',
  },
  content: {
    flex: 1,
  },
  title: {
    marginBottom: 2,
  },
  objective: {},
});
