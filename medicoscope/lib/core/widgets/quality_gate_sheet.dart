import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/models/quality_gate_result.dart';
import 'package:provider/provider.dart';

/// Modal bottom sheet that presents a complete Repeatable Quality Gate evaluation.
class QualityGateSheet extends StatefulWidget {
  final QualityGateResult result;
  final VoidCallback? onFinalize;
  final VoidCallback? onAutoFix;
  final String title;

  const QualityGateSheet({
    super.key,
    required this.result,
    this.onFinalize,
    this.onAutoFix,
    this.title = 'Repeatable Quality Gate',
  });

  static Future<bool?> show(
    BuildContext context, {
    required QualityGateResult result,
    VoidCallback? onAutoFix,
    String title = 'Repeatable Quality Gate',
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QualityGateSheet(
        result: result,
        onAutoFix: onAutoFix,
        title: title,
        onFinalize: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  @override
  State<QualityGateSheet> createState() => _QualityGateSheetState();
}

class _QualityGateSheetState extends State<QualityGateSheet> {
  final Set<QualityDimensionType> _expanded = {};

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

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final r = widget.result;
    final statColor = _statusColor(r.status);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.50,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141824) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, -5),
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
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
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
                        'Standardized Clinical Content Quality Check',
                        style: TextStyle(
                          fontSize: 12,
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
            const SizedBox(height: 16),

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
                            width: 64,
                            height: 64,
                            child: CircularProgressIndicator(
                              value: r.overallScore,
                              strokeWidth: 6,
                              backgroundColor: statColor.withOpacity(0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(statColor),
                            ),
                          ),
                          Text(
                            '${r.overallScorePercent}%',
                            style: TextStyle(
                              fontSize: 16,
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
            const SizedBox(height: 20),

            // Dimension Checklist Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '5-Point Quality Verification',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                  ),
                ),
                Text(
                  '${r.dimensions.where((d) => d.status == QualityGateStatus.passed).length}/5 Passed',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 5 Dimension Cards
            ...r.dimensions.map((dim) {
              final isExpanded = _expanded.contains(dim.type);
              final dimColor = _statusColor(dim.status);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
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
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            dim.description,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Passed items
                        ...dim.passedChecks.map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.check_circle, size: 14, color: Color(0xFF2ECC71)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        // Warnings
                        ...dim.warnings.map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFF39C12)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: const Color(0xFFF39C12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        // Critical issues
                        ...dim.criticalIssues.map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error_outline, size: 14, color: Color(0xFFE74C3C)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFE74C3C),
                                      ),
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

            const SizedBox(height: 16),

            // Action Buttons
            if (widget.onAutoFix != null && r.autoFixSuggestions.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: widget.onAutoFix,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text('Apply ${r.autoFixSuggestions.length} Quality Enhancements'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: const Color(0xFF667EEA).withOpacity(0.6)),
                  foregroundColor: const Color(0xFF667EEA),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
            ],

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
