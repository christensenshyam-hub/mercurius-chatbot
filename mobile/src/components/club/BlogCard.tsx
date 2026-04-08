import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';
import { BlogPost } from '../../types';

interface Props {
  post: BlogPost;
  onPress: () => void;
}

export function BlogCard({ post, onPress }: Props) {
  const { colors, typography: typo } = useTheme();

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.card,
        {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          opacity: pressed ? 0.8 : 1,
        },
      ]}
    >
      <View style={styles.header}>
        <View style={[styles.categoryBadge, { backgroundColor: colors.accentDim }]}>
          <Text style={[styles.category, { color: colors.accent, ...typo.caption }]}>
            {post.category}
          </Text>
        </View>
        <Text style={[styles.date, { color: colors.textSecondary, ...typo.caption }]}>
          {post.date}
        </Text>
      </View>
      <Text style={[styles.title, { color: colors.text, ...typo.bodyMedium }]} numberOfLines={2}>
        {post.title}
      </Text>
      <Text style={[styles.author, { color: colors.textSecondary, ...typo.caption }]}>
        by {post.author}
      </Text>
      <Text style={[styles.summary, { color: colors.textSecondary, ...typo.caption }]} numberOfLines={2}>
        {post.summary}
      </Text>
      <View style={styles.readMore}>
        <Text style={[styles.readMoreText, { color: colors.accent, ...typo.caption }]}>
          Read more
        </Text>
        <Icon name="arrow-forward" size={14} color={colors.accent} />
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    padding: 14,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    marginBottom: 10,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  categoryBadge: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 8,
  },
  category: {
    fontWeight: '600',
    textTransform: 'capitalize',
  },
  date: {},
  title: {
    marginBottom: 4,
  },
  author: {
    marginBottom: 6,
  },
  summary: {
    marginBottom: 8,
  },
  readMore: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  readMoreText: {
    fontWeight: '600',
  },
});
