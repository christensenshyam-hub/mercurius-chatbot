import React from 'react';
import { View, Text, StyleSheet, ScrollView } from 'react-native';
import { useTheme } from '../../theme';
import { ACHIEVEMENTS } from '../../data/curriculum';
import { useCurriculumStore } from '../../stores/useCurriculumStore';

export function BadgeDisplay() {
  const { colors, typography: typo, spacing } = useTheme();
  const hasBadge = useCurriculumStore((s) => s.hasBadge);

  return (
    <View style={styles.container}>
      <Text style={[styles.header, { color: colors.text, ...typo.heading }]}>
        Achievements
      </Text>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.scroll}>
        {ACHIEVEMENTS.map((badge) => {
          const earned = hasBadge(badge.id);
          return (
            <View
              key={badge.id}
              style={[
                styles.badge,
                {
                  backgroundColor: earned ? colors.accentDim : colors.surfaceElevated,
                  borderColor: earned ? colors.accent : colors.border,
                },
              ]}
            >
              <Text
                style={[
                  styles.icon,
                  { color: earned ? colors.accent : colors.gray, ...typo.heading },
                ]}
              >
                {badge.icon}
              </Text>
              <Text
                style={[styles.name, { color: earned ? colors.text : colors.gray, ...typo.caption }]}
                numberOfLines={1}
              >
                {badge.name}
              </Text>
            </View>
          );
        })}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: 16,
  },
  header: {
    marginHorizontal: 16,
    marginBottom: 12,
  },
  scroll: {
    paddingHorizontal: 16,
    gap: 10,
  },
  badge: {
    width: 80,
    paddingVertical: 12,
    borderRadius: 10,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    marginBottom: 4,
  },
  name: {
    textAlign: 'center',
    paddingHorizontal: 4,
  },
});
