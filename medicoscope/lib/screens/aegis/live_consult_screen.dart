import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/services/consult_service.dart';
import 'package:medicoscope/services/location_service.dart';

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
  final String agent; // named agent for this step
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  String? verdict; // GREEN/AMBER/RED for the gate step
  _TraceItem(this.agent, this.title, this.subtitle, this.color, this.icon,
      {this.verdict});
}

class _LiveConsultScreenState extends State<LiveConsultScreen> {
  final _complaintCtrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_TraceItem> _trace = [];
  bool _running = false;
  bool _done = false;
  String? _error;
  String _verdict = '';
  String _dataBasis = ''; // measured | symptom_only | insufficient

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
        return 'Based on your real screening data';
      case 'symptom_only':
        return 'Symptom-based triage only, not a diagnosis. Run a screening (lab, photo or vitals) for a real assessment.';
      case 'insufficient':
        return 'No screening data yet, not a diagnosis. Run a screening to get a real assessment.';
      default:
        return 'modalities agree';
    }
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
      _trace.clear();
    });

    // Attach the patient's live location so a gate-raised alert reaches the
    // doctor with a map link. Best-effort; the consult runs regardless.
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
            final plan = e.data['plan'] as List? ?? [];
            _add(_TraceItem('Planner', 'Evidence plan published',
                '${plan.length} tool steps queued',
                const Color(0xFF8FB8D6), Icons.list_alt));
            break;
          case 'saved_evidence':
            final count = e.data['count'] ?? 0;
            final mods = (e.data['modalities'] as List?)?.join(', ') ?? '';
            _add(_TraceItem(
                'Evidence',
                'Loaded $count saved screening${count == 1 ? '' : 's'}',
                mods.isNotEmpty ? 'From your records: $mods' : 'From your records',
                const Color(0xFF7EA68C), Icons.folder_shared_outlined));
            break;
          case 'tool_call':
            _add(_TraceItem('Diagnosis Agent', 'Calling ${e.data['tool']}',
                'for ${e.data['disease']}', const Color(0xFF7EA68C),
                Icons.biotech_outlined));
            break;
          case 'tool_result':
            final status = e.data['status']?.toString() ?? '';
            final risk = e.data['risk']?.toString();
            final conf = e.data['confidence'];
            if (status == 'skipped_no_data' || status == 'unavailable') {
              // Honest: no data for this modality, so it is NOT counted.
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
            final ac = e.data['actionClass']?.toString() ?? '';
            final reasons = (e.data['reasons'] as List?)?.join('; ') ?? '';
            _verdict = ac;
            _add(_TraceItem('Aegis Gate', 'Verdict: $ac',
                reasons.isEmpty ? 'no red flags' : reasons,
                _riskColor(ac), Icons.shield_outlined, verdict: ac));
            break;
          case 'consult_complete':
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
        child: SafeArea(
          child: Column(
            children: [
              _header(isDark),
              if (!_running && _trace.isEmpty) _inputArea(isDark),
              if (_error != null) _errorBar(_error!, isDark),
              Expanded(child: _traceList(isDark)),
              if (_done && _dataBasis.isNotEmpty && _dataBasis != 'measured')
                _basisBanner(isDark),
              if (_done) _verdictBar(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool isDark) => Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Row(
          children: [
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
                    Text('Live Agent Consult',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.textDark)),
                    const SizedBox(width: 8),
                    _aegisChip(),
                  ]),
                  Text('Autonomous reasoning · streamed live',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: (isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textGray)
                              .withValues(alpha: .8))),
                ],
              ),
            ),
            if (_running)
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4)),
          ],
        ),
      );

  Widget _aegisChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          gradient: AppTheme.orangeGradient,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text('AEGIS',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Colors.white)),
      );

  Widget _inputArea(bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLarge),
        child: GlassCard(
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How are you feeling?',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.darkTextLight
                          : AppTheme.textDark)),
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
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Run autonomous consult'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorBar(String msg, bool isDark) => Container(
        margin: const EdgeInsets.fromLTRB(AppTheme.spacingLarge, 8,
            AppTheme.spacingLarge, 0),
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

  Widget _traceList(bool isDark) => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        itemCount: _trace.length,
        itemBuilder: (context, i) {
          final t = _trace[i];
          final last = i == _trace.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // timeline rail
                Column(
                  children: [
                    Container(
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
                    ),
                    if (!last)
                      Expanded(
                          child: Container(
                              width: 2,
                              color: t.color.withValues(alpha: .25))),
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

  Widget _basisBanner(bool isDark) {
    final insufficient = _dataBasis == 'insufficient';
    final c = const Color(0xFF8FB8D6);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
          AppTheme.spacingLarge, 0, AppTheme.spacingLarge, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: .35)),
      ),
      child: Row(children: [
        Icon(insufficient ? Icons.info_outline : Icons.science_outlined,
            color: c, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _basisLabel(_dataBasis),
            style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark),
          ),
        ),
      ]),
    );
  }

  Widget _verdictBar(bool isDark) {
    final c = _riskColor(_verdict);
    final msg = _verdict.toUpperCase() == 'RED'
        ? 'Action BLOCKED - escalated to a clinician for review.'
        : _verdict.toUpperCase() == 'AMBER'
            ? 'Executed with oversight - doctor notified.'
            : 'Cleared - safe to proceed autonomously.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppTheme.spacingLarge),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [c, c.withValues(alpha: .82)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: c.withValues(alpha: .35),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(children: [
        const Icon(Icons.verified_user, color: Colors.white, size: 26),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aegis verdict · ${_verdict.toUpperCase()}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 2),
              Text(msg,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: .92))),
            ],
          ),
        ),
      ]),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0);
  }
}
