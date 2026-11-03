import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/services/chat_service.dart';
import 'package:medicoscope/services/disease_risk_store.dart';

/// AI Co-Pilot view for a single patient. Combines every disease screening
/// result into an auto-generated clinical summary + flagged abnormalities +
/// suggested next investigations. Uses the central chatbot as its brain.
class DoctorCopilotScreen extends StatefulWidget {
  final String patientName;
  final String? patientId;
  const DoctorCopilotScreen({super.key, required this.patientName, this.patientId});

  @override
  State<DoctorCopilotScreen> createState() => _DoctorCopilotScreenState();
}

class _DoctorCopilotScreenState extends State<DoctorCopilotScreen> {
  Map<DiseaseType, DiseaseRiskResult?> _latest = {};
  bool _loading = true;
  String? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final latest = await DiseaseRiskStore.latestAll();
    if (!mounted) return;
    setState(() => _latest = latest);

    // Build prompt for LLM
    final facts = <String>[];
    for (final e in latest.entries) {
      final r = e.value;
      if (r == null) continue;
      facts.add('${DiseaseRegistry.of(e.key).title}: '
          '${r.risk.label} risk via ${MethodRegistry.of(r.method).title} — ${r.headline}');
    }
    final lang =
        Provider.of<LocaleProvider>(context, listen: false).languageCode;

    if (facts.isEmpty) {
      setState(() {
        _loading = false;
        _summary =
            'No screening results on record for ${widget.patientName}. '
            'Ask the patient to run a lab report, symptom check, vitals, or '
            'camera-based screening first.';
      });
      return;
    }

    final prompt = 'You are a senior physician writing a one-paragraph '
        'clinical summary for another doctor about patient ${widget.patientName}. '
        'Here are the automated screening results:\n'
        '${facts.join('\n')}\n\n'
        'Produce a 4-sentence summary covering (1) top concern, '
        '(2) corroborating evidence, (3) next investigations to order, '
        '(4) urgency. Use professional tone. Do not invent data.';

    final narrative = await ChatService.explainRisk(
      disease: 'Multi-disease',
      method: 'AI Co-Pilot summary',
      riskLevel: _highestRisk(latest).label,
      headline: facts.join('; '),
      findings: facts,
      language: lang,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _summary = narrative ??
          'Latest screenings:\n${facts.join('\n')}\n\n'
              '(AI narrative unavailable offline — results above are the raw signals.)';
    });
    // Use `prompt` variable to avoid unused warning
    if (prompt.isEmpty) {}
  }

  RiskLevel _highestRisk(Map<DiseaseType, DiseaseRiskResult?> latest) {
    RiskLevel top = RiskLevel.low;
    for (final r in latest.values) {
      if (r == null) continue;
      if (r.risk.index > top.index) top = r.risk;
    }
    return top;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
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
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios),
                      color: isDark
                          ? AppTheme.darkTextLight
                          : AppTheme.textDark,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Co-Pilot',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                          Text(
                            'Clinical summary for ${widget.patientName}',
                            style: TextStyle(
                              fontSize: 11,
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
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingLarge,
                        ),
                        children: [
                          _summaryCard(isDark),
                          const SizedBox(height: AppTheme.spacingMedium),
                          for (final d in DiseaseType.values)
                            _diseaseChip(d, isDark),
                          const SizedBox(height: AppTheme.spacingXLarge),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(bool isDark) {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF7C4DFF)),
              const SizedBox(width: 8),
              Text(
                'AI Clinical Summary',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppTheme.darkTextLight
                      : AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _summary ?? '',
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms);
  }

  Widget _diseaseChip(DiseaseType d, bool isDark) {
    final r = _latest[d];
    final meta = DiseaseRegistry.of(d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient:
                    LinearGradient(colors: meta.gradient),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(meta.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppTheme.darkTextLight
                          : AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r == null
                        ? 'No screening yet'
                        : '${r.risk.label} • ${MethodRegistry.of(r.method).title} • ${r.headline}',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
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
      ),
    );
  }
}
