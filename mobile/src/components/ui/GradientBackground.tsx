import React from 'react';
import { View, Image, StyleSheet } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useTheme } from '../../theme';

const logoSource = require('../../../assets/logo-watermark.png');

interface Props {
  children: React.ReactNode;
  showWatermark?: boolean;
}

export function GradientBackground({ children, showWatermark = true }: Props) {
  const { isDark } = useTheme();

  const gradientColors: [string, string] = isDark
    ? ['#0a1610', '#0f2118']
    : ['#f5f8f6', '#edf4ef'];

  return (
    <LinearGradient colors={gradientColors} style={styles.container}>
      {showWatermark && (
        <View style={styles.watermarkContainer} pointerEvents="none">
          <Image
            source={logoSource}
            style={[styles.watermark, { opacity: isDark ? 0.09 : 0.08 }]}
            resizeMode="contain"
          />
        </View>
      )}
      {children}
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  watermarkContainer: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  watermark: {
    width: 320,
    height: 320,
  },
});
