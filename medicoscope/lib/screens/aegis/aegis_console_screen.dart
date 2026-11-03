import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/services/aegis_service.dart';
import 'package:medicoscope/widgets/aegis/aegis_shield.dart';

const Color _kRed = Color(0xFFE26D6D);
const Color _kRedDark = Color(0xFFC0392B);
const Color _kGreen = Color(0xFF7EC08F);

/// Aegis Console - the clinician's view of the safety gate. Lists RED cases the
/// agent BLOCKED and escalated, lets a clinician approve/modify/override, and
/// shows the tamper-evident audit ledger ("chain INTACT").
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
        child: Column(
          children: [
            _hero(isDark),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _cases.isEmpty
                          ? _empty(isDark)
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(AppTheme.spacingLarge),
                              itemCount: _cases.length,
                              itemBuilder: (c, i) =>
                                  _caseCard(_cases[i], isDark, i),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(bool isDark) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE26D6D), Color(0xFF9B2C4E)],
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 18),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              AegisShield(
                  size: 46,
                  color: Colors.white,
                  pulsing: _cases.isNotEmpty,
                  icon: Icons.gpp_maybe_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('Aegis Console',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      const SizedBox(width: 8),
                      if (!_loading)
                        _redBadge('${_cases.length} RED'),
                    ]),
                    const SizedBox(height: 2),
                    Text('Human-in-the-loop · gate-blocked actions',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: .85))),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _redBadge(String label) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .24),
          borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
    );
    if (_cases.isEmpty) return badge;
    return badge
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 1.0, end: 1.12, duration: 900.ms);
  }

  Widget _empty(bool isDark) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
              child: AegisShield(
                  size: 90,
                  color: _kGreen,
                  pulsing: false,
                  icon: Icons.verified_user_rounded)),
          const SizedBox(height: 16),
          Center(
            child: Text('No actions awaiting review',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                  'The gate escalates a case here when it blocks a RED action.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: (isDark ? AppTheme.darkTextLight : AppTheme.textGray)
                          .withValues(alpha: .8))),
            ),
          ),
        ],
      );

  String? _slaText(Map<String, dynamic> k) {
    final raw = k['slaDeadline']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'SLA overdue';
    if (diff.inMinutes < 60) return 'SLA ${diff.inMinutes}m';
    return 'SLA ${diff.inHours}h';
  }

  Widget _caseCard(Map<String, dynamic> k, bool isDark, int i) {
    final flags = (k['triggeredFlags'] as List?)?.join(', ') ?? '';
    final sla = _slaText(k);
    final overdue = sla == 'SLA overdue';

    final card = GestureDetector(
      onTap: () => _openDetail(k),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kRed.withValues(alpha: .3), width: 1),
          boxShadow: [
            BoxShadow(
                color: _kRed.withValues(alpha: .12),
                blurRadius: 14,
                offset: const Offset(0, 5))
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // RED urgency accent bar.
            Container(
              width: 6,
              decoration: const BoxDecoration(
                color: _kRed,
                borderRadius: BorderRadius.horizontal(left: Radius.circular(18)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                            color: _kRed,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text('RED · BLOCKED',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                      const Spacer(),
                      if (sla != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: (overdue ? _kRed : const Color(0xFFF0B45C))
                                  .withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(999)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.timer_outlined,
                                size: 12,
                                color: overdue ? _kRedDark : const Color(0xFF9A6A16)),
                            const SizedBox(width: 4),
                            Text(sla,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: overdue
                                        ? _kRedDark
                                        : const Color(0xFF9A6A16))),
                          ]),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                        k['patientName']?.toString().isNotEmpty == true
                            ? k['patientName']
                            : 'Patient ${k['patientId'] ?? ''}',
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.textDark)),
                    const SizedBox(height: 4),
                    Text(
                        k['summary']?.toString() ??
                            'Screening signal requires review',
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: (isDark
                                    ? AppTheme.darkTextLight
                                    : AppTheme.textGray)
                                .withValues(alpha: .85))),
                    if (flags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: _kRed.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.flag, size: 13, color: _kRedDark),
                          const SizedBox(width: 6),
                          Flexible(
                              child: Text(flags,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: _kRedDark))),
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
            ),
          ],
        ),
      ),
    );

    return card
        .animate()
        .fadeIn(delay: (i * 70).ms, duration: 360.ms)
        .slideY(begin: 0.08, end: 0);
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

/// Detail sheet: frozen proposal + reasoning + animated hash-chain ledger + verbs.
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
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                    color: _kRed, borderRadius: BorderRadius.circular(8)),
                child: const Text('RED CASE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 900.ms)
                  .then()
                  .fadeOut(duration: 900.ms),
            ]),
            const SizedBox(height: 12),
            Text(
                caseData['summary']?.toString() ??
                    'Action withheld pending review',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark)),

            if ((caseData['mapsUrl']?.toString().isNotEmpty ?? false) ||
                (caseData['locationLabel']?.toString().isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.location_on, size: 16, color: _kRed),
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

            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 16),
              _section('Why the agent stopped'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(reasons,
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.5, color: _kRedDark)),
              ),
            ],

            // Audit ledger as an animated hash-chain.
            const SizedBox(height: 18),
            Row(children: [
              _section('Audit ledger'),
              const Spacer(),
              _chainBadge(intact),
            ]),
            const SizedBox(height: 12),
            if (ledger.isEmpty)
              Text('No ledger rows loaded.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textGray))
            else
              for (int i = 0; i < ledger.length; i++)
                _ledgerLink(ledger[i] as Map<String, dynamic>, isDark,
                    first: i == 0, last: i == ledger.length - 1, index: i),

            const SizedBox(height: 22),
            _section('Clinician decision'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _verbBtn('Approve', _kGreen,
                      () => onResolve('approve', 'Reviewed and approved'))),
              const SizedBox(width: 10),
              Expanded(
                  child: _verbBtn('Override', _kRed,
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

  Widget _chainBadge(bool intact) {
    final c = intact ? _kGreen : _kRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(intact ? Icons.link_rounded : Icons.link_off_rounded,
            size: 13, color: intact ? const Color(0xFF5E8A6E) : _kRedDark),
        const SizedBox(width: 5),
        Text(intact ? 'Chain INTACT' : 'Chain BROKEN',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: intact ? const Color(0xFF5E8A6E) : _kRedDark)),
      ]),
    )
        .animate()
        .fadeIn(delay: 500.ms, duration: 400.ms)
        .scaleXY(begin: 0.8, end: 1.0, curve: Curves.easeOutBack)
        .shimmer(delay: 900.ms, duration: 1000.ms, color: c.withValues(alpha: .4));
  }

  Widget _ledgerLink(Map<String, dynamic> row, bool isDark,
      {required bool first, required bool last, required int index}) {
    final type = row['decisionType']?.toString() ?? '';
    final cls = row['actionClass']?.toString();
    final seq = row['seq']?.toString() ?? '';
    final hash = row['hash']?.toString() ?? '';
    final shortHash = hash.length > 8 ? hash.substring(0, 8) : hash;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // chain node + connector
            Column(children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAegisNodeColor(cls),
                ),
                child: Text(seq,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11,
                        height: 2.0,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(type,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark)),
                      if (shortHash.isNotEmpty)
                        Text('#$shortHash',
                            style: const TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: AppTheme.textGray)),
                    ],
                  )),
                  if (cls != null && cls != 'null')
                    Text(cls,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _kAegisNodeColor(cls))),
                ]),
              ),
            ),
          ],
        ),
        if (!last)
          Container(
            margin: const EdgeInsets.only(left: 12),
            child: Row(children: [
              Icon(Icons.link_rounded,
                  size: 14, color: _kGreen.withValues(alpha: .6)),
              const SizedBox(width: 6),
              Container(
                  width: 2,
                  height: 10,
                  color: _kGreen.withValues(alpha: .3)),
            ]),
          ),
      ],
    )
        .animate()
        .fadeIn(delay: (index * 120).ms, duration: 350.ms)
        .slideX(begin: 0.08, end: 0);
  }

  static Color _kAegisNodeColor(String? cls) {
    switch ((cls ?? '').toUpperCase()) {
      case 'RED':
        return _kRed;
      case 'AMBER':
        return const Color(0xFFF0B45C);
      case 'GREEN':
        return _kGreen;
      default:
        return const Color(0xFF8FB8D6);
    }
  }

  Widget _section(String t) => Text(t,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppTheme.primaryOrange));

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
          elevation: 4,
          shadowColor: color.withValues(alpha: .5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 350.ms).scaleXY(begin: 0.96, end: 1.0);
  }
}
