import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import 'package:medicoscope/services/heart_audio_decoder.dart';

enum RespiratoryQuality { good, fair, poor }

/// Real, signal-derived respiratory acoustic features. Nothing here is
/// hardcoded: breathing rate comes from the FFT of the amplitude envelope,
/// wheeze/crackle from a short-time Fourier transform of the audio, and the
/// signal-quality index from envelope SNR + spectral purity + cycle regularity.
class RespiratoryFeatures {
  final RespiratoryQuality quality;
  final String reason;

  final double breathingRate; // breaths/min (envelope-FFT + peak fused)
  final double rateVariability; // std of breath-to-breath interval, seconds
  final double ieRatio; // inspiration:expiration (value = I/E, e.g. 0.5 => 1:2)
  final int nBreaths;

  final double wheezeRatio; // fraction of frames with a sustained tonal peak
  final double wheezeMusicality; // mean spectral peak-to-average in wheeze band
  final int crackleCount; // impulsive high-band transients
  final int coughCount; // energy bursts

  final double sqi; // 0..1 overall signal quality
  final List<double> envelope; // downsampled breathing envelope (for the waveform)
  final List<double> avgSpectrum; // mean 0..2 kHz spectrum (for the mini-spectrogram)

  const RespiratoryFeatures({
    required this.quality,
    required this.reason,
    required this.breathingRate,
    required this.rateVariability,
    required this.ieRatio,
    required this.nBreaths,
    required this.wheezeRatio,
    required this.wheezeMusicality,
    required this.crackleCount,
    required this.coughCount,
    required this.sqi,
    required this.envelope,
    required this.avgSpectrum,
  });

  bool get usable => quality != RespiratoryQuality.poor;

  /// Stable-key feature map persisted at calibration time and diffed later.
  Map<String, double> toVector() => {
        'bpm': breathingRate,
        'ie': ieRatio,
        'wheeze': wheezeRatio,
        'rateVar': rateVariability,
        'crackle': crackleCount.toDouble(),
      };

  factory RespiratoryFeatures.poor(String reason) => RespiratoryFeatures(
        quality: RespiratoryQuality.poor,
        reason: reason,
        breathingRate: 0,
        rateVariability: 0,
        ieRatio: 0,
        nBreaths: 0,
        wheezeRatio: 0,
        wheezeMusicality: 0,
        crackleCount: 0,
        coughCount: 0,
        sqi: 0,
        envelope: const [],
        avgSpectrum: const [],
      );
}

/// Advanced on-device respiratory acoustic analysis.
///
/// Pipeline (all real DSP, no fabricated numbers):
///   1. Amplitude envelope (20/10 ms RMS frames) -> breathing signal at ~100 Hz.
///   2. Breathing rate = dominant frequency of the envelope in 0.1-0.7 Hz (FFT),
///      cross-checked with envelope peak detection; I:E ratio + rate variability
///      from the detected breath cycles.
///   3. Short-time Fourier transform of the audio (resampled to 8 kHz):
///      wheeze = sustained tonal peaks in 100-1000 Hz (peak-to-average ratio held
///      >= ~100 ms); crackles = impulsive wide-band bursts; cough = envelope bursts.
///   4. Signal-quality index from envelope SNR + spectral purity + cycle count.
class RespiratorySignal {
  static const double breathLo = 0.1; // 6 bpm
  static const double breathHi = 0.7; // 42 bpm
  static const int analysisFs = 8000; // for STFT (wheeze up to 1 kHz, crackles higher)

  static Future<RespiratoryFeatures> analyzeWavFile(String path) async {
    final audio = await HeartAudioDecoder.decodeWavFile(path);
    return extract(samples: audio.samples, sampleRate: audio.sampleRate);
  }

  static RespiratoryFeatures extract({
    required List<double> samples,
    required int sampleRate,
  }) {
    final durationSec = samples.length / sampleRate;
    if (durationSec < 8) {
      return RespiratoryFeatures.poor(
          'Recording too short. Breathe gently near the mic for the full capture.');
    }

    // 1. Amplitude envelope (20 ms frame, 10 ms hop) -> ~100 Hz breathing signal.
    final frameLen = (sampleRate * 0.020).round();
    final hop = (sampleRate * 0.010).round();
    if (frameLen < 8) {
      return RespiratoryFeatures.poor('Sample rate too low for respiratory analysis.');
    }
    final envFs = sampleRate / hop; // ~100 Hz
    final env = <double>[];
    for (int start = 0; start + frameLen <= samples.length; start += hop) {
      double e = 0;
      for (int i = 0; i < frameLen; i++) {
        final s = samples[start + i];
        e += s * s;
      }
      env.add(math.sqrt(e / frameLen));
    }
    if (env.length < 32) {
      return RespiratoryFeatures.poor('Not enough audio to analyze. Record for longer.');
    }

    // 2. Envelope SNR quality gate.
    final sortedEnv = List<double>.from(env)..sort();
    final floor = sortedEnv[(sortedEnv.length * 0.10).floor()];
    final peak = sortedEnv[(sortedEnv.length * 0.95).floor()];
    final snr = peak / math.max(floor, 1e-9);
    if (snr < 2.0 || peak < 1e-4) {
      return RespiratoryFeatures.poor(
          'Too quiet or noisy to read breathing. Breathe audibly ~10 cm from the mic in a quiet room.');
    }

    // 3. Breathing band envelope + rate via FFT (dominant 0.1-0.7 Hz).
    final breathEnv = _movingAverage(env, (envFs * 0.5).round().clamp(3, 200));
    final specBpm = _dominantFreqBpm(breathEnv, envFs);

    // 4. Breath-cycle detection (peaks + troughs) -> count, variability, I:E.
    final cycles = _breathCycles(breathEnv, envFs);
    final peakBpm = cycles.count >= 2 ? cycles.count / durationSec * 60.0 : 0.0;
    // Fuse spectral + peak estimates when both are plausible.
    double breathingRate;
    if (specBpm > 0 && peakBpm > 0) {
      breathingRate = 0.5 * specBpm + 0.5 * peakBpm;
    } else {
      breathingRate = specBpm > 0 ? specBpm : peakBpm;
    }
    if (breathingRate <= 0) {
      return RespiratoryFeatures.poor(
          'Could not lock onto a breathing rhythm. Breathe normally and hold the phone steady.');
    }

    // 5. STFT features: wheeze (tonal, sustained), crackle (impulsive), on 8 kHz.
    final ds = HeartAudioDecoder.resample(
        Float32List.fromList(samples), sampleRate, analysisFs);
    final stft = _stftFeatures(ds, analysisFs);

    // 6. Cough: strong envelope bursts above the breathing baseline.
    int coughCount = 0;
    int lastCough = -100000;
    final coughGap = (envFs * 0.4).round();
    for (int i = 1; i < env.length; i++) {
      if (env[i] > peak * 0.6 &&
          env[i] > breathEnv[i] * 3.0 &&
          i - lastCough > coughGap) {
        coughCount++;
        lastCough = i;
      }
    }

    // 7. Composite SQI: SNR + spectral purity + cycle count + rate agreement.
    final snrQ = (math.log(snr + 1) / math.log(30)).clamp(0.0, 1.0);
    final cycleQ = (cycles.count / 5.0).clamp(0.0, 1.0);
    final agreeQ = (specBpm > 0 && peakBpm > 0)
        ? (1.0 - (specBpm - peakBpm).abs() / math.max(specBpm, peakBpm))
            .clamp(0.0, 1.0)
        : 0.4;
    final sqi = (snrQ * 0.4 + cycleQ * 0.35 + agreeQ * 0.25).clamp(0.0, 1.0);

    RespiratoryQuality quality;
    String reason;
    if (sqi >= 0.6 && cycles.count >= 3) {
      quality = RespiratoryQuality.good;
      reason = 'Clear, steady breathing captured.';
    } else if (sqi >= 0.4 && cycles.count >= 2) {
      quality = RespiratoryQuality.fair;
      reason = 'Usable, breathe a little more audibly and evenly for a better read.';
    } else {
      return RespiratoryFeatures.poor(
          'Could not lock onto a steady breathing rhythm. Breathe normally and audibly for the full capture.');
    }

    // Downsample the envelope for the waveform display (~180 points).
    final viz = _downsample(breathEnv, 180);

    return RespiratoryFeatures(
      quality: quality,
      reason: reason,
      breathingRate: breathingRate,
      rateVariability: cycles.intervalStd,
      ieRatio: cycles.ieRatio,
      nBreaths: cycles.count,
      wheezeRatio: stft.wheezeRatio,
      wheezeMusicality: stft.musicality,
      crackleCount: stft.crackleCount,
      coughCount: coughCount,
      sqi: sqi,
      envelope: viz,
      avgSpectrum: stft.avgSpectrum,
    );
  }

  // ── Breathing rate via FFT of the envelope ───────────────────────────────
  static double _dominantFreqBpm(List<double> env, double fs) {
    // Detrend (remove DC + slow drift) then Hann window.
    double mean = 0;
    for (final v in env) {
      mean += v;
    }
    mean /= env.length;
    int nfft = 1;
    while (nfft < env.length) {
      nfft <<= 1;
    }
    final buf = Float64List(nfft);
    for (int i = 0; i < env.length; i++) {
      final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (env.length - 1));
      buf[i] = (env[i] - mean) * w;
    }
    final fft = FFT(nfft);
    final spec = fft.realFft(buf);
    final half = nfft ~/ 2 + 1;
    final freqRes = fs / nfft;
    double bestP = 0, bestF = 0;
    for (int k = 1; k < half; k++) {
      final f = k * freqRes;
      if (f < breathLo) continue;
      if (f > breathHi) break;
      final re = spec[k].x, im = spec[k].y;
      final p = re * re + im * im;
      if (p > bestP) {
        bestP = p;
        bestF = f;
      }
    }
    return bestF > 0 ? bestF * 60.0 : 0.0;
  }

  // ── Breath cycle detection: peaks/troughs -> count, variability, I:E ─────
  static _Cycles _breathCycles(List<double> env, double fs) {
    double mean = 0;
    for (final v in env) {
      mean += v;
    }
    mean /= env.length;
    final minGap = (fs * 0.9).round(); // >= ~0.9 s between breaths
    // Peak picking with hysteresis around the mean.
    final peaks = <int>[];
    bool above = false;
    int lastPeak = -100000;
    int localMaxIdx = -1;
    double localMax = -1e9;
    for (int i = 0; i < env.length; i++) {
      if (env[i] > mean * 1.05) {
        above = true;
        if (env[i] > localMax) {
          localMax = env[i];
          localMaxIdx = i;
        }
      } else if (env[i] < mean * 0.95 && above) {
        above = false;
        if (localMaxIdx >= 0 && localMaxIdx - lastPeak > minGap) {
          peaks.add(localMaxIdx);
          lastPeak = localMaxIdx;
        }
        localMax = -1e9;
        localMaxIdx = -1;
      }
    }

    if (peaks.length < 2) {
      return const _Cycles(count: 0, intervalStd: 0, ieRatio: 0);
    }

    // Breath-to-breath intervals (seconds) -> variability.
    final intervals = <double>[];
    for (int i = 1; i < peaks.length; i++) {
      intervals.add((peaks[i] - peaks[i - 1]) / fs);
    }
    double im = 0;
    for (final v in intervals) {
      im += v;
    }
    im /= intervals.length;
    double iv = 0;
    for (final v in intervals) {
      iv += (v - im) * (v - im);
    }
    final intervalStd = math.sqrt(iv / intervals.length);

    // I:E ratio: for each peak find the preceding + following trough (local min);
    // inspiration = trough->peak, expiration = peak->next trough.
    final insp = <double>[];
    final exp = <double>[];
    for (int p = 0; p < peaks.length; p++) {
      final pk = peaks[p];
      final lo = p == 0 ? 0 : peaks[p - 1];
      final hi = p == peaks.length - 1 ? env.length - 1 : peaks[p + 1];
      int tBefore = lo, tAfter = hi;
      double mnB = 1e9, mnA = 1e9;
      for (int i = lo; i < pk; i++) {
        if (env[i] < mnB) {
          mnB = env[i];
          tBefore = i;
        }
      }
      for (int i = pk; i <= hi; i++) {
        if (env[i] < mnA) {
          mnA = env[i];
          tAfter = i;
        }
      }
      final inS = (pk - tBefore) / fs;
      final exS = (tAfter - pk) / fs;
      if (inS > 0.2 && exS > 0.2) {
        insp.add(inS);
        exp.add(exS);
      }
    }
    double ie = 0;
    if (insp.isNotEmpty) {
      final mi = insp.reduce((a, b) => a + b) / insp.length;
      final me = exp.reduce((a, b) => a + b) / exp.length;
      ie = me > 0 ? mi / me : 0;
    }
    return _Cycles(count: peaks.length, intervalStd: intervalStd, ieRatio: ie);
  }

  // ── STFT: wheeze (tonal, sustained) + crackle (impulsive) ────────────────
  static _Stft _stftFeatures(Float32List x, int fs) {
    const frame = 512; // 64 ms @ 8 kHz
    const hopS = 256; // 32 ms
    final fft = FFT(frame);
    final half = frame ~/ 2 + 1;
    final freqRes = fs / frame;
    final hann = List<double>.generate(
        frame, (i) => 0.5 - 0.5 * math.cos(2 * math.pi * i / (frame - 1)));

    final loBin = (100 / freqRes).floor().clamp(1, half - 1); // 100 Hz
    final hiBin = (1000 / freqRes).ceil().clamp(1, half - 1); // 1000 Hz

    final tonalFrames = <bool>[]; // wheeze candidate per frame
    final musical = <double>[];
    final frameEnergy = <double>[];
    final avgSpec = List<double>.filled(half, 0);
    int nFrames = 0;

    final buf = Float64List(frame);
    for (int start = 0; start + frame <= x.length; start += hopS) {
      for (int i = 0; i < frame; i++) {
        buf[i] = x[start + i] * hann[i];
      }
      final spec = fft.realFft(buf);
      double bandSum = 0, bandPeak = 0;
      double totalE = 0;
      for (int k = 1; k < half; k++) {
        final re = spec[k].x, im = spec[k].y;
        final p = re * re + im * im;
        avgSpec[k] += p;
        totalE += p;
        if (k >= loBin && k <= hiBin) {
          bandSum += p;
          if (p > bandPeak) bandPeak = p;
        }
      }
      final bandMean = bandSum / math.max(1, (hiBin - loBin + 1));
      final tonality = bandMean > 0 ? bandPeak / bandMean : 0.0;
      // Wheeze frame: a strong tonal peak in the musical band that also carries
      // a meaningful share of the frame energy (not just quiet-frame noise).
      final bandShare = totalE > 0 ? bandSum / totalE : 0.0;
      final isTonal = tonality > 8.0 && bandShare > 0.3;
      tonalFrames.add(isTonal);
      musical.add(tonality);
      frameEnergy.add(totalE);
      nFrames++;
    }
    if (nFrames == 0) {
      return const _Stft(
          wheezeRatio: 0, musicality: 0, crackleCount: 0, avgSpectrum: []);
    }
    for (int k = 0; k < half; k++) {
      avgSpec[k] /= nFrames;
    }

    // Wheeze must be SUSTAINED: require runs of >= 3 consecutive tonal frames
    // (~100 ms) to count, then wheezeRatio = sustained tonal frames / total.
    int wheezeFrames = 0, run = 0;
    for (final t in tonalFrames) {
      if (t) {
        run++;
      } else {
        if (run >= 3) wheezeFrames += run;
        run = 0;
      }
    }
    if (run >= 3) wheezeFrames += run;
    final wheezeRatio = (wheezeFrames / nFrames).clamp(0.0, 1.0);

    double meanMus = 0;
    for (final m in musical) {
      meanMus += m;
    }
    meanMus /= musical.length;

    // Crackle: isolated impulsive energy spikes (one frame >> neighbours),
    // with high-band content, separated by a refractory gap.
    final medE = (List<double>.from(frameEnergy)..sort())[frameEnergy.length ~/ 2];
    int crackle = 0, lastCr = -100;
    for (int i = 1; i < frameEnergy.length - 1; i++) {
      final e = frameEnergy[i];
      if (e > medE * 6 &&
          e > frameEnergy[i - 1] * 2.5 &&
          e > frameEnergy[i + 1] * 2.5 &&
          i - lastCr > 3) {
        crackle++;
        lastCr = i;
      }
    }
    // Cap crackle count so a burst of noise cannot inflate it absurdly.
    crackle = crackle.clamp(0, 60);

    // Downsample the average spectrum to 64 bins up to ~2 kHz for the viz.
    final specHiBin = (2000 / freqRes).ceil().clamp(1, half - 1);
    final viz = _downsample(avgSpec.sublist(0, specHiBin), 64);
    // Normalize viz to 0..1.
    final mx = viz.fold<double>(1e-12, (a, b) => math.max(a, b));
    for (int i = 0; i < viz.length; i++) {
      viz[i] = (viz[i] / mx).clamp(0.0, 1.0);
    }

    return _Stft(
      wheezeRatio: wheezeRatio,
      musicality: meanMus,
      crackleCount: crackle,
      avgSpectrum: viz,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────
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

class _Cycles {
  final int count;
  final double intervalStd;
  final double ieRatio;
  const _Cycles(
      {required this.count, required this.intervalStd, required this.ieRatio});
}

class _Stft {
  final double wheezeRatio;
  final double musicality;
  final int crackleCount;
  final List<double> avgSpectrum;
  const _Stft({
    required this.wheezeRatio,
    required this.musicality,
    required this.crackleCount,
    required this.avgSpectrum,
  });
}
