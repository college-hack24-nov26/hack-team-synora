import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/services/aegis_service.dart';

/// Aegis Console — the clinician's view of the safety gate. Lists RED cases the
/// agent BLOCKED and escalated, lets a clinician approve/modify/override, and
/// shows the tamper-evident audit ledger ("chain INTACT"). This is where the
/// "human-in-the-loop, governed autonomy" story becomes tangible.
class AegisConsoleScreen extends StatefulWidget {
  const AegisConsoleScreen({super.key});

  @override
  State<AegisConsoleScreen> createState() => _AegisConsoleScreenState();
}

class _AegisConsoleScreenState extends State<AegisConsoleScreen> {
  List<Map<String, dynamic>> _cases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token == null) {
      setState(() => _loading = false);
      return;
    }
    final svc = AegisService(auth.token!);
    final cases = await svc.getCases();
    if (!mounted) return;
    setState(() {
      _cases = cases;
      _loading = false;
    });
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
              _header(isDark),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _cases.isEmpty
                            ? _empty(isDark)
                            : ListView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(
                                    AppTheme.spacingLarge),
                                itemCount: _cases.length,
                                itemBuilder: (c, i) =>
                                    _caseCard(_cases[i], isDark, i),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool isDark) => Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Row(children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new,
                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Aegis Console',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppTheme.darkTextLight
                              : AppTheme.textDark)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE26D6D),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text('${_cases.length} RED',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ]),
                Text('Human-in-the-loop · gate-blocked actions',
                    style: TextStyle(
                        fontSize: 12.5,
                        color:
                            (isDark ? AppTheme.darkTextLight : AppTheme.textGray)
                                .withValues(alpha: .8))),
              ],
            ),
          ),
        ]),
      );

  Widget _empty(bool isDark) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 140),
          Icon(Icons.verified_user_outlined,
              size: 60,
              color: const Color(0xFF7EC08F).withValues(alpha: .7)),
          const SizedBox(height: 16),
          Center(
            child: Text('No actions awaiting review',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('The gate escalates a case here when it blocks a RED action.',
                style: TextStyle(
                    fontSize: 13,
                    color:
                        (isDark ? AppTheme.darkTextLight : AppTheme.textGray)
                            .withValues(alpha: .8))),
          ),
        ],
      );

  Widget _caseCard(Map<String, dynamic> k, bool isDark, int i) {
    final flags = (k['triggeredFlags'] as List?)?.join(', ') ?? '';
    final risk = (k['riskLevel'] ?? 'critical').toString();
    return GestureDetector(
      onTap: () => _openDetail(k),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: const Color(0xFFE26D6D).withValues(alpha: .3), width: 1),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFE26D6D).withValues(alpha: .10),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFE26D6D),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('RED · BLOCKED',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
              const Spacer(),
              Text(risk.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFC0392B))),
            ]),
            const SizedBox(height: 10),
            Text(k['patientName']?.toString().isNotEmpty == true
                ? k['patientName']
                : 'Patient ${k['patientId'] ?? ''}',
                style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
            const SizedBox(height: 4),
            Text(k['summary']?.toString() ?? 'Screening signal requires review',
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: (isDark ? AppTheme.darkTextLight : AppTheme.textGray)
                        .withValues(alpha: .85))),
            if (flags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xFFE26D6D).withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.flag, size: 13, color: Color(0xFFC0392B)),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(flags,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFC0392B)))),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.touch_app_outlined,
                  size: 14, color: AppTheme.primaryOrange),
              const SizedBox(width: 6),
              Text('Tap to review · approve / modify / override',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.primaryOrange,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      ),
    ).animate().fadeIn(delay: (i * 60).ms, duration: 350.ms).slideY(begin: 0.06, end: 0);
  }

  Future<void> _openDetail(Map<String, dynamic> k) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final svc = AegisService(auth.token!);
    final detail = await svc.getCase(k['_id']?.toString() ?? '');
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CaseDetailSheet(
        caseData: k,
        detail: detail,
        onResolve: (verb, reason) async {
          final res = await svc.resolve(k['_id'].toString(), verb, reason: reason);
          if (mounted) Navigator.of(context).pop();
          if (res != null) _load();
        },
      ),
    );
  }
}

/// Detail sheet: frozen proposal + reasoning + audit ledger + clinician verbs.
class _CaseDetailSheet extends StatelessWidget {
  final Map<String, dynamic> caseData;
  final Map<String, dynamic>? detail;
  final Future<void> Function(String verb, String reason) onResolve;
  const _CaseDetailSheet(
      {required this.caseData, required this.detail, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ledger = (detail?['ledger'] as List?) ?? const [];
    final integrity = detail?['ledgerIntegrity'] as Map<String, dynamic>?;
    final intact = integrity?['ok'] == true;
    final proposed = caseData['proposedAction'] as Map<String, dynamic>?;
    final reasons = proposed?['rationale']?.toString() ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, sc) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkBackground : const Color(0xFFFFFBFC),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: sc,
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          children: [
            Center(
              child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(4))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFE26D6D),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('RED CASE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(caseData['summary']?.toString() ?? 'Action withheld pending review',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark)),

            // Patient live location (for outreach on a RED case)
            if ((caseData['mapsUrl']?.toString().isNotEmpty ?? false) ||
                (caseData['locationLabel']?.toString().isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.location_on, size: 16, color: Color(0xFFE26D6D)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (caseData['locationLabel']?.toString().isNotEmpty ?? false)
                        ? caseData['locationLabel'].toString()
                        : 'Location shared',
                    style: TextStyle(
                        fontSize: 13,
                        color:
                            isDark ? AppTheme.darkTextLight : AppTheme.textDark),
                  ),
                ),
                if (caseData['mapsUrl']?.toString().isNotEmpty ?? false)
                  GestureDetector(
                    onTap: () => launchUrl(
                        Uri.parse(caseData['mapsUrl'].toString()),
                        mode: LaunchMode.externalApplication),
                    child: const Text('Open in Maps',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF667EEA),
                            decoration: TextDecoration.underline)),
                  ),
              ]),
            ],

            // WHY panel (reasoning transparency)
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 16),
              _section('Why the agent stopped', isDark),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFFE26D6D).withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(reasons,
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.5, color: Color(0xFFC0392B))),
              ),
            ],

            // Audit ledger
            const SizedBox(height: 18),
            Row(children: [
              _section('Audit ledger', isDark),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: (intact ? const Color(0xFF7EC08F) : const Color(0xFFE26D6D))
                        .withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(intact ? Icons.link : Icons.link_off,
                      size: 13,
                      color: intact
                          ? const Color(0xFF5E8A6E)
                          : const Color(0xFFC0392B)),
                  const SizedBox(width: 5),
                  Text(intact ? 'Chain INTACT' : 'Chain BROKEN',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: intact
                              ? const Color(0xFF5E8A6E)
                              : const Color(0xFFC0392B))),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            if (ledger.isEmpty)
              Text('No ledger rows loaded.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textGray))
            else
              ...ledger.map((row) => _ledgerRow(row as Map<String, dynamic>, isDark)),

            // Verbs
            const SizedBox(height: 22),
            _section('Clinician decision', isDark),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _verbBtn('Approve', const Color(0xFF7EC08F),
                      () => onResolve('approve', 'Reviewed and approved'))),
              const SizedBox(width: 10),
              Expanded(
                  child: _verbBtn('Override', const Color(0xFFE26D6D),
                      () => onResolve('override', 'Clinician override'))),
            ]),
            const SizedBox(height: 10),
            _verbBtn('Escalate further', const Color(0xFFF0B45C),
                () => onResolve('escalate', 'Escalated'),
                full: true),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _section(String t, bool isDark) => Text(t,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .08 * 16,
          color: AppTheme.primaryOrange));

  Widget _ledgerRow(Map<String, dynamic> row, bool isDark) {
    final type = row['decisionType']?.toString() ?? '';
    final cls = row['actionClass']?.toString();
    final seq = row['seq']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: .04),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Text('#$seq',
            style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.textGray)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(type,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark))),
        if (cls != null && cls != 'null')
          Text(cls,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _verbBtn(String label, Color color, VoidCallback onTap,
      {bool full = false}) {
    return SizedBox(
      width: full ? double.infinity : null,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
