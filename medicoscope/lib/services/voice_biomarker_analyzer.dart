import 'package:medicoscope/services/voice_calibration_store.dart';
import 'package:medicoscope/services/voice_signal.dart';

/// Result of voice acoustic-biomarker analysis. Deliberately NOT a
/// DiseaseRiskResult: this screens a different domain (affective / voice
/// markers), not the diabetes / hypertension / anemia deck.
class VoiceBiomarkerResult {
  final bool usable;
  final String headline;
  final double markerScore; // 0..1 affective-marker load
  final double confidence; // 0..1 honest signal-quality confidence
  final bool calibrated;

  // Real acoustic features (see VoiceSignal).
  final double f0Mean; // Hz
  final double f0Cv; // pitch variability (0 = monotone)
  final double jitterPct;
  final double shimmerPct;
  final double hnrDb;
  final double speechRate;
  final double pauseRatio;
  final double spectralTiltDb;
  final double sqi;
  final List<double> avgSpectrum;
  final List<String> notes;

  const VoiceBiomarkerResult({
    required this.usable,
    required this.headline,
    this.markerScore = 0,
    this.confidence = 0,
    this.calibrated = false,
    this.f0Mean = 0,
    this.f0Cv = 0,
    this.jitterPct = 0,
    this.shimmerPct = 0,
    this.hnrDb = 0,
    this.speechRate = 0,
    this.pauseRatio = 0,
    this.spectralTiltDb = 0,
    this.sqi = 0,
    this.avgSpectrum = const [],
    this.notes = const [],
  });

  /// Compact payload persisted with the MindSpace session / doctor alert.
  Map<String, dynamic> toJson() => {
        'markerScore': markerScore,
        'confidence': confidence,
        'calibrated': calibrated,
        'f0Mean': f0Mean,
        'f0Cv': f0Cv,
        'jitterPct': jitterPct,
        'shimmerPct': shimmerPct,
        'hnrDb': hnrDb,
        'speechRate': speechRate,
        'pauseRatio': pauseRatio,
        'headline': headline,
      };
}

/// Voice acoustic-biomarker analyzer.
///
/// HONESTY NOTE: this measures REAL acoustic properties of speech (autocorrelation
/// F0 + pitch variability, jitter, shimmer, HNR, speech rate, pausing, spectral
/// tilt). Slower, more monotone, more pausing speech with a flatter spectrum are
/// acoustic markers ASSOCIATED with low mood / psychomotor slowing in the
/// research literature (Cummins 2015, Mundt 2007). This is a SCREENING SIGNAL
/// that complements the transcript, never a diagnosis of depression. With a
/// personal voice calibration the markers are judged against the user's OWN
/// baseline, which is far more meaningful than a population assumption.
class VoiceBiomarkerAnalyzer {
  static Future<VoiceBiomarkerResult> analyzeWavFile(String path,
      {VoiceCalibration? calibration}) async {
    final f = await VoiceSignal.analyzeWavFile(path);
    return fromFeatures(f, calibration: calibration);
  }

  static VoiceBiomarkerResult analyze(List<double> samples, int sampleRate,
      {VoiceCalibration? calibration}) {
    final f = VoiceSignal.extract(samples: samples, sampleRate: sampleRate);
    return fromFeatures(f, calibration: calibration);
  }

  static VoiceBiomarkerResult fromFeatures(VoiceFeatures f,
      {VoiceCalibration? calibration}) {
    if (!f.usable) {
      return VoiceBiomarkerResult(usable: false, headline: f.reason);
    }
    final calibrated = calibration != null;

    double slowness, pausing, monotone, flatEnergy;
    if (calibrated) {
      // Change vs the user's OWN baseline (more sensitive + fair than absolutes).
      final baseRate = calibration.baselineRate;
      final baseF0Cv = calibration.refFeatures['f0cv'] ?? f.f0Cv;
      final baseEnergyCv = calibration.refFeatures['energyCv'] ?? 0.6;
      final basePause = calibration.refFeatures['pause'] ?? f.pauseRatio;
      slowness = baseRate > 0
          ? ((baseRate - f.speechRate) / baseRate).clamp(0.0, 1.0)
          : (1.0 - (f.speechRate / 2.0)).clamp(0.0, 1.0);
      monotone = baseF0Cv > 0
          ? ((baseF0Cv - f.f0Cv) / baseF0Cv).clamp(0.0, 1.0)
          : (1.0 - (f.f0Cv / 0.15)).clamp(0.0, 1.0);
      flatEnergy = baseEnergyCv > 0
          ? ((baseEnergyCv - f.energyCv) / baseEnergyCv).clamp(0.0, 1.0)
          : 0.0;
      pausing = (f.pauseRatio - basePause).clamp(0.0, 1.0);
    } else {
      slowness = (1.0 - (f.speechRate / 2.0)).clamp(0.0, 1.0); // < 2 onsets/s
      pausing = f.pauseRatio.clamp(0.0, 1.0);
      monotone = (1.0 - (f.f0Cv / 0.15)).clamp(0.0, 1.0);
      flatEnergy = 0.0;
    }
    final markerScore =
        (slowness * 0.32 + pausing * 0.26 + monotone * 0.30 + flatEnergy * 0.12)
            .clamp(0.0, 1.0);

    double confidence;
    if (calibrated) {
      confidence = (0.5 + 0.35 * f.sqi).clamp(0.0, 0.8);
      if (calibration.isStale) confidence *= 0.85;
    } else {
      confidence = (0.3 + 0.35 * f.sqi).clamp(0.0, 0.6);
    }

    String headline;
    if (markerScore >= 0.6) {
      headline = calibrated
          ? 'Voice is notably slower / flatter than your baseline.'
          : 'Several low-mood voice markers (slow, monotone, pausing).';
    } else if (markerScore >= 0.4) {
      headline = 'Some voice markers worth noting - talk it through.';
    } else {
      headline = 'Voice markers within a typical range.';
    }
    final lowConf = confidence < 0.35;
    if (lowConf && markerScore >= 0.6) {
      headline =
          'Possible voice markers, but the recording was noisy - try again in a quiet room.';
    }
    if (!calibrated) headline = '$headline (uncalibrated)';

    return VoiceBiomarkerResult(
      usable: true,
      headline: headline,
      markerScore: double.parse(markerScore.toStringAsFixed(2)),
      confidence: double.parse(confidence.toStringAsFixed(2)),
      calibrated: calibrated,
      f0Mean: double.parse(f.f0Mean.toStringAsFixed(0)),
      f0Cv: double.parse(f.f0Cv.toStringAsFixed(2)),
      jitterPct: double.parse(f.jitterPct.toStringAsFixed(1)),
      shimmerPct: double.parse(f.shimmerPct.toStringAsFixed(1)),
      hnrDb: double.parse(f.hnrDb.toStringAsFixed(1)),
      speechRate: double.parse(f.speechRate.toStringAsFixed(1)),
      pauseRatio: double.parse(f.pauseRatio.toStringAsFixed(2)),
      spectralTiltDb: double.parse(f.spectralTiltDb.toStringAsFixed(1)),
      sqi: f.sqi,
      avgSpectrum: f.avgSpectrum,
      notes: [
        'Screening signal only - NOT a diagnosis of depression.',
        'Complements the transcript analysis; both are supportive, not diagnostic.',
        if (!calibrated)
          'Calibrate your baseline voice once (on a calm day) for a far more meaningful read.',
        if (markerScore >= 0.6 && confidence >= 0.4)
          'If low mood persists, please talk to someone you trust or a professional.',
      ],
    );
  }
}
