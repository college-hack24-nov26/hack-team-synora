import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Signal-quality verdict for a PPG capture.
enum PpgQuality { good, fair, poor }

/// Extracted PPG features. This is the honest, signal-derived output that the
/// BP estimator and the personal-calibration model consume. Every field here is
/// computed from the real waveform (no hardcoded numbers).
class PpgFeatures {
  final PpgQuality quality;
  final String reason; // human-readable quality explanation / rejection reason

  final double hrBpm; // fused spectral + time-domain heart rate
  final double hrvRmssd; // ms
  final double sqi; // 0..1 signal-quality index (spectral + template)
  final double perfusionIndex; // AC/DC %, real perfusion
  final int nBeats;

  // Morphology (from the ensemble-averaged beat) - the physiology BP leans on.
  final double upstrokeTimeMs; // foot -> systolic peak
  final double pulseWidthMs; // width at half systolic amplitude
  final double reflectionIndex; // dicrotic/systolic amplitude ratio (0..1)
  final double augmentationIndex; // (inflection/peak) proxy, arterial stiffness
  final double sdppgRatioBA; // second-derivative b/a wave ratio (aging index)

  const PpgFeatures({
    required this.quality,
    required this.reason,
    required this.hrBpm,
    required this.hrvRmssd,
    required this.sqi,
    required this.perfusionIndex,
    required this.nBeats,
    required this.upstrokeTimeMs,
    required this.pulseWidthMs,
    required this.reflectionIndex,
    required this.augmentationIndex,
    required this.sdppgRatioBA,
  });

  bool get usable => quality != PpgQuality.poor;

  /// Compact feature vector persisted at calibration time and diffed at
  /// estimation time. Keep the keys stable - the calibration store depends on them.
  Map<String, double> toVector() => {
        'hr': hrBpm,
        'ri': reflectionIndex,
        'ai': augmentationIndex,
        'upstroke': upstrokeTimeMs,
        'width': pulseWidthMs,
        'sdppgBA': sdppgRatioBA,
        'perfusion': perfusionIndex,
      };

  factory PpgFeatures.poor(String reason) => PpgFeatures(
        quality: PpgQuality.poor,
        reason: reason,
        hrBpm: 0,
        hrvRmssd: 0,
        sqi: 0,
        perfusionIndex: 0,
        nBeats: 0,
        upstrokeTimeMs: 0,
        pulseWidthMs: 0,
        reflectionIndex: 0,
        augmentationIndex: 0,
        sdppgRatioBA: 0,
      );
}

/// Advanced PPG signal processing for cuff-less BP screening.
///
/// Pipeline (all real, no fabricated numbers):
///   1. Resample the raw red-channel series onto a uniform grid (removes the
///      frame-drop error where fps was back-computed from frame count).
///   2. Zero-phase Butterworth band-pass (0.5-8 Hz) via forward-backward biquads.
///   3. FFT (fftea) -> spectral heart rate + a spectral signal-quality index
///      (in-band cardiac power / total power).
///   4. Beat delineation (feet + systolic peaks) -> time-domain HR, HRV, and a
///      template-correlation SQI.
///   5. Ensemble-average one clean beat -> morphology features (upstroke time,
///      pulse width, reflection index, augmentation index, SDPPG b/a).
class PpgSignal {
  static const double targetFs = 30.0; // uniform analysis rate (Hz)
  static const double hrLo = 0.7; // 42 bpm
  static const double hrHi = 3.5; // 210 bpm

  /// [raw] = red-channel mean per frame. [timestampsMs] = capture time of each
  /// frame in ms (preferred; enables true resampling). [nominalFps] is a
  /// fallback when timestamps are absent.
  static PpgFeatures extract({
    required List<double> raw,
    List<double>? timestampsMs,
    double nominalFps = 30.0,
  }) {
    if (raw.length < 30) {
      return PpgFeatures.poor(
          'Not enough frames captured. Hold your finger steady on the lens and flash.');
    }

    // DC level (mean brightness) before any filtering - needed for perfusion.
    double dc = 0;
    for (final v in raw) {
      dc += v;
    }
    dc /= raw.length;
    if (dc.abs() < 1e-6) dc = 1.0;

    // 1. Resample to a uniform grid at targetFs.
    final resampled = _resample(raw, timestampsMs, nominalFps, targetFs);
    if (resampled.length < targetFs * 4) {
      return PpgFeatures.poor(
          'Signal too short after cleanup. Hold still for the full capture.');
    }

    // Trim 1.5 s transient at each end (finger settling / release).
    final cut = (targetFs * 1.5).round();
    if (resampled.length - 2 * cut < targetFs * 4) {
      return PpgFeatures.poor('Too much of the capture was unstable. Try again, holding still.');
    }
    final trimmed = resampled.sublist(cut, resampled.length - cut);

    // 2. Zero-phase Butterworth band-pass 0.5-8 Hz.
    var bp = _biquadFiltFilt(trimmed, targetFs, 0.5, isHighPass: true);
    bp = _biquadFiltFilt(bp, targetFs, 8.0, isHighPass: false);

    // Amplitude (robust) + weak-signal gate.
    final stats = _meanStd(bp);
    if (stats.$2 < 0.15) {
      return PpgFeatures.poor(
          'Pulse too weak to read. Press your fingertip firmly over BOTH the camera lens and the flash.');
    }
    final acAmp = _percentileRange(bp, 0.05, 0.95);
    final perfusion = (acAmp / dc.abs() * 100).clamp(0.0, 20.0);

    // 3. Spectral HR + spectral SQI via FFT.
    final spec = _spectral(bp, targetFs);
    if (spec.hr <= 0) {
      return PpgFeatures.poor('No clear cardiac rhythm found. Rest your hand and hold completely still.');
    }

    // 4. Beat delineation.
    final peaks = _detectPeaks(bp, targetFs, acAmp);
    if (peaks.length < 4) {
      return PpgFeatures.poor(
          'Could not lock onto a steady pulse (need >= 4 beats). Keep steady pressure and do not move.');
    }
    final ibis = <double>[];
    for (int i = 1; i < peaks.length; i++) {
      final ibi = (peaks[i] - peaks[i - 1]) * 1000.0 / targetFs;
      if (ibi > 285 && ibi < 1500) ibis.add(ibi); // 40-210 bpm
    }
    if (ibis.length < 3) {
      return PpgFeatures.poor('Only a few clean beats detected. Try again, holding very still.');
    }
    ibis.sort();
    final medIbi = ibis[ibis.length ~/ 2];
    final cleanIbis =
        ibis.where((v) => v > medIbi * 0.6 && v < medIbi * 1.6).toList();
    final meanIbi = cleanIbis.reduce((a, b) => a + b) / cleanIbis.length;
    final hrTime = 60000.0 / meanIbi;

    // HRV RMSSD
    double rms = 0;
    int rc = 0;
    for (int i = 1; i < cleanIbis.length; i++) {
      final d = cleanIbis[i] - cleanIbis[i - 1];
      rms += d * d;
      rc++;
    }
    final hrv = rc > 0 ? math.sqrt(rms / rc) : 0.0;

    // Beat-regularity coefficient of variation.
    final cvMean = cleanIbis.reduce((a, b) => a + b) / cleanIbis.length;
    double cvVar = 0;
    for (final v in cleanIbis) {
      cvVar += (v - cvMean) * (v - cvMean);
    }
    final ibiCv = math.sqrt(cvVar / cleanIbis.length) / cvMean;

    // Fuse spectral + time-domain HR (they should agree on a good trace).
    final hr = (spec.hr * 0.5 + hrTime * 0.5);

    // 5. Ensemble-average one clean beat -> morphology + template SQI.
    final beat = _ensembleBeat(bp, peaks, targetFs);
    final templateSqi = beat == null ? 0.0 : _templateSqi(bp, peaks, beat);
    final morph = beat == null
        ? _Morph.empty()
        : _morphology(beat, targetFs);

    // Composite SQI: spectral purity, beat regularity, template match, length.
    final regQ = (1.0 - ibiCv * 3.0).clamp(0.0, 1.0);
    final lenQ = (cleanIbis.length / 15.0).clamp(0.0, 1.0);
    final sqi = (spec.sqi * 0.4 + templateSqi * 0.25 + regQ * 0.25 + lenQ * 0.1)
        .clamp(0.0, 1.0);

    PpgQuality quality;
    String reason;
    if (sqi >= 0.6 && perfusion >= 0.5) {
      quality = PpgQuality.good;
      reason = 'Strong, clean pulse.';
    } else if (sqi >= 0.4) {
      quality = PpgQuality.fair;
      reason = 'Usable pulse - firmer, stiller pressure would improve it.';
    } else {
      quality = PpgQuality.poor;
      reason = 'Marginal signal - press firmly over lens + flash and hold still.';
    }

    return PpgFeatures(
      quality: quality,
      reason: reason,
      hrBpm: hr,
      hrvRmssd: hrv,
      sqi: sqi,
      perfusionIndex: perfusion,
      nBeats: cleanIbis.length + 1,
      upstrokeTimeMs: morph.upstrokeMs,
      pulseWidthMs: morph.widthMs,
      reflectionIndex: morph.reflectionIndex,
      augmentationIndex: morph.augmentationIndex,
      sdppgRatioBA: morph.sdppgBA,
    );
  }

  // ── Resampling ──────────────────────────────────────────────────────────
  static List<double> _resample(
      List<double> raw, List<double>? tsMs, double nominalFps, double outFs) {
    // Build a monotonic time axis (ms) for the input samples.
    final n = raw.length;
    final List<double> t;
    if (tsMs != null && tsMs.length == n) {
      t = tsMs;
    } else {
      final dt = 1000.0 / (nominalFps <= 0 ? outFs : nominalFps);
      t = List<double>.generate(n, (i) => i * dt);
    }
    final t0 = t.first;
    final tEnd = t.last;
    final durMs = tEnd - t0;
    if (durMs <= 0) return List<double>.from(raw);
    final outN = (durMs / 1000.0 * outFs).floor();
    if (outN < 2) return List<double>.from(raw);
    final out = List<double>.filled(outN, 0);
    int j = 0;
    final step = 1000.0 / outFs;
    for (int i = 0; i < outN; i++) {
      final ti = t0 + i * step;
      while (j < n - 2 && t[j + 1] < ti) {
        j++;
      }
      final t1 = t[j], t2 = t[j + 1];
      final span = (t2 - t1);
      final frac = span.abs() < 1e-9 ? 0.0 : ((ti - t1) / span).clamp(0.0, 1.0);
      out[i] = raw[j] + (raw[j + 1] - raw[j]) * frac;
    }
    return out;
  }

  // ── Zero-phase 2nd-order Butterworth (RBJ biquad, filtfilt) ─────────────
  static List<double> _biquadFiltFilt(List<double> x, double fs, double f0,
      {required bool isHighPass}) {
    final w0 = 2 * math.pi * f0 / fs;
    final cw = math.cos(w0);
    final sw = math.sin(w0);
    const q = 0.70710678; // Butterworth
    final alpha = sw / (2 * q);
    double b0, b1, b2;
    final a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha;
    if (isHighPass) {
      b0 = (1 + cw) / 2;
      b1 = -(1 + cw);
      b2 = (1 + cw) / 2;
    } else {
      b0 = (1 - cw) / 2;
      b1 = 1 - cw;
      b2 = (1 - cw) / 2;
    }
    final nb0 = b0 / a0, nb1 = b1 / a0, nb2 = b2 / a0;
    final na1 = a1 / a0, na2 = a2 / a0;
    List<double> pass(List<double> input) {
      final out = List<double>.filled(input.length, 0);
      double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
      for (int i = 0; i < input.length; i++) {
        final xn = input[i];
        final yn = nb0 * xn + nb1 * x1 + nb2 * x2 - na1 * y1 - na2 * y2;
        out[i] = yn;
        x2 = x1;
        x1 = xn;
        y2 = y1;
        y1 = yn;
      }
      return out;
    }

    final fwd = pass(x);
    final rev = pass(fwd.reversed.toList());
    return rev.reversed.toList();
  }

  // ── FFT: spectral HR + in-band/total power SQI ──────────────────────────
  static ({double hr, double sqi}) _spectral(List<double> x, double fs) {
    // Next power of two >= length, zero-padded, Hann-windowed.
    int nfft = 1;
    while (nfft < x.length) {
      nfft <<= 1;
    }
    final buf = Float64List(nfft);
    for (int i = 0; i < x.length; i++) {
      final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (x.length - 1));
      buf[i] = x[i] * w;
    }
    final fft = FFT(nfft);
    final spec = fft.realFft(buf);
    final half = nfft ~/ 2 + 1;
    final freqRes = fs / nfft;
    double inBand = 0, total = 0, peakP = 0;
    double peakF = 0;
    for (int k = 1; k < half; k++) {
      final f = k * freqRes;
      if (f > 8.0) break;
      final re = spec[k].x, im = spec[k].y;
      final p = re * re + im * im;
      total += p;
      if (f >= hrLo && f <= hrHi) {
        inBand += p;
        if (p > peakP) {
          peakP = p;
          peakF = f;
        }
      }
    }
    if (total <= 0 || peakF <= 0) return (hr: 0.0, sqi: 0.0);
    return (hr: peakF * 60.0, sqi: (inBand / total).clamp(0.0, 1.0));
  }

  // ── Peak detection (adaptive threshold + refractory) ────────────────────
  static List<int> _detectPeaks(List<double> x, double fs, double amp) {
    final refractory = (0.3 * fs).round();
    double thr = amp * 0.4;
    List<int> find(double t) {
      final peaks = <int>[];
      for (int i = 2; i < x.length - 2; i++) {
        final v = x[i];
        if (v > t &&
            v > x[i - 1] &&
            v > x[i - 2] &&
            v >= x[i + 1] &&
            v >= x[i + 2]) {
          if (peaks.isEmpty || i - peaks.last > refractory) {
            peaks.add(i);
          } else if (v > x[peaks.last]) {
            peaks[peaks.length - 1] = i; // keep the taller of two close peaks
          }
        }
      }
      return peaks;
    }

    var peaks = find(thr);
    if (peaks.length < 4) peaks = find(amp * 0.2);
    return peaks;
  }

  // ── Ensemble-average beat (aligned on systolic peaks) ───────────────────
  static List<double>? _ensembleBeat(List<double> x, List<int> peaks, double fs) {
    if (peaks.length < 4) return null;
    final pre = (0.25 * fs).round();
    final post = (0.55 * fs).round();
    final len = pre + post;
    final acc = List<double>.filled(len, 0);
    int used = 0;
    for (final p in peaks) {
      if (p - pre < 0 || p + post >= x.length) continue;
      for (int k = 0; k < len; k++) {
        acc[k] += x[p - pre + k];
      }
      used++;
    }
    if (used < 3) return null;
    for (int k = 0; k < len; k++) {
      acc[k] /= used;
    }
    return acc;
  }

  static double _templateSqi(List<double> x, List<int> peaks, List<double> tmpl) {
    final pre = (tmpl.length * 0.31).round();
    final post = tmpl.length - pre;
    double sum = 0;
    int cnt = 0;
    for (final p in peaks) {
      if (p - pre < 0 || p + post >= x.length) continue;
      final seg = x.sublist(p - pre, p - pre + tmpl.length);
      final c = _corr(seg, tmpl);
      if (!c.isNaN) {
        sum += c.clamp(0.0, 1.0);
        cnt++;
      }
    }
    return cnt == 0 ? 0.0 : sum / cnt;
  }

  // ── Morphology from the ensemble beat ───────────────────────────────────
  static _Morph _morphology(List<double> beat, double fs) {
    // Foot = global min in the first third; systolic peak = global max.
    int peakIdx = 0;
    double peakVal = -1e9;
    for (int i = 0; i < beat.length; i++) {
      if (beat[i] > peakVal) {
        peakVal = beat[i];
        peakIdx = i;
      }
    }
    int footIdx = 0;
    double footVal = 1e9;
    for (int i = 0; i <= peakIdx; i++) {
      if (beat[i] < footVal) {
        footVal = beat[i];
        footIdx = i;
      }
    }
    final amp = (peakVal - footVal).abs();
    if (amp < 1e-6) return _Morph.empty();

    final upstrokeMs = (peakIdx - footIdx) * 1000.0 / fs;

    // Pulse width at half systolic amplitude.
    final halfLevel = footVal + amp * 0.5;
    int left = footIdx, right = beat.length - 1;
    for (int i = footIdx; i <= peakIdx; i++) {
      if (beat[i] >= halfLevel) {
        left = i;
        break;
      }
    }
    for (int i = peakIdx; i < beat.length; i++) {
      if (beat[i] <= halfLevel) {
        right = i;
        break;
      }
    }
    final widthMs = (right - left) * 1000.0 / fs;

    // Dicrotic notch / diastolic peak after the systolic peak -> reflection idx.
    // Search the descending limb for a local minimum (notch) then a rebound.
    int notchIdx = peakIdx;
    for (int i = peakIdx + 2; i < beat.length - 2; i++) {
      if (beat[i] < beat[i - 1] && beat[i] <= beat[i + 1]) {
        notchIdx = i;
        break;
      }
    }
    double diastolicPeak = beat[notchIdx];
    for (int i = notchIdx; i < beat.length; i++) {
      if (beat[i] > diastolicPeak) diastolicPeak = beat[i];
    }
    final reflectionIndex =
        ((diastolicPeak - footVal) / amp).clamp(0.0, 1.0);
    // Augmentation index proxy: notch height relative to systolic amplitude.
    final augmentationIndex =
        ((beat[notchIdx] - footVal) / amp).clamp(0.0, 1.0);

    // SDPPG b/a: second derivative early waves. a = first max, b = first min.
    final d2 = List<double>.filled(beat.length, 0);
    for (int i = 1; i < beat.length - 1; i++) {
      d2[i] = beat[i + 1] - 2 * beat[i] + beat[i - 1];
    }
    double aWave = 0;
    int aIdx = 1;
    for (int i = 1; i < peakIdx + 1 && i < beat.length - 1; i++) {
      if (d2[i] > aWave) {
        aWave = d2[i];
        aIdx = i;
      }
    }
    double bWave = 0;
    for (int i = aIdx; i < math.min(beat.length - 1, aIdx + (0.15 * fs).round()); i++) {
      if (d2[i] < bWave) bWave = d2[i];
    }
    final sdppgBA = aWave.abs() < 1e-9 ? 0.0 : (bWave / aWave);

    return _Morph(
      upstrokeMs: upstrokeMs,
      widthMs: widthMs,
      reflectionIndex: reflectionIndex,
      augmentationIndex: augmentationIndex,
      sdppgBA: sdppgBA,
    );
  }

  // ── small helpers ───────────────────────────────────────────────────────
  static (double, double) _meanStd(List<double> x) {
    double m = 0;
    for (final v in x) {
      m += v;
    }
    m /= x.length;
    double s = 0;
    for (final v in x) {
      s += (v - m) * (v - m);
    }
    return (m, math.sqrt(s / x.length));
  }

  static double _percentileRange(List<double> x, double lo, double hi) {
    final s = List<double>.from(x)..sort();
    final a = s[(s.length * lo).clamp(0, s.length - 1).toInt()];
    final b = s[(s.length * hi).clamp(0, s.length - 1).toInt()];
    return (b - a).abs();
  }

  static double _corr(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    double ma = 0, mb = 0;
    for (int i = 0; i < n; i++) {
      ma += a[i];
      mb += b[i];
    }
    ma /= n;
    mb /= n;
    double num = 0, da = 0, db = 0;
    for (int i = 0; i < n; i++) {
      final xa = a[i] - ma, xb = b[i] - mb;
      num += xa * xb;
      da += xa * xa;
      db += xb * xb;
    }
    final den = math.sqrt(da * db);
    return den < 1e-9 ? 0.0 : num / den;
  }
}

class _Morph {
  final double upstrokeMs;
  final double widthMs;
  final double reflectionIndex;
  final double augmentationIndex;
  final double sdppgBA;
  const _Morph({
    required this.upstrokeMs,
    required this.widthMs,
    required this.reflectionIndex,
    required this.augmentationIndex,
    required this.sdppgBA,
  });
  factory _Morph.empty() => const _Morph(
        upstrokeMs: 0,
        widthMs: 0,
        reflectionIndex: 0,
        augmentationIndex: 0,
        sdppgBA: 0,
      );
}
