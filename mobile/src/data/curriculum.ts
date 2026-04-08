import { CurriculumUnit, Achievement } from '../types';

export const CURRICULUM_UNITS: CurriculumUnit[] = [
  {
    id: 'unit_1',
    number: '01',
    title: 'How AI Actually Works',
    description: 'LLMs, training data, next-token prediction, and why AI sounds confident but can be wrong.',
    lessons: [
      { id: 'u1_l1', title: 'What happens when you type a prompt', objective: 'Understand tokenization and next-token prediction.', starter: '[CURRICULUM: Unit 1, Lesson 1] Teach me what physically happens inside an LLM when I type a prompt. Start with tokenization and next-token prediction. After explaining, give me a hands-on exercise.' },
      { id: 'u1_l2', title: 'Training data and where knowledge comes from', objective: 'Understand how LLMs are trained and what their knowledge actually is.', starter: "[CURRICULUM: Unit 1, Lesson 2] Explain where an LLM's knowledge comes from — training data, RLHF, and fine-tuning. After the explanation, give me an exercise to test my understanding." },
      { id: 'u1_l3', title: 'Why AI sounds confident but can be wrong', objective: 'Understand hallucination and the confidence-accuracy gap.', starter: '[CURRICULUM: Unit 1, Lesson 3] Teach me about AI hallucination and why LLMs can sound confident even when wrong. Give a concrete example, then an exercise where I have to identify a potential hallucination.' },
      { id: 'u1_l4', title: 'Unit review and application', objective: 'Apply everything from Unit 1 to a real scenario.', starter: '[CURRICULUM: Unit 1, Lesson 4 - Review] Give me a comprehensive exercise that tests everything from Unit 1: tokenization, training data, and hallucination. Then grade my performance and tell me what to revisit.' },
    ],
  },
  {
    id: 'unit_2',
    number: '02',
    title: 'Bias & Fairness',
    description: 'Where AI bias comes from, real examples like COMPAS and facial recognition, and why "objective algorithm" is a myth.',
    lessons: [
      { id: 'u2_l1', title: 'Where bias enters AI systems', objective: 'Understand the pipeline of bias: data, design, deployment.', starter: '[CURRICULUM: Unit 2, Lesson 1] Walk me through how bias enters AI systems at each stage — data collection, model design, and deployment. After explaining, give me an exercise.' },
      { id: 'u2_l2', title: 'Case study: COMPAS and criminal justice', objective: 'Analyze a real-world case of algorithmic bias.', starter: '[CURRICULUM: Unit 2, Lesson 2] Teach me about the COMPAS algorithm and what went wrong. Present the case, then give me an exercise where I analyze the tradeoffs involved.' },
      { id: 'u2_l3', title: 'Facial recognition and representation', objective: 'Understand bias in computer vision systems.', starter: "[CURRICULUM: Unit 2, Lesson 3] Explain the bias problems in facial recognition systems — the Gender Shades study and Joy Buolamwini's work. Then give me an exercise." },
      { id: 'u2_l4', title: 'Unit review: building a bias audit', objective: 'Apply bias analysis to a new scenario.', starter: '[CURRICULUM: Unit 2, Lesson 4 - Review] Give me a scenario where an AI system is being deployed and have me conduct a bias audit. Grade my analysis and provide detailed feedback.' },
    ],
  },
  {
    id: 'unit_3',
    number: '03',
    title: 'AI in Society',
    description: 'AI in hiring, healthcare, criminal justice, and education — who benefits, who gets harmed, and what the stakes are.',
    lessons: [
      { id: 'u3_l1', title: 'AI in hiring and employment', objective: 'Understand automated hiring tools and their consequences.', starter: '[CURRICULUM: Unit 3, Lesson 1] Teach me how AI is used in hiring — resume screening, video interviews, personality analysis. What are the benefits and what can go wrong? Then give me an exercise.' },
      { id: 'u3_l2', title: 'AI in healthcare', objective: 'Evaluate AI applications in medical contexts.', starter: '[CURRICULUM: Unit 3, Lesson 2] Walk me through how AI is used in healthcare — diagnostics, drug discovery, triage. What are the stakes when it fails? Give me an exercise after.' },
      { id: 'u3_l3', title: 'AI in education', objective: 'Think critically about AI tools in learning.', starter: '[CURRICULUM: Unit 3, Lesson 3] How is AI changing education — tutoring, grading, plagiarism detection? What should students and teachers be aware of? Give me an exercise.' },
      { id: 'u3_l4', title: 'Unit review: stakeholder analysis', objective: 'Map who benefits and who is harmed by an AI system.', starter: '[CURRICULUM: Unit 3, Lesson 4 - Review] Present me with a real AI deployment scenario and have me do a full stakeholder analysis: who benefits, who is harmed, what are the power dynamics. Grade my work.' },
    ],
  },
  {
    id: 'unit_4',
    number: '04',
    title: 'Prompt Engineering',
    description: 'How framing changes outputs, few-shot prompting, and how to use AI tools critically rather than passively.',
    lessons: [
      { id: 'u4_l1', title: 'How framing changes everything', objective: 'Learn how different phrasings produce different outputs.', starter: '[CURRICULUM: Unit 4, Lesson 1] Show me how the way I phrase a prompt completely changes the output. Give me examples of the same question asked 3 different ways with different results. Then give me a practice exercise.' },
      { id: 'u4_l2', title: 'Few-shot prompting and chain-of-thought', objective: 'Master intermediate prompting techniques.', starter: '[CURRICULUM: Unit 4, Lesson 2] Teach me few-shot prompting and chain-of-thought techniques. Explain each with examples, then give me exercises where I practice both.' },
      { id: 'u4_l3', title: 'Critical prompting: getting AI to admit uncertainty', objective: 'Learn how to prompt for honesty, not just answers.', starter: '[CURRICULUM: Unit 4, Lesson 3] Teach me how to prompt AI to be more honest — asking for confidence levels, requesting counterarguments, forcing nuance. Give me exercises to practice.' },
      { id: 'u4_l4', title: 'Unit review: prompt challenge', objective: 'Solve a real problem using advanced prompting.', starter: '[CURRICULUM: Unit 4, Lesson 4 - Review] Give me a challenging real-world task and have me write the best prompt I can for it. Then critique my prompt and suggest improvements. Grade my technique.' },
    ],
  },
  {
    id: 'unit_5',
    number: '05',
    title: 'Ethics & Alignment',
    description: 'The hardest problems: alignment, autonomous weapons, corporate responsibility, and what happens when AI fails.',
    lessons: [
      { id: 'u5_l1', title: 'The alignment problem', objective: 'Understand why aligning AI with human values is hard.', starter: '[CURRICULUM: Unit 5, Lesson 1] Explain the alignment problem in AI — what it is, why it is hard, and what the stakes are. Use concrete examples. Then give me an exercise.' },
      { id: 'u5_l2', title: 'Autonomous weapons and lethal AI', objective: 'Grapple with the ethics of autonomous weapons systems.', starter: '[CURRICULUM: Unit 5, Lesson 2] Teach me about autonomous weapons and the debate around lethal AI decision-making. Present both sides, then give me a scenario-based exercise.' },
      { id: 'u5_l3', title: 'Corporate responsibility and open vs. closed AI', objective: 'Understand who controls AI and why it matters.', starter: '[CURRICULUM: Unit 5, Lesson 3] Walk me through the debate about open vs. closed AI models and corporate responsibility. Who should control AI development? Exercise after.' },
      { id: 'u5_l4', title: 'Final review: your AI ethics framework', objective: 'Build a personal ethical framework for AI.', starter: '[CURRICULUM: Unit 5, Lesson 4 - Final Review] Have me build my own AI ethics framework from everything I have learned across all 5 units. Ask me hard questions, challenge my reasoning, and grade the result.' },
    ],
  },
];

export const ACHIEVEMENTS: Achievement[] = [
  { id: 'first_chat', icon: 'I', name: 'First Conversation', desc: 'Sent your first message to Mercurius' },
  { id: 'critical_thinker', icon: 'II', name: 'Critical Thinker', desc: 'Unlocked Direct Mode by demonstrating genuine thinking' },
  { id: 'debate_starter', icon: 'III', name: 'Debate Starter', desc: 'Entered Debate Mode and challenged Mercurius' },
  { id: 'fact_checker', icon: 'IV', name: 'Fact Checker', desc: 'Used the Fact Check tool to verify an AI claim' },
  { id: 'analyst', icon: 'V', name: 'AI Output Analyst', desc: 'Analyzed an AI-generated response critically' },
  { id: 'meeting_prepper', icon: 'VI', name: 'Meeting Prepper', desc: 'Generated a pre-meeting briefing' },
  { id: 'bookmarker', icon: 'VII', name: 'Bookmarker', desc: 'Saved your first conversation highlight' },
  { id: 'streak_3', icon: 'VIII', name: '3-Day Streak', desc: 'Learned with Mercurius 3 days in a row' },
  { id: 'streak_7', icon: 'IX', name: 'Weekly Scholar', desc: 'Kept a 7-day learning streak' },
  { id: 'deep_diver', icon: 'X', name: 'Deep Diver', desc: 'Sent 20 or more messages in your sessions' },
  { id: 'challenger', icon: 'XI', name: 'Challenger', desc: 'Started the weekly club challenge' },
  { id: 'quiz_master', icon: 'XII', name: 'Quiz Master', desc: 'Scored 3 or more on a comprehension quiz' },
  { id: 'curriculum_unit', icon: 'XIII', name: 'Curriculum Explorer', desc: 'Started a structured curriculum unit' },
];
