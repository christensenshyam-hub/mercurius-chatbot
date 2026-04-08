import React, { useRef, useEffect, useCallback } from 'react';
import { FlatList, StyleSheet } from 'react-native';
import { Message } from '../../types';
import { MessageBubble } from './MessageBubble';
import { TypingIndicator } from './TypingIndicator';

interface Props {
  messages: Message[];
  isLoading: boolean;
  onMessageLongPress?: (message: Message) => void;
}

export function MessageList({ messages, isLoading, onMessageLongPress }: Props) {
  const listRef = useRef<FlatList>(null);
  const prevCountRef = useRef(0);

  // Only auto-scroll when a NEW message is added (not on every delta)
  useEffect(() => {
    if (messages.length > prevCountRef.current) {
      setTimeout(() => {
        listRef.current?.scrollToEnd({ animated: true });
      }, 80);
    }
    prevCountRef.current = messages.length;
  }, [messages.length]);

  const renderItem = useCallback(
    ({ item }: { item: Message }) => (
      <MessageBubble message={item} onLongPress={onMessageLongPress} />
    ),
    [onMessageLongPress]
  );

  const keyExtractor = useCallback((item: Message) => item.id, []);

  return (
    <FlatList
      ref={listRef}
      data={messages}
      renderItem={renderItem}
      keyExtractor={keyExtractor}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
      keyboardDismissMode="interactive"
      keyboardShouldPersistTaps="handled"
      removeClippedSubviews={true}
      maxToRenderPerBatch={10}
      windowSize={7}
      ListFooterComponent={
        isLoading && messages[messages.length - 1]?.content === '' ? (
          <TypingIndicator />
        ) : null
      }
    />
  );
}

const styles = StyleSheet.create({
  content: {
    paddingTop: 12,
    paddingBottom: 8,
  },
});
