import React, { useEffect, useRef, useState } from 'react';
import { View, Text, Animated, StyleSheet } from 'react-native';
import { Icon } from './Icon';
import { useTheme } from '../../theme';
import { ACHIEVEMENTS } from '../../data/curriculum';

let toastCallback: ((badgeId: string) => void) | null = null;

export function showAchievementToast(badgeId: string) {
  toastCallback?.(badgeId);
}

export function AchievementToastProvider({ children }: { children: React.ReactNode }) {
  const { colors, typography: typo } = useTheme();
  const [badge, setBadge] = useState<{ id: string; icon: string; name: string; desc: string } | null>(null);
  const translateY = useRef(new Animated.Value(-120)).current;
  const opacity = useRef(new Animated.Value(0)).current;

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    toastCallback = (badgeId: string) => {
      const found = ACHIEVEMENTS.find((a) => a.id === badgeId);
      if (!found) return;
      setBadge(found);

      // Clear any previous dismiss timer
      if (timerRef.current) clearTimeout(timerRef.current);

      Animated.parallel([
        Animated.spring(translateY, { toValue: 60, useNativeDriver: true, tension: 60, friction: 10 }),
        Animated.timing(opacity, { toValue: 1, duration: 200, useNativeDriver: true }),
      ]).start();

      timerRef.current = setTimeout(() => {
        Animated.parallel([
          Animated.timing(translateY, { toValue: -120, duration: 300, useNativeDriver: true }),
          Animated.timing(opacity, { toValue: 0, duration: 300, useNativeDriver: true }),
        ]).start(() => setBadge(null));
        timerRef.current = null;
      }, 3000);
    };
    return () => {
      toastCallback = null;
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  return (
    <View style={{ flex: 1 }}>
      {children}
      {badge && (
        <Animated.View
          style={[
            styles.toast,
            {
              backgroundColor: colors.surface,
              borderColor: colors.accent,
              transform: [{ translateY }],
              opacity,
            },
          ]}
        >
          <View style={[styles.iconBg, { backgroundColor: colors.accentDim }]}>
            <Text style={[styles.icon, { color: colors.accent }]}>{badge.icon}</Text>
          </View>
          <View style={styles.textContainer}>
            <Text style={[styles.label, { color: colors.accent, ...typo.caption }]}>
              ACHIEVEMENT UNLOCKED
            </Text>
            <Text style={[styles.name, { color: colors.text, ...typo.bodyMedium }]}>
              {badge.name}
            </Text>
            <Text style={[styles.desc, { color: colors.textSecondary, ...typo.caption }]} numberOfLines={1}>
              {badge.desc}
            </Text>
          </View>
          <Icon name="trophy" size={20} color={colors.accent} />
        </Animated.View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  toast: {
    position: 'absolute',
    top: 0,
    left: 16,
    right: 16,
    flexDirection: 'row',
    alignItems: 'center',
    padding: 14,
    borderRadius: 16,
    borderWidth: 1.5,
    gap: 12,
    zIndex: 9999,
  },
  iconBg: {
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
  },
  icon: {
    fontSize: 18,
    fontWeight: '700',
  },
  textContainer: {
    flex: 1,
  },
  label: {
    fontWeight: '700',
    letterSpacing: 1,
    fontSize: 10,
    marginBottom: 2,
  },
  name: {},
  desc: {},
});
