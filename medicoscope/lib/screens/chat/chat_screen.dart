import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/locale/app_strings.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/widgets/chat/chat_view.dart';

/// Opens the full-screen immersive medical-assistant chat with a fade/slide.
void openChatScreen(BuildContext context, {String? presetPrompt}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => ChatScreen(presetPrompt: presetPrompt),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .04), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    ),
  );
}

/// Full-screen medical-assistant chat: a gradient hero header over the shared
/// [ChatView]. The bottom sheet hosts the same [ChatView] for quick, in-context
/// questions and can expand into this screen.
class ChatScreen extends StatelessWidget {
  final String? presetPrompt;
  const ChatScreen({super.key, this.presetPrompt});

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;
    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : const Color(0xFFF5F7F8),
      body: Column(
        children: [
          _hero(context, isDark, lang),
          Expanded(
              child: ChatView(fullScreen: true, presetPrompt: presetPrompt)),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context, bool isDark, String lang) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.chatGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 14, 14),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 18),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.smart_toy_outlined,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.get('medical_assistant', lang),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                    Row(children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: Color(0xFFB8FFE6), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${AppStrings.get('online', lang)} · ${AppStrings.get('ai_powered_guidance', lang)}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: .9)),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
