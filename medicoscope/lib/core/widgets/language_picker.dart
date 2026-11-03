import 'package:flutter/material.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:provider/provider.dart';

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentName =
        LocaleProvider.supportedLanguages[localeProvider.languageCode] ??
            'English';

    return ListTile(
      leading: Icon(
        Icons.translate,
        color: AppTheme.primaryOrange,
        size: 24,
      ),
      title: Text(
        'Language',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
        ),
      ),
      subtitle: Text(
        currentName,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
        size: 20,
      ),
      onTap: () => _showLanguageSheet(context),
    );
  }

  void _showLanguageSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final localeProvider = Provider.of<LocaleProvider>(ctx);
        final currentCode = localeProvider.languageCode;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkBackground : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Select Language',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              // Language list
              ...LocaleProvider.supportedLanguages.entries.map((entry) {
                final isSelected = entry.key == currentCode;
                return ListTile(
                  leading: isSelected
                      ? Icon(Icons.check_circle,
                          color: AppTheme.primaryOrange, size: 22)
                      : Icon(Icons.circle_outlined,
                          color:
                              isDark ? AppTheme.darkTextDim : AppTheme.textLight,
                          size: 22),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? AppTheme.primaryOrange
                          : (isDark
                              ? AppTheme.darkTextLight
                              : AppTheme.textDark),
                    ),
                  ),
                  onTap: () {
                    localeProvider.setLanguage(entry.key);
                    Navigator.of(ctx).pop();
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
