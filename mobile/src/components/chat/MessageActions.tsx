import React from 'react';
import { View, Text, Pressable, Modal, StyleSheet } from 'react-native';
import { Icon } from '../ui/Icon';
import { useTheme } from '../../theme';
import * as Clipboard from 'expo-clipboard';

interface Props {
  visible: boolean;
  messageContent: string;
  onClose: () => void;
  onBookmark: () => void;
  onUnpack: () => void;
  onFlag: () => void;
}

const ACTIONS = [
  { id: 'bookmark', label: 'Bookmark', icon: 'bookmark', color: 'accent' as const },
  { id: 'unpack', label: 'Unpack This', icon: 'search', color: 'text' as const },
  { id: 'flag', label: 'Fact-Check', icon: 'flag', color: 'warning' as const },
  { id: 'copy', label: 'Copy Text', icon: 'copy', color: 'textSecondary' as const },
];

export function MessageActions({ visible, messageContent, onClose, onBookmark, onUnpack, onFlag }: Props) {
  const { colors, typography: typo } = useTheme();

  const handleAction = async (actionId: string) => {
    switch (actionId) {
      case 'bookmark':
        onBookmark();
        break;
      case 'unpack':
        onUnpack();
        break;
      case 'flag':
        onFlag();
        break;
      case 'copy':
        try { await Clipboard.setStringAsync(messageContent); } catch {}
        break;
    }
    onClose();
  };

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.overlay} onPress={onClose}>
        <View style={[styles.sheet, { backgroundColor: colors.surface, borderColor: colors.border }]}>
          <View style={[styles.handle, { backgroundColor: colors.border }]} />
          <Text style={[styles.title, { color: colors.textSecondary, ...typo.caption }]}>
            MESSAGE ACTIONS
          </Text>
          {ACTIONS.map((action) => (
            <Pressable
              key={action.id}
              onPress={() => handleAction(action.id)}
              style={({ pressed }) => [
                styles.actionRow,
                { backgroundColor: pressed ? colors.surfaceElevated : 'transparent' },
              ]}
            >
              <View style={[styles.actionIcon, { backgroundColor: colors.surfaceElevated }]}>
                <Icon name={action.icon} size={18} color={(colors as any)[action.color]} />
              </View>
              <Text style={[styles.actionLabel, { color: colors.text, ...typo.body }]}>
                {action.label}
              </Text>
              <Icon name="chevron-forward" size={16} color={colors.textSecondary} />
            </Pressable>
          ))}
        </View>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  sheet: {
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    paddingBottom: 34,
    paddingTop: 12,
  },
  handle: {
    width: 36,
    height: 4,
    borderRadius: 2,
    alignSelf: 'center',
    marginBottom: 16,
  },
  title: {
    fontWeight: '600',
    letterSpacing: 1,
    paddingHorizontal: 20,
    marginBottom: 8,
  },
  actionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 14,
    gap: 14,
  },
  actionIcon: {
    width: 36,
    height: 36,
    borderRadius: 10,
    justifyContent: 'center',
    alignItems: 'center',
  },
  actionLabel: {
    flex: 1,
  },
});
