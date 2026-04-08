import React from 'react';
import { View, Text, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams, useRouter, Stack } from 'expo-router';
import { useTheme } from '../../../src/theme';
import { LessonItem } from '../../../src/components/curriculum/LessonItem';
import { CURRICULUM_UNITS } from '../../../src/data/curriculum';
import { useChatStore } from '../../../src/stores/useChatStore';
import { useCurriculumStore } from '../../../src/stores/useCurriculumStore';

function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

export default function UnitDetailScreen() {
  const { unitId } = useLocalSearchParams<{ unitId: string }>();
  const { colors, typography: typo } = useTheme();
  const router = useRouter();
  const newConversation = useChatStore((s) => s.newConversation);
  const setPendingMessage = useChatStore((s) => s.setPendingMessage);

  const unit = CURRICULUM_UNITS.find((u) => u.id === unitId);

  if (!unit) {
    return (
      <View style={[styles.center, { backgroundColor: colors.background }]}>
        <Text style={{ color: colors.text }}>Unit not found</Text>
      </View>
    );
  }

  const handleStartLesson = (lessonIndex: number) => {
    const lesson = unit.lessons[lessonIndex];
    // Save current chat, create a new one, queue the lesson starter
    const convId = generateId();
    newConversation(convId);
    setPendingMessage(lesson.starter);
    useCurriculumStore.getState().earnBadge('curriculum_unit');
    // Navigate to chat — the chat screen will pick up pendingMessage and send it
    router.push('/(tabs)/chat');
  };

  return (
    <>
      <Stack.Screen
        options={{
          title: unit.title,
          headerStyle: { backgroundColor: colors.background },
          headerTintColor: colors.text,
        }}
      />
      <ScrollView
        style={{ backgroundColor: colors.background }}
        contentContainerStyle={styles.content}
      >
        <View style={[styles.header, { borderBottomColor: colors.border }]}>
          <Text style={[styles.number, { color: colors.accent, ...typo.title }]}>
            Unit {unit.number}
          </Text>
          <Text style={[styles.title, { color: colors.text, ...typo.heading }]}>
            {unit.title}
          </Text>
          <Text style={[styles.desc, { color: colors.textSecondary, ...typo.body }]}>
            {unit.description}
          </Text>
        </View>

        <View style={styles.lessons}>
          <Text style={[styles.lessonsHeader, { color: colors.text, ...typo.bodyMedium }]}>
            Lessons
          </Text>
          {unit.lessons.map((lesson, i) => (
            <LessonItem
              key={lesson.id}
              lesson={lesson}
              index={i}
              onPress={() => handleStartLesson(i)}
            />
          ))}
        </View>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    paddingBottom: 32,
  },
  header: {
    paddingHorizontal: 16,
    paddingVertical: 20,
    borderBottomWidth: StyleSheet.hairlineWidth,
    marginBottom: 16,
  },
  number: {
    marginBottom: 4,
  },
  title: {
    marginBottom: 8,
  },
  desc: {
    lineHeight: 22,
  },
  lessons: {
    paddingHorizontal: 16,
  },
  lessonsHeader: {
    marginBottom: 12,
  },
});
