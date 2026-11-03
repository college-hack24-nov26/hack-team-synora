import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A saved personal resting-breathing baseline, captured while the user is calm,
/// so later scans can be reported relative to THEIR normal (e.g. "6 breaths/min
/// above your resting rate") instead of a one-size population cutoff.
class RespiratoryCalibration {
  final double restingBpm;
  final Map<String, double> refFeatures; // RespiratoryFeatures.toVector() at calib
  final DateTime timestamp;

  const RespiratoryCalibration({
    required this.restingBpm,
    required this.refFeatures,
    required this.timestamp,
  });

  Duration get age => DateTime.now().difference(timestamp);
  bool get isStale => age.inDays > 30;

  Map<String, dynamic> toJson() => {
        'restingBpm': restingBpm,
        'refFeatures': refFeatures,
        'timestamp': timestamp.toIso8601String(),
      };

  factory RespiratoryCalibration.fromJson(Map<String, dynamic> j) =>
      RespiratoryCalibration(
        restingBpm: (j['restingBpm'] as num?)?.toDouble() ?? 14,
        refFeatures: (j['refFeatures'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ) ??
            const {},
        timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
      );
}

/// Per-user local store for the respiratory calibration (shared_preferences).
class RespiratoryCalibrationStore {
  static String _key(String userId) =>
      'resp_calibration_${userId.isEmpty ? 'local' : userId}';

  static Future<void> save(String userId, RespiratoryCalibration c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), jsonEncode(c.toJson()));
  }

  static Future<RespiratoryCalibration?> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return RespiratoryCalibration.fromJson(
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
