import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/services/vitals_service.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';

class PatientAlertsScreen extends StatefulWidget {
  const PatientAlertsScreen({super.key});

  @override
  State<PatientAlertsScreen> createState() => _PatientAlertsScreenState();
}

class _PatientAlertsScreenState extends State<PatientAlertsScreen> {
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;
  String? _expandedId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
    // Auto-refresh every 10 seconds for near real-time alert updates
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchAlerts(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAlerts({bool silent = false}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final patientId = authProvider.user?.id ?? '';

    try {
      final alerts = await VitalsService.getPatientAlerts(
        patientId: patientId,
      );
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        if (!silent) _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      await VitalsService.markAlertRead(alertId: id);
      setState(() {
        for (final a in _alerts) {
          if (a['id'] == id) {
            a['read'] = true;
            break;
          }
        }
      });
    } catch (_) {}
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFFF5252);
      case 'high':
        return const Color(0xFFFF7043);
      case 'medium':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  IconData _vitalIcon(String vital) {
    switch (vital.toLowerCase()) {
      case 'heart_rate':
        return Icons.favorite;
      case 'blood_pressure':
        return Icons.speed;
      case 'spo2':
        return Icons.air;
      default:
        return Icons.monitor_heart;
    }
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

  String _formatTimestamp(String isoDate) {
    try {
      final date = DateTime.parse(isoDate).toLocal();
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      return '$day/$month/${date.year} $hour:$minute';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;
    final unreadCount = _alerts.where((a) => !(a['read'] ?? false)).length;

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
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios),
                      color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                    ),
                    Expanded(
                      child: Text(
                        AppStrings.get('health_alerts', lang),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color:
                              isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                        ),
                      ),
                    ),
                    if (unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5252).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          AppStrings.format('new_alerts', lang, {'count': '$unreadCount'}),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF5252),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Summary card
              if (_alerts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingLarge,
                  ),
                  child: GlassCard(
                    padding: const EdgeInsets.all(AppTheme.spacingMedium),
                    child: Row(
                      children: [
                        _buildSummaryItem(
                          isDark,
                          '${_alerts.length}',
                          AppStrings.get('total', lang),
                          const Color(0xFF667EEA),
                        ),
                        _buildSummaryDivider(isDark),
                        _buildSummaryItem(
                          isDark,
                          '${_alerts.where((a) => a['severity'] == 'critical').length}',
                          AppStrings.get('critical', lang),
                          const Color(0xFFFF5252),
                        ),
                        _buildSummaryDivider(isDark),
                        _buildSummaryItem(
                          isDark,
                          '${_alerts.where((a) => a['doctor_notified'] == true).length}',
                          AppStrings.get('sent_to_doctor', lang),
                          const Color(0xFF4CAF50),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
                ),

              const SizedBox(height: AppTheme.spacingMedium),

              // Alerts list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _alerts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.notifications_none_rounded,
                                  size: 64,
                                  color: isDark
                                      ? AppTheme.darkTextDim
                                      : AppTheme.textLight,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  AppStrings.get('no_alerts_yet', lang),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDark
                                        ? AppTheme.darkTextGray
                                        : AppTheme.textGray,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppStrings.get('alerts_appear_here', lang),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? AppTheme.darkTextDim
                                        : AppTheme.textLight,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchAlerts,
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacingLarge,
                              ),
                              itemCount: _alerts.length,
                              itemBuilder: (context, index) =>
                                  _buildAlertCard(index, isDark, lang),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    bool isDark,
    String value,
    String label,
    Color color,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryDivider(bool isDark) {
    return Container(
      width: 1,
      height: 30,
      color: isDark ? Colors.white12 : Colors.black12,
    );
  }

  Widget _buildAlertCard(int index, bool isDark, String lang) {
    final a = _alerts[index];
    final isExpanded = _expandedId == a['id'];
    final severity = a['severity'] ?? 'high';
    final isUnread = !(a['read'] ?? false);
    final emergencyNotified = a['emergency_notified'] ?? false;
    final doctorNotified = a['doctor_notified'] ?? false;
    final vital = a['vital'] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMedium),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _expandedId = isExpanded ? null : a['id'];
          });
          if (isUnread) {
            _markAsRead(a['id']);
          }
        },
        child: GlassCard(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          borderRadius: AppTheme.radiusMedium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Vital icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _severityColor(severity).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _vitalIcon(vital),
                      size: 18,
                      color: _severityColor(severity),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (a['alert_type'] ?? severity)
                              .toString()
                              .replaceAll('_', ' ')
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                isUnread ? FontWeight.w800 : FontWeight.w600,
                            color: isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _timeAgo(a['created_at'] ?? ''),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppTheme.darkTextDim
                                : AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Severity badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _severityColor(severity).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      severity.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _severityColor(severity),
                      ),
                    ),
                  ),
                  if (isUnread)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: _severityColor(severity),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Message
              Text(
                a['message'] ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                ),
                maxLines: isExpanded ? null : 2,
                overflow: isExpanded ? null : TextOverflow.ellipsis,
              ),

              // Expanded details
              if (isExpanded) ...[
                const SizedBox(height: 12),
                Divider(color: isDark ? Colors.white12 : Colors.black12),
                const SizedBox(height: 8),

                _buildInfoRow(isDark, AppStrings.get('vital', lang), vital.replaceAll('_', ' ')),
                _buildInfoRow(
                  isDark,
                  AppStrings.get('current_value', lang),
                  '${a['current_value'] ?? 'N/A'}',
                ),
                _buildInfoRow(
                  isDark,
                  AppStrings.get('predicted_value', lang),
                  '${a['predicted_value'] ?? 'N/A'}',
                ),
                _buildInfoRow(
                  isDark,
                  AppStrings.get('location', lang),
                  a['location'] ?? 'Unknown',
                ),
                if (a['maps_url'] != null && (a['maps_url'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 110),
                        GestureDetector(
                          onTap: () => launchUrl(Uri.parse(a['maps_url'])),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.map, size: 14, color: Color(0xFF667EEA)),
                              const SizedBox(width: 4),
                              Text(
                                AppStrings.get('open_maps', lang),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF667EEA),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildInfoRow(
                  isDark,
                  AppStrings.get('time', lang),
                  _formatTimestamp(a['created_at'] ?? ''),
                ),

                const SizedBox(height: 10),

                // Dispatch status
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.get('alert_sent_to', lang),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextGray
                              : AppTheme.textGray,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (doctorNotified)
                        _buildStatusRow(
                          Icons.medical_services,
                          AppStrings.get('sent_to_linked_doctor', lang),
                          const Color(0xFF4CAF50),
                        ),
                      if (!doctorNotified)
                        _buildStatusRow(
                          Icons.medical_services,
                          AppStrings.get('no_linked_doctor', lang),
                          isDark ? Colors.white30 : Colors.black26,
                        ),
                      const SizedBox(height: 4),
                      if (emergencyNotified)
                        _buildStatusRow(
                          Icons.emergency,
                          'Sent to ${a['emergency_contact_name'] ?? 'emergency contact'} (${a['emergency_contact_phone'] ?? ''})',
                          const Color(0xFFFF5252),
                        ),
                      if (!emergencyNotified)
                        _buildStatusRow(
                          Icons.emergency,
                          AppStrings.get('no_emergency_contact', lang),
                          isDark ? Colors.white30 : Colors.black26,
                        ),
                    ],
                  ),
                ),
              ],

              if (!isExpanded)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      if (emergencyNotified)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.emergency,
                            size: 14,
                            color: const Color(0xFFFF5252).withOpacity(0.7),
                          ),
                        ),
                      if (doctorNotified)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.medical_services,
                            size: 14,
                            color: const Color(0xFF4CAF50).withOpacity(0.7),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          AppStrings.get('tap_for_details', lang),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppTheme.darkTextDim
                                : AppTheme.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(
          delay: (index * 80).ms,
          duration: 400.ms,
        );
  }

  Widget _buildInfoRow(bool isDark, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
