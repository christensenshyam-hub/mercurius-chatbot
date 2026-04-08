import React, { useEffect, useRef } from 'react';
import { Text, Animated, StyleSheet } from 'react-native';
import { useTheme } from '../../theme';

interface Props {
  content: string;
  textColor: string;
}

export function StreamingText({ content, textColor }: Props) {
  const { typography: typo, colors } = useTheme();
  const opacity = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    const animation = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, {
          toValue: 0,
          duration: 400,
          useNativeDriver: true,
        }),
        Animated.timing(opacity, {
          toValue: 1,
          duration: 400,
          useNativeDriver: true,
        }),
      ])
    );
    animation.start();
    return () => animation.stop();
  }, []);

  return (
    <Text style={[styles.text, { color: textColor, fontSize: typo.body.fontSize, lineHeight: typo.body.lineHeight }]}>
      {content}
      <Animated.Text style={[styles.cursor, { opacity, color: colors.accent }]}>
        |
      </Animated.Text>
    </Text>
  );
}

const styles = StyleSheet.create({
  text: {
    flexWrap: 'wrap',
  },
  cursor: {
    fontWeight: '300',
    fontSize: 18,
  },
});
