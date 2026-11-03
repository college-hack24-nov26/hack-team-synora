import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/locale/app_strings.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/screens/chat/chat_screen.dart';
import 'package:medicoscope/widgets/chat/chat_view.dart';

/// Quick, in-context medical-assistant chat in a draggable bottom sheet. Hosts
/// the SAME [ChatView] as the full-screen [ChatScreen] and can expand into it.
void showChatBottomSheet(BuildContext context, {String? presetPrompt}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ChatBottomSheet(presetPrompt: presetPrompt),
  );
}

class _ChatBottomSheet extends StatelessWidget {
  final String? presetPrompt;
  const _ChatBottomSheet({this.presetPrompt});

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkBackground : const Color(0xFFF5F7F8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .3),
                  blurRadius: 20,
                  offset: const Offset(0, -4)),
            ],
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _header(context, isDark, lang),
              Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : Colors.grey.shade300),
              Expanded(child: ChatView(presetPrompt: presetPrompt)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, bool isDark, String lang) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppTheme.chatGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy_outlined,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.get('medical_assistant', lang),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextLight
                              : AppTheme.textDark)),
                  Text(AppStrings.get('ai_powered_guidance', lang),
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppTheme.darkTextGray
                              : AppTheme.textGray)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Full screen',
              icon: Icon(Icons.open_in_full_rounded,
                  size: 18, color: AppTheme.chatTealDark),
              onPressed: () {
                Navigator.of(context).pop();
                openChatScreen(context, presetPrompt: presetPrompt);
              },
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Icons.close_rounded,
                  color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                  size: 22),
            ),
          ],
        ),
      );
}
