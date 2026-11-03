import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';
import 'package:medicoscope/core/widgets/animated_button.dart';
import 'package:medicoscope/core/widgets/auth_text_field.dart';
import 'package:medicoscope/core/widgets/theme_toggle_button.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/screens/dashboard/patient_dashboard_screen.dart';
import 'package:medicoscope/screens/dashboard/doctor_dashboard_screen.dart';
import 'package:medicoscope/screens/admin/admin_dashboard_screen.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      final Widget screen;
      if (authProvider.isAdmin) {
        screen = const AdminDashboardScreen();
      } else if (authProvider.isPatient) {
        screen = const PatientDashboardScreen();
      } else {
        screen = const DoctorDashboardScreen();
      }

      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => screen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade400,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppTheme.spacingMedium),

                        // Back button
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkCard
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSmall),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: Icon(
                              Icons.arrow_back,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                        ),

                        const SizedBox(height: AppTheme.spacingXXLarge),

                        // Logo
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppTheme.orangeGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryOrange
                                      .withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.favorite,
                              size: 40,
                              color: Colors.white,
                            ),
                          )
                              .animate()
                              .fadeIn(duration: 600.ms)
                              .scale(
                                begin: const Offset(0.5, 0.5),
                                end: const Offset(1, 1),
                                curve: Curves.elasticOut,
                                duration: 800.ms,
                              ),
                        ),

                        const SizedBox(height: AppTheme.spacingXLarge),

                        // Title
                        Center(
                          child: Text(
                            AppStrings.get('welcome_back', lang),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 200.ms, duration: 600.ms)
                            .slideY(begin: 0.3, end: 0),

                        const SizedBox(height: AppTheme.spacingSmall),

                        Center(
                          child: Text(
                            AppStrings.get('sign_in_to_account', lang),
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark
                                  ? AppTheme.darkTextGray
                                  : AppTheme.textGray,
                            ),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 300.ms, duration: 600.ms),

                        const SizedBox(height: AppTheme.spacingXXLarge),

                        // Email field
                        AuthTextField(
                          controller: _emailController,
                          label: AppStrings.get('email', lang),
                          hint: AppStrings.get('email_hint', lang),
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return AppStrings.get('email_required', lang);
                            }
                            if (!value.contains('@')) {
                              return AppStrings.get('email_invalid', lang);
                            }
                            return null;
                          },
                        )
                            .animate()
                            .fadeIn(delay: 400.ms, duration: 600.ms)
                            .slideY(begin: 0.2, end: 0),

                        const SizedBox(height: AppTheme.spacingMedium),

                        // Password field
                        AuthTextField(
                          controller: _passwordController,
                          label: AppStrings.get('password', lang),
                          hint: AppStrings.get('password_hint', lang),
                          prefixIcon: Icons.lock_outlined,
                          obscureText: _obscurePassword,
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppTheme.textGray,
                              size: 20,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return AppStrings.get('password_required', lang);
                            }
                            return null;
                          },
                        )
                            .animate()
                            .fadeIn(delay: 500.ms, duration: 600.ms)
                            .slideY(begin: 0.2, end: 0),

                        const SizedBox(height: AppTheme.spacingXLarge),

                        // Login button
                        AnimatedButton(
                          text: _isLoading ? AppStrings.get('signing_in', lang) : AppStrings.get('sign_in', lang),
                          icon: _isLoading ? null : Icons.login,
                          onPressed: _isLoading ? () {} : _login,
                          width: double.infinity,
                        )
                            .animate()
                            .fadeIn(delay: 600.ms, duration: 600.ms)
                            .slideY(begin: 0.2, end: 0),

                        const SizedBox(height: AppTheme.spacingXLarge),

                        // Register link
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                AppStrings.get('no_account', lang),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? AppTheme.darkTextGray
                                      : AppTheme.textGray,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Text(
                                  AppStrings.get('register', lang),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.primaryOrange,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 700.ms, duration: 600.ms),
                      ],
                    ),
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
}
