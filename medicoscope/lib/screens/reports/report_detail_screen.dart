import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/data/disease_database.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';

class ReportDetailScreen extends StatelessWidget {
  final String patientName;
  final DetectionRecord record;

  const ReportDetailScreen({
    super.key,
    required this.patientName,
    required this.record,
  });

  Map<String, dynamic>? get _diseaseInfo =>
      DiseaseDatabase.getDiseaseInfo(record.className);

  String get _severity {
    final info = _diseaseInfo;
    if (info != null && info['severity'] != null) return info['severity'];
    // Infer severity from confidence for non-heart categories
    if (record.category == 'heart_sound') return 'MEDIUM';
    if (record.confidence >= 0.8) return 'HIGH';
    if (record.confidence >= 0.5) return 'MEDIUM';
    return 'LOW';
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'HIGH':
        return const Color(0xFFFF5252);
      case 'MEDIUM':
        return const Color(0xFFFF9800);
      case 'LOW':
        return const Color(0xFF4CAF50);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'skin':
        return Icons.face_outlined;
      case 'chest':
        return Icons.monitor_heart_outlined;
      case 'brain':
        return Icons.psychology_outlined;
      case 'heart_sound':
        return Icons.favorite_outline;
      default:
        return Icons.description_outlined;
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'skin':
        return const Color(0xFFFF6B35);
      case 'chest':
        return const Color(0xFF667EEA);
      case 'brain':
        return const Color(0xFFF5576C);
      case 'heart_sound':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  String _categoryLabel(String category, String lang) {
    switch (category) {
      case 'skin':
        return AppStrings.get('dermatology', lang);
      case 'chest':
        return AppStrings.get('pulmonology', lang);
      case 'brain':
        return AppStrings.get('neurology', lang);
      case 'heart_sound':
        return AppStrings.get('cardiology', lang);
      default:
        return category;
    }
  }

  List<String> _getRecommendations(String lang) {
    final severity = _severity;
    final recs = <String>[];

    switch (record.category) {
      case 'skin':
        recs.add(AppStrings.get('rec_dermatology_appointment', lang));
        if (severity == 'HIGH') {
          recs.add(AppStrings.get('rec_urgent_dermatology', lang));
          recs.add(AppStrings.get('rec_biopsy', lang));
        }
        recs.add(AppStrings.get('rec_sun_exposure', lang));
        recs.add(AppStrings.get('rec_monitor_changes', lang));
        recs.add(AppStrings.get('rec_document_lesion', lang));
        break;
      case 'chest':
        recs.add(AppStrings.get('rec_pulmonologist', lang));
        if (severity == 'HIGH') {
          recs.add(AppStrings.get('rec_urgent_medical', lang));
          recs.add(AppStrings.get('rec_additional_imaging', lang));
        }
        recs.add(AppStrings.get('rec_monitor_respiratory', lang));
        recs.add(AppStrings.get('rec_avoid_smoking', lang));
        break;
      case 'brain':
        recs.add(AppStrings.get('rec_urgent_neurology', lang));
        recs.add(AppStrings.get('rec_mri_followup', lang));
        recs.add(AppStrings.get('rec_monitor_neurological', lang));
        recs.add(AppStrings.get('rec_symptom_diary', lang));
        break;
      case 'heart_sound':
        recs.add(AppStrings.get('rec_cardiologist', lang));
        if (severity == 'HIGH') {
          recs.add(AppStrings.get('rec_urgent_cardiology', lang));
          recs.add(AppStrings.get('rec_echocardiogram', lang));
        }
        recs.add(AppStrings.get('rec_monitor_cardiac', lang));
        recs.add(AppStrings.get('rec_avoid_strenuous', lang));
        break;
    }

    return recs;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;
    final severity = _severity;
    final catColor = _categoryColor(record.category);

    final dateStr =
        '${record.timestamp.day}/${record.timestamp.month}/${record.timestamp.year}';
    final timeStr =
        '${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}';

    final confStr = record.category == 'heart_sound'
        ? '${record.confidence.toStringAsFixed(0)} ${AppStrings.get('bpm', lang)}'
        : '${(record.confidence * 100).toStringAsFixed(1)}%';

    final description = _diseaseInfo?['description'] ??
        (record.description.isNotEmpty
            ? record.description
            : AppStrings.get('no_description', lang));

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppTheme.darkBackgroundGradient
              : AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios),
                      color:
                          isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.get('medical_report', lang),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                          Text(
                            _categoryLabel(record.category, lang),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextGray
                                  : AppTheme.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Severity badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _severityColor(severity).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _severityColor(severity).withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        severity,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _severityColor(severity),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingLarge),
                  children: [
                    // Section 1: Patient Info
                    _sectionCard(
                      isDark: isDark,
                      delay: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(AppStrings.get('patient_information', lang), isDark),
                          const SizedBox(height: 12),
                          _infoRow(AppStrings.get('patient', lang), patientName, isDark),
                          _infoRow(AppStrings.get('report_date', lang), '$dateStr at $timeStr', isDark),
                          _infoRow(AppStrings.get('report_id', lang),
                              record.id?.substring(0, 8).toUpperCase() ?? 'N/A', isDark),
                          if (record.performedByName != null)
                            _infoRow(
                              AppStrings.get('performed_by', lang),
                              '${record.performedByName} (${record.performedByRole ?? 'N/A'})',
                              isDark,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Section 2: Diagnosis
                    _sectionCard(
                      isDark: isDark,
                      delay: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(AppStrings.get('diagnosis', lang), isDark),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: catColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _categoryIcon(record.category),
                                  color: catColor,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _categoryLabel(record.category, lang),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: catColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      record.className,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: isDark
                                            ? AppTheme.darkTextLight
                                            : AppTheme.textDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Confidence meter
                          _confidenceMeter(confStr, catColor, isDark, lang),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Section 3: Clinical Description
                    _sectionCard(
                      isDark: isDark,
                      delay: 200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(AppStrings.get('clinical_description', lang), isDark),
                          const SizedBox(height: 10),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Section 4: Recommendations
                    _sectionCard(
                      isDark: isDark,
                      delay: 300,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(AppStrings.get('recommendations', lang), isDark),
                          const SizedBox(height: 10),
                          ..._getRecommendations(lang).map(
                            (rec) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    rec.startsWith('URGENT')
                                        ? Icons.warning_amber_rounded
                                        : Icons.check_circle_outline,
                                    size: 18,
                                    color: rec.startsWith('URGENT')
                                        ? const Color(0xFFFF5252)
                                        : const Color(0xFF4ECDC4),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      rec,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        fontWeight: rec.startsWith('URGENT')
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: rec.startsWith('URGENT')
                                            ? const Color(0xFFFF5252)
                                            : isDark
                                                ? AppTheme.darkTextLight
                                                : AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Section 5: Detection Metadata
                    _sectionCard(
                      isDark: isDark,
                      delay: 400,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(AppStrings.get('detection_metadata', lang), isDark),
                          const SizedBox(height: 12),
                          _infoRow(AppStrings.get('category', lang), record.category, isDark),
                          _infoRow(AppStrings.get('timestamp', lang), '$dateStr $timeStr', isDark),
                          _infoRow(AppStrings.get('model_confidence', lang), confStr, isDark),
                          _infoRow(AppStrings.get('severity', lang), severity, isDark),
                          if (record.performedByName != null)
                            _infoRow(AppStrings.get('performer', lang), record.performedByName!, isDark),
                          if (record.performedByRole != null)
                            _infoRow(AppStrings.get('performer_role', lang), record.performedByRole!, isDark),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required bool isDark,
    required int delay,
    required Widget child,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: child,
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delay), duration: 400.ms)
        .slideY(begin: 0.05, end: 0);
  }

  Widget _sectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
      ),
    );
  }

  Widget _infoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confidenceMeter(String label, Color color, bool isDark, String lang) {
    // For heart_sound, confidence is BPM, not a percentage
    final isPercentage = record.category != 'heart_sound';
    final barValue = isPercentage ? record.confidence : 0.75; // normalized for heart

    Color barColor;
    if (isPercentage) {
      if (record.confidence >= 0.8) {
        barColor = const Color(0xFF4CAF50);
      } else if (record.confidence >= 0.5) {
        barColor = const Color(0xFFFF9800);
      } else {
        barColor = const Color(0xFFFF5252);
      }
    } else {
      barColor = color;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isPercentage ? AppStrings.get('confidence', lang) : AppStrings.get('heart_rate', lang),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: barValue.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}
