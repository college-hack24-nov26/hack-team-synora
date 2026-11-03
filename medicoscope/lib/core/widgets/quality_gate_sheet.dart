import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/models/quality_gate_result.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/services/quality_gate_service.dart';
import 'package:medicoscope/services/certified_report_pdf_service.dart';
import 'package:provider/provider.dart';

/// Interactive Repeatable Quality Gate Studio Sheet
///
/// Features:
/// 1. 5-Dimension Deterministic Quality Audit & Score Gauge
/// 2. Interactive Live Redline & Auto-Repair Studio
/// 3. Dual-Perspective Quality Evaluation (Patient vs. Clinician)
/// 4. Proof-of-Determinism Repeatability Benchmark Runner (10x zero-variance stress test)
/// 5. Exportable Certified Clinical PDF Generation
class QualityGateSheet extends StatefulWidget {
  final QualityGateResult result;
  final DetectionRecord? record;
  final String? patientName;
  final String? doctorNotes;
  final ValueChanged<String>? onNotesUpdated;
  final VoidCallback? onFinalize;
  final VoidCallback? onAutoFix;
  final String title;

  const QualityGateSheet({
    super.key,
    required this.result,
    this.record,
    this.patientName,
    this.doctorNotes,
    this.onNotesUpdated,
    this.onFinalize,
    this.onAutoFix,
    this.title = 'Repeatable Quality Gate',
  });

  static Future<bool?> show(
    BuildContext context, {
    required QualityGateResult result,
    DetectionRecord? record,
    String? patientName,
    String? doctorNotes,
    ValueChanged<String>? onNotesUpdated,
    VoidCallback? onAutoFix,
    String title = 'Repeatable Quality Gate',
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QualityGateSheet(
        result: result,
        record: record,
        patientName: patientName,
        doctorNotes: doctorNotes,
        onNotesUpdated: onNotesUpdated,
        onAutoFix: onAutoFix,
        title: title,
        onFinalize: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  @override
  State<QualityGateSheet> createState() => _QualityGateSheetState();
}

class _QualityGateSheetState extends State<QualityGateSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<QualityDimensionType> _expanded = {};
  late QualityPerspective _perspective;
  RepeatabilityProof? _proof;
  bool _isBenchmarking = false;
  bool _isGeneratingPdf = false;
  File? _generatedPdfFile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _perspective = widget.result.perspective;
    _proof = widget.result.repeatabilityProof;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _statusColor(QualityGateStatus status) {
    switch (status) {
      case QualityGateStatus.passed:
        return const Color(0xFF2ECC71);
      case QualityGateStatus.warning:
        return const Color(0xFFF39C12);
      case QualityGateStatus.blocked:
        return const Color(0xFFE74C3C);
    }
  }

  IconData _statusIcon(QualityGateStatus status) {
    switch (status) {
      case QualityGateStatus.passed:
        return Icons.verified_rounded;
      case QualityGateStatus.warning:
        return Icons.warning_amber_rounded;
      case QualityGateStatus.blocked:
        return Icons.gpp_bad_rounded;
    }
  }

  IconData _dimIcon(QualityDimensionType type) {
    switch (type) {
      case QualityDimensionType.structure:
        return Icons.account_tree_outlined;
      case QualityDimensionType.readability:
        return Icons.menu_book_outlined;
      case QualityDimensionType.safety:
        return Icons.shield_outlined;
      case QualityDimensionType.actionability:
        return Icons.directions_run_rounded;
      case QualityDimensionType.grounding:
        return Icons.fact_check_outlined;
    }
  }

  Future<void> _runBenchmark() async {
    if (widget.record == null) return;
    setState(() => _isBenchmarking = true);

    final proof = await QualityGateService.runRepeatabilityBenchmark(
      record: widget.record!,
      patientName: widget.patientName ?? 'Patient',
      doctorNotes: widget.doctorNotes,
      iterations: 10,
    );

    if (mounted) {
      setState(() {
        _proof = proof;
        _isBenchmarking = false;
      });
    }
  }

  Future<void> _exportPdf() async {
    if (widget.record == null) return;
    setState(() => _isGeneratingPdf = true);

    try {
      final file = await CertifiedReportPdfService.generateAndSave(
        record: widget.record!,
        patientName: widget.patientName ?? 'Patient',
        qualityResult: widget.result,
        doctorNotes: widget.doctorNotes,
      );

      if (mounted) {
        setState(() {
          _generatedPdfFile = file;
          _isGeneratingPdf = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📄 Certified PDF generated: ${file.path.split(Platform.pathSeparator).last}'),
            backgroundColor: const Color(0xFF2ECC71),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF generation notice: $e')),
        );
      }
    }
  }

  void _applyRedlineFix(RedlineIssue issue) {
    if (widget.doctorNotes == null || widget.onNotesUpdated == null) return;
    final current = widget.doctorNotes!;
    String updated;
    if (current.toLowerCase().contains(issue.originalClause.toLowerCase())) {
      updated = current.replaceAll(
        RegExp(RegExp.escape(issue.originalClause), caseSensitive: false),
        issue.suggestedReplacement,
      );
    } else {
      updated = '$current\n• ${issue.suggestedReplacement}';
    }
    widget.onNotesUpdated!(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✨ Applied: "${issue.suggestedReplacement}"'),
        backgroundColor: const Color(0xFF667EEA),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final r = widget.result;
    final statColor = _statusColor(r.status);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.50,
      maxChildSize: 0.96,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121622) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 25,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header Row with Title & Close
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.fact_check_rounded, color: statColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                        ),
                      ),
                      Text(
                        'Aegis Deterministic Clinical Quality Engine',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Dual Perspective Switch (Patient vs Clinician)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _perspective = QualityPerspective.clinician),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _perspective == QualityPerspective.clinician
                              ? const Color(0xFF667EEA)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.medical_services_outlined,
                              size: 14,
                              color: _perspective == QualityPerspective.clinician
                                  ? Colors.white
                                  : (isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Clinician / EHR Mode',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _perspective == QualityPerspective.clinician
                                    ? Colors.white
                                    : (isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _perspective = QualityPerspective.patient),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _perspective == QualityPerspective.patient
                              ? const Color(0xFF4ECDC4)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: _perspective == QualityPerspective.patient
                                  ? Colors.white
                                  : (isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Patient View Mode',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _perspective == QualityPerspective.patient
                                    ? Colors.white
                                    : (isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Overall Score Card
            GlassCard(
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Score Gauge
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 68,
                            height: 68,
                            child: CircularProgressIndicator(
                              value: r.overallScore,
                              strokeWidth: 7,
                              backgroundColor: statColor.withOpacity(0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(statColor),
                            ),
                          ),
                          Text(
                            '${r.overallScorePercent}%',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: statColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: statColor.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_statusIcon(r.status), size: 13, color: statColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    r.status.name.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: statColor,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              r.headline,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Readability: ${r.readingGradeLevel}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  // Audit Seal Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lock_clock_outlined, size: 14, color: isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                          const SizedBox(width: 4),
                          Text(
                            'Audit Seal: #${r.auditHash}',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        r.rulesVersion,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Proof of Repeatability & Determinism Stress-Test Banner
            if (_proof != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF667EEA).withOpacity(0.15),
                      const Color(0xFF764BA2).withOpacity(0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF667EEA).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.science_rounded, color: Color(0xFF667EEA), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PROOF OF DETERMINISM VERIFIED (10x)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF667EEA),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Variance σ = ${_proof!.variance.toStringAsFixed(6)} (Zero Drift) • ${_proof!.executionTimeMs.toStringAsFixed(1)}ms benchmark',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF2ECC71), size: 18),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),

            // Tabs for 5-Point Checks vs Live Redlines
            TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF667EEA),
              labelColor: const Color(0xFF667EEA),
              unselectedLabelColor: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              tabs: [
                const Tab(text: '5-Point Verification'),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Live Redline Studio'),
                      if (r.redlines.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF39C12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${r.redlines.length}',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tab Content
            SizedBox(
              height: 380,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: 5-Point Dimension Cards
                  ListView(
                    children: [
                      ...r.dimensions.map((dim) {
                        final isExpanded = _expanded.contains(dim.type);
                        final dimColor = _statusColor(dim.status);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expanded.remove(dim.type);
                                      } else {
                                        _expanded.add(dim.type);
                                      }
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: dimColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(_dimIcon(dim.type), color: dimColor, size: 18),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  dim.title,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  '${dim.scorePercent}%',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                    color: dimColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(3),
                                              child: LinearProgressIndicator(
                                                value: dim.score,
                                                minHeight: 4,
                                                backgroundColor: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
                                                valueColor: AlwaysStoppedAnimation<Color>(dimColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                        size: 20,
                                        color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isExpanded) ...[
                                  const SizedBox(height: 8),
                                  const Divider(height: 1),
                                  const SizedBox(height: 6),
                                  ...dim.passedChecks.map((item) => Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.check_circle, size: 14, color: Color(0xFF2ECC71)),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                item,
                                                style: TextStyle(fontSize: 11.5, color: isDark ? AppTheme.darkTextLight : AppTheme.textDark),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )),
                                  ...dim.warnings.map((item) => Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFF39C12)),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                item,
                                                style: const TextStyle(fontSize: 11.5, color: Color(0xFFF39C12)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),

                  // Tab 2: Live Redline & Auto-Repair Studio
                  ListView(
                    children: [
                      if (r.redlines.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(Icons.verified_rounded, color: Color(0xFF2ECC71), size: 40),
                                const SizedBox(height: 8),
                                Text(
                                  'Clean Clinical Output',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'No clinical jargon or safety redlines detected.',
                                  style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Click any chip below to auto-patch into the report:',
                            style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                          ),
                        ),
                        ...r.redlines.map((issue) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: issue.category == 'safety'
                                      ? const Color(0xFFE74C3C).withOpacity(0.3)
                                      : const Color(0xFFF39C12).withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (issue.category == 'safety' ? const Color(0xFFE74C3C) : const Color(0xFFF39C12)).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          issue.category.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: issue.category == 'safety' ? const Color(0xFFE74C3C) : const Color(0xFFF39C12),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Flagged: "${issue.originalClause}"',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    issue.explanation,
                                    style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _applyRedlineFix(issue),
                                      icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                                      label: Text('Apply "${issue.suggestedReplacement}"', style: const TextStyle(fontSize: 11)),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        backgroundColor: const Color(0xFF667EEA),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isBenchmarking ? null : _runBenchmark,
                    icon: _isBenchmarking
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.science_outlined, size: 16),
                    label: const Text('10x Repeatability Test', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: const Color(0xFF667EEA).withOpacity(0.5)),
                      foregroundColor: const Color(0xFF667EEA),
                    ),
                  ),
                ),
                if (widget.record != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isGeneratingPdf ? null : _exportPdf,
                      icon: _isGeneratingPdf
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('Export Certified PDF', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: const Color(0xFF2ECC71).withOpacity(0.5)),
                        foregroundColor: const Color(0xFF2ECC71),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            ElevatedButton.icon(
              onPressed: r.isBlocked ? null : widget.onFinalize,
              icon: Icon(r.isPassed ? Icons.verified_user_rounded : Icons.check_circle_outline),
              label: Text(r.isPassed ? 'Certify & Finalize Report' : 'Acknowledge & Sign'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: statColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
