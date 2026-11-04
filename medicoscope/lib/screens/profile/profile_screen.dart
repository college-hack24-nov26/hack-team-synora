import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/core/widgets/auth_text_field.dart';
import 'package:medicoscope/core/widgets/animated_button.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';
import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/services/sos_emergency_service.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/screens/profile/edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  SosContact _sosContact = SosContact.empty;
  bool _isTestingSms = false;

  @override
  void initState() {
    super.initState();
    _loadSosContact();
  }

  Future<void> _loadSosContact() async {
    final contact = await SosEmergencyService.getContact();
    if (mounted) {
      setState(() {
        _sosContact = contact;
      });
    }

    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isPatient && authProvider.token != null) {
      try {
        final api = ApiService(token: authProvider.token);
        final response = await api.get(ApiConstants.profile);
        final profile = response['profile'] as Map<String, dynamic>?;
        if (profile != null) {
          await SosEmergencyService.syncFromProfile(profile);
          final updated = await SosEmergencyService.getContact();
          if (mounted) {
            setState(() {
              _sosContact = updated;
            });
            return;
          }
        }
      } catch (_) {}
    }
  }

  void _openQuickEditSos(BuildContext context, String lang, bool isDark) {
    final nameCtrl = TextEditingController(text: _sosContact.name);
    final phoneCtrl = TextEditingController(text: _sosContact.phone);
    final relationCtrl = TextEditingController(text: _sosContact.relationship);
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.emergency_rounded,
                                color: Color(0xFFFF5252), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.get('edit_sos_contact', lang),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppTheme.darkTextLight
                                        : AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Receives SMS + GPS link during alerts',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? AppTheme.darkTextDim
                                        : AppTheme.textGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                color: isDark
                                    ? AppTheme.darkTextDim
                                    : AppTheme.textGray),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5252).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          AppStrings.get('sos_notice', lang),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AuthTextField(
                        controller: nameCtrl,
                        label: AppStrings.get('contact_name', lang),
                        prefixIcon: Icons.person_outline,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller: phoneCtrl,
                        label: '${AppStrings.get('contact_phone', lang)} (SOS)',
                        prefixIcon: Icons.phone_in_talk_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return AppStrings.get('sos_number_required', lang);
                          }
                          final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                          if (digits.length < 7) {
                            return AppStrings.get('sos_number_required', lang);
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller: relationCtrl,
                        label: AppStrings.get('relationship', lang),
                        prefixIcon: Icons.people_outline,
                      ),
                      const SizedBox(height: 20),
                      AnimatedButton(
                        text: isSaving
                            ? 'Saving...'
                            : AppStrings.get('save_sos_contact', lang),
                        icon: isSaving ? null : Icons.check_circle_outline,
                        onPressed: isSaving
                            ? () {}
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setSheetState(() => isSaving = true);
                                final authProvider = Provider.of<AuthProvider>(
                                    context,
                                    listen: false);
                                final messenger = ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(ctx);

                                await SosEmergencyService.saveContact(
                                  name: nameCtrl.text.trim(),
                                  phone: phoneCtrl.text.trim(),
                                  relationship: relationCtrl.text.trim(),
                                  authToken: authProvider.token,
                                );

                                navigator.pop();
                                await _loadSosContact();
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'SOS Emergency Contact updated successfully!'),
                                    backgroundColor: Color(0xFF4CAF50),
                                  ),
                                );
                              },
                        width: double.infinity,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleTestSms(String lang, String userName) async {
    setState(() => _isTestingSms = true);
    try {
      final success = await SosEmergencyService.sendTestSms(
        patientName: userName.isNotEmpty ? userName : 'Patient',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? AppStrings.get('sos_test_sent', lang)
                  : AppStrings.get('sos_test_failed', lang),
            ),
            backgroundColor:
                success ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.get('sos_test_failed', lang)),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTestingSms = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final lang = Provider.of<LocaleProvider>(context).languageCode;
    final isDark = themeProvider.isDarkMode;
    final user = authProvider.user;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppTheme.darkBackgroundGradient
              : AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingXLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button & Edit button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkCard : Colors.white,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSmall),
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
                      GestureDetector(
                        onTap: () async {
                          await Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      const EditProfileScreen(),
                              transitionsBuilder: (context, animation,
                                  secondaryAnimation, child) {
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
                              transitionDuration:
                                  const Duration(milliseconds: 300),
                            ),
                          );
                          _loadSosContact();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: AppTheme.orangeGradient,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSmall),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryOrange.withOpacity(0.3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.edit_outlined,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                AppStrings.get('edit_profile', lang),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppTheme.spacingXLarge),

                  // Profile header
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor:
                              AppTheme.primaryOrange.withOpacity(0.15),
                          child: Text(
                            user?.name.isNotEmpty == true
                                ? user!.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryOrange,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingMedium),
                        Text(
                          user?.name ?? AppStrings.get('user', lang),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: authProvider.isPatient
                                ? const LinearGradient(colors: [
                                    Color(0xFF4ECDC4),
                                    Color(0xFF44A08D)
                                  ])
                                : const LinearGradient(colors: [
                                    Color(0xFF667EEA),
                                    Color(0xFF764BA2)
                                  ]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            authProvider.isPatient
                                ? AppStrings.get('patient', lang)
                                : AppStrings.get('doctor', lang),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .scale(
                        begin: const Offset(0.9, 0.9),
                        end: const Offset(1, 1),
                      ),

                  const SizedBox(height: AppTheme.spacingXXLarge),

                  // Info cards
                  _buildInfoCard(
                    isDark,
                    icon: Icons.email_outlined,
                    label: AppStrings.get('email', lang),
                    value: user?.email ?? '',
                    delay: 200,
                  ),

                  _buildInfoCard(
                    isDark,
                    icon: Icons.phone_outlined,
                    label: AppStrings.get('phone', lang),
                    value: user?.phone ?? AppStrings.get('not_provided', lang),
                    delay: 300,
                  ),

                  _buildInfoCard(
                    isDark,
                    icon: Icons.qr_code,
                    label: AppStrings.get('unique_code', lang),
                    value: user?.uniqueCode ?? '',
                    valueColor: AppTheme.primaryOrange,
                    delay: 400,
                  ),

                  _buildInfoCard(
                    isDark,
                    icon: Icons.calendar_today_outlined,
                    label: AppStrings.get('member_since', lang),
                    value: user?.createdAt != null
                        ? DateTime.tryParse(user!.createdAt!)
                                ?.toLocal()
                                .toString()
                                .split(' ')
                                .first ??
                            AppStrings.get('unknown', lang)
                        : AppStrings.get('unknown', lang),
                    delay: 500,
                  ),

                  // Patient SOS Emergency Card
                  if (authProvider.isPatient) ...[
                    const SizedBox(height: AppTheme.spacingMedium),
                    _buildSosContactCard(
                      context,
                      isDark: isDark,
                      lang: lang,
                      userName: user?.name ?? 'Patient',
                    ),
                  ],

                  const SizedBox(height: AppTheme.spacingXLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSosContactCard(
    BuildContext context, {
    required bool isDark,
    required String lang,
    required String userName,
  }) {
    final hasContact = _sosContact.isValid;

    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: const Icon(
                  Icons.emergency_rounded,
                  color: Color(0xFFFF5252),
                  size: 22,
                ),
              ),
              const SizedBox(width: AppTheme.spacingMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.get('sos_emergency_contact', lang),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextLight
                            : AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasContact
                          ? AppStrings.get('sos_contact_configured', lang)
                          : AppStrings.get('sos_contact_not_set', lang),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: hasContact
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF9800),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    color: Color(0xFFFF5252), size: 20),
                tooltip: AppStrings.get('edit_sos_contact', lang),
                onPressed: () => _openQuickEditSos(context, lang, isDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasContact) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: AppTheme.textGray),
                      const SizedBox(width: 6),
                      Text(
                        _sosContact.name.isNotEmpty
                            ? _sosContact.name
                            : 'Emergency Contact',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppTheme.darkTextLight
                              : AppTheme.textDark,
                        ),
                      ),
                      if (_sosContact.relationship.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(${_sosContact.relationship})',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.darkTextDim
                                : AppTheme.textGray,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: Color(0xFFFF5252)),
                      const SizedBox(width: 6),
                      Text(
                        _sosContact.phone,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF5252),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _isTestingSms
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined, size: 16),
                    label: Text(
                      AppStrings.get('test_sos_sms', lang),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5252),
                      side: BorderSide(
                        color: const Color(0xFFFF5252).withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: _isTestingSms
                        ? null
                        : () => _handleTestSms(lang, userName),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.edit, size: 16),
                    label: Text(
                      AppStrings.get('edit_sos_contact', lang),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5252),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => _openQuickEditSos(context, lang, isDark),
                  ),
                ),
              ],
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.get('sos_notice', lang),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add SOS Emergency Number'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5252),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    onPressed: () => _openQuickEditSos(context, lang, isDark),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(delay: 550.ms, duration: 600.ms)
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildInfoCard(
    bool isDark, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    required int delay,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMedium),
      child: GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Icon(icon, color: AppTheme.primaryOrange, size: 20),
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: valueColor ??
                        (isDark ? AppTheme.darkTextLight : AppTheme.textDark),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delay), duration: 600.ms)
        .slideX(begin: 0.1, end: 0);
  }
}
