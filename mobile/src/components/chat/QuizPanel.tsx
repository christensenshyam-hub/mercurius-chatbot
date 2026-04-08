import React, { useState, useEffect } from 'react';
import { View, Text, ScrollView, Pressable, Modal, ActivityIndicator, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import Markdown from 'react-native-markdown-display';
import { useTheme } from '../../theme';
import { fetchQuiz } from '../../services/api';
import { useSessionStore } from '../../stores/useSessionStore';
import { useChatStore } from '../../stores/useChatStore';

interface Props {
  visible: boolean;
  onClose: () => void;
}

export function QuizPanel({ visible, onClose }: Props) {
  const { colors, typography: typo } = useTheme();
  const [quiz, setQuiz] = useState('');
  const [loading, setLoading] = useState(false);
  const sessionId = useSessionStore((s) => s.sessionId);
  const messages = useChatStore((s) => s.messages);

  useEffect(() => {
    if (visible && !quiz) {
      setLoading(true);
      const msgHistory = messages.map((m) => ({ role: m.role, content: m.content }));
      fetchQuiz(sessionId, msgHistory)
        .then(setQuiz)
        .catch(() => setQuiz('Could not generate quiz. Try again later.'))
        .finally(() => setLoading(false));
    }
  }, [visible]);

  const markdownStyles = {
    body: { color: colors.text, fontSize: typo.body.fontSize, lineHeight: 22 },
    heading2: { color: colors.accent, fontSize: 18, fontWeight: '600' as const, marginBottom: 8 },
    strong: { fontWeight: '600' as const, color: colors.accent },
    link: { color: colors.accent },
  };

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.overlay}>
        <View style={[styles.panel, { backgroundColor: colors.surface }]}>
          <View style={styles.header}>
            <View style={[styles.handle, { backgroundColor: colors.border }]} />
            <View style={styles.headerRow}>
              <Icon name="help-circle" size={20} color={colors.accent} />
              <Text style={[styles.title, { color: colors.text, ...typo.heading }]}>
                Comprehension Quiz
              </Text>
              <Pressable onPress={onClose} hitSlop={12}>
                <Icon name="close" size={22} color={colors.textSecondary} />
              </Pressable>
            </View>
          </View>
          <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
            {loading ? (
              <View style={styles.loadingContainer}>
                <ActivityIndicator size="large" color={colors.accent} />
                <Text style={[styles.loadingText, { color: colors.textSecondary, ...typo.caption }]}>
                  Generating quiz from your conversation...
                </Text>
              </View>
            ) : (
              <Markdown style={markdownStyles}>{quiz}</Markdown>
            )}
          </ScrollView>
          <Pressable
            onPress={() => { setQuiz(''); onClose(); }}
            style={[styles.closeBtn, { backgroundColor: colors.accent }]}
          >
            <Text style={styles.closeBtnText}>Done</Text>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'flex-end' },
  panel: { borderTopLeftRadius: 24, borderTopRightRadius: 24, maxHeight: '75%', paddingBottom: 34 },
  header: { paddingTop: 12, paddingHorizontal: 20 },
  handle: { width: 36, height: 4, borderRadius: 2, alignSelf: 'center', marginBottom: 14 },
  headerRow: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 12 },
  title: { flex: 1 },
  content: { paddingHorizontal: 20, paddingBottom: 16 },
  loadingContainer: { alignItems: 'center', paddingVertical: 40, gap: 12 },
  loadingText: { textAlign: 'center' },
  closeBtn: { marginHorizontal: 20, paddingVertical: 12, borderRadius: 12, alignItems: 'center' },
  closeBtnText: { color: '#fff', fontWeight: '600', fontSize: 16 },
});
