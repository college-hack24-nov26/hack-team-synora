import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/widgets/theme_toggle_button.dart';
import 'package:medicoscope/screens/auth/registration_screen.dart';
import 'package:medicoscope/screens/auth/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppTheme.darkBackgroundGradient
              : AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingXLarge),
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacingXXLarge),

                      // Logo
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppTheme.orangeGradient,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppTheme.primaryOrange.withOpacity(0.4),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.favorite,
                          size: 50,
                          color: Colors.white,
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .scale(
                            begin: const Offset(0.5, 0.5),
                            end: const Offset(1, 1),
                            curve: Curves.elasticOut,
                            duration: 1000.ms,
                          ),

                      const SizedBox(height: AppTheme.spacingLarge),

                      // Title
                      Text(
                        AppStrings.get('medicoscope', lang),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppTheme.darkTextLight
                              : AppTheme.textDark,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 600.ms)
                          .slideY(begin: 0.3, end: 0),

                      const SizedBox(height: AppTheme.spacingSmall),

                      Text(
                        AppStrings.get('who_are_you', lang),
                        style: TextStyle(
                          fontSize: 18,
                          color: isDark
                              ? AppTheme.darkTextGray
                              : AppTheme.textGray,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 600.ms),

                      const SizedBox(height: AppTheme.spacingXXLarge),

                      // Patient Card
                      _buildRoleCard(
                        context,
                        icon: Icons.person_outlined,
                        title: AppStrings.get('im_patient', lang),
                        description:
                            AppStrings.get('im_patient_desc', lang),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)],
                        ),
                        onTap: () => _navigateTo(
                          context,
                          const RegistrationScreen(role: 'patient'),
                        ),
                        delay: 500,
                      ),

                      const SizedBox(height: AppTheme.spacingMedium),

                      // Doctor Card
                      _buildRoleCard(
                        context,
                        icon: Icons.medical_services_outlined,
                        title: AppStrings.get('im_doctor', lang),
                        description:
                            AppStrings.get('im_doctor_desc', lang),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        ),
                        onTap: () => _navigateTo(
                          context,
                          const RegistrationScreen(role: 'doctor'),
                        ),
                        delay: 700,
                      ),

                      const SizedBox(height: AppTheme.spacingXXLarge),

                      // Login link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppStrings.get('already_have_account', lang),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? AppTheme.darkTextGray
                                  : AppTheme.textGray,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _navigateTo(
                              context,
                              const LoginScreen(),
                            ),
                            child: Text(
                              AppStrings.get('log_in', lang),
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.primaryOrange,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      )
                          .animate()
                          .fadeIn(delay: 900.ms, duration: 600.ms),

                      const SizedBox(height: AppTheme.spacingXLarge),
                    ],
                  ),
                ),
              ),

              // Theme toggle
              Positioned(
                top: AppTheme.spacingMedium,
                right: AppTheme.spacingMedium,
                child: const ThemeToggleButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required LinearGradient gradient,
    required VoidCallback onTap,
    required int delay,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: Icon(icon, size: 32, color: Colors.white),
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.85),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withOpacity(0.7),
              size: 18,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delay), duration: 600.ms)
        .slideX(begin: 0.2, end: 0);
  }
}
