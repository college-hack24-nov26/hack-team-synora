import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/services/respiratory_analyzer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

/// Respiratory acoustic screening - record ~15 s of breathing/coughing, then
/// run the on-device [RespiratoryAnalyzer]. Real signal only: nothing is
/// fabricated, and a noisy/short clip is honestly rejected rather than scored.
class RespiratoryScreen extends StatefulWidget {
  const RespiratoryScreen({super.key});

  @override
  State<RespiratoryScreen> createState() => _RespiratoryScreenState();
}

class _RespiratoryScreenState extends State<RespiratoryScreen>
    with TickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isProcessing = false;
  int _secondsElapsed = 0;
  Timer? _timer;
  String? _path;
  RespiratoryResult? _result;
  String? _error;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
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
      _isRecording = true;
      _secondsElapsed = 0;
      _path = path;
      _result = null;
      _error = null;
    });
    _pulse.repeat();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _secondsElapsed++);
      if (_secondsElapsed >= 20) _stop(); // auto-stop at 20 s
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _pulse.stop();
    _pulse.reset();
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _path = path ?? _path;
    });
    await _analyze();
  }

  Future<void> _analyze() async {
    if (_path == null) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final result = await RespiratoryAnalyzer.analyzeWavFile(_path!);
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        if (result.usable) {
          _result = result;
        } else {
          _error = result.headline;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = 'Could not analyze the recording. Please try again.';
      });
    }
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
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.spacingLarge),
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacingMedium),
                      _captureCard(isDark),
                      if (_isProcessing) ...[
                        const SizedBox(height: AppTheme.spacingLarge),
                        _processing(isDark),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: AppTheme.spacingLarge),
                        _errorCard(_error!, isDark),
                      ],
                      if (_result != null) ...[
                        const SizedBox(height: AppTheme.spacingLarge),
                        _resultCard(_result!, isDark),
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
                  Text(
                    'Respiratory Check',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                    ),
                  ),
                  Text(
                    'Breathing-pattern screening',
                    style: TextStyle(
                      fontSize: 13,
                      color: (isDark ? AppTheme.darkTextLight : AppTheme.textGray)
                          .withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppTheme.orangeGradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: const Icon(Icons.air, color: Colors.white),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms);

  Widget _captureCard(bool isDark) {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingLarge),
      child: Column(
        children: [
          Text(
            _isRecording
                ? 'Listening… breathe normally near the mic'
                : 'Hold the phone ~10 cm away and breathe steadily for ~15 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          GestureDetector(
            onTap: _isProcessing
                ? null
                : (_isRecording ? _stop : _start),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final scale = _isRecording ? 1 + _pulse.value * 0.12 : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.orangeGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryOrange.withValues(
                              alpha: _isRecording ? 0.45 : 0.30),
                          blurRadius: _isRecording ? 30 : 18,
                          spreadRadius: _isRecording ? 6 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          Text(
            _isRecording ? '00:${_secondsElapsed.toString().padLeft(2, '0')}' : 'Tap to record',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _isRecording
                  ? AppTheme.primaryOrange
                  : (isDark ? AppTheme.darkTextLight : AppTheme.textGray),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _processing(bool isDark) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Row(
          children: [
            const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 14),
            Text('Analyzing breathing pattern…',
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
                      color:
                          isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms);

  Widget _resultCard(RespiratoryResult r, bool isDark) {
    final tone = r.distressScore >= 0.6
        ? const Color(0xFFFF5252)
        : r.distressScore >= 0.4
            ? const Color(0xFFFF9800)
            : const Color(0xFF4CAF50);
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.air, size: 18, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Respiratory markers',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextLight
                            : AppTheme.textDark)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${(r.distressScore * 100).round()}%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tone)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(r.headline,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color:
                      isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric('Breathing rate', '${r.breathingRate.toStringAsFixed(0)}/min', isDark),
              _metric('Cough bursts', '${r.coughCount}', isDark),
              _metric('Wheeze band', '${(r.wheezeBandRatio * 100).round()}%', isDark),
              _metric('Confidence', '${(r.confidence * 100).round()}%', isDark),
            ],
          ),
          const SizedBox(height: 14),
          for (final note in r.notes) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  ', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Text(note,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: (isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.textDark)
                            .withValues(alpha: 0.8),
                      )),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _metric(String label, String value, bool isDark) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: (isDark ? AppTheme.darkTextLight : AppTheme.textGray)
                        .withValues(alpha: 0.7))),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.textDark)),
          ],
        ),
      );
}
