import { Platform } from 'react-native';

const fontFamily = Platform.select({
  ios: 'System',
  android: 'Roboto',
  default: 'System',
});

const monoFamily = Platform.select({
  ios: 'Menlo',
  android: 'monospace',
  default: 'monospace',
});

export const typography = {
  title: {
    fontFamily,
    fontSize: 24,
    fontWeight: '700' as const,
    lineHeight: 32,
    letterSpacing: -0.5,
  },
  heading: {
    fontFamily,
    fontSize: 22,
    fontWeight: '700' as const,
    lineHeight: 28,
    letterSpacing: -0.5,
  },
  subheading: {
    fontFamily,
    fontSize: 17,
    fontWeight: '600' as const,
    lineHeight: 22,
    letterSpacing: -0.3,
  },
  body: {
    fontFamily,
    fontSize: 16,
    fontWeight: '400' as const,
    lineHeight: 24,
    letterSpacing: -0.2,
  },
  bodyMedium: {
    fontFamily,
    fontSize: 16,
    fontWeight: '500' as const,
    lineHeight: 24,
    letterSpacing: -0.2,
  },
  caption: {
    fontFamily,
    fontSize: 13,
    fontWeight: '400' as const,
    lineHeight: 18,
    letterSpacing: 0,
  },
  mono: {
    fontFamily: monoFamily,
    fontSize: 13,
    fontWeight: '400' as const,
    lineHeight: 18,
  },
  code: {
    fontFamily: monoFamily,
    fontSize: 14,
    fontWeight: '400' as const,
    lineHeight: 20,
  },
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
};
