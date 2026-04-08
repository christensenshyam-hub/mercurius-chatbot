// Web stub — SQLite is not available on web, all operations are no-ops
import { Message, Conversation } from '../types';

export function getConversations(): Conversation[] { return []; }
export function getMessages(_conversationId: string, _limit?: number, _offset?: number): Message[] { return []; }
export function insertMessage(_conversationId: string, _msg: Message) {}
export function upsertConversation(_conv: Conversation) {}
export function deleteConversation(_id: string) {}
