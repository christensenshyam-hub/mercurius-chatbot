import React from 'react';
import { ScrollView, Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTheme } from '../../../src/theme';
import { GradientBackground } from '../../../src/components/ui/GradientBackground';
import { UnitCard } from '../../../src/components/curriculum/UnitCard';
import { BadgeDisplay } from '../../../src/components/curriculum/BadgeDisplay';
import { CURRICULUM_UNITS } from '../../../src/data/curriculum';

export default function CurriculumScreen() {
  const { colors, typography: typo, spacing } = useTheme();
  const router = useRouter();

  return (
    <GradientBackground>
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <Text style={[styles.subtitle, { color: colors.textSecondary, ...typo.caption }]}>
          5 units, 20 structured lessons on AI literacy
        </Text>

        <BadgeDisplay />

        {CURRICULUM_UNITS.map((unit) => (
          <UnitCard
            key={unit.id}
            unit={unit}
            onPress={() =>
              router.push({
                pathname: '/(tabs)/curriculum/[unitId]',
                params: { unitId: unit.id },
              })
            }
          />
        ))}
      </ScrollView>
    </GradientBackground>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingTop: 16,
    paddingBottom: 32,
  },
  subtitle: {
    textAlign: 'center',
    marginBottom: 16,
    paddingHorizontal: 16,
  },
});
