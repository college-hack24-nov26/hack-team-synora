import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/services/voice_biomarker_analyzer.dart';
import 'package:medicoscope/services/respiratory_analyzer.dart';
import 'package:medicoscope/services/respiratory_signal.dart';

/// Synthetic-waveform unit tests for the on-device acoustic analyzers. These
/// verify the HONEST-by-construction behaviour: garbage in → rejected (not
/// scored), and a structured signal → usable with physiologically sane metrics.
/// No audio files needed — analyzers accept raw samples.

List<double> _silence(int n) => List<double>.filled(n, 0);

/// White-ish noise (deterministic seed so tests are stable).
List<double> _noise(int n, {double amp = 0.02, int seed = 7}) {
  final r = math.Random(seed);
  return List<double>.generate(n, (_) => (r.nextDouble() * 2 - 1) * amp);
}

/// A voiced-speech-like signal: a carrier tone, amplitude-modulated into
/// syllable bursts, with silent gaps (pauses) between bursts.
List<double> _speechLike(int sampleRate, double seconds,
    {double burstHz = 2.0, double carrierHz = 180}) {
  final n = (sampleRate * seconds).round();
  final out = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final t = i / sampleRate;
    // Syllable envelope: on for ~60% of each burst cycle, off (pause) otherwise.
    final phase = (t * burstHz) % 1.0;
    final voiced = phase < 0.6 ? 1.0 : 0.0;
    final carrier = math.sin(2 * math.pi * carrierHz * t);
    out[i] = voiced * carrier * 0.5;
  }
  return out;
}

/// A breathing-like signal: slow amplitude envelope (breaths) modulating a
/// broadband hiss (air through airways).
List<double> _breathingLike(int sampleRate, double seconds,
    {double breathHz = 0.3, int seed = 3}) {
  final n = (sampleRate * seconds).round();
  final r = math.Random(seed);
  final out = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final t = i / sampleRate;
    // Breathing envelope 0..1.
    final env = (math.sin(2 * math.pi * breathHz * t) * 0.5 + 0.5);
    final hiss = (r.nextDouble() * 2 - 1);
    out[i] = env * hiss * 0.4;
  }
  return out;
}

void main() {
  group('VoiceBiomarkerAnalyzer', () {
    const sr = 16000;

    test('rejects a too-short clip', () {
      final r = VoiceBiomarkerAnalyzer.analyze(_speechLike(sr, 1.0), sr);
      expect(r.usable, isFalse);
    });

    test('rejects silence (no voice) rather than scoring it', () {
      final r = VoiceBiomarkerAnalyzer.analyze(_silence(sr * 8), sr);
      expect(r.usable, isFalse);
      // Never fabricates a marker score for an unusable clip.
      expect(r.markerScore, 0);
    });

    test('produces a usable, bounded result for speech-like audio', () {
      final r = VoiceBiomarkerAnalyzer.analyze(_speechLike(sr, 10.0), sr);
      expect(r.usable, isTrue);
      expect(r.markerScore, inInclusiveRange(0.0, 1.0));
      expect(r.confidence, inInclusiveRange(0.0, 1.0));
      expect(r.pauseRatio, inInclusiveRange(0.0, 1.0));
      expect(r.speechRate, greaterThan(0));
    });

    test('confidence is never NaN/Inf', () {
      final r = VoiceBiomarkerAnalyzer.analyze(_speechLike(sr, 8.0), sr);
      expect(r.confidence.isFinite, isTrue);
      expect(r.markerScore.isFinite, isTrue);
    });
  });

  group('RespiratorySignal / RespiratoryAnalyzer', () {
    const sr = 16000;

    test('rejects a too-short clip', () {
      final f = RespiratorySignal.extract(
          samples: _breathingLike(sr, 4.0), sampleRate: sr);
      expect(f.usable, isFalse);
    });

    test('rejects near-silence rather than scoring it', () {
      final f = RespiratorySignal.extract(
          samples: _noise(sr * 15, amp: 0.0005), sampleRate: sr);
      expect(f.usable, isFalse);
    });

    test('usable, bounded, plausible features for breathing-like audio', () {
      final f = RespiratorySignal.extract(
          samples: _breathingLike(sr, 16.0), sampleRate: sr);
      expect(f.usable, isTrue);
      expect(f.breathingRate, greaterThan(0));
      expect(f.breathingRate, lessThan(60));
      expect(f.wheezeRatio, inInclusiveRange(0.0, 1.0));
      expect(f.sqi, inInclusiveRange(0.0, 1.0));
      expect(f.breathingRate.isFinite, isTrue);
    });

    test('analyzer maps usable features to a respiratory DiseaseRiskResult', () {
      final f = RespiratorySignal.extract(
          samples: _breathingLike(sr, 16.0), sampleRate: sr);
      final r = RespiratoryAnalyzer.analyze(features: f);
      expect(r.disease, DiseaseType.respiratory);
      expect(r.method, DetectionMethod.respiratoryAcoustic);
      expect(r.findings, isNotEmpty);
      expect(r.score, inInclusiveRange(0.0, 1.0));
    });

    test('poor signal yields an empty (non-scored) result', () {
      final f = RespiratorySignal.extract(
          samples: _noise(sr * 15, amp: 0.0005), sampleRate: sr);
      final r = RespiratoryAnalyzer.analyze(features: f);
      expect(r.findings, isEmpty);
      expect(r.score, 0);
    });
  });
}
