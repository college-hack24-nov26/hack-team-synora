import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';

class ThemeToggleButton extends StatelessWidget {
  final double size;
  
  const ThemeToggleButton({
    super.key,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return GestureDetector(
      onTap: () => themeProvider.toggleTheme(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDark 
              ? AppTheme.darkSurface.withOpacity(0.8)
              : Colors.white.withOpacity(0.8),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppTheme.primaryOrange.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryOrange.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          color: AppTheme.primaryOrange,
          size: size * 0.5,
        ),
      )
          .animate(
            target: isDark ? 1 : 0,
          )
          .rotate(
            begin: 0,
            end: 0.5,
            duration: 300.ms,
            curve: Curves.easeInOut,
          ),
    );
  }
}
