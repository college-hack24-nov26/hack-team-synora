import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/services/respiratory_calibration_store.dart';
import 'package:medicoscope/services/respiratory_signal.dart';

/// Respiratory acoustic-screening analyzer.
///
/// HONESTY NOTE: this turns REAL signal-derived features (see [RespiratorySignal]:
/// envelope-FFT breathing rate, STFT wheeze/crackle detection, I:E ratio) into a
/// screening result. With a one-time PERSONAL resting-breathing calibration the
/// breathing rate is judged against the user's own normal; otherwise a population
/// cutoff is used with a wider band and lower confidence. It is NOT a diagnosis
/// of asthma, COPD, or pneumonia, and every reading carries an honest confidence.
class RespiratoryAnalyzer {
  static const double _populationTachypnea = 20.0; // bpm

  /// Convenience: decode + extract + analyze (used by tests / simple callers).
  static Future<DiseaseRiskResult> analyzeWavFile(String path,
      {RespiratoryCalibration? calibration}) async {
    final f = await RespiratorySignal.analyzeWavFile(path);
    return analyze(features: f, calibration: calibration);
  }

  static DiseaseRiskResult analyze({
    required RespiratoryFeatures features,
    RespiratoryCalibration? calibration,
  }) {
    if (!features.usable) return _empty(features.reason);
    final f = features;
    final calibrated = calibration != null;

    // Breathing-rate elevation vs the right reference (personal or population).
    final ref = calibrated ? calibration.restingBpm : _populationTachypnea;
    final double rateElev;
    if (calibrated) {
      rateElev = ((f.breathingRate - ref) / 8.0).clamp(0.0, 1.0); // +8 => full
    } else {
      rateElev = ((f.breathingRate - ref) / 12.0).clamp(0.0, 1.0);
    }
    final wheeze = ((f.wheezeRatio - 0.05) / 0.25).clamp(0.0, 1.0);
    final crackle = (f.crackleCount / 8.0).clamp(0.0, 1.0);
    final cough = (f.coughCount / 5.0).clamp(0.0, 1.0);
    final distress =
        (rateElev * 0.4 + wheeze * 0.3 + crackle * 0.2 + cough * 0.1)
            .clamp(0.0, 1.0);

    // Confidence + breathing-rate error band. Calibrated is tighter.
    double confidence;
    double rateBand; // +- breaths/min
    if (calibrated) {
      confidence = (0.5 + 0.35 * f.sqi).clamp(0.0, 0.85);
      if (calibration.isStale) confidence *= 0.85;
      rateBand = 2 + (1 - f.sqi) * 3; // ~2..5
    } else {
      confidence = (0.3 + 0.35 * f.sqi).clamp(0.0, 0.6);
      rateBand = 3 + (1 - f.sqi) * 4; // ~3..7
    }
    final rateBandR = rateBand.round();

    RiskLevel risk;
    String headline;
    if (distress >= 0.8 || f.breathingRate >= 30) {
      risk = RiskLevel.critical;
      headline = 'Marked respiratory-distress markers - seek care if breathless.';
    } else if (distress >= 0.55) {
      risk = RiskLevel.high;
      headline = 'Several respiratory-distress markers present.';
    } else if (distress >= 0.35) {
      risk = RiskLevel.moderate;
      headline = 'Some respiratory markers - worth monitoring.';
    } else {
      risk = RiskLevel.low;
      headline = 'Breathing pattern within a typical range.';
    }

    // Guardrail: do not alarm on a number we do not trust.
    final lowConf = confidence < 0.35;
    if (lowConf && (risk == RiskLevel.high || risk == RiskLevel.critical)) {
      headline =
          'Possible respiratory markers, but the signal was noisy - re-record in a quiet room.';
    }
    if (!calibrated) headline = '$headline (uncalibrated)';

    final ieText = f.ieRatio > 0
        ? '1:${(1 / f.ieRatio).clamp(0.3, 6).toStringAsFixed(1)}'
        : 'n/a';

    final findings = <MarkerFinding>[
      MarkerFinding(
        name: 'Breathing Rate',
        value: f.breathingRate.toStringAsFixed(0),
        unit: 'breaths/min',
        referenceRange: '12-20 resting typical',
        flag: f.breathingRate >= 25
            ? 'critical'
            : f.breathingRate > (calibrated ? ref + 4 : _populationTachypnea)
                ? 'high'
                : 'normal',
        interpretation: calibrated
            ? 'Estimate ±$rateBandR; your resting baseline is ${ref.toStringAsFixed(0)}/min'
            : 'Estimate ±$rateBandR (uncalibrated)',
      ),
      MarkerFinding(
        name: 'Inspiration:Expiration',
        value: ieText,
        unit: '',
        referenceRange: '~1:2 typical at rest',
        flag: 'normal',
        interpretation: 'Ratio of inhale to exhale duration',
      ),
      MarkerFinding(
        name: 'Wheeze (tonal 100-1000 Hz)',
        value: '${(f.wheezeRatio * 100).toStringAsFixed(0)}%',
        unit: 'of frames',
        referenceRange: 'Sustained musical tones suggest wheeze',
        flag: f.wheezeRatio >= 0.25 ? 'high' : f.wheezeRatio >= 0.12 ? 'low' : 'normal',
        interpretation: f.wheezeRatio >= 0.12
            ? 'Tonal content detected - a clinician should listen'
            : 'No sustained wheeze detected',
      ),
      MarkerFinding(
        name: 'Crackles',
        value: f.crackleCount.toString(),
        unit: 'bursts',
        referenceRange: 'Impulsive high-band transients',
        flag: f.crackleCount >= 6 ? 'high' : f.crackleCount >= 3 ? 'low' : 'normal',
        interpretation: f.crackleCount >= 3
            ? 'Crackle-like transients present'
            : 'Few or no crackles',
      ),
      MarkerFinding(
        name: 'Cough bursts',
        value: f.coughCount.toString(),
        unit: '',
        referenceRange: 'Energy bursts in the clip',
        flag: f.coughCount >= 3 ? 'high' : 'normal',
        interpretation: f.coughCount >= 3 ? 'Frequent coughing' : 'Little/no coughing',
      ),
      MarkerFinding(
        name: 'Signal quality (SQI)',
        value: '${(f.sqi * 100).toStringAsFixed(0)}%',
        unit: '',
        referenceRange: '>= 60% strong - 40-60% usable',
        flag: f.sqi >= 0.6 ? 'normal' : f.sqi >= 0.4 ? 'low' : 'high',
        interpretation: f.reason,
      ),
      MarkerFinding(
        name: 'Estimate confidence',
        value: '${(confidence * 100).toStringAsFixed(0)}%',
        unit: '',
        referenceRange: 'Screening-grade; not diagnostic',
        flag: confidence >= 0.5 ? 'normal' : confidence >= 0.35 ? 'low' : 'high',
        interpretation: calibrated
            ? 'Personally calibrated - screening estimate, not a diagnosis'
            : 'Uncalibrated - calibrate your resting breathing once for a closer read',
      ),
      MarkerFinding(
        name: 'Calibration',
        value: calibrated ? 'Calibrated' : 'Not calibrated',
        unit: '',
        referenceRange: 'One-time resting-breathing baseline personalizes this',
        flag: calibrated ? 'normal' : 'low',
        interpretation: calibrated
            ? (calibration.isStale
                ? 'Calibrated ${calibration.age.inDays} days ago - re-calibrate for best accuracy'
                : 'Anchored to your resting breathing from ${calibration.age.inDays} day(s) ago')
            : 'Tap "Calibrate resting breathing" to personalize future scans',
      ),
    ];

    return DiseaseRiskResult(
      disease: DiseaseType.respiratory,
      method: DetectionMethod.respiratoryAcoustic,
      risk: risk,
      score: distress,
      headline: headline,
      findings: findings,
      topContributors: [
        'Breathing rate ${f.breathingRate.toStringAsFixed(0)} ±$rateBandR /min',
        if (f.wheezeRatio >= 0.12)
          'Wheeze in ${(f.wheezeRatio * 100).toStringAsFixed(0)}% of frames',
        if (f.crackleCount >= 3) '${f.crackleCount} crackle bursts',
        'Signal quality ${(f.sqi * 100).toStringAsFixed(0)}%',
      ],
      recommendations: [
        if (risk == RiskLevel.critical)
          'If you feel breathless, have chest tightness, or lips look blue, seek care now.',
        if (risk == RiskLevel.high)
          'Monitor your breathing and see a clinician if it worsens or persists.',
        if (!calibrated)
          'Calibrate once with calm resting breathing - it makes the rate judgement personal and more accurate.',
        'Acoustic screening is not a diagnosis of asthma, COPD, or pneumonia. Confirm concerns with a clinician.',
        if (lowConf)
          'This reading had low signal confidence - re-record in a quiet room, phone ~10 cm from the mouth.',
      ],
      dataSource: calibrated
          ? 'On-device respiratory acoustics: envelope-FFT breathing rate + STFT wheeze/crackle features, personally calibrated - screening-grade (±$rateBandR /min, ${(confidence * 100).toStringAsFixed(0)}% confidence)'
          : 'On-device respiratory acoustics: envelope-FFT breathing rate + STFT wheeze/crackle features, uncalibrated - screening-grade (±$rateBandR /min, ${(confidence * 100).toStringAsFixed(0)}% confidence)',
      timestamp: DateTime.now(),
    );
  }

  static DiseaseRiskResult _empty(String why) => DiseaseRiskResult(
        disease: DiseaseType.respiratory,
        method: DetectionMethod.respiratoryAcoustic,
        risk: RiskLevel.low,
        score: 0,
        headline: why,
        findings: const [],
        topContributors: const [],
        recommendations: const [
          'Sit upright in a quiet room and hold the phone ~10 cm from your mouth.',
          'Breathe normally and audibly through your mouth for the full capture.',
          'Avoid talking, background TV, or fans during the recording.',
        ],
        dataSource: 'On-device respiratory acoustic pipeline',
        timestamp: DateTime.now(),
      );
}
