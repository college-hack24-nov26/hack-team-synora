import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/services/consult_service.dart';
import 'package:medicoscope/services/location_service.dart';
import 'package:medicoscope/widgets/aegis/aegis_shield.dart';

/// Live Agent Consult - the autonomous loop, on screen. Streams the Aegis
/// decision-trace (triage -> plan -> tool calls -> fusion -> gate verdict) and
/// renders each step as it happens, so the "agentic" system is visible, not
/// just claimed. Calls POST /aegis/consult (SSE).
class LiveConsultScreen extends StatefulWidget {
  final String? presetComplaint;
  const LiveConsultScreen({super.key, this.presetComplaint});

  @override
  State<LiveConsultScreen> createState() => _LiveConsultScreenState();
}

class _TraceItem {
  final String agent;
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  String? verdict;
  _TraceItem(this.agent, this.title, this.subtitle, this.color, this.icon,
      {this.verdict});
}

const List<String> _kStages = ['Triage', 'Plan', 'Evidence', 'Fuse', 'Gate'];
const Color _kAegis = Color(0xFF7C5CE6); // aegis violet accent

class _LiveConsultScreenState extends State<LiveConsultScreen> {
  final _complaintCtrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_TraceItem> _trace = [];
  bool _running = false;
  bool _done = false;
  String? _error;
  String _verdict = '';
  String _dataBasis = '';
  int _stage = 0; // 0..5 pipeline progress

  @override
  void initState() {
    super.initState();
    if (widget.presetComplaint != null) {
      _complaintCtrl.text = widget.presetComplaint!;
    }
  }

  @override
  void dispose() {
    _complaintCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Color _riskColor(String? r) {
    switch ((r ?? '').toUpperCase()) {
      case 'RED':
      case 'CRITICAL':
        return const Color(0xFFE26D6D);
      case 'AMBER':
      case 'HIGH':
        return const Color(0xFFF0B45C);
      case 'GREEN':
      case 'LOW':
        return const Color(0xFF7EC08F);
      default:
        return AppTheme.primaryOrange;
    }
  }

  String _basisLabel(String basis) {
    switch (basis) {
      case 'measured':
        return 'Based on your real screening data.';
      case 'symptom_only':
        return 'Symptom-based triage only, not a diagnosis. Run a screening (lab, photo or vitals) for a real assessment.';
      case 'insufficient':
        return 'No screening data yet, not a diagnosis. Run a screening to get a real assessment.';
      default:
        return 'Modalities agree.';
    }
  }

  void _reach(int s) {
    if (_stage < s) _stage = s;
  }

  void _add(_TraceItem t) {
    setState(() => _trace.add(t));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _start() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    if (user == null || auth.token == null) {
      setState(() => _error = 'Please sign in to run a consult.');
      return;
    }
    if (_complaintCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Describe how you feel to start the consult.');
      return;
    }
    setState(() {
      _running = true;
      _done = false;
      _error = null;
      _verdict = '';
      _dataBasis = '';
      _stage = 0;
      _trace.clear();
    });

    final fix = await LocationService.getFix();

    final stream = ConsultService.run(
      patientId: user.id,
      patientName: user.name,
      complaint: _complaintCtrl.text.trim(),
      authToken: auth.token!,
      latitude: fix.latitude,
      longitude: fix.longitude,
      locationLabel: fix.label,
      mapsUrl: fix.mapsUrl,
    );

    try {
      await for (final e in stream) {
        switch (e.event) {
          case 'consult_start':
            _add(_TraceItem('Orchestrator', 'Consult started',
                'Patient: ${e.data['patient'] ?? ''}', AppTheme.primaryOrange,
                Icons.play_circle_outline));
            break;
          case 'triage_result':
            _reach(1);
            final suspected = (e.data['suspected'] as List?)?.join(', ') ?? '';
            final acuity = e.data['acuity'] ?? 'routine';
            final reasoning = e.data['reasoning']?.toString() ?? '';
            final llm = e.data['planner'] == 'llm';
            _add(_TraceItem(
                llm ? 'Triage Agent · Llama' : 'Triage Agent',
                'Triaged complaint',
                reasoning.isNotEmpty
                    ? '$reasoning\nSuspected: $suspected · acuity: $acuity'
                    : 'Suspected: $suspected · acuity: $acuity',
                const Color(0xFFE36B8E), Icons.alt_route));
            break;
          case 'plan_published':
            _reach(2);
            final plan = e.data['plan'] as List? ?? [];
            _add(_TraceItem('Planner', 'Evidence plan published',
                '${plan.length} tool steps queued',
                const Color(0xFF8FB8D6), Icons.list_alt));
            break;
          case 'saved_evidence':
            _reach(3);
            final count = e.data['count'] ?? 0;
            final mods = (e.data['modalities'] as List?)?.join(', ') ?? '';
            _add(_TraceItem(
                'Evidence',
                'Loaded $count saved screening${count == 1 ? '' : 's'}',
                mods.isNotEmpty ? 'From your records: $mods' : 'From your records',
                const Color(0xFF7EA68C), Icons.folder_shared_outlined));
            break;
          case 'tool_call':
            _reach(3);
            _add(_TraceItem('Diagnosis Agent', 'Calling ${e.data['tool']}',
                'for ${e.data['disease']}', const Color(0xFF7EA68C),
                Icons.biotech_outlined));
            break;
          case 'tool_result':
            _reach(3);
            final status = e.data['status']?.toString() ?? '';
            final risk = e.data['risk']?.toString();
            final conf = e.data['confidence'];
            if (status == 'skipped_no_data' || status == 'unavailable') {
              _add(_TraceItem(
                  'Diagnosis Agent',
                  '${e.data['tool']} → not assessed',
                  'No data provided for this modality',
                  const Color(0xFF9AA4B2), Icons.remove_circle_outline));
            } else if (status == 'error') {
              _add(_TraceItem(
                  'Diagnosis Agent',
                  '${e.data['tool']} → unavailable',
                  'tool error, not counted',
                  const Color(0xFF9AA4B2), Icons.error_outline));
            } else {
              _add(_TraceItem(
                  'Diagnosis Agent',
                  '${e.data['tool']} → ${risk ?? status}',
                  conf != null ? 'confidence ${conf.toString()}' : status,
                  _riskColor(risk), Icons.check_circle_outline,
                  verdict: risk));
            }
            break;
          case 'diagnostic_result':
            _reach(4);
            final overall = e.data['overall_risk']?.toString();
            _dataBasis = e.data['data_basis']?.toString() ?? '';
            final conflicts = (e.data['conflicts'] as List?) ?? [];
            final notAssessed = overall == 'not_assessed';
            _add(_TraceItem(
                'Concordance Agent',
                notAssessed ? 'Not assessed' : 'Evidence fused → overall $overall',
                notAssessed
                    ? _basisLabel(_dataBasis)
                    : (conflicts.isEmpty
                        ? _basisLabel(_dataBasis)
                        : 'contradiction: ${conflicts.join(', ')}'),
                notAssessed ? const Color(0xFF9AA4B2) : const Color(0xFFE8B46B),
                Icons.hub_outlined,
                verdict: notAssessed ? null : overall));
            break;
          case 'plan_replan':
            _add(_TraceItem('Planner', 'Re-planning',
                '${e.data['reason']} → ${e.data['action']}',
                const Color(0xFF8FB8D6), Icons.refresh));
            break;
          case 'guardrail_verdict':
            _reach(5);
            final ac = e.data['actionClass']?.toString() ?? '';
            final reasons = (e.data['reasons'] as List?)?.join('; ') ?? '';
            _verdict = ac;
            _add(_TraceItem('Aegis Gate', 'Verdict: $ac',
                reasons.isEmpty ? 'no red flags' : reasons,
                _riskColor(ac), Icons.shield_outlined, verdict: ac));
            break;
          case 'consult_complete':
            _reach(5);
            setState(() {
              _running = false;
              _done = true;
            });
            break;
          case 'consult_error':
            setState(() {
              _running = false;
              _error = e.data['error']?.toString() ?? 'Consult error';
            });
            break;
        }
      }
    } catch (err) {
      setState(() {
        _running = false;
        _error = err.toString();
      });
    }
    if (mounted && _running) setState(() => _running = false);
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
            if (_trace.isNotEmpty || _running) _pipeline(isDark),
            if (_error != null) _errorBar(_error!, isDark),
            Expanded(
              child: (_trace.isEmpty && !_running)
                  ? _idle(isDark)
                  : _traceList(isDark),
            ),
            if (_done) _verdictReveal(isDark),
          ],
        ),
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────
  Widget _hero(bool isDark) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7C5CE6), Color(0xFF4A2FB0)],
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 18),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                AegisShield(
                    size: 46,
                    color: Colors.white,
                    pulsing: _running,
                    icon: Icons.shield_moon_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Text('Live Agent Consult',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .22),
                              borderRadius: BorderRadius.circular(999)),
                          child: const Text('AEGIS',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: Colors.white)),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      _running
                          ? Row(children: [
                              _blinkDot(),
                              const SizedBox(width: 6),
                              Text('Agent working…',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Colors.white.withValues(alpha: .9))),
                            ])
                          : Text('The agent proposes, the gate disposes',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: .85))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _blinkDot() => Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            color: Color(0xFFB8FFE6), shape: BoxShape.circle),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .fadeIn(duration: 600.ms)
          .then()
          .fadeOut(duration: 600.ms);

  // ── Pipeline tracker ────────────────────────────────────────────────────
  Widget _pipeline(bool isDark) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
        child: Row(
          children: [
            for (int i = 0; i < _kStages.length; i++) ...[
              _stageNode(i, isDark),
              if (i < _kStages.length - 1) _stageConnector(i),
            ],
          ],
        ),
      );

  Widget _stageNode(int i, bool isDark) {
    final done = _stage > i + 1 || (_stage == i + 1 && _done);
    final active = _running && _stage == i + 1;
    final reached = _stage >= i + 1;
    final c = reached ? _kAegis : (isDark ? Colors.white24 : Colors.black26);
    Widget dot = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reached ? _kAegis : Colors.transparent,
        border: Border.all(color: c, width: 2),
      ),
      child: done
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : (active
              ? const Padding(
                  padding: EdgeInsets.all(4),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : null),
    );
    if (active) {
      dot = dot
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1.0, end: 1.18, duration: 700.ms);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(height: 4),
        Text(_kStages[i],
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
                color: reached
                    ? _kAegis
                    : (isDark ? AppTheme.darkTextGray : AppTheme.textGray))),
      ],
    );
  }

  Widget _stageConnector(int i) => Expanded(
        child: Container(
          height: 2.5,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: _stage > i + 1 ? _kAegis : const Color(0x33808080),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  // ── Idle state ────────────────────────────────────────────────────────────
  Widget _idle(bool isDark) => ListView(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        children: [
          const SizedBox(height: 8),
          Center(
              child: AegisShield(
                  size: 96, color: _kAegis, icon: Icons.shield_moon_rounded)),
          const SizedBox(height: 14),
          Center(
            child: Text('Governed autonomy',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'An AI agent reasons over your real data step by step, then a deterministic safety gate decides. Every action is logged to a tamper-evident ledger.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: (isDark ? AppTheme.darkTextLight : AppTheme.textGray)
                        .withValues(alpha: .9)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _kStages) _miniStageChip(s, isDark),
            ],
          ),
          const SizedBox(height: 22),
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.spacingLarge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How are you feeling?',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
                const SizedBox(height: 10),
                TextField(
                  controller: _complaintCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText:
                        'e.g. tired and breathless, occasional chest tightness',
                    filled: true,
                    fillColor: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: .04),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in const [
                      'Tired and breathless',
                      'Frequent headaches',
                      'Dizzy and weak',
                    ])
                      ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 11.5)),
                        onPressed: () {
                          _complaintCtrl.text = s;
                          _start();
                        },
                        backgroundColor: _kAegis.withValues(alpha: .10),
                        side: BorderSide(color: _kAegis.withValues(alpha: .3)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Run autonomous consult'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAegis,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0),
        ],
      );

  Widget _miniStageChip(String s, bool isDark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _kAegis.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kAegis.withValues(alpha: .25)),
        ),
        child: Text(s,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: _kAegis)),
      );

  Widget _errorBar(String msg, bool isDark) => Container(
        margin: const EdgeInsets.fromLTRB(
            AppTheme.spacingLarge, 10, AppTheme.spacingLarge, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE26D6D).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Color(0xFFE26D6D), size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFFC0392B)))),
        ]),
      );

  // ── Timeline ────────────────────────────────────────────────────────────
  Widget _traceList(bool isDark) => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        itemCount: _trace.length,
        itemBuilder: (context, i) {
          final t = _trace[i];
          final last = i == _trace.length - 1;
          Widget node = Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: t.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: t.color.withValues(alpha: .35),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Icon(t.icon, color: Colors.white, size: 19),
          );
          if (last && _running) {
            node = node
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(begin: 1.0, end: 1.12, duration: 700.ms);
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    node,
                    if (!last)
                      Expanded(
                          child: Container(
                              width: 2,
                              color: t.color.withValues(alpha: .25))
                          .animate()
                          .scaleY(
                              begin: 0, end: 1, duration: 300.ms,
                              alignment: Alignment.topCenter)),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: t.color.withValues(alpha: .18), width: 1),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: .04),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: t.color.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(t.agent,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.color)),
                          ),
                          if (t.verdict != null) ...[
                            const Spacer(),
                            Text(t.verdict!.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: t.color)),
                          ],
                        ]),
                        const SizedBox(height: 8),
                        Text(t.title,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppTheme.darkTextLight
                                    : AppTheme.textDark)),
                        if (t.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(t.subtitle,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: (isDark
                                          ? AppTheme.darkTextLight
                                          : AppTheme.textGray)
                                      .withValues(alpha: .85))),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 350.ms).slideX(begin: 0.06, end: 0);
        },
      );

  // ── Verdict reveal (honesty-aware) ────────────────────────────────────────
  Widget _verdictReveal(bool isDark) {
    final insufficient = _dataBasis == 'insufficient';
    final symptomOnly = _dataBasis == 'symptom_only';
    final measured = !insufficient && !symptomOnly;

    late Color c;
    late String title;
    late String msg;
    late IconData icon;
    if (insufficient) {
      c = const Color(0xFF8FB8D6);
      title = 'Insufficient data';
      msg = _basisLabel('insufficient');
      icon = Icons.info_outline;
    } else if (symptomOnly) {
      c = const Color(0xFF6C9BC0);
      title = 'Preliminary · symptom-only';
      msg = _basisLabel('symptom_only');
      icon = Icons.science_outlined;
    } else {
      c = _riskColor(_verdict);
      final v = _verdict.toUpperCase();
      title = 'Aegis verdict · ${v.isEmpty ? 'DONE' : v}';
      msg = v == 'RED'
          ? 'Action BLOCKED, escalated to a clinician for review.'
          : v == 'AMBER'
              ? 'Executed with oversight, doctor notified.'
              : 'Cleared, safe to proceed autonomously.';
      icon = v == 'RED'
          ? Icons.gpp_maybe_rounded
          : v == 'AMBER'
              ? Icons.shield_rounded
              : Icons.verified_user_rounded;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppTheme.spacingLarge),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [c, Color.lerp(c, Colors.black, 0.22)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: c.withValues(alpha: .45),
              blurRadius: 22,
              offset: const Offset(0, 8))
        ],
      ),
      child: Row(children: [
        AegisShield(size: 54, color: Colors.white, pulsing: false, icon: icon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 3),
              Text(msg,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: .95))),
              if (!measured) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .22),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('NOT A DIAGNOSIS',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                          color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ]),
    )
        .animate()
        .fadeIn(duration: 450.ms)
        .scaleXY(begin: 0.9, end: 1.0, curve: Curves.easeOutBack)
        .shimmer(delay: 300.ms, duration: 1100.ms, color: Colors.white24);
  }
}
