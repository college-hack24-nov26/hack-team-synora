import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import 'package:medicoscope/services/heart_audio_decoder.dart';

enum VoiceQuality { good, fair, poor }

/// Real, signal-derived voice acoustic features. Unlike the old analyzer (which
/// used a zero-crossing-rate coefficient of variation as a fake "pitch"), F0 is
/// measured by autocorrelation, and jitter/shimmer/HNR/spectral tilt are genuine
/// acoustic biomarkers used in the affective-speech literature. Screening only,
/// never a diagnosis.
class VoiceFeatures {
  final VoiceQuality quality;
  final String reason;

  final double f0Mean; // Hz, mean fundamental frequency over voiced frames
  final double f0Cv; // pitch variability (std/mean of F0), 0 = monotone
  final double jitterPct; // cycle-to-cycle F0 period perturbation, %
  final double shimmerPct; // cycle-to-cycle amplitude perturbation, %
  final double hnrDb; // harmonics-to-noise ratio, dB (voice clarity)
  final double speechRate; // voiced onsets per second (tempo proxy)
  final double pauseRatio; // fraction of frames that are silence
  final double energyCv; // loudness dynamics (std/mean of voiced energy)
  final double spectralCentroidHz; // brightness
  final double spectralTiltDb; // high vs low band energy (dB); flat = dull affect
  final int voicedFrames;

  final double sqi; // 0..1 overall signal quality
  final List<double> avgSpectrum; // mean 0..4 kHz spectrum for the mini-spectrogram

  const VoiceFeatures({
    required this.quality,
    required this.reason,
    required this.f0Mean,
    required this.f0Cv,
    required this.jitterPct,
    required this.shimmerPct,
    required this.hnrDb,
    required this.speechRate,
    required this.pauseRatio,
    required this.energyCv,
    required this.spectralCentroidHz,
    required this.spectralTiltDb,
    required this.voicedFrames,
    required this.sqi,
    required this.avgSpectrum,
  });

  bool get usable => quality != VoiceQuality.poor;

  /// Stable-key feature map for personal calibration (baseline vs later deltas).
  Map<String, double> toVector() => {
        'f0': f0Mean,
        'f0cv': f0Cv,
        'rate': speechRate,
        'pause': pauseRatio,
        'energyCv': energyCv,
        'hnr': hnrDb,
        'tilt': spectralTiltDb,
      };

  factory VoiceFeatures.poor(String reason) => VoiceFeatures(
        quality: VoiceQuality.poor,
        reason: reason,
        f0Mean: 0,
        f0Cv: 0,
        jitterPct: 0,
        shimmerPct: 0,
        hnrDb: 0,
        speechRate: 0,
        pauseRatio: 0,
        energyCv: 0,
        spectralCentroidHz: 0,
        spectralTiltDb: 0,
        voicedFrames: 0,
        sqi: 0,
        avgSpectrum: const [],
      );
}

/// On-device voice acoustic analysis (all real DSP):
///   - Autocorrelation F0 per voiced frame -> mean pitch + pitch variability,
///     jitter (period perturbation) and HNR (harmonics-to-noise).
///   - Frame amplitude perturbation -> shimmer.
///   - Energy-based VAD -> pause ratio + voiced-onset speech rate.
///   - FFT per frame -> spectral centroid + spectral tilt (affect flatness) and
///     an average spectrum for the mini-spectrogram.
class VoiceSignal {
  static const int analysisFs = 16000;
  static const double f0Lo = 75; // Hz
  static const double f0Hi = 400; // Hz

  static Future<VoiceFeatures> analyzeWavFile(String path) async {
    final a = await HeartAudioDecoder.decodeWavFile(path);
    return extract(samples: a.samples, sampleRate: a.sampleRate);
  }

  static VoiceFeatures extract({
    required List<double> samples,
    required int sampleRate,
  }) {
    // Resample to a fixed 16 kHz analysis rate.
    final x = HeartAudioDecoder.resample(
        Float32List.fromList(samples), sampleRate, analysisFs);
    final fs = analysisFs;
    final durationSec = x.length / fs;
    if (durationSec < 3) {
      return VoiceFeatures.poor(
          'Too short. Speak for at least a few seconds near the mic.');
    }

    final frameLen = (fs * 0.025).round(); // 25 ms
    final hop = (fs * 0.010).round(); // 10 ms
    final hann = List<double>.generate(
        frameLen, (i) => 0.5 - 0.5 * math.cos(2 * math.pi * i / (frameLen - 1)));

    final energies = <double>[];
    final frameStarts = <int>[];
    for (int s = 0; s + frameLen <= x.length; s += hop) {
      double e = 0;
      for (int i = 0; i < frameLen; i++) {
        final v = x[s + i];
        e += v * v;
      }
      energies.add(e / frameLen);
      frameStarts.add(s);
    }
    if (energies.length < 10) {
      return VoiceFeatures.poor('Not enough audio to analyze.');
    }

    // VAD: adaptive threshold between the noise floor and the loud peak.
    final sortedE = List<double>.from(energies)..sort();
    final noiseFloor = sortedE[(sortedE.length * 0.10).floor()];
    final peakE = sortedE[(sortedE.length * 0.95).floor()];
    final snr = peakE / math.max(noiseFloor, 1e-12);
    if (snr < 2.0 || peakE < 1e-6) {
      return VoiceFeatures.poor(
          'Too quiet or noisy. Speak clearly ~15 cm from the mic in a quiet room.');
    }
    final speechThresh = noiseFloor + (peakE - noiseFloor) * 0.15;
    final isSpeech = energies.map((e) => e > speechThresh).toList();
    int speechFrames = 0;
    for (final b in isSpeech) {
      if (b) speechFrames++;
    }
    if (speechFrames < 10) {
      return VoiceFeatures.poor('Not enough speech detected. Please speak a few sentences.');
    }
    final pauseRatio = 1.0 - speechFrames / isSpeech.length;

    int onsets = 0;
    for (int i = 1; i < isSpeech.length; i++) {
      if (isSpeech[i] && !isSpeech[i - 1]) onsets++;
    }
    final speechRate = onsets / durationSec;

    // Per voiced frame: F0 (autocorrelation), period, amplitude, HNR.
    final minLag = (fs / f0Hi).floor(); // 40 @16k
    final maxLag = (fs / f0Lo).ceil(); // 213 @16k
    final f0s = <double>[];
    final periods = <double>[]; // in samples
    final amps = <double>[];
    final hnrs = <double>[];
    for (int fi = 0; fi < frameStarts.length; fi++) {
      if (!isSpeech[fi]) continue;
      final s = frameStarts[fi];
      // Remove DC + measure amplitude.
      double mean = 0;
      for (int i = 0; i < frameLen; i++) {
        mean += x[s + i];
      }
      mean /= frameLen;
      double amp = 0;
      for (int i = 0; i < frameLen; i++) {
        amp += (x[s + i] - mean).abs();
      }
      amp /= frameLen;

      // Autocorrelation over the F0 lag range.
      double r0 = 0;
      for (int i = 0; i < frameLen; i++) {
        final v = x[s + i] - mean;
        r0 += v * v;
      }
      if (r0 < 1e-9) continue;
      double bestR = 0;
      int bestLag = 0;
      for (int lag = minLag; lag <= maxLag && lag < frameLen; lag++) {
        double r = 0;
        for (int i = 0; i + lag < frameLen; i++) {
          r += (x[s + i] - mean) * (x[s + i + lag] - mean);
        }
        if (r > bestR) {
          bestR = r;
          bestLag = lag;
        }
      }
      if (bestLag == 0) continue;
      final norm = bestR / r0; // 0..1 harmonicity
      // Only accept clearly-voiced frames (periodic) for F0/jitter/HNR.
      if (norm < 0.35) continue;
      f0s.add(fs / bestLag);
      periods.add(bestLag.toDouble());
      amps.add(amp);
      // HNR: harmonic (norm) vs noise (1-norm), in dB.
      hnrs.add(10 * (math.log(norm / math.max(1 - norm, 1e-6)) / math.ln10));
    }

    if (f0s.length < 5) {
      return VoiceFeatures.poor(
          'Could not track a stable voice pitch. Speak a bit louder and more steadily.');
    }

    final f0Mean = f0s.reduce((a, b) => a + b) / f0s.length;
    final f0Cv = _cv(f0s);
    // Jitter: mean |Ti - Ti-1| / mean T (period perturbation), percent.
    double jSum = 0;
    for (int i = 1; i < periods.length; i++) {
      jSum += (periods[i] - periods[i - 1]).abs();
    }
    final meanPeriod = periods.reduce((a, b) => a + b) / periods.length;
    final jitterPct =
        (periods.length > 1 ? (jSum / (periods.length - 1)) / meanPeriod : 0.0) *
            100;
    // Shimmer: mean |Ai - Ai-1| / mean A, percent.
    double shSum = 0;
    for (int i = 1; i < amps.length; i++) {
      shSum += (amps[i] - amps[i - 1]).abs();
    }
    final meanAmp = amps.reduce((a, b) => a + b) / amps.length;
    final shimmerPct =
        (amps.length > 1 && meanAmp > 0 ? (shSum / (amps.length - 1)) / meanAmp : 0.0) *
            100;
    final hnrDb = hnrs.isEmpty ? 0.0 : hnrs.reduce((a, b) => a + b) / hnrs.length;

    // Energy dynamics over voiced frames.
    final voicedE = <double>[];
    for (int i = 0; i < energies.length; i++) {
      if (isSpeech[i]) voicedE.add(energies[i]);
    }
    final energyCv = _cv(voicedE);

    // Spectral features via FFT over voiced frames.
    final spec = _spectral(x, frameStarts, isSpeech, hann, frameLen, fs);

    // Composite SQI.
    final snrQ = (math.log(snr + 1) / math.log(50)).clamp(0.0, 1.0);
    final voicedQ = (f0s.length / 40.0).clamp(0.0, 1.0);
    final durQ = ((durationSec - 3) / 9).clamp(0.0, 1.0);
    final sqi = (snrQ * 0.45 + voicedQ * 0.35 + durQ * 0.20).clamp(0.0, 1.0);

    VoiceQuality quality;
    String reason;
    if (sqi >= 0.55 && f0s.length >= 20) {
      quality = VoiceQuality.good;
      reason = 'Clear speech captured.';
    } else if (sqi >= 0.35) {
      quality = VoiceQuality.fair;
      reason = 'Usable, speak a little longer and clearer for a better read.';
    } else {
      return VoiceFeatures.poor(
          'Voice signal too weak to analyze. Speak clearly for a few sentences in a quiet room.');
    }

    return VoiceFeatures(
      quality: quality,
      reason: reason,
      f0Mean: f0Mean,
      f0Cv: f0Cv,
      jitterPct: jitterPct.clamp(0, 100),
      shimmerPct: shimmerPct.clamp(0, 100),
      hnrDb: hnrDb,
      speechRate: speechRate,
      pauseRatio: pauseRatio.clamp(0, 1),
      energyCv: energyCv,
      spectralCentroidHz: spec.centroid,
      spectralTiltDb: spec.tiltDb,
      voicedFrames: f0s.length,
      sqi: sqi,
      avgSpectrum: spec.viz,
    );
  }

  static ({double centroid, double tiltDb, List<double> viz}) _spectral(
      Float32List x,
      List<int> frameStarts,
      List<bool> isSpeech,
      List<double> hann,
      int frameLen,
      int fs) {
    int nfft = 1;
    while (nfft < frameLen) {
      nfft <<= 1;
    }
    final fft = FFT(nfft);
    final half = nfft ~/ 2 + 1;
    final freqRes = fs / nfft;
    final avg = List<double>.filled(half, 0);
    int n = 0;
    final buf = Float64List(nfft);
    for (int fi = 0; fi < frameStarts.length; fi++) {
      if (!isSpeech[fi]) continue;
      final s = frameStarts[fi];
      for (int i = 0; i < frameLen; i++) {
        buf[i] = x[s + i] * hann[i];
      }
      for (int i = frameLen; i < nfft; i++) {
        buf[i] = 0;
      }
      final sp = fft.realFft(buf);
      for (int k = 0; k < half; k++) {
        final re = sp[k].x, im = sp[k].y;
        avg[k] += re * re + im * im;
      }
      n++;
    }
    if (n == 0) return (centroid: 0, tiltDb: 0, viz: const []);
    for (int k = 0; k < half; k++) {
      avg[k] /= n;
    }
    // Spectral centroid.
    double num = 0, den = 0;
    for (int k = 1; k < half; k++) {
      final f = k * freqRes;
      num += f * avg[k];
      den += avg[k];
    }
    final centroid = den > 0 ? num / den : 0.0;
    // Spectral tilt: high band (1-4 kHz) vs low band (0-1 kHz) energy, dB.
    double lowE = 0, hiE = 0;
    for (int k = 1; k < half; k++) {
      final f = k * freqRes;
      if (f <= 1000) {
        lowE += avg[k];
      } else if (f <= 4000) {
        hiE += avg[k];
      }
    }
    final tiltDb = 10 * (math.log((hiE + 1e-12) / (lowE + 1e-12)) / math.ln10);
    // Downsample 0..4 kHz to 64 bins, normalized, for the viz.
    final hiBin = (4000 / freqRes).ceil().clamp(1, half - 1);
    final viz = _downsample(avg.sublist(0, hiBin), 64);
    final mx = viz.fold<double>(1e-12, (a, b) => math.max(a, b));
    for (int i = 0; i < viz.length; i++) {
      viz[i] = (viz[i] / mx).clamp(0.0, 1.0);
    }
    return (centroid: centroid, tiltDb: tiltDb, viz: viz);
  }

  static double _cv(List<double> x) {
    if (x.isEmpty) return 0;
    double m = 0;
    for (final v in x) {
      m += v;
    }
    m /= x.length;
    if (m.abs() < 1e-12) return 0;
    double s = 0;
    for (final v in x) {
      s += (v - m) * (v - m);
    }
    return math.sqrt(s / x.length) / m.abs();
  }

  static List<double> _downsample(List<double> x, int target) {
    if (x.length <= target) return List<double>.from(x);
    final out = List<double>.filled(target, 0);
    final bin = x.length / target;
    for (int i = 0; i < target; i++) {
      final s = (i * bin).floor();
      final e = ((i + 1) * bin).floor().clamp(s + 1, x.length);
      double mx = 0;
      for (int j = s; j < e; j++) {
        if (x[j] > mx) mx = x[j];
      }
      out[i] = mx;
    }
    return out;
  }
}
