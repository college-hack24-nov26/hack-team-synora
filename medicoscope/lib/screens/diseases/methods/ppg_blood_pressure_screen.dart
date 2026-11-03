import 'dart:async';

import 'package:camera/camera.dart';
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
import 'package:medicoscope/services/ppg_bp_analyzer.dart';

enum _PpgStage { idle, initializing, capturing, analyzing, done, error }

class PpgBloodPressureScreen extends StatefulWidget {
  final String? patientId;
  const PpgBloodPressureScreen({super.key, this.patientId});

  @override
  State<PpgBloodPressureScreen> createState() =>
      _PpgBloodPressureScreenState();
}

class _PpgBloodPressureScreenState extends State<PpgBloodPressureScreen> {
  CameraController? _controller;
  _PpgStage _stage = _PpgStage.idle;
  String? _error;
  int _remaining = 15;
  Timer? _countdown;
  final List<double> _samples = [];
  DateTime? _captureStart;
  DiseaseRiskResult? _result;

  @override
  void dispose() {
    _countdown?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _startCapture() async {
    setState(() {
      _stage = _PpgStage.initializing;
      _error = null;
      _samples.clear();
    });
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // Use medium resolution — low can be as tiny as 176×144 on some devices
      // (barely enough frame data for a stable mean). Medium is the sweet spot.
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();

      // Lock exposure/focus so the pulse modulation is visible (auto-exposure
      // would counteract it and flatten the signal).
      try {
        await controller.setFocusMode(FocusMode.locked);
      } catch (_) {}
      try {
        await controller.setExposureMode(ExposureMode.locked);
      } catch (_) {}
      try {
        await controller.setFlashMode(FlashMode.torch);
      } catch (_) {}
      _controller = controller;

      setState(() {
        _stage = _PpgStage.capturing;
        _remaining = 15;
      });
      _captureStart = DateTime.now();

      _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining = (_remaining - 1).clamp(0, 15));
        if (_remaining <= 0) _finishCapture();
      });

      await controller.startImageStream((CameraImage image) {
        try {
          // Only sample the CENTER 40% × 40% of the frame — this is the part
          // directly over the sensor where the fingertip is pressed. Corners
          // often catch stray light or shadow that flattens the signal.
          //
          // YUV420 is laid out with 3 planes. We need the RED component of the
          // fingertip, not luminance alone. For best results we reconstruct
          // approximate red from Y + V: R ≈ Y + 1.402·(V − 128).
          final yPlane = image.planes[0];
          final vPlane = image.planes.length > 2 ? image.planes[2] : null;
          final width = image.width;
          final height = image.height;

          final rowStride = yPlane.bytesPerRow;
          final startX = (width * 0.3).toInt();
          final endX = (width * 0.7).toInt();
          final startY = (height * 0.3).toInt();
          final endY = (height * 0.7).toInt();

          double rSum = 0;
          int count = 0;

          // UV plane is half-resolution in both axes (NV21 / YV12 layouts).
          final uvRowStride = vPlane?.bytesPerRow ?? 0;
          final uvPixelStride = vPlane?.bytesPerPixel ?? 1;

          for (int y = startY; y < endY; y += 2) {
            final yRow = y * rowStride;
            final uvRow = (y >> 1) * uvRowStride;
            for (int x = startX; x < endX; x += 2) {
              final yIdx = yRow + x;
              if (yIdx >= yPlane.bytes.length) continue;
              final yVal = yPlane.bytes[yIdx].toDouble();

              double r;
              if (vPlane != null) {
                final uvIdx = uvRow + (x >> 1) * uvPixelStride;
                if (uvIdx < vPlane.bytes.length) {
                  final v = vPlane.bytes[uvIdx].toDouble() - 128.0;
                  r = yVal + 1.402 * v;
                } else {
                  r = yVal;
                }
              } else {
                r = yVal;
              }
              rSum += r;
              count++;
            }
          }

          if (count > 0) {
            _samples.add(rSum / count);
          }
        } catch (_) {
          // Never crash the stream; just drop the frame.
        }
      });
    } catch (e) {
      setState(() {
        _stage = _PpgStage.error;
        _error =
            'Could not open camera. Please grant camera permission and try again.';
      });
    }
  }

  Future<void> _finishCapture() async {
    _countdown?.cancel();
    _countdown = null;

    if (_controller != null && _controller!.value.isStreamingImages) {
      try {
        await _controller!.stopImageStream();
      } catch (_) {}
    }
    try {
      await _controller?.setFlashMode(FlashMode.off);
    } catch (_) {}

    setState(() => _stage = _PpgStage.analyzing);

    final duration = _captureStart == null
        ? 15.0
        : DateTime.now().difference(_captureStart!).inMilliseconds / 1000.0;
    final fps = _samples.length / duration.clamp(1.0, 999.0);

    final base = PpgBpAnalyzer.analyze(samples: _samples, fps: fps);

    if (!mounted) return;
    setState(() => _result = base);

    final lang = Provider.of<LocaleProvider>(context, listen: false)
        .languageCode;
    final explanation = await ChatService.explainRisk(
      disease: 'Hypertension',
      method: 'cuff-less PPG blood pressure',
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
      _stage = _PpgStage.done;
    });
    if (base.findings.isNotEmpty && mounted) {
      await DiseaseResultPipeline.persist(context, enriched);
    }

    await _controller?.dispose();
    _controller = null;
  }

  Future<void> _cancel() async {
    _countdown?.cancel();
    if (_controller != null && _controller!.value.isStreamingImages) {
      try {
        await _controller!.stopImageStream();
      } catch (_) {}
    }
    try {
      await _controller?.setFlashMode(FlashMode.off);
    } catch (_) {}
    await _controller?.dispose();
    _controller = null;
    if (!mounted) return;
    setState(() {
      _stage = _PpgStage.idle;
      _samples.clear();
    });
  }

  void _reset() => setState(() {
        _stage = _PpgStage.idle;
        _result = null;
        _samples.clear();
      });

  @override
  Widget build(BuildContext context) {
    final m = MethodRegistry.of(DetectionMethod.ppgBloodPressure);
    return MethodScaffold(
      title: 'Cuff-less Blood Pressure',
      subtitle: m.subtitle,
      icon: m.icon,
      gradient: m.gradient,
      disease: DiseaseType.hypertension,
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final accent = MethodRegistry.of(DetectionMethod.ppgBloodPressure)
        .gradient
        .first;

    if (_stage == _PpgStage.done && _result != null) {
      return RiskResultView(result: _result!, onRetry: _reset);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.fingerprint, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    'How this works',
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
              const SizedBox(height: 8),
              Text(
                'Cover the rear camera and flash with your fingertip. Press '
                'gently — enough to see a steady pink glow. Hold still for 15 '
                'seconds. MedicoScope analyses the red-channel pulse '
                'waveform (PPG) and estimates BP using a MIMIC-III-derived '
                'regression (Wu 2009 / Teng 2003).',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color:
                      isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        _captureCard(isDark, accent),
        if (_stage == _PpgStage.error)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingMedium),
            child: GlassCard(
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFFF5252)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error ?? 'Unknown error.',
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
    );
  }

  Widget _captureCard(bool isDark, Color accent) {
    if (_stage == _PpgStage.idle || _stage == _PpgStage.error) {
      return ElevatedButton.icon(
        onPressed: _startCapture,
        icon: const Icon(Icons.play_circle_fill_rounded),
        label: const Text('Start 15-second BP scan'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 15),
        ),
      );
    }

    if (_stage == _PpgStage.initializing) {
      return GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            const SizedBox(width: 12),
            Text('Initialising camera…',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.darkTextLight
                        : AppTheme.textDark)),
          ],
        ),
      );
    }

    if (_stage == _PpgStage.capturing) {
      return GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Column(
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [accent.withOpacity(0.9), accent.withOpacity(0.2)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.6),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                '$_remaining',
                style: const TextStyle(
                  fontSize: 60,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .scale(
                    begin: const Offset(0.96, 0.96),
                    end: const Offset(1.02, 1.02),
                    duration: 600.ms,
                    curve: Curves.easeInOut),
            const SizedBox(height: AppTheme.spacingLarge),
            Text(
              'Hold your fingertip still',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.darkTextLight
                    : AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Samples collected: ${_samples.length}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accent.withOpacity(0.5)),
              ),
            ),
          ],
        ),
      );
    }

    if (_stage == _PpgStage.analyzing) {
      return GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Column(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Running PPG-BP regression…',
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
      );
    }

    return const SizedBox.shrink();
  }
}
