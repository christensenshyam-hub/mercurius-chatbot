import React, { useState, useEffect } from 'react';
import { View, Text, ScrollView, Pressable, Modal, ActivityIndicator, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';
import { fetchLeaderboard } from '../../services/api';
import { useSettingsStore } from '../../stores/useSettingsStore';

interface Props {
  visible: boolean;
  onClose: () => void;
}

export function LeaderboardPanel({ visible, onClose }: Props) {
  const { colors, typography: typo } = useTheme();
  const [entries, setEntries] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const studentName = useSettingsStore((s) => s.studentName);

  useEffect(() => {
    if (visible) {
      setLoading(true);
      fetchLeaderboard()
        .then(setEntries)
        .catch(() => setEntries([]))
        .finally(() => setLoading(false));
    }
  }, [visible]);

  const medals = ['#D4A843', '#A8A8A8', '#CD7F32'];

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.overlay}>
        <View style={[styles.panel, { backgroundColor: colors.surface }]}>
          <View style={styles.header}>
            <View style={[styles.handle, { backgroundColor: colors.border }]} />
            <View style={styles.headerRow}>
              <Icon name="trophy" size={20} color={colors.accent} />
              <Text style={[styles.title, { color: colors.text, ...typo.heading }]}>
                Leaderboard
              </Text>
              <Pressable onPress={onClose} hitSlop={12}>
                <Icon name="close" size={22} color={colors.textSecondary} />
              </Pressable>
            </View>
          </View>
          <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
            {loading ? (
              <ActivityIndicator size="large" color={colors.accent} style={{ paddingVertical: 40 }} />
            ) : entries.length === 0 ? (
              <Text style={[styles.empty, { color: colors.textSecondary, ...typo.body }]}>
                No leaderboard data yet. Keep learning!
              </Text>
            ) : (
              entries.map((entry: any, i: number) => {
                const isMe = entry.display_name === studentName || entry.student_name === studentName;
                return (
                  <View
                    key={i}
                    style={[
                      styles.row,
                      {
                        backgroundColor: isMe ? colors.accentDim : 'transparent',
                        borderColor: isMe ? colors.accent : colors.border,
                      },
                    ]}
                  >
                    <Text style={[styles.rank, { color: i < 3 ? (medals[i] || colors.text) : colors.textSecondary }]}>
                      {i + 1}
                    </Text>
                    <View style={styles.info}>
                      <Text style={[styles.name, { color: colors.text, ...typo.bodyMedium }]}>
                        {entry.display_name || entry.student_name || 'Student'}
                        {isMe ? ' (you)' : ''}
                      </Text>
                      <Text style={[styles.stats, { color: colors.textSecondary, ...typo.caption }]}>
                        {entry.message_count || 0} messages &middot; {entry.streak || 0} day streak
                      </Text>
                    </View>
                    {i === 0 && <Icon name="trophy" size={18} color={colors.accent} />}
                  </View>
                );
              })
            )}
          </ScrollView>
          <Pressable onPress={onClose} style={[styles.closeBtn, { backgroundColor: colors.accent }]}>
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
  empty: { textAlign: 'center', paddingVertical: 40 },
  row: { flexDirection: 'row', alignItems: 'center', padding: 12, borderRadius: 10, borderWidth: 1, marginBottom: 8, gap: 12 },
  rank: { fontSize: 18, fontWeight: '700', width: 28, textAlign: 'center' },
  info: { flex: 1 },
  name: {},
  stats: {},
  closeBtn: { marginHorizontal: 20, paddingVertical: 12, borderRadius: 12, alignItems: 'center' },
  closeBtnText: { color: '#fff', fontWeight: '600', fontSize: 16 },
});
