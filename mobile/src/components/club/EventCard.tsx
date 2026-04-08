import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';

interface Props {
  title: string;
  date: string;
  description: string;
  isPast?: boolean;
}

export function EventCard({ title, date, description, isPast }: Props) {
  const { colors, typography: typo } = useTheme();

  const formattedDate = (() => {
    try {
      return new Date(date + 'T12:00:00').toLocaleDateString('en-US', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
      });
    } catch {
      return date;
    }
  })();

  return (
    <View
      style={[
        styles.card,
        {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          opacity: isPast ? 0.6 : 1,
        },
      ]}
    >
      <View style={[styles.dateBadge, { backgroundColor: isPast ? colors.surfaceElevated : colors.accentDim }]}>
        <Icon name="calendar" size={16} color={isPast ? colors.textSecondary : colors.accent} />
        <Text style={[styles.date, { color: isPast ? colors.textSecondary : colors.accent, ...typo.caption }]}>
          {formattedDate}
        </Text>
      </View>
      <Text style={[styles.title, { color: colors.text, ...typo.bodyMedium }]}>
        {title}
      </Text>
      <Text style={[styles.desc, { color: colors.textSecondary, ...typo.caption }]} numberOfLines={2}>
        {description}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    padding: 14,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    marginBottom: 10,
  },
  dateBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    gap: 6,
    marginBottom: 8,
  },
  date: {
    fontWeight: '600',
  },
  title: {
    marginBottom: 4,
  },
  desc: {},
});
