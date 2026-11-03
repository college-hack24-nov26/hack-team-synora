import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/screens/patients/patient_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  List<Map<String, dynamic>> _patients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPatients();
  }

  Future<void> _fetchPatients() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.token == null) return;

    try {
      final api = ApiService(token: authProvider.token);
      final response = await api.get(ApiConstants.doctorPatients);
      setState(() {
        _patients = List<Map<String, dynamic>>.from(response['patients'] ?? []);
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade400),
      );
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingXLarge),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingLarge),
                    Text(
                      AppStrings.get('my_patients', lang),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.format('linked_patients', lang, {'count': '${_patients.length}'}),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ),

              // Patient list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange))
                    : _patients.isEmpty
                        ? _buildEmptyState(isDark, authProvider, lang)
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacingXLarge,
                            ),
                            itemCount: _patients.length,
                            itemBuilder: (context, index) {
                              final patient = _patients[index];
                              return _buildPatientCard(context, patient, index, isDark);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, AuthProvider authProvider, String lang) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
            ),
            const SizedBox(height: AppTheme.spacingLarge),
            Text(
              AppStrings.get('no_patients_linked', lang),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              AppStrings.get('share_code_instruction', lang),
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              authProvider.user?.uniqueCode ?? '',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryOrange,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientCard(
    BuildContext context,
    Map<String, dynamic> patient,
    int index,
    bool isDark,
  ) {
    final conditions = List<String>.from(patient['conditions'] ?? []);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                PatientDetailScreen(patient: patient),
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
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spacingMedium),
        child: GlassCard(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primaryOrange.withOpacity(0.15),
                child: Text(
                  (patient['name'] ?? '?')[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryOrange,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacingMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient['name'] ?? 'Unknown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      patient['uniqueCode'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                      ),
                    ),
                    if (conditions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        children: conditions.take(3).map((c) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryOrange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              c,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.primaryOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
            delay: Duration(milliseconds: 200 + (index * 100)),
            duration: 600.ms)
        .slideX(begin: 0.1, end: 0);
  }
}
