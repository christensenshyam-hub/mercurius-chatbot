export interface Message {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: number;
  isStreaming?: boolean;
}

export interface Conversation {
  id: string;
  sessionId: string;
  title: string;
  lastMessage: string;
  lastTimestamp: number;
  messageCount: number;
}

export interface ChatResponse {
  reply: string;
  sessionId: string;
  mode: string;
  unlocked: boolean;
  justUnlocked?: boolean;
  streak: number;
  difficulty: number;
}

export interface CurriculumUnit {
  id: string;
  number: string;
  title: string;
  description: string;
  lessons: CurriculumLesson[];
}

export interface CurriculumLesson {
  id: string;
  title: string;
  objective: string;
  starter: string;
}

export interface Achievement {
  id: string;
  icon: string;
  name: string;
  desc: string;
}

export interface EventData {
  schedule?: {
    day: string;
    time: string;
    location: string;
  };
  upcoming?: Array<{
    date: string;
    title: string;
    description: string;
    type?: string;
  }>;
  past?: Array<{
    date: string;
    title: string;
    description: string;
  }>;
}

export interface BlogPost {
  id: string;
  title: string;
  author: string;
  date: string;
  category: string;
  summary: string;
  content: string;
}
