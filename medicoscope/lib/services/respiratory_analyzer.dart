import 'dart:math' as math;

import 'package:medicoscope/services/heart_audio_decoder.dart';

/// Result of respiratory acoustic screening. Its own domain (respiratory
/// distress), not the diabetes/hypertension/anemia deck.
class RespiratoryResult {
  final bool usable;
  final String headline;
  final double breathingRate; // breaths per minute (envelope-derived)
  final int coughCount; // sharp energy transients in the clip
  final double wheezeBandRatio; // hi-freq energy fraction (wheeze proxy)
  final double distressScore; // 0..1 - elevated respiratory-distress markers
  final double confidence; // 0..1 - honest signal-quality confidence
  final List<String> notes;

  const RespiratoryResult({
    required this.usable,
    required this.headline,
    this.breathingRate = 0,
    this.coughCount = 0,
    this.wheezeBandRatio = 0,
    this.distressScore = 0,
    this.confidence = 0,
    this.notes = const [],
  });

  Map<String, dynamic> toJson() => {
        'usable': usable,
        'headline': headline,
        'breathingRate': breathingRate,
        'coughCount': coughCount,
        'wheezeBandRatio': wheezeBandRatio,
        'distressScore': distressScore,
        'confidence': confidence,
        'notes': notes,
      };
}

/// Respiratory acoustic-screening analyzer.
///
/// HONESTY NOTE: this extracts REAL audio features from a breathing/cough
/// recording - breathing rate (from the low-frequency amplitude envelope),
/// cough-burst count (sharp energy transients), and a high-frequency energy
/// ratio used as a coarse wheeze proxy. These are screening signals associated
/// with respiratory distress in the acoustic literature (e.g. ResAppDx, cough
/// classification studies). It is NOT a diagnosis of asthma, COPD, or
/// pneumonia - it flags patterns worth a clinician's attention, with an honest
/// confidence. Reuses the same WAV decoder as the heart-sound pipeline.
class RespiratoryAnalyzer {
  // Resting adult breathing rate ≈ 12-20 bpm; > 20 = tachypnea (a distress sign).
  static const _tachypneaBpm = 20.0;

  static Future<RespiratoryResult> analyzeWavFile(String path) async {
    final audio = await HeartAudioDecoder.decodeWavFile(path);
    return analyze(audio.samples, audio.sampleRate);
  }

  static RespiratoryResult analyze(List<double> samples, int sampleRate) {
    final durationSec = samples.length / sampleRate;
    if (durationSec < 8) {
      return const RespiratoryResult(
        usable: false,
        headline: 'Recording too short - breathe near the mic for ~15 seconds.',
        notes: ['We need at least two full breaths to estimate a rate.'],
      );
    }

    // 1. Short-frame energy envelope (20 ms frames, 10 ms hop).
    final frameLen = (sampleRate * 0.020).round();
    final hop = (sampleRate * 0.010).round();
    if (frameLen < 8) {
      return const RespiratoryResult(
          usable: false, headline: 'Sample rate too low for respiratory analysis.');
    }
    final framesPerSec = sampleRate / hop;

    final env = <double>[];
    final hiEnergy = <double>[]; // high-frequency (ZCR-weighted) energy per frame
    for (int start = 0; start + frameLen <= samples.length; start += hop) {
      double e = 0;
      int zc = 0;
      for (int i = 0; i < frameLen; i++) {
        final s = samples[start + i];
        e += s * s;
        if (i > 0 && ((s >= 0) != (samples[start + i - 1] >= 0))) zc++;
      }
      final rms = math.sqrt(e / frameLen);
      env.add(rms);
      hiEnergy.add(rms * (zc / frameLen)); // energy in the higher band
    }
    if (env.length < 20) {
      return const RespiratoryResult(
          usable: false, headline: 'Not enough audio frames to analyze.');
    }

    // 2. Signal quality: SNR of the envelope (peak vs quietest decile).
    final sortedEnv = List<double>.from(env)..sort();
    final floor = sortedEnv[(sortedEnv.length * 0.10).floor()];
    final peak = sortedEnv[(sortedEnv.length * 0.95).floor()];
    final snr = peak / math.max(floor, 1e-9);
    if (snr < 2.0 || peak < 1e-4) {
      return RespiratoryResult(
        usable: false,
        headline: 'Too quiet/noisy to read breathing reliably.',
        confidence: ((math.log(snr + 1) / math.log(30))).clamp(0.0, 1.0),
        notes: const [
          'Breathe gently but audibly ~10 cm from the mic, in a quiet room.'
        ],
      );
    }

    // 3. Smooth the envelope to the breathing band (~0.1-0.7 Hz) with a long
    //    moving average, then count breath cycles as threshold up-crossings.
    final smoothWin = (framesPerSec * 0.7).round().clamp(3, 200);
    final breathEnv = _movingAverage(env, smoothWin);
    final bMean = breathEnv.reduce((a, b) => a + b) / breathEnv.length;
    int crossings = 0;
    bool above = false;
    int lastCrossFrame = -1000;
    final minGap = (framesPerSec * 1.0).round(); // ≥1 s between breaths (≤60 bpm)
    for (int i = 0; i < breathEnv.length; i++) {
      if (!above && breathEnv[i] > bMean * 1.05) {
        if (i - lastCrossFrame > minGap) {
          crossings++;
          lastCrossFrame = i;
        }
        above = true;
      } else if (above && breathEnv[i] < bMean * 0.95) {
        above = false;
      }
    }
    final breathingRate = crossings / durationSec * 60.0;

    // 4. Cough detection: sharp energy transients - a frame whose energy jumps
    //    far above the local envelope, separated by a refractory gap.
    int coughCount = 0;
    int lastCough = -1000;
    final coughGap = (framesPerSec * 0.4).round();
    for (int i = 1; i < env.length; i++) {
      if (env[i] > peak * 0.6 &&
          env[i] > breathEnv[i] * 3.0 &&
          i - lastCough > coughGap) {
        coughCount++;
        lastCough = i;
      }
    }

    // 5. Wheeze proxy: fraction of total energy in the high-frequency band.
    final totalE = env.fold<double>(0, (a, b) => a + b);
    final hiE = hiEnergy.fold<double>(0, (a, b) => a + b);
    final wheezeBandRatio = totalE > 0 ? (hiE / totalE).clamp(0.0, 1.0) : 0.0;

    // 6. Confidence.
    final snrQ = (math.log(snr + 1) / math.log(30)).clamp(0.0, 1.0);
    final durQ = ((durationSec - 8) / 12).clamp(0.0, 1.0);
    final cycleQ = (crossings / 4.0).clamp(0.0, 1.0); // ≥4 breaths = solid rate
    final confidence = (snrQ * 0.4 + durQ * 0.25 + cycleQ * 0.35);

    if (confidence < 0.25 || crossings < 2) {
      return RespiratoryResult(
        usable: false,
        headline: 'Could not lock onto a steady breathing rhythm.',
        confidence: confidence,
        notes: const [
          'Hold the phone close, breathe normally and audibly for ~15 seconds.'
        ],
      );
    }

    // 7. Distress score - tachypnea, frequent coughing, and elevated
    //    high-frequency (wheeze-band) energy each push the score up.
    final tachy = ((breathingRate - _tachypneaBpm) / 12.0).clamp(0.0, 1.0);
    final coughing = (coughCount / 5.0).clamp(0.0, 1.0);
    final wheeze = ((wheezeBandRatio - 0.25) / 0.35).clamp(0.0, 1.0);
    final distressScore =
        (tachy * 0.45 + coughing * 0.30 + wheeze * 0.25).clamp(0.0, 1.0);

    String headline;
    if (distressScore >= 0.6) {
      headline =
          'Several respiratory-distress markers (fast/laboured breathing, coughing).';
    } else if (distressScore >= 0.4) {
      headline = 'Some respiratory markers present - worth monitoring.';
    } else {
      headline = 'Breathing pattern within a typical resting range.';
    }

    return RespiratoryResult(
      usable: true,
      headline: headline,
      breathingRate: double.parse(breathingRate.toStringAsFixed(1)),
      coughCount: coughCount,
      wheezeBandRatio: double.parse(wheezeBandRatio.toStringAsFixed(2)),
      distressScore: double.parse(distressScore.toStringAsFixed(2)),
      confidence: double.parse(confidence.toStringAsFixed(2)),
      notes: [
        'Screening signal only - NOT a diagnosis of asthma, COPD, or pneumonia.',
        if (breathingRate > _tachypneaBpm)
          'Breathing rate ${breathingRate.toStringAsFixed(0)}/min is above the typical resting range.',
        if (distressScore >= 0.6 && confidence >= 0.4)
          'If you feel breathless or this persists, seek medical attention.',
      ],
    );
  }

  static List<double> _movingAverage(List<double> x, int win) {
    final n = x.length;
    if (win <= 1) return List<double>.from(x);
    final out = List<double>.filled(n, 0);
    final prefix = List<double>.filled(n + 1, 0);
    for (int i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + x[i];
    }
    final half = win ~/ 2;
    for (int i = 0; i < n; i++) {
      final lo = math.max(0, i - half);
      final hi = math.min(n - 1, i + half);
      out[i] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
    }
    return out;
  }
}
