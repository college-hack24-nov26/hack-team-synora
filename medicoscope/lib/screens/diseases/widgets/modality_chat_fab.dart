import 'package:flutter/material.dart';

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/screens/chat/chat_bottom_sheet.dart';

/// Floating chatbot FAB for every modality / deck / result screen.
/// The underlying chatbot already receives the live disease-risk summary
/// (via `ChatService.fetchMedicalContext` → `DiseaseRiskStore.chatbotSummary`),
/// so questions about the patient's latest screening are answered off the
/// freshest data without us having to forward it explicitly here.
class ModalityChatFab extends StatelessWidget {
  final DiseaseType? disease;

  const ModalityChatFab({super.key, this.disease});

  @override
  Widget build(BuildContext context) {
    final accent = disease == null
        ? const Color(0xFF7C4DFF)
        : DiseaseRegistry.of(disease!).gradient.first;
    // heroTag `null` disables the hero animation entirely — prevents
    // duplicate-hero-tag crashes when the same FAB is visible across
    // multiple routes simultaneously (nested navigators, bottom sheets).
    return FloatingActionButton.extended(
      heroTag: null,
      onPressed: () => showChatBottomSheet(context),
      backgroundColor: accent,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.psychology_alt_rounded),
      label: const Text(
        'Ask AI',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
