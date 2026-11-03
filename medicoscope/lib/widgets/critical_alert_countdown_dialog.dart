import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';

class CriticalAlertCountdownDialog extends StatefulWidget {
  final String alertHeadline;
  final String alertSeverity;
  final String patientName;
  final VoidCallback onConfirmed;
  final VoidCallback onCancelled;
  final int countdownSeconds;

  const CriticalAlertCountdownDialog({
    super.key,
    required this.alertHeadline,
    required this.alertSeverity,
    required this.patientName,
    required this.onConfirmed,
    required this.onCancelled,
    this.countdownSeconds = 5,
  });

  @override
  State<CriticalAlertCountdownDialog> createState() =>
      _CriticalAlertCountdownDialogState();
}

class _CriticalAlertCountdownDialogState
    extends State<CriticalAlertCountdownDialog> with SingleTickerProviderStateMixin {
  late int _secondsRemaining;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.countdownSeconds;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        if (mounted) {
          widget.onConfirmed();
        }
      } else {
        if (mounted) {
          setState(() {
            _secondsRemaining--;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _secondsRemaining / widget.countdownSeconds;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1418) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.6),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.35),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated Pulse Badge
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF3B30).withValues(
                        alpha: 0.15 + (_pulseController.value * 0.15),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3B30).withValues(
                            alpha: 0.2 + (_pulseController.value * 0.3),
                          ),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.emergency_rounded,
                      color: Color(0xFFFF3B30),
                      size: 40,
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Title
              const Text(
                'EMERGENCY ALERT (SIMULATION)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: Color(0xFFFF3B30),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              // Alert Headline
              Text(
                widget.alertHeadline,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 20),

              // Decreasing Animated Countdown Circle
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 6,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF3B30),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_secondsRemaining',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFF3B30),
                        ),
                      )
                          .animate(key: ValueKey(_secondsRemaining))
                          .scale(begin: const Offset(1.3, 1.3), end: const Offset(1, 1), duration: 250.ms),
                      Text(
                        'SECONDS',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextDim
                              : AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Text(
                'Booking nearest emergency ambulance to your live location in $_secondsRemaining seconds...',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkTextDim : AppTheme.textGray,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),
              const Text(
                'Simulation mode only — no real ambulance or 108/911 service is contacted.',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Action Buttons: Cancel vs Book Now
              Row(
                children: [
                  // Cancel Option
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark
                            ? AppTheme.darkTextLight
                            : AppTheme.textDark,
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        _timer?.cancel();
                        widget.onCancelled();
                      },
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Approve / Book Now Option
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B30),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      icon: const Icon(Icons.flash_on_rounded, size: 18),
                      label: const Text(
                        'Book Now',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: () {
                        _timer?.cancel();
                        widget.onConfirmed();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

