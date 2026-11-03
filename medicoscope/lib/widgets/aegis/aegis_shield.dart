import 'package:flutter/material.dart';

/// Animated AEGIS shield: a glyph inside concentric rings that pulse outward.
/// Reused in the Live Consult hero / idle state / verdict reveal and the Console
/// header. Respects reduced-motion (renders static rings when animations are off).
class AegisShield extends StatefulWidget {
  final double size;
  final Color color;
  final bool pulsing;
  final IconData icon;
  const AegisShield({
    super.key,
    this.size = 64,
    this.color = const Color(0xFF7EA68C),
    this.pulsing = true,
    this.icon = Icons.verified_user_rounded,
  });

  @override
  State<AegisShield> createState() => _AegisShieldState();
}

class _AegisShieldState extends State<AegisShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.pulsing && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void didUpdateWidget(covariant AegisShield old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.pulsing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return CustomPaint(
            painter: _RingsPainter(_c.value, widget.color, widget.pulsing),
            child: Center(
              child: Container(
                width: s * 0.52,
                height: s * 0.52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color,
                      Color.lerp(widget.color, Colors.black, 0.28)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: widget.color.withValues(alpha: .45),
                        blurRadius: 16,
                        spreadRadius: 1),
                  ],
                ),
                child: Icon(widget.icon,
                    color: Colors.white, size: s * 0.28),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  final bool pulsing;
  _RingsPainter(this.t, this.color, this.pulsing);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final baseR = maxR * 0.28;
    // Two staggered expanding rings.
    for (int i = 0; i < 2; i++) {
      final phase = pulsing ? ((t + i * 0.5) % 1.0) : 0.35;
      final r = baseR + (maxR - baseR) * phase;
      final alpha = pulsing ? (1.0 - phase).clamp(0.0, 1.0) * 0.5 : 0.28;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, r, paint);
    }
    // Soft static halo.
    canvas.drawCircle(
      center,
      baseR * 1.35,
      Paint()..color = color.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) =>
      old.t != t || old.color != color || old.pulsing != pulsing;
}
