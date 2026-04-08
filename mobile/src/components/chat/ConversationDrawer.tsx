import React, { useEffect, useState } from 'react';
import { View, Text, Pressable, Modal, ScrollView, StyleSheet, Alert } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';
import * as db from '../../services/database';
import { Conversation } from '../../types';
import { useChatStore } from '../../stores/useChatStore';
import { useSessionStore } from '../../stores/useSessionStore';

interface Props {
  visible: boolean;
  onClose: () => void;
}

function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

function timeAgo(ts: number): string {
  const diff = Date.now() - ts;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'Just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(ts).toLocaleDateString();
}

export function ConversationDrawer({ visible, onClose }: Props) {
  const { colors, typography: typo } = useTheme();
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const setConversationId = useChatStore((s) => s.setConversationId);
  const loadMessages = useChatStore((s) => s.loadMessages);
  const clearMessages = useChatStore((s) => s.clearMessages);
  const sessionId = useSessionStore((s) => s.sessionId);

  useEffect(() => {
    if (visible) {
      setConversations(db.getConversations());
    }
  }, [visible]);

  const handleNewChat = () => {
    const id = generateId();
    clearMessages();
    setConversationId(id);
    try {
      db.upsertConversation({
        id,
        sessionId,
        title: 'New Conversation',
        lastMessage: '',
        lastTimestamp: Date.now(),
        messageCount: 0,
      } as Conversation);
    } catch {}
    onClose();
  };

  const handleSelectConversation = (conv: Conversation) => {
    setConversationId(conv.id);
    loadMessages(conv.id);
    onClose();
  };

  const handleDelete = (conv: Conversation) => {
    Alert.alert('Delete Conversation', `Delete "${conv.title}"?`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          db.deleteConversation(conv.id);
          setConversations((prev) => prev.filter((c) => c.id !== conv.id));
        },
      },
    ]);
  };

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.overlay}>
        <Pressable style={styles.backdrop} onPress={onClose} />
        <View style={[styles.drawer, { backgroundColor: colors.surface }]}>
          <View style={styles.header}>
            <Text style={[styles.headerTitle, { color: colors.text, ...typo.heading }]}>
              Conversations
            </Text>
            <Pressable onPress={onClose} hitSlop={12}>
              <Icon name="close" size={22} color={colors.textSecondary} />
            </Pressable>
          </View>

          <Pressable
            onPress={handleNewChat}
            style={[styles.newChatBtn, { backgroundColor: colors.accent }]}
          >
            <Icon name="add" size={20} color="#fff" />
            <Text style={styles.newChatText}>New Chat</Text>
          </Pressable>

          <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.list}>
            {conversations.length === 0 ? (
              <Text style={[styles.empty, { color: colors.textSecondary, ...typo.body }]}>
                No conversations yet
              </Text>
            ) : (
              conversations.map((conv) => (
                <Pressable
                  key={conv.id}
                  onPress={() => handleSelectConversation(conv)}
                  onLongPress={() => handleDelete(conv)}
                  style={({ pressed }) => [
                    styles.convRow,
                    {
                      backgroundColor: pressed ? colors.surfaceElevated : 'transparent',
                      borderColor: colors.border,
                    },
                  ]}
                >
                  <View style={[styles.convIcon, { backgroundColor: colors.accentDim }]}>
                    <Icon name="chatbubble" size={16} color={colors.accent} />
                  </View>
                  <View style={styles.convInfo}>
                    <Text style={[styles.convTitle, { color: colors.text, ...typo.bodyMedium }]} numberOfLines={1}>
                      {conv.title || 'Untitled'}
                    </Text>
                    <Text style={[styles.convPreview, { color: colors.textSecondary, ...typo.caption }]} numberOfLines={1}>
                      {conv.lastMessage || 'No messages'}
                    </Text>
                  </View>
                  <Text style={[styles.convTime, { color: colors.gray, ...typo.caption }]}>
                    {conv.lastTimestamp ? timeAgo(conv.lastTimestamp) : ''}
                  </Text>
                </Pressable>
              ))
            )}
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: { flex: 1, flexDirection: 'row' },
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.4)' },
  drawer: { width: 300, paddingTop: 60 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, marginBottom: 16 },
  headerTitle: {},
  newChatBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginHorizontal: 16, paddingVertical: 10, borderRadius: 10, gap: 6, marginBottom: 16 },
  newChatText: { color: '#fff', fontWeight: '600', fontSize: 15 },
  list: { paddingHorizontal: 8, paddingBottom: 32 },
  empty: { textAlign: 'center', paddingVertical: 32 },
  convRow: { flexDirection: 'row', alignItems: 'center', padding: 12, borderRadius: 10, borderWidth: StyleSheet.hairlineWidth, marginBottom: 6, gap: 10 },
  convIcon: { width: 36, height: 36, borderRadius: 18, justifyContent: 'center', alignItems: 'center' },
  convInfo: { flex: 1 },
  convTitle: {},
  convPreview: {},
  convTime: { fontSize: 11 },
});
