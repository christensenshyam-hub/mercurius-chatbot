import React, { useEffect, useRef } from 'react';
import { View, Animated, StyleSheet } from 'react-native';
import { useTheme } from '../../theme';

interface Props {
  width?: number | string;
  height?: number;
  borderRadius?: number;
  style?: any;
}

export function SkeletonLoader({ width = '100%', height = 16, borderRadius = 8, style }: Props) {
  const { colors } = useTheme();
  const shimmer = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const animation = Animated.loop(
      Animated.sequence([
        Animated.timing(shimmer, { toValue: 1, duration: 1000, useNativeDriver: true }),
        Animated.timing(shimmer, { toValue: 0, duration: 1000, useNativeDriver: true }),
      ])
    );
    animation.start();
    return () => animation.stop();
  }, []);

  return (
    <Animated.View
      style={[
        {
          width: width as any,
          height,
          borderRadius,
          backgroundColor: colors.surfaceElevated,
          opacity: shimmer.interpolate({ inputRange: [0, 1], outputRange: [0.4, 0.8] }),
        },
        style,
      ]}
    />
  );
}

export function SkeletonCard() {
  const { colors, spacing } = useTheme();
  return (
    <View style={[styles.card, { backgroundColor: colors.surface, borderColor: colors.border }]}>
      <View style={styles.cardRow}>
        <SkeletonLoader width={44} height={44} borderRadius={22} />
        <View style={styles.cardContent}>
          <SkeletonLoader width="70%" height={16} />
          <SkeletonLoader width="90%" height={12} style={{ marginTop: 8 }} />
          <SkeletonLoader width="40%" height={4} style={{ marginTop: 10 }} />
        </View>
      </View>
    </View>
  );
}

export function SkeletonMessage({ isUser = false }: { isUser?: boolean }) {
  return (
    <View style={[styles.msgRow, { alignSelf: isUser ? 'flex-end' : 'flex-start' }]}>
      <SkeletonLoader
        width={isUser ? 180 : 240}
        height={isUser ? 40 : 60}
        borderRadius={16}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    padding: 16,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    marginHorizontal: 16,
    marginBottom: 12,
  },
  cardRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  cardContent: {
    flex: 1,
  },
  msgRow: {
    marginHorizontal: 16,
    marginBottom: 8,
  },
});
