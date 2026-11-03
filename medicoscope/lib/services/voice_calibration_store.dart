import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A saved personal "baseline voice" captured on a calm day, so later check-ins
/// can be judged against the user's OWN normal speech (e.g. "slower and more
/// monotone than your baseline") instead of a population assumption. Voice
/// affect is highly individual, so this is what makes the marker meaningful.
class VoiceCalibration {
  final Map<String, double> refFeatures; // VoiceFeatures.toVector() at baseline
  final DateTime timestamp;

  const VoiceCalibration({required this.refFeatures, required this.timestamp});

  Duration get age => DateTime.now().difference(timestamp);
  bool get isStale => age.inDays > 30;

  double get baselineF0 => refFeatures['f0'] ?? 0;
  double get baselineRate => refFeatures['rate'] ?? 0;

  Map<String, dynamic> toJson() => {
        'refFeatures': refFeatures,
        'timestamp': timestamp.toIso8601String(),
      };

  factory VoiceCalibration.fromJson(Map<String, dynamic> j) => VoiceCalibration(
        refFeatures: (j['refFeatures'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ) ??
            const {},
        timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
      );
}

/// Per-user local store for the voice baseline (shared_preferences).
class VoiceCalibrationStore {
  static String _key(String userId) =>
      'voice_calibration_${userId.isEmpty ? 'local' : userId}';

  static Future<void> save(String userId, VoiceCalibration c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), jsonEncode(c.toJson()));
  }

  static Future<VoiceCalibration?> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return VoiceCalibration.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }
}
