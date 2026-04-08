import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';
import { useChatStore } from '../../stores/useChatStore';
import { useSessionStore } from '../../stores/useSessionStore';
import * as db from '../../services/database';
import { Conversation } from '../../types';

function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

interface Tab {
  id: string;
  title: string;
}

export function ConversationTabs() {
  const { colors, typography: typo } = useTheme();
  const conversationId = useChatStore((s) => s.conversationId);
  const setConversationId = useChatStore((s) => s.setConversationId);
  const switchConversation = useChatStore((s) => s.switchConversation);
  const newConversation = useChatStore((s) => s.newConversation);
  const messages = useChatStore((s) => s.messages);
  const sessionId = useSessionStore((s) => s.sessionId);
  const [tabs, setTabs] = useState<Tab[]>([]);

  // Initialize: load open tabs or create first one
  useEffect(() => {
    const convs = db.getConversations();
    if (convs.length > 0) {
      const openTabs = convs.slice(0, 8).map((c) => ({
        id: c.id,
        title: c.title || 'Chat',
      }));
      setTabs(openTabs);
      if (!conversationId || !openTabs.find((t) => t.id === conversationId)) {
        switchConversation(openTabs[0].id);
      }
    } else {
      const id = generateId();
      setTabs([{ id, title: 'New Chat' }]);
      setConversationId(id);
      try {
        db.upsertConversation({
          id,
          sessionId,
          title: 'New Chat',
          lastMessage: '',
          lastTimestamp: Date.now(),
          messageCount: 0,
        } as Conversation);
      } catch {}
    }
  }, []);

  // Update tab title when first message arrives
  useEffect(() => {
    if (messages.length === 1 && messages[0].role === 'user' && conversationId) {
      const newTitle = messages[0].content.slice(0, 30) + (messages[0].content.length > 30 ? '...' : '');
      setTabs((prev) =>
        prev.map((t) => (t.id === conversationId ? { ...t, title: newTitle } : t))
      );
    }
  }, [messages, conversationId]);

  const handleSelectTab = useCallback(
    (id: string) => {
      if (id === conversationId) return;
      switchConversation(id);
    },
    [conversationId, switchConversation]
  );

  const handleNewTab = useCallback(() => {
    const id = generateId();
    const newTab = { id, title: 'New Chat' };
    setTabs((prev) => [...prev, newTab]);
    // Save current conversation to cache, then start fresh
    newConversation(id);
    try {
      db.upsertConversation({
        id,
        sessionId,
        title: 'New Chat',
        lastMessage: '',
        lastTimestamp: Date.now(),
        messageCount: 0,
      } as Conversation);
    } catch {}
  }, [newConversation, sessionId]);

  const handleCloseTab = useCallback(
    (id: string) => {
      if (tabs.length <= 1) return; // Keep at least one tab
      const remaining = tabs.filter((t) => t.id !== id);
      setTabs(remaining);
      if (id === conversationId) {
        const next = remaining[remaining.length - 1];
        switchConversation(next.id);
      }
    },
    [tabs, conversationId, switchConversation]
  );

  const currentTab = tabs.find((t) => t.id === conversationId);
  const currentTitle = currentTab?.title || 'New Chat';

  return (
    <View style={[styles.container, { backgroundColor: colors.surface, borderBottomColor: colors.border }]}>
      <View style={styles.header}>
        <Text style={[styles.title, { color: colors.text }]} numberOfLines={1}>
          {currentTitle}
        </Text>
        <Pressable
          onPress={handleNewTab}
          hitSlop={8}
          style={({ pressed }) => [
            styles.newChatBtn,
            {
              backgroundColor: pressed ? colors.accentLight : colors.accent,
            },
          ]}
        >
          <Icon name="add" size={16} color="#ffffff" />
          <Text style={styles.newChatLabel}>New Chat</Text>
        </Pressable>
      </View>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.scroll}
      >
        {tabs.map((tab) => {
          const isActive = tab.id === conversationId;
          return (
            <Pressable
              key={tab.id}
              onPress={() => handleSelectTab(tab.id)}
              style={[
                styles.tab,
                {
                  backgroundColor: isActive ? colors.background : 'transparent',
                  borderColor: isActive ? colors.border : 'transparent',
                },
              ]}
            >
              <Text
                style={[
                  styles.tabText,
                  {
                    color: isActive ? colors.text : colors.textSecondary,
                    fontWeight: isActive ? '600' : '400',
                  },
                ]}
                numberOfLines={1}
              >
                {tab.title}
              </Text>
              {tabs.length > 1 && (
                <Pressable
                  onPress={(e) => {
                    e.stopPropagation();
                    handleCloseTab(tab.id);
                  }}
                  hitSlop={8}
                  style={styles.closeBtn}
                >
                  <Text style={{ color: colors.textSecondary, fontSize: 12 }}>
                    {'\u2715'}
                  </Text>
                </Pressable>
              )}
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingTop: 8,
    paddingBottom: 8,
  },
  title: {
    fontSize: 20,
    fontWeight: '700',
    flex: 1,
    marginRight: 12,
  },
  newChatBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 20,
    gap: 4,
  },
  newChatLabel: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '600',
  },
  scroll: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  tab: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
    borderWidth: 1,
    maxWidth: 160,
    gap: 6,
  },
  tabText: {
    fontSize: 13,
    maxWidth: 110,
  },
  closeBtn: {
    padding: 2,
  },
});
