import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/providers/coins_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/services/mental_health_service.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/screens/rewards/rewards_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';
import 'package:record/record.dart';

class MentalHealthScreen extends StatefulWidget {
  const MentalHealthScreen({super.key});

  @override
  State<MentalHealthScreen> createState() => _MentalHealthScreenState();
}

class _MentalHealthScreenState extends State<MentalHealthScreen>
    with TickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isProcessing = false;
  int _secondsLeft = 30;
  Timer? _countdownTimer;
  String? _responseText;
  int _coinsEarned = 0;
  bool _showCoins = false;
  String? _recordedPath;
  String _linkedDoctorId = '';

  // Pulse animation for mic button
  late AnimationController _pulseController;
  // Rotation animation for hourglass
  late AnimationController _hourglassController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _hourglassController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fetchLinkedDoctor();
  }

  Future<void> _fetchLinkedDoctor() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final api = ApiService(token: authProvider.token);
      final response = await api.get(ApiConstants.patientDoctor);
      if (response['doctor'] != null) {
        setState(() {
          _linkedDoctorId =
              response['doctor']['_id'] ?? response['doctor']['id'] ?? '';
        });
      }
    } catch (_) {
      // Patient may not have linked a doctor yet — that's ok
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _hourglassController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    // Explicit permission request — `record` will prompt on first use.
    final granted = await _recorder.hasPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Microphone permission is required for MindSpace. Open Settings → Apps → MedicoScope → Permissions and enable Microphone, then try again.'),
          backgroundColor: Color(0xFFFF5252),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/mind_checkin_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _secondsLeft = 30;
        _responseText = null;
        _showCoins = false;
        _recordedPath = path;
      });

      _pulseController.repeat();

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) {
          _stopRecording();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start recording: ${e.toString()}'),
          backgroundColor: const Color(0xFFFF5252),
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    _countdownTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });
    _hourglassController.repeat();

    await _analyzeAudio(path ?? _recordedPath ?? '');
  }

  Future<void> _analyzeAudio(String filePath) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final coinsProvider = Provider.of<CoinsProvider>(context, listen: false);
    final user = authProvider.user;

    // Defensive check: some Android OEMs return an empty/unreadable file
    // if the recording session terminated too fast. Bail with a clear error
    // instead of uploading garbage that Whisper will reject.
    if (filePath.isEmpty) {
      if (mounted) {
        setState(() {
          _responseText =
              'Recording failed — the audio file could not be saved. Please try again.';
          _isProcessing = false;
        });
      }
      return;
    }
    try {
      final f = await _getFileForPath(filePath);
      if (f == null || f == 0) {
        if (mounted) {
          setState(() {
            _responseText =
                'Recording was too short — please speak for at least a few seconds before stopping.';
            _isProcessing = false;
          });
        }
        return;
      }
    } catch (_) {}

    try {
      final result = await MentalHealthService.uploadAudio(
        filePath: filePath,
        patientId: user?.id ?? 'anonymous',
        patientName: user?.name ?? 'Unknown',
        doctorId: _linkedDoctorId,
      );

      final coins = result['coins_earned'] as int? ?? 0;

      _hourglassController.stop();
      _hourglassController.reset();
      setState(() {
        _responseText =
            result['user_message'] as String? ?? 'Thank you for sharing.';
        _coinsEarned = coins;
        _isProcessing = false;
      });

      if (coins > 0) {
        final totalEarned = await coinsProvider.addCoins(coins);
        await Future.delayed(const Duration(milliseconds: 500));
        setState(() {
          _coinsEarned = totalEarned;
          _showCoins = true;
        });
      }

      // Save session to DB
      if (authProvider.token != null) {
        MentalHealthService.saveSessionToDb(
          token: authProvider.token!,
          transcript: result['transcript'] as String? ?? '',
          userMessage: result['user_message'] as String? ?? '',
          doctorReport: result['doctor_report'] as String?,
          urgency: result['urgency'] as String? ?? 'low',
          coinsEarned: coins,
          doctorId: _linkedDoctorId.isNotEmpty ? _linkedDoctorId : null,
        );
      }
    } catch (e) {
      _hourglassController.stop();
      _hourglassController.reset();
      final errorMsg = e.toString();
      String displayMsg;
      if (errorMsg.contains('warming up') || errorMsg.contains('503')) {
        displayMsg =
            'The MindSpace service is warming up — please try again in a moment.';
      } else if (errorMsg.contains('TimeoutException') ||
          errorMsg.contains('timed out')) {
        displayMsg =
            'The analysis took too long. The server may be cold-starting — try again in ~30 seconds.';
      } else if (errorMsg.contains('429') ||
          errorMsg.toLowerCase().contains('rate limit')) {
        displayMsg =
            'The AI service has hit its daily free-tier quota. Please try again later.';
      } else {
        displayMsg =
            'Could not analyse your check-in. Please try again.\n(${errorMsg.replaceFirst("Exception: ", "")})';
      }
      if (mounted) {
        setState(() {
          _responseText = displayMsg;
          _isProcessing = false;
        });
      }
    }
  }

  /// Returns the file size in bytes, or null if the file doesn't exist.
  Future<int?> _getFileForPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final coinsProvider = Provider.of<CoinsProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                : [const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios),
                      color:
                          isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.get('mind_space', lang),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                          Text(
                            AppStrings.get('share_your_day', lang),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextGray
                                  : AppTheme.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Coins display — tappable to open rewards
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RewardsScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.stars_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '${coinsProvider.totalCoins}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(AppTheme.spacingLarge),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Prompt text
                      Text(
                        _isRecording
                            ? AppStrings.get('listening', lang)
                            : _isProcessing
                                ? AppStrings.get('analyzing', lang)
                                : AppStrings.get('how_was_your_day', lang),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextLight
                              : AppTheme.textDark,
                        ),
                      ).animate().fadeIn(duration: 400.ms),

                      const SizedBox(height: 8),

                      Text(
                        _isRecording
                            ? AppStrings.get('share_your_mind', lang)
                            : _isProcessing
                                ? AppStrings.get('give_moment', lang)
                                : AppStrings.get('tap_mic', lang),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? AppTheme.darkTextGray
                              : AppTheme.textGray,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Mic button with pulse animation
                      GestureDetector(
                        onTap: _isProcessing
                            ? null
                            : _isRecording
                                ? _stopRecording
                                : _startRecording,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final scale = _isRecording
                                ? 1.0 +
                                    0.08 * sin(_pulseController.value * 2 * pi)
                                : 1.0;
                            return Transform.scale(
                              scale: scale,
                              child: child,
                            );
                          },
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _isRecording
                                    ? [
                                        const Color(0xFFFF5252),
                                        const Color(0xFFD32F2F)
                                      ]
                                    : _isProcessing
                                        ? [
                                            const Color(0xFF9E9E9E),
                                            const Color(0xFF757575)
                                          ]
                                        : [
                                            const Color(0xFF7C4DFF),
                                            const Color(0xFF536DFE)
                                          ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isRecording
                                          ? const Color(0xFFFF5252)
                                          : const Color(0xFF7C4DFF))
                                      .withOpacity(0.4),
                                  blurRadius: _isRecording ? 30 : 20,
                                  spreadRadius: _isRecording ? 5 : 0,
                                ),
                              ],
                            ),
                            child: _isProcessing
                                ? RotationTransition(
                                    turns: _hourglassController,
                                    child: const Icon(
                                      Icons.hourglass_top_rounded,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  )
                                : Icon(
                                    _isRecording
                                        ? Icons.stop_rounded
                                        : Icons.mic_rounded,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Timer display
                      if (_isRecording)
                        Text(
                          '0:${_secondsLeft.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w300,
                            color: isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.textDark,
                          ),
                        ).animate().fadeIn(),

                      // Processing indicator
                      if (_isProcessing)
                        Column(
                          children: [
                            const SizedBox(height: 10),
                            Text(
                              AppStrings.get('listening_heart', lang),
                              style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: isDark
                                    ? AppTheme.darkTextGray
                                    : AppTheme.textGray,
                              ),
                            ).animate(onPlay: (c) => c.repeat()).shimmer(
                                  duration: 1500.ms,
                                  color: isDark
                                      ? Colors.white24
                                      : const Color(0xFF7C4DFF)
                                          .withOpacity(0.3),
                                ),
                          ],
                        ),

                      const SizedBox(height: 30),

                      // Coin animation
                      if (_showCoins && _coinsEarned > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                            ),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLarge),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withOpacity(0.3),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.stars_rounded,
                                  color: Colors.white, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                AppStrings.format('coins_earned', lang,
                                    {'coins': '$_coinsEarned'}),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 400.ms)
                            .scale(
                                begin: const Offset(0.5, 0.5),
                                end: const Offset(1, 1))
                            .then()
                            .shimmer(duration: 1200.ms, color: Colors.white38),

                      const SizedBox(height: 20),

                      // Response card
                      if (_responseText != null)
                        GlassCard(
                          padding: const EdgeInsets.all(AppTheme.spacingLarge),
                          borderRadius: AppTheme.radiusMedium,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF7C4DFF),
                                          Color(0xFF536DFE)
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.favorite_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    AppStrings.get('mindbot', lang),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? AppTheme.darkTextLight
                                          : AppTheme.textDark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _responseText!,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: isDark
                                      ? AppTheme.darkTextLight
                                      : AppTheme.textDark,
                                ),
                              ),
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 500.ms)
                            .slideY(begin: 0.1, end: 0),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
