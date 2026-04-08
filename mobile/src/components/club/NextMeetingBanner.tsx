import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import { LinearGradient } from 'expo-linear-gradient';
import { useTheme } from '../../theme';

interface Props {
  title: string;
  date: string;
  time: string;
  location: string;
}

export function NextMeetingBanner({ title, date, time, location }: Props) {
  const { colors, typography: typo } = useTheme();

  const formattedDate = (() => {
    try {
      return new Date(date + 'T12:00:00').toLocaleDateString('en-US', {
        weekday: 'long',
        month: 'long',
        day: 'numeric',
      });
    } catch {
      return date;
    }
  })();

  return (
    <LinearGradient
      colors={[colors.primary, colors.surfaceElevated]}
      start={{ x: 0, y: 0 }}
      end={{ x: 1, y: 1 }}
      style={styles.banner}
    >
      <View style={styles.row}>
        <Icon name="people" size={20} color={colors.accent} />
        <Text style={[styles.label, { color: colors.accent, ...typo.caption }]}>
          NEXT MEETING
        </Text>
      </View>
      <Text style={[styles.title, { color: '#ffffff', ...typo.heading }]}>
        {title}
      </Text>
      <View style={styles.details}>
        <View style={styles.detailRow}>
          <Icon name="calendar-outline" size={14} color={colors.accent} />
          <Text style={[styles.detailText, { color: '#e0e0e0', ...typo.caption }]}>
            {formattedDate}
          </Text>
        </View>
        <View style={styles.detailRow}>
          <Icon name="time-outline" size={14} color={colors.accent} />
          <Text style={[styles.detailText, { color: '#e0e0e0', ...typo.caption }]}>
            {time}
          </Text>
        </View>
        <View style={styles.detailRow}>
          <Icon name="location-outline" size={14} color={colors.accent} />
          <Text style={[styles.detailText, { color: '#e0e0e0', ...typo.caption }]}>
            {location}
          </Text>
        </View>
      </View>
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  banner: {
    marginHorizontal: 16,
    marginBottom: 16,
    padding: 18,
    borderRadius: 16,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginBottom: 8,
  },
  label: {
    fontWeight: '700',
    letterSpacing: 1,
  },
  title: {
    marginBottom: 10,
  },
  details: {
    gap: 4,
  },
  detailRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  detailText: {},
});
