import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { zustandStorage } from '../services/storage';

interface CurriculumState {
  completedLessons: Record<string, boolean>;
  earnedBadges: string[];
  markLessonComplete: (lessonId: string) => void;
  earnBadge: (badgeId: string) => void;
  isLessonComplete: (lessonId: string) => boolean;
  hasBadge: (badgeId: string) => boolean;
  getUnitProgress: (lessonIds: string[]) => { completed: number; total: number };
}

export const useCurriculumStore = create<CurriculumState>()(
  persist(
    (set, get) => ({
      completedLessons: {},
      earnedBadges: [],

      markLessonComplete: (lessonId) =>
        set((state) => ({
          completedLessons: { ...state.completedLessons, [lessonId]: true },
        })),

      earnBadge: (badgeId) =>
        set((state) => ({
          earnedBadges: state.earnedBadges.includes(badgeId)
            ? state.earnedBadges
            : [...state.earnedBadges, badgeId],
        })),

      isLessonComplete: (lessonId) => !!get().completedLessons[lessonId],

      hasBadge: (badgeId) => get().earnedBadges.includes(badgeId),

      getUnitProgress: (lessonIds) => {
        const completed = lessonIds.filter(
          (id) => !!get().completedLessons[id]
        ).length;
        return { completed, total: lessonIds.length };
      },
    }),
    {
      name: 'curriculum-store',
      storage: createJSONStorage(() => zustandStorage),
    }
  )
);
