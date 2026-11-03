import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/widgets/dashboard_tile.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/screens/diseases/doctor_copilot_screen.dart';
import 'package:medicoscope/screens/heart/heart_monitoring_screen.dart';
import 'package:medicoscope/services/mental_health_service.dart';
import 'package:medicoscope/services/vitals_service.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';

class PatientDetailScreen extends StatefulWidget {
  final Map<String, dynamic> patient;

  const PatientDetailScreen({super.key, required this.patient});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  List<Map<String, dynamic>> _mentalHealthReports = [];
  bool _loadingReports = true;

  List<Map<String, dynamic>> _vitalsAlerts = [];
  bool _loadingVitals = true;

  @override
  void initState() {
    super.initState();
    _fetchReports();
    _fetchVitalsAlerts();
  }

  Future<void> _fetchReports() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final doctorId = authProvider.user?.id ?? '';
    try {
      final all = await MentalHealthService.getNotifications(
        doctorId: doctorId,
        token: authProvider.token ?? '',
      );
      final patientId = widget.patient['userId']?.toString() ?? '';
      setState(() {
        _mentalHealthReports =
            all.where((n) => n['patient_id'] == patientId).toList();
        _loadingReports = false;
      });
    } catch (_) {
      setState(() => _loadingReports = false);
    }
  }

  Future<void> _fetchVitalsAlerts() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final doctorId = authProvider.user?.id ?? '';
    final patientId = widget.patient['userId']?.toString() ?? '';
    try {
      final all = await VitalsService.getDoctorAlerts(doctorId: doctorId);
      setState(() {
        _vitalsAlerts = all
            .where((a) =>
                a['patient_id'] == patientId ||
                a['patient_name'] == widget.patient['name'])
            .toList();
        _loadingVitals = false;
      });
    } catch (_) {
      setState(() => _loadingVitals = false);
    }
  }

  Future<void> _deleteVitalsAlert(String alertId) async {
    try {
      await VitalsService.deleteAlert(alertId: alertId);
      setState(() {
        _vitalsAlerts.removeWhere((a) => a['id'] == alertId);
      });
    } catch (_) {}
  }

  Future<void> _deleteMentalReport(String reportId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      await MentalHealthService.deleteNotification(
        notificationId: reportId,
        token: authProvider.token ?? '',
      );
      setState(() {
        _mentalHealthReports.removeWhere((r) => r['id'] == reportId);
      });
    } catch (_) {}
  }

  void _confirmDelete(String title, VoidCallback onDelete) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: const Text('Are you sure you want to delete this?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().toUtc().difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFFF5252);
      case 'high':
      case 'warning':
        return const Color(0xFFFF7043);
      case 'medium':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  Color _urgencyColor(String urgency) {
    switch (urgency.toLowerCase()) {
      case 'high':
        return const Color(0xFFFF5252);
      case 'medium':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF4CAF50);
    }
  }

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

    final name = widget.patient['name'] ?? 'Unknown';
    final code = widget.patient['uniqueCode'] ?? '';
    final conditions = List<String>.from(widget.patient['conditions'] ?? []);
    final bloodGroup = widget.patient['bloodGroup'] ?? '';
    final dob = widget.patient['dateOfBirth'] ?? '';
    final patientUserId = widget.patient['userId']?.toString() ?? '';

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
                  // Back button
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
                        color:
                            isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                      ),
                    ),
                  ),

                  const SizedBox(height: AppTheme.spacingLarge),

                  // Patient info card
                  GlassCard(
                    padding: const EdgeInsets.all(AppTheme.spacingLarge),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor:
                              AppTheme.primaryOrange.withOpacity(0.15),
                          child: Text(
                            name[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryOrange,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingMedium),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.textDark,
                          ),
                        ),
                        Text(
                          code,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? AppTheme.darkTextGray
                                : AppTheme.textGray,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingMedium),

                        // Info row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (bloodGroup.isNotEmpty) ...[
                              _infoBadge('Blood: $bloodGroup', isDark),
                              const SizedBox(width: 8),
                            ],
                            if (dob.isNotEmpty) _infoBadge('DOB: $dob', isDark),
                          ],
                        ),

                        if (conditions.isNotEmpty) ...[
                          const SizedBox(height: AppTheme.spacingMedium),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: conditions.map((c) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primaryOrange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  c,
                                  style: const TextStyle(
                                    fontSize: 12,
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
                  )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .slideY(begin: 0.2, end: 0),

                  const SizedBox(height: AppTheme.spacingXLarge),

                  // Scan section
                  Text(
                    AppStrings.get('scan_for_patient', lang),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                    ),
                  ).animate().fadeIn(delay: 300.ms, duration: 600.ms),

                  const SizedBox(height: AppTheme.spacingMedium),

                  // AI Co-Pilot Summary
                  DashboardTile(
                    icon: Icons.auto_awesome,
                    title: 'AI Co-Pilot',
                    description: 'Auto-generated clinical summary for $name',
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)],
                    ),
                    onTap: () => _navigateTo(
                      context,
                      DoctorCopilotScreen(
                        patientName: name,
                        patientId: patientUserId,
                      ),
                    ),
                    animationDelay: 350,
                  ),

                  const SizedBox(height: AppTheme.spacingMedium),

                  // Heart Sound
                  DashboardTile(
                    icon: Icons.favorite_outline,
                    title: AppStrings.get('heart_sound', lang),
                    description: AppStrings.format('analyze_for', lang, {
                      'type': AppStrings.get('heart_sound', lang).toLowerCase(),
                      'name': name
                    }),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
                    ),
                    onTap: () => _navigateTo(
                      context,
                      HeartMonitoringScreen(patientId: patientUserId),
                    ),
                    animationDelay: 600,
                  ),

                  const SizedBox(height: AppTheme.spacingXLarge),

                  // Vitals Alerts Section
                  Text(
                    AppStrings.get('vitals_alerts', lang),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                    ),
                  ).animate().fadeIn(delay: 600.ms, duration: 600.ms),

                  const SizedBox(height: AppTheme.spacingMedium),

                  if (_loadingVitals)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_vitalsAlerts.isEmpty)
                    GlassCard(
                      padding: const EdgeInsets.all(AppTheme.spacingLarge),
                      child: Center(
                        child: Text(
                          AppStrings.get('no_vitals_alerts_patient', lang),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppTheme.darkTextGray
                                : AppTheme.textGray,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 700.ms, duration: 400.ms)
                  else
                    ..._vitalsAlerts.asMap().entries.map((entry) {
                      final a = entry.value;
                      final severity = a['severity'] ?? 'warning';
                      return Padding(
                        padding: const EdgeInsets.only(
                            bottom: AppTheme.spacingSmall),
                        child: GlassCard(
                          padding: const EdgeInsets.all(AppTheme.spacingMedium),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _severityColor(severity)
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      severity.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _severityColor(severity),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.monitor_heart_outlined,
                                    size: 14,
                                    color: isDark
                                        ? AppTheme.darkTextDim
                                        : AppTheme.textLight,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    (a['vital'] ?? '')
                                        .toString()
                                        .replaceAll('_', ' '),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppTheme.darkTextGray
                                          : AppTheme.textGray,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _timeAgo(a['created_at'] ??
                                        a['timestamp'] ??
                                        ''),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppTheme.darkTextDim
                                          : AppTheme.textLight,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => _confirmDelete(
                                      AppStrings.get('delete_alert', lang),
                                      () => _deleteVitalsAlert(a['id']),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Color(0xFFFF5252),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                a['message'] ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: isDark
                                      ? AppTheme.darkTextLight
                                      : AppTheme.textDark,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    'Current: ${a['current_value'] ?? 'N/A'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppTheme.darkTextGray
                                          : AppTheme.textGray,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Threshold: ${a['predicted_value'] ?? 'N/A'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppTheme.darkTextGray
                                          : AppTheme.textGray,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(
                          delay: (700 + entry.key * 100).ms, duration: 400.ms);
                    }),

                  const SizedBox(height: AppTheme.spacingXLarge),

                  // Mental Health Reports Section
                  Text(
                    AppStrings.get('mental_health_reports', lang),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                    ),
                  ).animate().fadeIn(delay: 600.ms, duration: 600.ms),

                  const SizedBox(height: AppTheme.spacingMedium),

                  if (_loadingReports)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_mentalHealthReports.isEmpty)
                    GlassCard(
                      padding: const EdgeInsets.all(AppTheme.spacingLarge),
                      child: Center(
                        child: Text(
                          AppStrings.get('no_mental_reports', lang),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppTheme.darkTextGray
                                : AppTheme.textGray,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 700.ms, duration: 400.ms)
                  else
                    ..._mentalHealthReports.asMap().entries.map((entry) {
                      final n = entry.value;
                      final urgency = n['urgency'] ?? 'Low';
                      return Padding(
                        padding: const EdgeInsets.only(
                            bottom: AppTheme.spacingSmall),
                        child: GlassCard(
                          padding: const EdgeInsets.all(AppTheme.spacingMedium),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _urgencyColor(urgency)
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      urgency,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _urgencyColor(urgency),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    n['created_at']
                                            ?.toString()
                                            .substring(0, 10) ??
                                        '',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppTheme.darkTextDim
                                          : AppTheme.textLight,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _confirmDelete(
                                      AppStrings.get('delete_alert', lang),
                                      () => _deleteMentalReport(n['id']),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Color(0xFFFF5252),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                n['report'] ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: isDark
                                      ? AppTheme.darkTextLight
                                      : AppTheme.textDark,
                                ),
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(
                          delay: (700 + entry.key * 100).ms, duration: 400.ms);
                    }),

                  const SizedBox(height: AppTheme.spacingXLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoBadge(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
