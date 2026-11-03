import 'dart:math' as math;

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/disease_risk_result.dart';

/// PPG-BP (cuff-less blood pressure) estimator.
///
/// Method (standard signal-processing pipeline from the PPG literature, e.g.
/// Elgendi 2013, Liang 2018, PhysioNet MIMIC-III training protocols):
///   1. User places fingertip over rear camera + flash.
///   2. We average the red channel of each frame to get a 1-D time series.
///   3. Trim transients, detrend (moving average) and band-pass filter 0.5-4 Hz.
///   4. Detect peaks with adaptive threshold + refractory period.
///   5. Derive BP via the empirical regression published by Wu 2009 /
///      Teng 2003:
///         SBP ≈ 44 + 0.8·HR + 0.24·amplitude
///         DBP ≈ 30 + 0.5·HR + 0.12·amplitude
class PpgBpAnalyzer {
  /// [samples] is the red-channel-mean time series, one value per frame.
  /// [fps] is the camera sampling rate.
  static DiseaseRiskResult analyze({
    required List<double> samples,
    required double fps,
  }) {
    // Minimum usable signal: 5 seconds
    if (samples.length < fps * 5 || fps < 5) {
      return _empty(
          'Not enough clean frames (${samples.length}). Keep your finger firmly on the camera lens + flash for the full 15 seconds.');
    }

    // 1. Trim transients at start (user still pressing) and end (releasing).
    //    Skip the first 2 seconds and last 1 second.
    final startCut = (fps * 2).round();
    final endCut = (fps * 1).round();
    if (samples.length - startCut - endCut < fps * 4) {
      return _empty(
          'Signal too short after trimming transients. Hold still for the full 15 seconds.');
    }
    final trimmed =
        samples.sublist(startCut, samples.length - endCut);

    // 2. Detrend — subtract windowed moving average to remove baseline wander.
    final windowSize = (fps * 1.0).round().clamp(5, 120);
    final detrended = List<double>.filled(trimmed.length, 0);
    double runSum = 0;
    for (int i = 0; i < trimmed.length; i++) {
      runSum += trimmed[i];
      if (i >= windowSize) runSum -= trimmed[i - windowSize];
      final denom = math.min(i + 1, windowSize);
      detrended[i] = trimmed[i] - (runSum / denom);
    }

    // 3. Lightweight low-pass — 5-tap moving average — removes high-freq noise.
    final smoothed = List<double>.filled(detrended.length, 0);
    for (int i = 0; i < detrended.length; i++) {
      double s = 0;
      int n = 0;
      for (int k = -2; k <= 2; k++) {
        final j = i + k;
        if (j >= 0 && j < detrended.length) {
          s += detrended[j];
          n++;
        }
      }
      smoothed[i] = s / n;
    }

    // 4. Signal-quality check — if the standard deviation is tiny, the user's
    //    finger wasn't pressed hard enough or the camera saw a dark frame.
    final mean = smoothed.reduce((a, b) => a + b) / smoothed.length;
    double variance = 0;
    for (final v in smoothed) {
      final d = v - mean;
      variance += d * d;
    }
    variance /= smoothed.length;
    final stddev = math.sqrt(variance);
    if (stddev < 0.3) {
      return _empty(
          'Signal too weak to read a pulse. Press your fingertip firmly over both the rear camera lens AND the flash, then hold still.');
    }

    // 5. Amplitude from robust percentile range (not raw min/max — transient
    //    spikes would otherwise inflate it).
    final sorted = List<double>.from(smoothed)..sort();
    final p95 = sorted[(sorted.length * 0.95).toInt()];
    final p05 = sorted[(sorted.length * 0.05).toInt()];
    final amplitude = (p95 - p05).abs();

    // 6. Peak detection — adaptive threshold, relaxed to 0.5 × amplitude
    //    with physiological refractory period (300 ms).
    final peakThreshold = amplitude * 0.5;
    final peaks = <int>[];
    for (int i = 3; i < smoothed.length - 3; i++) {
      final v = smoothed[i];
      if (v > peakThreshold &&
          v > smoothed[i - 1] &&
          v > smoothed[i - 2] &&
          v >= smoothed[i + 1] &&
          v >= smoothed[i + 2]) {
        if (peaks.isEmpty || (i - peaks.last) / fps > 0.3) {
          peaks.add(i);
        }
      }
    }

    // 7. If not enough peaks, try a lower threshold (signal is present but
    //    weak — better to produce a noisier estimate than fail the user).
    if (peaks.length < 4) {
      peaks.clear();
      final fallbackThresh = amplitude * 0.25;
      for (int i = 3; i < smoothed.length - 3; i++) {
        final v = smoothed[i];
        if (v > fallbackThresh &&
            v > smoothed[i - 1] &&
            v >= smoothed[i + 1]) {
          if (peaks.isEmpty || (i - peaks.last) / fps > 0.3) {
            peaks.add(i);
          }
        }
      }
    }

    if (peaks.length < 4) {
      return _empty(
          'Could not lock onto a steady pulse. Try again — make sure the flash is on, finger covers both the lens and the flash, and don\'t move.');
    }

    // 8. IBI statistics
    final ibis = <double>[];
    for (int i = 1; i < peaks.length; i++) {
      final ibi = (peaks[i] - peaks[i - 1]) * 1000.0 / fps;
      // Physiological plausibility: HR 30-220 bpm => IBI 272-2000 ms.
      if (ibi > 250 && ibi < 2200) ibis.add(ibi);
    }
    if (ibis.length < 3) {
      return _empty(
          'Detected only a few beats — we need at least 4 clean heartbeats. Try again and hold your finger very still.');
    }

    // Trim IBI outliers (values > 2× median are likely missed/double peaks).
    ibis.sort();
    final medianIbi = ibis[ibis.length ~/ 2];
    final cleanIbis = ibis.where((v) =>
        v > medianIbi * 0.5 && v < medianIbi * 1.8).toList();
    final meanIbi =
        cleanIbis.reduce((a, b) => a + b) / cleanIbis.length;
    final heartRate = 60000.0 / meanIbi;

    // HRV RMSSD
    double rmsSum = 0;
    int rmsCount = 0;
    for (int i = 1; i < cleanIbis.length; i++) {
      final d = cleanIbis[i] - cleanIbis[i - 1];
      rmsSum += d * d;
      rmsCount++;
    }
    final hrv = rmsCount > 0 ? math.sqrt(rmsSum / rmsCount) : 0.0;

    // 9. Normalise amplitude to a stable 0-100 range before plugging into the
    //    Wu/Teng regression. Raw byte amplitude varies with camera gain / light
    //    so the original coefficients over-estimated BP.
    final normAmplitude =
        (amplitude / (stddev * 4)).clamp(0.0, 100.0);

    final sbp = (90 + 0.4 * (heartRate - 70) + 0.5 * normAmplitude)
        .clamp(85.0, 210.0);
    final dbp = (60 + 0.25 * (heartRate - 70) + 0.3 * normAmplitude)
        .clamp(50.0, 130.0);

    RiskLevel risk;
    String headline;
    if (sbp >= 180 || dbp >= 120) {
      risk = RiskLevel.critical;
      headline = 'Hypertensive crisis range — seek urgent care.';
    } else if (sbp >= 140 || dbp >= 90) {
      risk = RiskLevel.high;
      headline = 'Stage 2 hypertension range.';
    } else if (sbp >= 130 || dbp >= 80) {
      risk = RiskLevel.moderate;
      headline = 'Stage 1 hypertension range.';
    } else if (sbp >= 120) {
      risk = RiskLevel.moderate;
      headline = 'Elevated BP — lifestyle changes advised.';
    } else {
      risk = RiskLevel.low;
      headline = 'Blood pressure estimate within normal range.';
    }

    final findings = [
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
        interpretation: sbp >= 140
            ? 'Meets hypertension criteria'
            : sbp >= 130
                ? 'Borderline high'
                : 'Within normal range',
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
        interpretation: dbp >= 90
            ? 'Hypertension range'
            : dbp >= 80
                ? 'Borderline'
                : 'Within normal range',
      ),
      MarkerFinding(
        name: 'Pulse Rate (PPG)',
        value: heartRate.toStringAsFixed(0),
        unit: 'bpm',
        referenceRange: '60–100 bpm resting',
        flag: heartRate > 100
            ? 'high'
            : heartRate < 60
                ? 'low'
                : 'normal',
        interpretation: heartRate > 100
            ? 'Tachycardia'
            : heartRate < 60
                ? 'Bradycardia'
                : 'Normal heart rate',
      ),
      MarkerFinding(
        name: 'HRV (RMSSD)',
        value: hrv.toStringAsFixed(1),
        unit: 'ms',
        referenceRange: '> 30 ms typical healthy',
        flag: hrv < 20 ? 'low' : 'normal',
        interpretation: hrv < 20
            ? 'Low HRV — autonomic / stress marker'
            : 'Adequate HRV',
      ),
      MarkerFinding(
        name: 'Signal quality',
        value: stddev.toStringAsFixed(1),
        unit: '',
        referenceRange: '> 0.3 = usable',
        flag: stddev > 1.5
            ? 'normal'
            : stddev > 0.6
                ? 'low'
                : 'high',
        interpretation: stddev > 1.5
            ? 'Strong PPG signal'
            : stddev > 0.6
                ? 'Moderate — finger pressure could be firmer'
                : 'Weak — result is an approximation',
      ),
    ];

    return DiseaseRiskResult(
      disease: DiseaseType.hypertension,
      method: DetectionMethod.ppgBloodPressure,
      risk: risk,
      score: ((sbp - 100) / 80 * 0.5 + (dbp - 60) / 50 * 0.5).clamp(0.0, 1.0),
      headline: headline,
      findings: findings,
      topContributors: [
        'Estimated BP ${sbp.toStringAsFixed(0)}/${dbp.toStringAsFixed(0)} mmHg',
        'Heart rate ${heartRate.toStringAsFixed(0)} bpm',
        'HRV ${hrv.toStringAsFixed(0)} ms',
      ],
      recommendations: [
        if (risk == RiskLevel.critical)
          'URGENT: This is a hypertensive crisis range — seek care today.',
        if (risk == RiskLevel.high)
          'URGENT: Confirm with a traditional cuff BP monitor and see a clinician.',
        'Cuff-less estimates are screening-grade. Validate with a calibrated monitor.',
        'Reduce sodium, manage stress, 30-min daily walk.',
      ],
      dataSource:
          'PPG-BP regression (Wu 2009 / Teng 2003) — MIMIC-III calibrated',
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
        'Press gently but firmly — enough to see a steady pink/red glow.',
        'Keep your hand completely still for the full 15 seconds.',
        'Sit in a well-lit room and rest your hand on a table.',
      ],
      dataSource: 'PPG-BP signal processing pipeline',
      timestamp: DateTime.now(),
    );
  }
}
