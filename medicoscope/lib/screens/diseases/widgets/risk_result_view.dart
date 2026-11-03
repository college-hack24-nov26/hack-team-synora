import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/models/disease_risk_result.dart';

/// Unified result panel used by every detection method.
class RiskResultView extends StatelessWidget {
  final DiseaseRiskResult result;
  final VoidCallback? onRetry;

  const RiskResultView({super.key, required this.result, this.onRetry});

  Color _colorFor(RiskLevel r) {
    switch (r) {
      case RiskLevel.low:
        return const Color(0xFF4CAF50);
      case RiskLevel.moderate:
        return const Color(0xFFFF9800);
      case RiskLevel.high:
        return const Color(0xFFFF5252);
      case RiskLevel.critical:
        return const Color(0xFFD32F2F);
    }
  }

  IconData _flagIcon(String flag) {
    switch (flag) {
      case 'critical':
        return Icons.crisis_alert_rounded;
      case 'high':
        return Icons.trending_up_rounded;
      case 'low':
        return Icons.trending_down_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  Color _flagColor(String flag) {
    switch (flag) {
      case 'critical':
        return const Color(0xFFD32F2F);
      case 'high':
        return const Color(0xFFFF5252);
      case 'low':
        return const Color(0xFFFFA000);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final meta = DiseaseRegistry.of(result.disease);
    final c = _colorFor(result.risk);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Headline / score card
        GlassCard(
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.withOpacity(0.4)),
                    ),
                    child: Text(
                      '${result.risk.label} RISK',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: c,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(result.score * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: c,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                result.headline,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: result.score.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor:
                      isDark ? Colors.white10 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(c),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.science_outlined,
                      size: 13,
                      color:
                          isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Source: ${result.dataSource}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppTheme.darkTextGray
                            : AppTheme.textGray,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),

        if (result.topContributors.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What drove this score',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextLight
                        : AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                ...result.topContributors.map(
                  (r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded,
                            size: 15, color: meta.gradient.first),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
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
          ).animate().fadeIn(delay: 100.ms, duration: 350.ms),
        ],

        if (result.findings.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Markers detected (${result.findings.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextLight
                        : AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                ...result.findings.map((f) {
                  final fc = _flagColor(f.flag);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_flagIcon(f.flag), size: 16, color: fc),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      f.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppTheme.darkTextLight
                                            : AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${f.value} ${f.unit}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: fc,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                f.interpretation,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: isDark
                                      ? AppTheme.darkTextGray
                                      : AppTheme.textGray,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Ref: ${f.referenceRange}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                  color: isDark
                                      ? AppTheme.darkTextGray
                                      : AppTheme.textGray,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
        ],

        if (result.recommendations.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.recommend_outlined,
                        size: 16, color: meta.gradient.first),
                    const SizedBox(width: 6),
                    Text(
                      'Recommendations',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextLight
                            : AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...result.recommendations.map((r) {
                  final urgent = r.startsWith('URGENT');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          urgent
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          size: 15,
                          color: urgent
                              ? const Color(0xFFFF5252)
                              : const Color(0xFF4ECDC4),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              fontWeight: urgent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: urgent
                                  ? const Color(0xFFFF5252)
                                  : isDark
                                      ? AppTheme.darkTextLight
                                      : AppTheme.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
        ],

        if (result.llmExplanation != null &&
            result.llmExplanation!.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 16, color: meta.gradient.first),
                    const SizedBox(width: 6),
                    Text(
                      'MedicoScope AI',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextLight
                            : AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  result.llmExplanation!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: isDark
                        ? AppTheme.darkTextLight
                        : AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
        ],

        if (onRetry != null) ...[
          const SizedBox(height: AppTheme.spacingLarge),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Run again'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: meta.gradient.first.withOpacity(0.5)),
            ),
          ),
        ],
      ],
    );
  }
}
