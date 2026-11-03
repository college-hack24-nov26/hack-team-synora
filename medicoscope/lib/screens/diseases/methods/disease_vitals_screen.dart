import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/screens/diseases/methods/_method_scaffold.dart';
import 'package:medicoscope/screens/diseases/widgets/risk_result_view.dart';
import 'package:medicoscope/services/chat_service.dart';
import 'package:medicoscope/services/disease_result_pipeline.dart';
import 'package:medicoscope/services/health_connect_service.dart';
import 'package:medicoscope/services/vitals_analyzer.dart';

enum _VSource { unknown, live, simulated }

class DiseaseVitalsScreen extends StatefulWidget {
  final DiseaseType disease;
  final String? patientId;
  const DiseaseVitalsScreen(
      {super.key, required this.disease, this.patientId});

  @override
  State<DiseaseVitalsScreen> createState() => _DiseaseVitalsScreenState();
}

class _DiseaseVitalsScreenState extends State<DiseaseVitalsScreen> {
  _VSource _source = _VSource.unknown;
  bool _busy = false;
  bool _refreshing = false;
  WearableSnapshot? _snapshot;
  DiseaseRiskResult? _result;
  String? _status;
  Timer? _autoPollTimer;
  DateTime? _lastRefreshedAt;

  /// Per-metric rolling history (last 20 samples) used to draw sparklines.
  final List<double> _hrHistory = [];
  final List<double> _restingHrHistory = [];
  final List<double> _spo2History = [];
  final List<double> _sysHistory = [];
  final List<double> _diaHistory = [];

  @override
  void initState() {
    super.initState();
    // Don't auto-start — let the user pick Live or Simulation explicitly.
    // Auto-poll still runs every 30 s but only after the user has chosen Live.
    _autoPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_source == _VSource.live) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _autoPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _tryLive() async {
    setState(() {
      _busy = true;
      _status = 'Checking Health Connect…';
    });
    final availability = await HealthConnectService.getAvailability();
    if (availability != HCAvailability.available) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = availability == HCAvailability.notInstalled
            ? 'Health Connect is not installed. Install it from the Play Store to use your smartwatch data.'
            : 'This platform does not support Health Connect directly.';
      });
      return;
    }
    final hasPerms = await HealthConnectService.hasPermissions();
    if (!hasPerms) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Grant wearable permissions to stream live data.';
      });
      return;
    }
    await _readLive();
  }

  Future<void> _requestAndRead() async {
    setState(() => _busy = true);
    final granted = await HealthConnectService.requestPermissions();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Permission denied. You can still try simulation.';
      });
      return;
    }
    await _readLive();
  }

  Future<void> _readLive({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _status = 'Reading your wearable…';
      });
    }
    final snapshot = await HealthConnectService.getSnapshot();
    if (!mounted) return;

    if (!snapshot.hasClinicalData) {
      setState(() {
        _busy = false;
        _status =
            'No recent vitals found on your device. Try wearing your watch for a few minutes, then tap Refresh — or use simulation.';
      });
      return;
    }

    _pushHistory(snapshot);
    setState(() {
      _snapshot = snapshot;
      _source = _VSource.live;
      _lastRefreshedAt = DateTime.now();
    });
    await _analyze(snapshot, isSimulated: false, silent: silent);
  }

  /// User-triggered refresh — re-reads the watch and re-runs detection.
  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _refreshing = true);
    try {
      if (_source == _VSource.simulated) {
        await _runSimulation(silent: silent);
      } else {
        await _readLive(silent: silent);
      }
    } finally {
      if (!silent && mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _runSimulation({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _status = 'Running MedicoScope simulation…';
      });
    }
    final rng = math.Random();
    double gauss(double mean, double sd) =>
        mean + sd * (rng.nextDouble() * 2 - 1);
    final sim = WearableSnapshot(
      steps: (gauss(6500, 2500)).clamp(1000, 15000).toInt(),
      avgHeartRate: gauss(78, 8).clamp(55, 130),
      restingHeartRate: gauss(72, 8).clamp(48, 110),
      spO2: gauss(97, 1.5).clamp(88, 100),
      systolic: gauss(128, 14).clamp(95, 180),
      diastolic: gauss(82, 9).clamp(60, 110),
      hrvRmssd: gauss(35, 12).clamp(10, 75),
      capturedAt: DateTime.now(),
    );
    _pushHistory(sim);
    if (!mounted) return;
    setState(() {
      _snapshot = sim;
      _source = _VSource.simulated;
      _lastRefreshedAt = DateTime.now();
    });
    await _analyze(sim, isSimulated: true, silent: silent);
  }

  void _pushHistory(WearableSnapshot s) {
    void push(List<double> list, double? v) {
      if (v == null || v == 0) return;
      list.add(v);
      if (list.length > 20) list.removeAt(0);
    }

    push(_hrHistory, s.avgHeartRate);
    push(_restingHrHistory, s.restingHeartRate);
    push(_spo2History, s.spO2);
    push(_sysHistory, s.systolic);
    push(_diaHistory, s.diastolic);
  }

  Future<void> _analyze(
    WearableSnapshot snap, {
    required bool isSimulated,
    bool silent = false,
  }) async {
    final base = VitalsAnalyzer.analyze(
      disease: widget.disease,
      snapshot: snap,
      isSimulated: isSimulated,
    );
    if (!mounted) return;
    setState(() {
      _result = base;
      _busy = false;
      _status = silent ? null : 'Generating explanation…';
    });

    final lang = Provider.of<LocaleProvider>(context, listen: false)
        .languageCode;
    final explanation = await ChatService.explainRisk(
      disease: DiseaseRegistry.of(widget.disease).title,
      method: isSimulated ? 'simulated vitals' : 'smartwatch vitals',
      riskLevel: base.risk.label,
      headline: base.headline,
      findings: base.findings
          .map((f) =>
              '${f.name} ${f.value} ${f.unit} (${f.flag}) — ${f.interpretation}')
          .toList(),
      language: lang,
    );

    final enriched = DiseaseRiskResult(
      disease: base.disease,
      method: base.method,
      risk: base.risk,
      score: base.score,
      headline: base.headline,
      findings: base.findings,
      topContributors: base.topContributors,
      recommendations: base.recommendations,
      dataSource: base.dataSource,
      timestamp: base.timestamp,
      llmExplanation: explanation,
    );
    if (!mounted) return;
    setState(() {
      _result = enriched;
      _busy = false;
      _status = null;
    });
    if (mounted) await DiseaseResultPipeline.persist(context, enriched);
  }

  @override
  Widget build(BuildContext context) {
    final m = MethodRegistry.of(DetectionMethod.vitalsWearable);
    final d = DiseaseRegistry.of(widget.disease);
    return MethodScaffold(
      title: '${d.title} • ${m.title}',
      subtitle: m.subtitle,
      icon: m.icon,
      gradient: m.gradient,
      disease: widget.disease,
      bodyIsScrollable: true,
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        color: d.gradient.first,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          children: [_body(context, d)],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DiseaseMeta d) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sourceBadge(isDark),
        const SizedBox(height: AppTheme.spacingMedium),
        if (_snapshot != null) _liveMetricGrid(isDark, d.gradient.first),
        if (_snapshot != null && _hasHistory())
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingMedium),
            child: _trendCard(isDark, d.gradient.first),
          ),
        if (_snapshot != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingMedium),
            child: _refreshBar(isDark, d.gradient.first),
          ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingMedium),
            child: _statusCard(isDark, d.gradient.first),
          ),
        if (_result == null && !_busy && _snapshot == null)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingMedium),
            child: _actionRow(d),
          ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingMedium),
            child: RiskResultView(
              result: _result!,
              onRetry: () {
                setState(() {
                  _result = null;
                  _snapshot = null;
                  _source = _VSource.unknown;
                  _status = null;
                  _hrHistory.clear();
                  _restingHrHistory.clear();
                  _spo2History.clear();
                  _sysHistory.clear();
                  _diaHistory.clear();
                });
                _tryLive();
              },
            ),
          ),
      ],
    );
  }

  bool _hasHistory() =>
      _hrHistory.length + _spo2History.length + _sysHistory.length > 2;

  Widget _sourceBadge(bool isDark) {
    Color color;
    String text;
    IconData icon;
    switch (_source) {
      case _VSource.live:
        color = const Color(0xFF4CAF50);
        text = 'LIVE from your wearable';
        icon = Icons.watch_rounded;
        break;
      case _VSource.simulated:
        color = const Color(0xFFFFA000);
        text = 'SIMULATION MODE';
        icon = Icons.science_outlined;
        break;
      default:
        color = Colors.grey;
        text = 'Waiting for source…';
        icon = Icons.hourglass_bottom_rounded;
    }
    final subtitle = _lastRefreshedAt == null
        ? null
        : 'Updated ${_formatAgo(_lastRefreshedAt!)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.22), color.withOpacity(0.10)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: color.withOpacity(0.85),
                    ),
                  ),
              ],
            ),
          ),
          if (_source == _VSource.live)
            _BlinkingDot(color: color)
                .animate(onPlay: (c) => c.repeat())
                .fadeIn(duration: 800.ms)
                .then()
                .fadeOut(duration: 800.ms),
        ],
      ),
    );
  }

  Widget _statusCard(bool isDark, Color accent) {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Row(
        children: [
          if (_busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            )
          else
            Icon(Icons.info_outline, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveMetricGrid(bool isDark, Color accent) {
    final s = _snapshot!;
    final tiles = <Widget>[];

    void add(String label, String value, IconData icon, {Color? tint}) {
      tiles.add(_MetricTile(
        label: label,
        value: value,
        icon: icon,
        accent: tint ?? accent,
        isDark: isDark,
      ));
    }

    if (s.restingHeartRate != null) {
      add('Resting HR', '${s.restingHeartRate!.toStringAsFixed(0)} bpm',
          Icons.favorite_outline,
          tint: const Color(0xFFFF5252));
    }
    if (s.avgHeartRate > 0) {
      add('Avg HR', '${s.avgHeartRate.toStringAsFixed(0)} bpm', Icons.timeline);
    }
    if (s.spO2 != null) {
      add('SpO₂', '${s.spO2!.toStringAsFixed(0)} %', Icons.bubble_chart,
          tint: const Color(0xFF4FC3F7));
    }
    if (s.systolic != null && s.diastolic != null) {
      add('BP',
          '${s.systolic!.toStringAsFixed(0)}/${s.diastolic!.toStringAsFixed(0)}',
          Icons.water_drop_outlined,
          tint: const Color(0xFF7C4DFF));
    }
    if (s.hrvRmssd != null) {
      add('HRV', '${s.hrvRmssd!.toStringAsFixed(0)} ms', Icons.graphic_eq,
          tint: const Color(0xFF66BB6A));
    }
    add('Steps', '${s.steps}', Icons.directions_walk_outlined,
        tint: const Color(0xFFFFA726));

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.7,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: tiles
          .asMap()
          .entries
          .map((e) => e.value
              .animate()
              .fadeIn(delay: (60 * e.key).ms, duration: 300.ms)
              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut))
          .toList(),
    );
  }

  Widget _trendCard(bool isDark, Color accent) {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, color: accent, size: 18),
              const SizedBox(width: 6),
              Text(
                'Live trend',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppTheme.darkTextLight
                      : AppTheme.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '${_hrHistory.length + _sysHistory.length + _spo2History.length} samples',
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_hrHistory.isNotEmpty)
            _sparkRow('Heart rate', _hrHistory, const Color(0xFFFF5252),
                suffix: ' bpm', isDark: isDark),
          if (_sysHistory.isNotEmpty) ...[
            const SizedBox(height: 6),
            _sparkRow('Systolic BP', _sysHistory, const Color(0xFF7C4DFF),
                suffix: ' mmHg', isDark: isDark),
          ],
          if (_diaHistory.isNotEmpty) ...[
            const SizedBox(height: 6),
            _sparkRow('Diastolic BP', _diaHistory, const Color(0xFF5C6BC0),
                suffix: ' mmHg', isDark: isDark),
          ],
          if (_spo2History.isNotEmpty) ...[
            const SizedBox(height: 6),
            _sparkRow('SpO₂', _spo2History, const Color(0xFF4FC3F7),
                suffix: ' %', isDark: isDark),
          ],
        ],
      ),
    );
  }

  Widget _sparkRow(
    String label,
    List<double> data,
    Color color, {
    required String suffix,
    required bool isDark,
  }) {
    final last = data.last;
    final prev = data.length > 1 ? data[data.length - 2] : last;
    final delta = last - prev;
    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 32,
            child: CustomPaint(
              painter: _SparklinePainter(data: data, color: color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${last.toStringAsFixed(0)}$suffix',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          delta > 0.01
              ? Icons.arrow_upward_rounded
              : delta < -0.01
                  ? Icons.arrow_downward_rounded
                  : Icons.remove_rounded,
          size: 12,
          color: delta.abs() < 0.01
              ? (isDark ? AppTheme.darkTextGray : AppTheme.textGray)
              : (delta > 0 ? const Color(0xFFFF5252) : const Color(0xFF4CAF50)),
        ),
      ],
    );
  }

  Widget _refreshBar(bool isDark, Color accent) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _refreshing || _busy ? null : () => _refresh(),
            icon: _refreshing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(_refreshing
                ? 'Refreshing…'
                : 'Refresh & re-detect'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Use simulation',
          onPressed: _busy ? null : () => _runSimulation(),
          icon: const Icon(Icons.science_outlined),
        ),
      ],
    );
  }

  Widget _actionRow(DiseaseMeta d) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pick a data source',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 10),
        _sourceCard(
          gradient: const [Color(0xFF11998E), Color(0xFF38EF7D)],
          icon: Icons.watch_rounded,
          title: 'Live Smart Device',
          subtitle:
              'Read real data from your smartwatch via Health Connect / HealthKit',
          badge: 'RECOMMENDED',
          onTap: _busy ? null : _requestAndRead,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        _sourceCard(
          gradient: [
            const Color(0xFFFFA751),
            const Color(0xFFFFE259),
          ],
          icon: Icons.science_outlined,
          title: 'Simulation Mode',
          subtitle: 'No watch? Generate a realistic synthetic snapshot',
          badge: 'DEMO',
          onTap: _busy ? null : () => _runSimulation(),
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _sourceCard({
    required List<Color> gradient,
    required IconData icon,
    required String title,
    required String subtitle,
    required String badge,
    required VoidCallback? onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withOpacity(0.92),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  String _formatAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool isDark;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.13),
            accent.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppTheme.darkTextGray
                      : AppTheme.textGray,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatelessWidget {
  final Color color;
  const _BlinkingDot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.6), blurRadius: 6),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.35), color.withOpacity(0.01)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV).abs() < 0.01 ? 1.0 : (maxV - minV);

    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i * size.width / (data.length - 1);
      final y = size.height - ((data[i] - minV) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.data != data || old.color != color;
}
