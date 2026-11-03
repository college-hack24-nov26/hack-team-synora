import 'dart:math' as math;

import 'package:medicoscope/services/heart_audio_decoder.dart';

/// Result of voice acoustic-biomarker analysis. Deliberately NOT a
/// DiseaseRiskResult: this screens a different domain (affective/voice
/// markers), not the diabetes/hypertension/anemia deck.
class VoiceBiomarkerResult {
  final bool usable;
  final String headline;
  final double speechRate; // approx syllable-onsets per second
  final double pauseRatio; // fraction of the clip that is silence
  final double pitchVariability; // normalised F0 spread (monotone ↓)
  final double energyVariability; // loudness dynamics
  final double markerScore; // 0..1 - elevated affective-marker load
  final double confidence; // 0..1 - honest signal-quality confidence
  final List<String> notes;

  const VoiceBiomarkerResult({
    required this.usable,
    required this.headline,
    this.speechRate = 0,
    this.pauseRatio = 0,
    this.pitchVariability = 0,
    this.energyVariability = 0,
    this.markerScore = 0,
    this.confidence = 0,
    this.notes = const [],
  });

  Map<String, dynamic> toJson() => {
        'usable': usable,
        'headline': headline,
        'speechRate': speechRate,
        'pauseRatio': pauseRatio,
        'pitchVariability': pitchVariability,
        'energyVariability': energyVariability,
        'markerScore': markerScore,
        'confidence': confidence,
        'notes': notes,
      };
}

/// Voice acoustic-biomarker analyzer.
///
/// HONESTY NOTE: this measures REAL acoustic properties of the voice signal
/// (speech rate, pausing, pitch/energy dynamics) that the affective-computing
/// literature associates with low mood / psychomotor slowing (e.g. Cummins
/// 2015, Mundt 2007). It is a SCREENING SIGNAL, never a diagnosis of
/// depression - and it complements (does not replace) the existing transcript
/// analysis. Reduced pitch variability ("monotone"), slow speech, and long
/// pauses are the classic markers; we surface them with an honest confidence.
class VoiceBiomarkerAnalyzer {
  /// Analyze the same WAV the MindSpace voice check-in already records.
  static Future<VoiceBiomarkerResult> analyzeWavFile(String path) async {
    final audio = await HeartAudioDecoder.decodeWavFile(path);
    return analyze(audio.samples, audio.sampleRate);
  }

  static VoiceBiomarkerResult analyze(List<double> samples, int sampleRate) {
    final durationSec = samples.length / sampleRate;
    if (durationSec < 3) {
      return const VoiceBiomarkerResult(
        usable: false,
        headline: 'Recording too short - please speak for at least 5 seconds.',
        notes: ['Tap record and talk naturally for 5-15 seconds.'],
      );
    }

    // 1. Frame the signal into 25 ms windows (10 ms hop) - standard for speech.
    final frameLen = (sampleRate * 0.025).round();
    final hop = (sampleRate * 0.010).round();
    if (frameLen < 8) {
      return const VoiceBiomarkerResult(
          usable: false, headline: 'Sample rate too low for voice analysis.');
    }

    final energies = <double>[];
    final zcrs = <double>[];
    for (int start = 0; start + frameLen <= samples.length; start += hop) {
      double e = 0;
      int zc = 0;
      for (int i = 0; i < frameLen; i++) {
        final s = samples[start + i];
        e += s * s;
        if (i > 0 &&
            ((s >= 0) != (samples[start + i - 1] >= 0))) {
          zc++;
        }
      }
      energies.add(e / frameLen);
      zcrs.add(zc / frameLen);
    }
    if (energies.length < 10) {
      return const VoiceBiomarkerResult(
          usable: false, headline: 'Not enough voiced frames to analyze.');
    }

    // 2. Voice-activity detection: a frame is "speech" if its energy is above
    //    an adaptive floor (noise estimate from the quietest 10% of frames).
    final sortedE = List<double>.from(energies)..sort();
    final noiseFloor = sortedE[(sortedE.length * 0.10).floor()];
    final peakE = sortedE[(sortedE.length * 0.95).floor()];
    final speechThresh = noiseFloor + (peakE - noiseFloor) * 0.15;
    final isSpeech = energies.map((e) => e > speechThresh).toList();

    final speechFrames = isSpeech.where((b) => b).length;
    final pauseRatio = 1.0 - speechFrames / isSpeech.length;

    // 3. Speech rate proxy: count onset transitions (silence→speech) per second.
    int onsets = 0;
    for (int i = 1; i < isSpeech.length; i++) {
      if (isSpeech[i] && !isSpeech[i - 1]) onsets++;
    }
    final speechRate = onsets / durationSec; // syllable-group onsets/sec

    // 4. Pitch-variability proxy via ZCR spread over voiced frames (higher ZCR
    //    spread ≈ more pitch movement; a flat ZCR ≈ monotone delivery).
    final voicedZcr = <double>[];
    for (int i = 0; i < zcrs.length; i++) {
      if (isSpeech[i]) voicedZcr.add(zcrs[i]);
    }
    final pitchVariability = voicedZcr.length > 2
        ? _coefficientOfVariation(voicedZcr).clamp(0.0, 2.0)
        : 0.0;

    // 5. Energy (loudness) dynamics over voiced frames.
    final voicedE = <double>[];
    for (int i = 0; i < energies.length; i++) {
      if (isSpeech[i]) voicedE.add(energies[i]);
    }
    final energyVariability = voicedE.length > 2
        ? _coefficientOfVariation(voicedE).clamp(0.0, 3.0)
        : 0.0;

    // 6. Confidence - honest signal quality. Needs enough speech, a decent
    //    SNR (peak vs noise floor), and adequate duration.
    final snr = peakE / math.max(noiseFloor, 1e-9);
    final snrQ = (math.log(snr + 1) / math.log(50)).clamp(0.0, 1.0);
    final speechQ = (speechFrames / 50.0).clamp(0.0, 1.0);
    final durQ = ((durationSec - 3) / 7).clamp(0.0, 1.0);
    final confidence = (snrQ * 0.45 + speechQ * 0.35 + durQ * 0.20);

    if (confidence < 0.2 || speechFrames < 10) {
      return VoiceBiomarkerResult(
        usable: false,
        headline: 'Too quiet or noisy to read voice markers reliably.',
        confidence: confidence,
        notes: const [
          'Find a quiet room, hold the phone ~20 cm away, and speak naturally.'
        ],
      );
    }

    // 7. Marker score - combine the three classic low-mood acoustic markers.
    //    Slow speech, high pausing, and LOW pitch variability (monotone) all
    //    push the score up. Each term is bounded; the score is screening-grade.
    final slowness = (1.0 - (speechRate / 2.0)).clamp(0.0, 1.0); // <2 onsets/s
    final pausing = pauseRatio.clamp(0.0, 1.0);
    final monotone = (1.0 - (pitchVariability / 0.6)).clamp(0.0, 1.0);
    final markerScore =
        (slowness * 0.35 + pausing * 0.30 + monotone * 0.35).clamp(0.0, 1.0);

    String headline;
    if (markerScore >= 0.6) {
      headline =
          'Voice shows several low-mood acoustic markers (slow, monotone, long pauses).';
    } else if (markerScore >= 0.4) {
      headline = 'Some voice markers of low mood present - worth a check-in.';
    } else {
      headline = 'Voice acoustics within an expressive, typical range.';
    }

    return VoiceBiomarkerResult(
      usable: true,
      headline: headline,
      speechRate: double.parse(speechRate.toStringAsFixed(2)),
      pauseRatio: double.parse(pauseRatio.toStringAsFixed(2)),
      pitchVariability: double.parse(pitchVariability.toStringAsFixed(2)),
      energyVariability: double.parse(energyVariability.toStringAsFixed(2)),
      markerScore: double.parse(markerScore.toStringAsFixed(2)),
      confidence: double.parse(confidence.toStringAsFixed(2)),
      notes: [
        'Screening signal only - NOT a diagnosis of depression.',
        'Complements the transcript analysis; combine with how you actually feel.',
        if (markerScore >= 0.6 && confidence >= 0.4)
          'If low mood persists, please talk to someone - your linked doctor can help.',
      ],
    );
  }

  static double _coefficientOfVariation(List<double> xs) {
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    if (mean.abs() < 1e-12) return 0;
    double v = 0;
    for (final x in xs) {
      final d = x - mean;
      v += d * d;
    }
    return math.sqrt(v / xs.length) / mean.abs();
  }
}
