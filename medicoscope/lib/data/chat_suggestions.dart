import 'package:flutter/material.dart';

/// A tappable starter prompt shown in the chat. [label] is the short chip text;
/// [prompt] is the full message actually sent to the assistant.
class ChatSuggestion {
  final String label;
  final String prompt;
  final IconData icon;
  const ChatSuggestion(this.label, this.prompt, this.icon);
}

/// Context-aware starter prompts. When the patient already has screenings/vitals
/// we steer toward interpreting their own data; otherwise toward getting started.
List<ChatSuggestion> buildChatSuggestions({required bool hasHealthData}) {
  if (hasHealthData) {
    return const [
      ChatSuggestion(
        'Explain my last screening',
        'Explain my most recent screening result in simple terms, and tell me what I should do next.',
        Icons.summarize_outlined,
      ),
      ChatSuggestion(
        'What do my vitals mean?',
        'Look at my recent vitals (blood pressure, heart rate, SpO2) and tell me if anything needs attention.',
        Icons.monitor_heart_outlined,
      ),
      ChatSuggestion(
        'Am I at risk?',
        'Based on all of my health data, which conditions am I most at risk for, and how do I lower that risk?',
        Icons.health_and_safety_outlined,
      ),
      ChatSuggestion(
        'Book an appointment',
        'Book an appointment with my doctor tomorrow at 10 am.',
        Icons.event_available_outlined,
      ),
    ];
  }
  return const [
    ChatSuggestion(
      'I feel unwell',
      'I have been feeling tired and a bit dizzy lately. What could be going on, and what should I check?',
      Icons.sick_outlined,
    ),
    ChatSuggestion(
      'Check my symptoms',
      'I want to check some symptoms. Ask me a few questions to understand what might be wrong.',
      Icons.checklist_rtl_outlined,
    ),
    ChatSuggestion(
      'Which screening first?',
      'Which MedicoScope screening should I start with for a general health check?',
      Icons.biotech_outlined,
    ),
    ChatSuggestion(
      'Book an appointment',
      'Book an appointment with my doctor tomorrow at 10 am.',
      Icons.event_available_outlined,
    ),
  ];
}
