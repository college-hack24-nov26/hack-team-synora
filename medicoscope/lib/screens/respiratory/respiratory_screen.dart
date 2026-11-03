import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/screens/diseases/widgets/risk_result_view.dart';
import 'package:medicoscope/services/chat_service.dart';
import 'package:medicoscope/services/disease_result_pipeline.dart';
import 'package:medicoscope/services/respiratory_analyzer.dart';
import 'package:medicoscope/services/respiratory_calibration_store.dart';
import 'package:medicoscope/services/respiratory_signal.dart';

/// Respiratory acoustic screening. Records breathing, extracts REAL features
/// (envelope-FFT breathing rate, STFT wheeze/crackle, I:E ratio), optionally
/// judged against a personal resting-breathing calibration, and persists an
/// honest [DiseaseRiskResult] (history + doctor alert like the other modalities).
class RespiratoryScreen extends StatefulWidget {
  final String? patientId;
  const RespiratoryScreen({super.key, this.patientId});

  @override
  State<RespiratoryScreen> createState() => _RespiratoryScreenState();
}

class _RespiratoryScreenState extends State<RespiratoryScreen>
    with TickerProviderStateMixin {
  static const int _captureSeconds = 18;

  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isProcessing = false;
  bool _calibrating = false;
  int _secondsElapsed = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  String? _path;

  final List<double> _levels = []; // rolling mic level for the live waveform
  double _level = 0;

  DiseaseRiskResult? _result;
  RespiratoryFeatures? _features; // for the spectrogram / envelope viz
  String? _error;
  RespiratoryCalibration? _calibration;

  late final AnimationController _pace = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  String _paceLabel = 'Inhale';

  @override
  void initState() {
    super.initState();
    _pace.addStatusListener((s) {
      if (s == AnimationStatus.forward) setState(() => _paceLabel = 'Inhale');
      if (s == AnimationStatus.reverse) setState(() => _paceLabel = 'Exhale');
    });
    _loadCalibration();
  }

  Future<void> _loadCalibration() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final c = await RespiratoryCalibrationStore.load(auth.user?.id ?? '');
    if (mounted) setState(() => _calibration = c);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _pace.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start({bool forCalibration = false}) async {
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Microphone permission is needed to record.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/respiratory_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, numChannels: 1),
      path: path,
    );
    setState(() {
      _calibrating = forCalibration;
      _isRecording = true;
      _secondsElapsed = 0;
      _path = path;
      _result = null;
      _features = null;
      _error = null;
      _levels.clear();
    });
    _pace.repeat(reverse: true);
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amp) {
      // dBFS (~ -45..0) -> 0..1 level for the meter + waveform.
      final lvl = ((amp.current + 45) / 45).clamp(0.0, 1.0);
      setState(() {
        _level = lvl;
        _levels.add(lvl);
        if (_levels.length > 60) _levels.removeAt(0);
      });
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _secondsElapsed++);
      if (_secondsElapsed >= _captureSeconds) _stop();
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    _pace.stop();
    _pace.reset();
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _path = path ?? _path;
    });
    await _finish();
  }

  Future<void> _finish() async {
    if (_path == null) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final feats = await RespiratorySignal.analyzeWavFile(_path!);

      // Calibration capture: store the resting baseline, no scoring.
      if (_calibrating) {
        if (!mounted) return;
        if (!feats.usable) {
          setState(() {
            _isProcessing = false;
            _calibrating = false;
            _error = 'Calibration needs a clean recording. ${feats.reason}';
          });
          return;
        }
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final calib = RespiratoryCalibration(
          restingBpm: feats.breathingRate,
          refFeatures: feats.toVector(),
          timestamp: DateTime.now(),
        );
        await RespiratoryCalibrationStore.save(auth.user?.id ?? '', calib);
        if (!mounted) return;
        setState(() {
          _calibration = calib;
          _calibrating = false;
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Calibrated: resting ${feats.breathingRate.toStringAsFixed(0)} breaths/min saved.')));
        return;
      }

      final base = RespiratoryAnalyzer.analyze(
          features: feats, calibration: _calibration);
      if (!mounted) return;
      if (base.findings.isEmpty) {
        setState(() {
          _isProcessing = false;
          _error = base.headline;
        });
        return;
      }
      setState(() {
        _features = feats;
        _result = base;
      });

      // LLM narrative + persist to history + doctor alert (with GPS) + coins.
      final lang =
          Provider.of<LocaleProvider>(context, listen: false).languageCode;
      final explanation = await ChatService.explainRisk(
        disease: 'Respiratory',
        method: 'respiratory acoustic screening',
        riskLevel: base.risk.label,
        headline: base.headline,
        findings: base.findings
            .map((f) =>
                '${f.name} ${f.value} ${f.unit} (${f.flag}) - ${f.interpretation}')
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
        _isProcessing = false;
      });
      await DiseaseResultPipeline.persist(context, enriched);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = 'Could not analyze the recording. Please try again.';
      });
    }
  }

  void _reset() => setState(() {
        _result = null;
        _features = null;
        _error = null;
        _levels.clear();
      });

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
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingLarge),
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacingMedium),
                      if (_result != null && !_isProcessing) ...[
                        RiskResultView(result: _result!, onRetry: _reset),
                        if (_features != null) ...[
                          const SizedBox(height: AppTheme.spacingMedium),
                          _spectrogramCard(_features!, isDark),
                        ],
                      ] else ...[
                        _captureCard(isDark),
                        if (!_isRecording && !_isProcessing) ...[
                          const SizedBox(height: AppTheme.spacingMedium),
                          _calibrationCard(isDark),
                        ],
                        if (_isProcessing) ...[
                          const SizedBox(height: AppTheme.spacingLarge),
                          _processing(isDark),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: AppTheme.spacingLarge),
                          _errorCard(_error!, isDark),
                        ],
                      ],
                      const SizedBox(height: AppTheme.spacingXLarge),
                    ],
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
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_ios_new,
                  color: isDark ? AppTheme.darkTextLight : AppTheme.textDark),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Respiratory Check',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextLight
                              : AppTheme.textDark)),
                  Text('Acoustic breathing screening',
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              (isDark ? AppTheme.darkTextLight : AppTheme.textGray)
                                  .withValues(alpha: 0.75))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF43C6AC), Color(0xFF191654)]),
                borderRadius:
                    BorderRadius.all(Radius.circular(AppTheme.radiusMedium)),
              ),
              child: const Icon(Icons.air, color: Colors.white),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms);

  Widget _captureCard(bool isDark) {
    const accent = Color(0xFF43C6AC);
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingLarge),
      child: Column(
        children: [
          Text(
            _isRecording
                ? (_calibrating
                    ? 'Calibration: breathe calmly and normally'
                    : 'Breathe steadily near the mic')
                : 'Sit upright, hold the phone ~10 cm from your mouth, and breathe steadily for the full capture.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          if (_isRecording) ...[
            // Breathing pacing guide.
            AnimatedBuilder(
              animation: _pace,
              builder: (_, __) {
                final scale = 0.7 + _pace.value * 0.5;
                return Column(children: [
                  Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                            colors: [Color(0xFF43C6AC), Color(0xFF191654)]),
                        boxShadow: [
                          BoxShadow(
                              color: accent.withValues(alpha: .45),
                              blurRadius: 24,
                              spreadRadius: 4),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(_paceLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  ),
                ]);
              },
            ),
            const SizedBox(height: AppTheme.spacingLarge),
            // Live waveform + level meter.
            SizedBox(
              height: 46,
              width: double.infinity,
              child: CustomPaint(painter: _WavePainter(_levels, accent)),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _level,
                minHeight: 8,
                backgroundColor:
                    (isDark ? Colors.white : Colors.black).withValues(alpha: .08),
                valueColor: AlwaysStoppedAnimation<Color>(
                    _level > 0.15 ? const Color(0xFF2ECC71) : const Color(0xFFF0B45C)),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _level < 0.08
                  ? 'Too quiet - breathe a little louder / closer'
                  : 'Good level - keep breathing steadily',
              style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? AppTheme.darkTextGray : AppTheme.textGray),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            Text('00:${_secondsElapsed.toString().padLeft(2, '0')} / 00:$_captureSeconds',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: accent)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop now'),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: accent.withValues(alpha: .5))),
            ),
          ] else
            GestureDetector(
              onTap: _isProcessing ? null : () => _start(),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      colors: [Color(0xFF43C6AC), Color(0xFF191654)]),
                  boxShadow: [
                    BoxShadow(
                        color: accent.withValues(alpha: 0.30),
                        blurRadius: 18,
                        spreadRadius: 2),
                  ],
                ),
                child: const Icon(Icons.mic_rounded, color: Colors.white, size: 48),
              ),
            ),
          if (!_isRecording) ...[
            const SizedBox(height: AppTheme.spacingMedium),
            Text('Tap to record ($_captureSeconds s)',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textGray)),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0);
  }

  Widget _calibrationCard(bool isDark) {
    final calibrated = _calibration != null;
    const accent = Color(0xFF43C6AC);
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Row(
        children: [
          Icon(calibrated ? Icons.verified : Icons.tune,
              size: 18, color: calibrated ? const Color(0xFF2ECC71) : accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              calibrated
                  ? 'Personalized: resting ${_calibration!.restingBpm.toStringAsFixed(0)}/min, ${_calibration!.age.inDays} day(s) ago${_calibration!.isStale ? ' • re-calibrate' : ''}'
                  : 'Not calibrated - scans use a population cutoff. Calibrate your resting breathing once for accuracy.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  color: isDark ? AppTheme.darkTextLight : AppTheme.textDark),
            ),
          ),
          TextButton(
            onPressed: () => _start(forCalibration: true),
            child: Text(calibrated ? 'Redo' : 'Calibrate'),
          ),
        ],
      ),
    );
  }

  Widget _spectrogramCard(RespiratoryFeatures f, bool isDark) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Frequency spectrum (0-2 kHz)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
            const SizedBox(height: 4),
            Text('Sustained tall bars in 100-1000 Hz can indicate wheeze',
                style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? AppTheme.darkTextGray : AppTheme.textGray)),
            const SizedBox(height: 10),
            SizedBox(
              height: 70,
              width: double.infinity,
              child: CustomPaint(
                  painter: _SpectrumPainter(f.avgSpectrum, const Color(0xFF43C6AC))),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 350.ms);

  Widget _processing(bool isDark) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Row(
          children: [
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 14),
            Text(_calibrating ? 'Saving calibration…' : 'Analyzing breathing…',
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
          ],
        ),
      );

  Widget _errorCard(String msg, bool isDark) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms);
}

/// Live rolling waveform from mic levels (0..1).
class _WavePainter extends CustomPainter {
  final List<double> levels;
  final Color color;
  _WavePainter(this.levels, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final barW = size.width / 60;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW * 0.6;
    final mid = size.height / 2;
    for (int i = 0; i < levels.length; i++) {
      final x = i * barW + barW / 2;
      final h = (levels[i] * size.height * 0.9).clamp(2.0, size.height);
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}

/// Static average-spectrum bars (0..1), a mini spectrogram of the whole clip.
class _SpectrumPainter extends CustomPainter {
  final List<double> spectrum;
  final Color color;
  _SpectrumPainter(this.spectrum, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrum.isEmpty) return;
    final barW = size.width / spectrum.length;
    for (int i = 0; i < spectrum.length; i++) {
      final h = (spectrum[i] * size.height).clamp(1.0, size.height);
      // Tint the 100-1000 Hz wheeze band brighter (roughly bins 3..32 of 64@2kHz).
      final inWheeze = i >= 3 && i <= 32;
      final paint = Paint()
        ..color = inWheeze ? color : color.withValues(alpha: .45);
      canvas.drawRect(
        Rect.fromLTWH(i * barW, size.height - h, barW * 0.85, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) => false;
}
