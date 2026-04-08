import React, { memo, useMemo } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Markdown from 'react-native-markdown-display';
import { useTheme } from '../../theme';
import { shadows } from '../../theme/colors';
import { Message } from '../../types';
import { StreamingText } from './StreamingText';

interface Props {
  message: Message;
  onLongPress?: (message: Message) => void;
}

export const MessageBubble = memo(
  function MessageBubble({ message, onLongPress }: Props) {
    const { colors, typography: typo, spacing } = useTheme();
    const isUser = message.role === 'user';
    const textColor = isUser ? colors.userBubbleText : colors.aiBubbleText;
    const isError = message.content.startsWith('Error:');

    // Memoize styles so they don't recreate on every streaming delta
    const bubbleStyle = useMemo(() => ({
      backgroundColor: isUser ? 'transparent' : colors.aiBubble,
      alignSelf: isUser ? ('flex-end' as const) : ('flex-start' as const),
      borderBottomRightRadius: isUser ? 4 : 18,
      borderBottomLeftRadius: isUser ? 18 : 4,
      maxWidth: '82%' as const,
      paddingHorizontal: isUser ? 0 : spacing.lg,
      paddingVertical: isUser ? 0 : spacing.md,
      marginBottom: spacing.sm,
      marginHorizontal: 16,
      borderTopLeftRadius: 20,
      borderTopRightRadius: 20,
      ...(isUser ? {} : {
        borderLeftWidth: 2,
        borderLeftColor: colors.accent,
      }),
      ...shadows.small,
    }), [isUser, colors, spacing]);

    const markdownStyles = useMemo(() => ({
      body: { color: textColor, fontSize: typo.body.fontSize, lineHeight: typo.body.lineHeight },
      heading1: { color: textColor, fontSize: 20, fontWeight: '600' as const, marginBottom: 8 },
      heading2: { color: textColor, fontSize: 18, fontWeight: '600' as const, marginBottom: 6 },
      heading3: { color: textColor, fontSize: 16, fontWeight: '600' as const, marginBottom: 4 },
      strong: { fontWeight: '600' as const },
      em: { fontStyle: 'italic' as const },
      link: { color: colors.accent },
      code_inline: {
        backgroundColor: isUser ? 'rgba(255,255,255,0.15)' : colors.surfaceElevated,
        color: textColor, fontSize: 14, paddingHorizontal: 5, paddingVertical: 1,
        borderRadius: 4, fontFamily: 'monospace',
      },
      fence: {
        backgroundColor: isUser ? 'rgba(255,255,255,0.1)' : colors.surfaceElevated,
        color: textColor, fontSize: 13, padding: 12, borderRadius: 10,
        fontFamily: 'monospace', overflow: 'hidden' as const,
      },
      bullet_list: { marginBottom: 6 },
      ordered_list: { marginBottom: 6 },
      list_item: { marginBottom: 3 },
      blockquote: {
        borderLeftWidth: 3, borderLeftColor: colors.accent,
        paddingLeft: 12, marginVertical: 6, opacity: 0.9,
      },
    }), [isUser, textColor, colors, typo]);

    const bubbleContent = message.isStreaming ? (
      <StreamingText content={message.content} textColor={textColor} />
    ) : (
      <Markdown style={markdownStyles}>{message.content}</Markdown>
    );

    return (
      <Pressable
        onLongPress={() => !isUser && onLongPress?.(message)}
        delayLongPress={400}
        style={[
          bubbleStyle,
          isError && { borderWidth: 1, borderColor: colors.error },
        ]}
      >
        {isUser ? (
          <LinearGradient
            colors={['#C9922A', '#b8841f']}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={{
              paddingHorizontal: spacing.lg,
              paddingVertical: spacing.md,
              borderTopLeftRadius: 20,
              borderTopRightRadius: 20,
              borderBottomRightRadius: 4,
              borderBottomLeftRadius: 18,
            }}
          >
            {bubbleContent}
          </LinearGradient>
        ) : (
          bubbleContent
        )}
      </Pressable>
    );
  },
  (prev, next) =>
    prev.message.content === next.message.content &&
    prev.message.isStreaming === next.message.isStreaming
);
