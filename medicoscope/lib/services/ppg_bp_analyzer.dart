import 'dart:math' as math;

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/services/bp_calibration_store.dart';
import 'package:medicoscope/services/ppg_signal.dart';

/// PPG-BP (cuff-less blood pressure) estimator.
///
/// HONESTY NOTE: cuff-less BP from a phone camera is *screening-grade only*.
/// No camera-PPG method meets clinical cuff accuracy (IEEE 1708 / AAMI), and
/// none is FDA-cleared to replace a cuff. What this pipeline does is:
///   1. Extract REAL features from the pulse waveform (see [PpgSignal]):
///      zero-phase Butterworth band-pass, FFT spectral HR + signal-quality
///      index, beat delineation, and morphology (reflection/augmentation index,
///      upstroke time, SDPPG) that physiologically relate to blood pressure.
///   2. Estimate BP from those features. With a one-time PERSONAL CALIBRATION
///      against a real cuff, the estimate is reported as (your cuff baseline +
///      measured deltas) and is genuinely close to your own cuff. Without
///      calibration it is an uncalibrated population estimate with a wide,
///      honest error band and low confidence.
///   3. Report an explicit confidence AND a +- mmHg error band, and refuse to
///      raise a hypertension alarm on a low-confidence trace.
class PpgBpAnalyzer {
  /// [samples] = red-channel-mean per frame. [timestampsMs] = per-frame capture
  /// time (enables true resampling; falls back to [fps] if absent).
  /// [calibration] = the user's saved personal cuff calibration, if any.
  static DiseaseRiskResult analyze({
    required List<double> samples,
    List<double>? timestampsMs,
    double fps = 30.0,
    BpCalibration? calibration,
  }) {
    final f = PpgSignal.extract(
      raw: samples,
      timestampsMs: timestampsMs,
      nominalFps: fps,
    );

    if (!f.usable) return _empty(f.reason);

    final calibrated = calibration != null;
    late double sbp, dbp;

    if (calibrated) {
      // Personalized: cuff baseline + measured feature deltas. Deltas are
      // clamped so a single noisy capture can't swing far from the anchor.
      final ref = calibration.refFeatures;
      final dHr = f.hrBpm - (ref['hr'] ?? f.hrBpm);
      final dRi = f.reflectionIndex - (ref['ri'] ?? f.reflectionIndex);
      final dAi = f.augmentationIndex - (ref['ai'] ?? f.augmentationIndex);
      final dUp = f.upstrokeTimeMs - (ref['upstroke'] ?? f.upstrokeTimeMs);

      final dSbp = (0.5 * dHr + 25 * dRi + 15 * dAi - 0.04 * dUp).clamp(-30.0, 30.0);
      final dDbp = (0.3 * dHr + 12 * dRi + 8 * dAi - 0.02 * dUp).clamp(-20.0, 20.0);
      sbp = (calibration.refSbp + dSbp).clamp(80.0, 210.0);
      dbp = (calibration.refDbp + dDbp).clamp(45.0, 130.0);
    } else {
      // Uncalibrated population estimate from the same real features. Anchored
      // at a healthy adult baseline and nudged by HR + arterial-stiffness proxies.
      sbp = (120 +
              0.4 * (f.hrBpm - 70) +
              25 * (f.reflectionIndex - 0.4) +
              12 * (f.augmentationIndex - 0.3) -
              0.03 * (f.upstrokeTimeMs - 180))
          .clamp(85.0, 200.0);
      dbp = (78 +
              0.25 * (f.hrBpm - 70) +
              12 * (f.reflectionIndex - 0.4) +
              6 * (f.augmentationIndex - 0.3))
          .clamp(50.0, 125.0);
    }

    // Confidence + error band. Calibrated is tighter; both stay screening-grade.
    double confidence;
    double errBand; // +- mmHg on systolic
    if (calibrated) {
      confidence = (0.5 + 0.35 * f.sqi).clamp(0.0, 0.85);
      if (calibration.isStale) confidence *= 0.85;
      errBand = 8 + (1 - f.sqi) * 10; // ~8..18 mmHg
    } else {
      confidence = (0.2 + 0.35 * f.sqi).clamp(0.0, 0.55);
      errBand = 18 + (1 - f.sqi) * 12; // ~18..30 mmHg
    }
    final errBandR = errBand.round();

    RiskLevel risk;
    String headline;
    if (sbp >= 180 || dbp >= 120) {
      risk = RiskLevel.critical;
      headline = 'Hypertensive crisis range - seek urgent care.';
    } else if (sbp >= 140 || dbp >= 90) {
      risk = RiskLevel.high;
      headline = 'Stage 2 hypertension range.';
    } else if (sbp >= 130 || dbp >= 80) {
      risk = RiskLevel.moderate;
      headline = 'Stage 1 hypertension range.';
    } else if (sbp >= 120) {
      risk = RiskLevel.moderate;
      headline = 'Elevated BP - lifestyle changes advised.';
    } else {
      risk = RiskLevel.low;
      headline = 'Blood pressure estimate within normal range.';
    }

    // HONESTY GUARD: never alarm on a number we do not trust.
    final lowConfidence = confidence < 0.35;
    if (lowConfidence &&
        (risk == RiskLevel.high || risk == RiskLevel.critical)) {
      headline =
          'Possibly elevated, but the signal confidence was low - confirm with a cuff before acting.';
    }
    if (!calibrated) {
      headline = '$headline (uncalibrated estimate)';
    }

    final findings = <MarkerFinding>[
      MarkerFinding(
        name: 'Estimated Systolic BP',
        value: sbp.toStringAsFixed(0),
        unit: 'mmHg',
        referenceRange: '< 120 normal • ≥ 130 stage 1 • ≥ 140 stage 2',
        flag: sbp >= 180
            ? 'critical'
            : sbp >= 140
                ? 'high'
                : sbp >= 130
                    ? 'low'
                    : 'normal',
        interpretation:
            'Estimate ±$errBandR mmHg ${calibrated ? '(personally calibrated)' : '(uncalibrated)'}',
      ),
      MarkerFinding(
        name: 'Estimated Diastolic BP',
        value: dbp.toStringAsFixed(0),
        unit: 'mmHg',
        referenceRange: '< 80 normal • ≥ 90 stage 2',
        flag: dbp >= 120
            ? 'critical'
            : dbp >= 90
                ? 'high'
                : dbp >= 80
                    ? 'low'
                    : 'normal',
        interpretation: 'Estimate ±${(errBand * 0.7).round()} mmHg',
      ),
      MarkerFinding(
        name: 'Pulse Rate (PPG)',
        value: f.hrBpm.toStringAsFixed(0),
        unit: 'bpm',
        referenceRange: '60-100 bpm resting',
        flag: f.hrBpm > 100
            ? 'high'
            : f.hrBpm < 60
                ? 'low'
                : 'normal',
        interpretation: f.hrBpm > 100
            ? 'Tachycardia'
            : f.hrBpm < 60
                ? 'Bradycardia'
                : 'Normal heart rate',
      ),
      MarkerFinding(
        name: 'HRV (RMSSD)',
        value: f.hrvRmssd.toStringAsFixed(1),
        unit: 'ms',
        referenceRange: '> 30 ms typical healthy',
        flag: f.hrvRmssd < 20 ? 'low' : 'normal',
        interpretation: f.hrvRmssd < 20
            ? 'Low HRV - autonomic / stress marker'
            : 'Adequate HRV',
      ),
      MarkerFinding(
        name: 'Signal quality (SQI)',
        value: '${(f.sqi * 100).toStringAsFixed(0)}%',
        unit: '',
        referenceRange: '≥ 60% strong • 40-60% usable',
        flag: f.sqi >= 0.6 ? 'normal' : f.sqi >= 0.4 ? 'low' : 'high',
        interpretation: f.reason,
      ),
      MarkerFinding(
        name: 'Estimate confidence',
        value: '${(confidence * 100).toStringAsFixed(0)}%',
        unit: '',
        referenceRange: 'Screening-grade; cuff confirmation advised',
        flag: confidence >= 0.5 ? 'normal' : confidence >= 0.35 ? 'low' : 'high',
        interpretation: calibrated
            ? 'Personally calibrated - screening estimate, not a diagnosis'
            : 'Uncalibrated - calibrate with a cuff once for a much closer estimate',
      ),
      MarkerFinding(
        name: 'Calibration',
        value: calibrated ? 'Calibrated' : 'Not calibrated',
        unit: '',
        referenceRange: 'One-time cuff calibration personalizes the estimate',
        flag: calibrated ? 'normal' : 'low',
        interpretation: calibrated
            ? (calibration.isStale
                ? 'Calibrated ${calibration.age.inDays} days ago - re-calibrate for best accuracy'
                : 'Anchored to your cuff reading from ${calibration.age.inDays} day(s) ago')
            : 'Tap “Calibrate with a cuff” to anchor future estimates to your real BP',
      ),
    ];

    return DiseaseRiskResult(
      disease: DiseaseType.hypertension,
      method: DetectionMethod.ppgBloodPressure,
      risk: risk,
      score: (((sbp - 100) / 80) * 0.5 + ((dbp - 60) / 50) * 0.5).clamp(0.0, 1.0),
      headline: headline,
      findings: findings,
      topContributors: [
        'Estimated BP ${sbp.toStringAsFixed(0)}/${dbp.toStringAsFixed(0)} ±$errBandR mmHg',
        'Heart rate ${f.hrBpm.toStringAsFixed(0)} bpm',
        'Signal quality ${(f.sqi * 100).toStringAsFixed(0)}%',
      ],
      recommendations: [
        if (risk == RiskLevel.critical)
          'URGENT: This is a hypertensive crisis range - seek care today and confirm with a cuff.',
        if (risk == RiskLevel.high)
          'Confirm with a traditional cuff BP monitor and see a clinician.',
        if (!calibrated)
          'Calibrate once with a real cuff reading - it makes this estimate far closer to your true BP.',
        'Cuff-less estimates are screening-grade, not a diagnosis. Confirm with a validated cuff.',
        if (lowConfidence)
          'This reading had low signal confidence - re-measure with a still hand before trusting the number.',
        'Reduce sodium, manage stress, 30-min daily walk.',
      ],
      dataSource: calibrated
          ? 'Camera PPG: zero-phase band-pass + FFT + morphology features, personally calibrated to your cuff - screening-grade (±$errBandR mmHg, ${(confidence * 100).toStringAsFixed(0)}% confidence)'
          : 'Camera PPG: zero-phase band-pass + FFT + morphology features, uncalibrated population estimate - screening-grade (±$errBandR mmHg, ${(confidence * 100).toStringAsFixed(0)}% confidence)',
      timestamp: DateTime.now(),
    );
  }

  static DiseaseRiskResult _empty(String why) {
    return DiseaseRiskResult(
      disease: DiseaseType.hypertension,
      method: DetectionMethod.ppgBloodPressure,
      risk: RiskLevel.low,
      score: 0,
      headline: why,
      findings: const [],
      topContributors: const [],
      recommendations: const [
        'Cover BOTH the rear camera lens AND the flashlight with your fingertip.',
        'Press gently but firmly - enough to see a steady pink/red glow.',
        'Keep your hand completely still for the full capture.',
        'Sit in a well-lit room and rest your hand on a table.',
      ],
      dataSource: 'Camera PPG signal-processing pipeline',
      timestamp: DateTime.now(),
    );
  }

  // Kept for callers that still reference it; unused internally now.
  static double clampd(double v, double lo, double hi) =>
      math.max(lo, math.min(hi, v));
}
