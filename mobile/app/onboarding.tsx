import React, { useRef, useState } from 'react';
import { View, Text, Pressable, FlatList, Dimensions, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { LinearGradient } from 'expo-linear-gradient';
import { Icon } from '../src/components/ui/Icon';
import { useTheme } from '../src/theme';
import { gradients } from '../src/theme/colors';
import { zustandStorage } from '../src/services/storage';

const { width } = Dimensions.get('window');

const PAGES = [
  {
    icon: 'chatbubbles',
    title: 'Meet Mercurius',
    subtitle: 'Your AI Literacy Tutor',
    description: 'An AI that teaches you to think critically about AI. Powered by the Socratic method — questions before answers.',
  },
  {
    icon: 'school',
    title: 'Learn by Asking',
    subtitle: '5 Units, 20 Lessons',
    description: 'Master AI literacy through structured curriculum: how AI works, bias, societal impact, prompt engineering, and ethics.',
  },
  {
    icon: 'trophy',
    title: 'Track Your Progress',
    subtitle: '13 Achievements to Earn',
    description: 'Earn badges, maintain streaks, take quizzes, and unlock advanced modes as you develop your critical thinking skills.',
  },
];

export default function OnboardingScreen() {
  const { colors, typography: typo, isDark } = useTheme();
  const router = useRouter();
  const [activeIndex, setActiveIndex] = useState(0);
  const listRef = useRef<FlatList>(null);
  const grad = isDark ? gradients.dark : gradients.light;

  const handleGetStarted = () => {
    zustandStorage.setItem('hasOnboarded', 'true');
    router.replace('/(tabs)/chat');
  };

  const handleNext = () => {
    if (activeIndex < PAGES.length - 1) {
      listRef.current?.scrollToIndex({ index: activeIndex + 1, animated: true });
    } else {
      handleGetStarted();
    }
  };

  return (
    <LinearGradient colors={grad.background} style={styles.container}>
      <FlatList
        ref={listRef}
        data={PAGES}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        onMomentumScrollEnd={(e) => {
          setActiveIndex(Math.round(e.nativeEvent.contentOffset.x / width));
        }}
        keyExtractor={(_, i) => String(i)}
        renderItem={({ item }) => (
          <View style={[styles.page, { width }]}>
            <View style={[styles.iconCircle, { backgroundColor: colors.accentDim }]}>
              <Icon name={item.icon} size={48} color={colors.accent} />
            </View>
            <Text style={[styles.title, { color: colors.accent, ...typo.title }]}>
              {item.title}
            </Text>
            <Text style={[styles.subtitle, { color: colors.text, ...typo.heading }]}>
              {item.subtitle}
            </Text>
            <Text style={[styles.description, { color: colors.textSecondary, ...typo.body }]}>
              {item.description}
            </Text>
          </View>
        )}
      />

      {/* Dots */}
      <View style={styles.dots}>
        {PAGES.map((_, i) => (
          <View
            key={i}
            style={[
              styles.dot,
              {
                backgroundColor: i === activeIndex ? colors.accent : colors.border,
                width: i === activeIndex ? 24 : 8,
              },
            ]}
          />
        ))}
      </View>

      {/* Buttons */}
      <View style={styles.buttons}>
        {activeIndex < PAGES.length - 1 ? (
          <>
            <Pressable onPress={handleGetStarted}>
              <Text style={[styles.skipText, { color: colors.textSecondary, ...typo.body }]}>
                Skip
              </Text>
            </Pressable>
            <Pressable onPress={handleNext} style={[styles.nextBtn, { backgroundColor: colors.accent }]}>
              <Text style={styles.nextBtnText}>Next</Text>
              <Icon name="arrow-forward" size={18} color="#fff" />
            </Pressable>
          </>
        ) : (
          <Pressable
            onPress={handleGetStarted}
            style={[styles.getStartedBtn, { backgroundColor: colors.accent }]}
          >
            <Text style={styles.getStartedText}>Get Started</Text>
            <Icon name="rocket" size={18} color="#fff" />
          </Pressable>
        )}
      </View>
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  page: { justifyContent: 'center', alignItems: 'center', paddingHorizontal: 40, paddingBottom: 120 },
  iconCircle: { width: 100, height: 100, borderRadius: 50, justifyContent: 'center', alignItems: 'center', marginBottom: 24 },
  title: { marginBottom: 6, textAlign: 'center' },
  subtitle: { marginBottom: 16, textAlign: 'center' },
  description: { textAlign: 'center', lineHeight: 24 },
  dots: { flexDirection: 'row', justifyContent: 'center', gap: 8, marginBottom: 24 },
  dot: { height: 8, borderRadius: 4 },
  buttons: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 24, paddingBottom: 48 },
  skipText: {},
  nextBtn: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 24, paddingVertical: 14, borderRadius: 14, gap: 6 },
  nextBtnText: { color: '#fff', fontWeight: '600', fontSize: 16 },
  getStartedBtn: { flex: 1, flexDirection: 'row', justifyContent: 'center', alignItems: 'center', paddingVertical: 16, borderRadius: 14, gap: 8 },
  getStartedText: { color: '#fff', fontWeight: '700', fontSize: 18 },
});
