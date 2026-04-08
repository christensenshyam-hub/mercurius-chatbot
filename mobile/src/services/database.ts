import { Platform } from 'react-native';
import { Message, Conversation } from '../types';

let db: any = null;

function getDb() {
  if (db) return db;
  if (Platform.OS === 'web') return null;

  try {
    const SQLite = require('expo-sqlite');
    db = SQLite.openDatabaseSync('mercurius-mobile.db');
    db.execSync(`
      CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        title TEXT NOT NULL,
        last_message TEXT,
        last_timestamp INTEGER,
        message_count INTEGER DEFAULT 0,
        created_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      );
      CREATE INDEX IF NOT EXISTS idx_msg_conv ON messages(conversation_id, timestamp);
    `);
    return db;
  } catch {
    return null;
  }
}

export function getConversations(): Conversation[] {
  const d = getDb();
  if (!d) return [];
  try {
    return d.getAllSync(
      'SELECT id, session_id as sessionId, title, last_message as lastMessage, last_timestamp as lastTimestamp, message_count as messageCount FROM conversations ORDER BY last_timestamp DESC'
    ) as Conversation[];
  } catch { return []; }
}

export function getMessages(conversationId: string, limit = 50, offset = 0): Message[] {
  const d = getDb();
  if (!d) return [];
  try {
    return d.getAllSync(
      'SELECT id, role, content, timestamp FROM messages WHERE conversation_id = ? ORDER BY timestamp ASC LIMIT ? OFFSET ?',
      [conversationId, limit, offset]
    ) as Message[];
  } catch { return []; }
}

export function insertMessage(conversationId: string, msg: Message) {
  const d = getDb();
  if (!d) return;
  try {
    d.runSync(
      'INSERT OR REPLACE INTO messages (id, conversation_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)',
      [msg.id, conversationId, msg.role, msg.content, msg.timestamp]
    );
  } catch {}
}

export function upsertConversation(conv: Conversation) {
  const d = getDb();
  if (!d) return;
  try {
    d.runSync(
      `INSERT INTO conversations (id, session_id, title, last_message, last_timestamp, message_count, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         title = excluded.title,
         last_message = excluded.last_message,
         last_timestamp = excluded.last_timestamp,
         message_count = excluded.message_count`,
      [conv.id, conv.sessionId, conv.title, conv.lastMessage, conv.lastTimestamp, conv.messageCount, conv.lastTimestamp]
    );
  } catch {}
}

export function deleteConversation(id: string) {
  const d = getDb();
  if (!d) return;
  try {
    d.runSync('DELETE FROM messages WHERE conversation_id = ?', [id]);
    d.runSync('DELETE FROM conversations WHERE id = ?', [id]);
  } catch {}
}
