import 'package:flutter/material.dart';

/// A live rolling waveform from mic levels (each 0..1). Reusable across the
/// respiratory and MindSpace capture screens.
class LiveWaveform extends StatelessWidget {
  final List<double> levels;
  final Color color;
  final double height;
  const LiveWaveform(this.levels,
      {super.key, this.color = const Color(0xFF7C4DFF), this.height = 46});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _WavePainter(levels, color)),
      );
}

class _WavePainter extends CustomPainter {
  final List<double> levels;
  final Color color;
  _WavePainter(this.levels, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    const cap = 60;
    final barW = size.width / cap;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW * 0.6;
    final mid = size.height / 2;
    final start = levels.length > cap ? levels.length - cap : 0;
    for (int i = start; i < levels.length; i++) {
      final x = (i - start) * barW + barW / 2;
      final h = (levels[i] * size.height * 0.9).clamp(2.0, size.height);
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}

/// Static average-spectrum bars (each 0..1) - a mini spectrogram of a clip.
/// [highlightFrom]/[highlightTo] tint a bin range brighter (e.g. a diagnostic band).
class SpectrumBars extends StatelessWidget {
  final List<double> spectrum;
  final Color color;
  final double height;
  final int highlightFrom;
  final int highlightTo;
  const SpectrumBars(this.spectrum,
      {super.key,
      this.color = const Color(0xFF7C4DFF),
      this.height = 70,
      this.highlightFrom = -1,
      this.highlightTo = -1});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
            painter:
                _SpectrumPainter(spectrum, color, highlightFrom, highlightTo)),
      );
}

class _SpectrumPainter extends CustomPainter {
  final List<double> spectrum;
  final Color color;
  final int hlFrom;
  final int hlTo;
  _SpectrumPainter(this.spectrum, this.color, this.hlFrom, this.hlTo);

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrum.isEmpty) return;
    final barW = size.width / spectrum.length;
    for (int i = 0; i < spectrum.length; i++) {
      final h = (spectrum[i] * size.height).clamp(1.0, size.height);
      final highlighted = hlFrom >= 0 && i >= hlFrom && i <= hlTo;
      final paint = Paint()
        ..color = highlighted ? color : color.withValues(alpha: .45);
      canvas.drawRect(
        Rect.fromLTWH(i * barW, size.height - h, barW * 0.85, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) => false;
}
