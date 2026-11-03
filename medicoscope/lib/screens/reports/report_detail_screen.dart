import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/data/disease_database.dart';
import 'package:medicoscope/models/quality_gate_result.dart';
import 'package:medicoscope/services/quality_gate_service.dart';
import 'package:medicoscope/services/certified_report_pdf_service.dart';
import 'package:medicoscope/core/widgets/quality_gate_sheet.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportDetailScreen extends StatefulWidget {
  final String patientName;
  final DetectionRecord record;

  const ReportDetailScreen({
    super.key,
    required this.patientName,
    required this.record,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final TextEditingController _notesCtrl = TextEditingController();
  bool _isFinalized = false;
  QualityGateResult? _finalizedGateResult;

  String get _storageKey =>
      'report_finalized_${widget.record.id ?? widget.record.timestamp.millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isFinal = prefs.getBool(_storageKey) ?? false;
      final savedNotes = prefs.getString('${_storageKey}_notes');
      if (savedNotes != null && savedNotes.isNotEmpty) {
        _notesCtrl.text = savedNotes;
      }
      if (isFinal && mounted) {
        final qg = _evaluateCurrentQuality();
        setState(() {
          _isFinalized = true;
          _finalizedGateResult = qg;
        });
      }
    } catch (_) {}
  }

  Future<void> _persistFinalizedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, true);
      await prefs.setString('${_storageKey}_notes', _notesCtrl.text);
    } catch (_) {}
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _diseaseInfo =>
      DiseaseDatabase.getDiseaseInfo(widget.record.className);

  String get _severity {
    final info = _diseaseInfo;
    if (info != null && info['severity'] != null) return info['severity'];
    if (widget.record.category == 'heart_sound') return 'MEDIUM';
    if (widget.record.confidence >= 0.8) return 'HIGH';
    if (widget.record.confidence >= 0.5) return 'MEDIUM';
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

    switch (widget.record.category) {
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

  QualityGateResult _evaluateCurrentQuality() {
    return QualityGateService.auditDetectionRecord(
      record: widget.record,
      patientName: widget.patientName,
      doctorNotes: _notesCtrl.text,
    );
  }

  Future<void> _openQualityGateSheet() async {
    final qg = _evaluateCurrentQuality();
    final finalized = await QualityGateSheet.show(
      context,
      result: qg,
      record: widget.record,
      patientName: widget.patientName,
      doctorNotes: _notesCtrl.text,
      onNotesUpdated: (newNotes) {
        setState(() => _notesCtrl.text = newNotes);
      },
      title: 'Report Quality Gate',
      onAutoFix: () {
        Navigator.of(context).pop();
        setState(() {
          _notesCtrl.text =
              'Clinical impression consistent with ${widget.record.className}. Patient advised to schedule clinical follow-up within 14 business days and report any acute symptom changes.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ Applied Quality Gate clinical format enhancements.'),
            backgroundColor: Color(0xFF667EEA),
          ),
        );
        // Re-open with updated score
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _openQualityGateSheet();
        });
      },
    );

    if (finalized == true && mounted) {
      final updatedQg = _evaluateCurrentQuality();
      setState(() {
        _isFinalized = true;
        _finalizedGateResult = updatedQg;
      });
      await _persistFinalizedState();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Report signed and sealed (#${updatedQg.auditHash})'),
          backgroundColor: const Color(0xFF2ECC71),
        ),
      );
    }
  }

  Future<void> _exportCertifiedPdf() async {
    if (_finalizedGateResult == null) return;
    try {
      final file = await CertifiedReportPdfService.generateAndSave(
        record: widget.record,
        patientName: widget.patientName,
        qualityResult: _finalizedGateResult!,
        doctorNotes: _notesCtrl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📄 PDF saved: ${file.path.split("/").last.split("\\").last}'),
            backgroundColor: const Color(0xFF2ECC71),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF notice: $e')),
        );
      }
    }
  }

  void _copyCertifiedReport() {
    if (_finalizedGateResult?.enhancedContent != null) {
      Clipboard.setData(ClipboardData(text: _finalizedGateResult!.enhancedContent!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📋 Certified clinical report copied to clipboard.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;
    final severity = _severity;
    final catColor = _categoryColor(widget.record.category);
    final liveQg = _evaluateCurrentQuality();

    final dateStr =
        '${widget.record.timestamp.day}/${widget.record.timestamp.month}/${widget.record.timestamp.year}';
    final timeStr =
        '${widget.record.timestamp.hour.toString().padLeft(2, '0')}:${widget.record.timestamp.minute.toString().padLeft(2, '0')}';

    final confStr = widget.record.category == 'heart_sound'
        ? '${widget.record.confidence.toStringAsFixed(0)} ${AppStrings.get('bpm', lang)}'
        : '${(widget.record.confidence * 100).toStringAsFixed(1)}%';

    final description = _diseaseInfo?['description'] ??
        (widget.record.description.isNotEmpty
            ? widget.record.description
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
                            _categoryLabel(widget.record.category, lang),
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
                    // Finalized Certification Banner (if signed)
                    if (_isFinalized && _finalizedGateResult != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2ECC71).withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_user_rounded, color: Colors.white, size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'CLINICALLY FINALIZED & SEALED',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    Text(
                                      'Audit Hash: #${_finalizedGateResult!.auditHash} • Score: ${_finalizedGateResult!.overallScorePercent}%',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _exportCertifiedPdf,
                                icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white, size: 20),
                                tooltip: 'Export Certified PDF',
                              ),
                              IconButton(
                                onPressed: _copyCertifiedReport,
                                icon: const Icon(Icons.copy, color: Colors.white, size: 18),
                                tooltip: 'Copy Certified Report',
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0),

                    // Section 1: Patient Info
                    _sectionCard(
                      isDark: isDark,
                      delay: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(AppStrings.get('patient_information', lang), isDark),
                          const SizedBox(height: 12),
                          _infoRow(AppStrings.get('patient', lang), widget.patientName, isDark),
                          _infoRow(AppStrings.get('report_date', lang), '$dateStr at $timeStr', isDark),
                          _infoRow(AppStrings.get('report_id', lang),
                              widget.record.id?.substring(0, 8).toUpperCase() ?? 'N/A', isDark),
                          if (widget.record.performedByName != null)
                            _infoRow(
                              AppStrings.get('performed_by', lang),
                              '${widget.record.performedByName} (${widget.record.performedByRole ?? 'N/A'})',
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
                                  _categoryIcon(widget.record.category),
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
                                      _categoryLabel(widget.record.category, lang),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: catColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.record.className,
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

                    // Section 5: Physician Notes & Quality Gate Sign-Off
                    _sectionCard(
                      isDark: isDark,
                      delay: 350,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _sectionTitle('Physician Assessment & Remarks', isDark),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (liveQg.isPassed ? const Color(0xFF2ECC71) : const Color(0xFFF39C12))
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Q-GATE ${liveQg.overallScorePercent}%',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: liveQg.isPassed ? const Color(0xFF2ECC71) : const Color(0xFFF39C12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Quick Recommendation Autofill Preset Chips
                          if (!_isFinalized) ...[
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  _presetChip(
                                    label: '✨ Clean Review (6m)',
                                    text: 'Clinical impression consistent with ${widget.record.className}. Vitals within physiological limits. Routine review in 6 months.',
                                    isDark: isDark,
                                    color: const Color(0xFF2ECC71),
                                  ),
                                  const SizedBox(width: 6),
                                  _presetChip(
                                    label: '⚠️ 14-Day Follow-Up',
                                    text: 'Clinical impression consistent with ${widget.record.className}. Dietary modifications advised. Follow-up recommended within 14 business days.',
                                    isDark: isDark,
                                    color: const Color(0xFFF39C12),
                                  ),
                                  const SizedBox(width: 6),
                                  _presetChip(
                                    label: '🚨 Urgent Referral (24-48h)',
                                    text: 'Abnormal high-risk profile for ${widget.record.className}. Prompt clinician review and confirmatory diagnostic workup recommended within 24-48 hours.',
                                    isDark: isDark,
                                    color: const Color(0xFFFF5252),
                                  ),
                                  const SizedBox(width: 6),
                                  _presetChip(
                                    label: '📋 Multi-Modality Labs',
                                    text: 'Correlate ${widget.record.className} findings with standard diagnostic lab panels. Repeat fasting readings in 30 days.',
                                    isDark: isDark,
                                    color: const Color(0xFF667EEA),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          TextField(
                            controller: _notesCtrl,
                            enabled: !_isFinalized,
                            maxLines: 3,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Add clinical impression, diagnostic confirmation, or specific follow-up timeframe...',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                              ),
                              filled: true,
                              fillColor: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: (isDark ? Colors.white : Colors.black).withOpacity(0.1)),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          // Action Button: Run Quality Gate & Finalize
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _openQualityGateSheet,
                              icon: Icon(
                                _isFinalized ? Icons.fact_check_rounded : Icons.verified_user_outlined,
                                size: 18,
                              ),
                              label: Text(
                                _isFinalized ? 'View Certified Quality Gate Audit' : 'Run Quality Gate & Sign Report',
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor: _isFinalized ? const Color(0xFF2ECC71) : const Color(0xFF667EEA),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Section 6: Detection Metadata
                    _sectionCard(
                      isDark: isDark,
                      delay: 400,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(AppStrings.get('detection_metadata', lang), isDark),
                          const SizedBox(height: 12),
                          _infoRow(AppStrings.get('category', lang), widget.record.category, isDark),
                          _infoRow(AppStrings.get('timestamp', lang), '$dateStr $timeStr', isDark),
                          _infoRow(AppStrings.get('model_confidence', lang), confStr, isDark),
                          _infoRow(AppStrings.get('severity', lang), severity, isDark),
                          if (widget.record.performedByName != null)
                            _infoRow(AppStrings.get('performer', lang), widget.record.performedByName!, isDark),
                          if (widget.record.performedByRole != null)
                            _infoRow(AppStrings.get('performer_role', lang), widget.record.performedByRole!, isDark),
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

  Widget _presetChip({
    required String label,
    required String text,
    required bool isDark,
    required Color color,
  }) {
    final isSelected = _notesCtrl.text.trim() == text.trim();

    return InkWell(
      onTap: () {
        setState(() {
          _notesCtrl.text = text;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✨ Applied template: $label'),
            backgroundColor: color,
            duration: const Duration(milliseconds: 1500),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : color,
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
    final isPercentage = widget.record.category != 'heart_sound';
    final barValue = isPercentage ? widget.record.confidence : 0.75;

    Color barColor;
    if (isPercentage) {
      if (widget.record.confidence >= 0.8) {
        barColor = const Color(0xFF4CAF50);
      } else if (widget.record.confidence >= 0.5) {
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
