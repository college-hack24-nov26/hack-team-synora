import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A saved personal BP calibration: a real cuff reading captured alongside a
/// clean PPG, so future estimates can be reported as (cuff baseline + measured
/// deltas) instead of a population guess. This is what turns a screening-grade
/// camera-PPG estimate into something close to the user's own cuff.
class BpCalibration {
  final double refSbp;
  final double refDbp;
  final Map<String, double> refFeatures; // PpgFeatures.toVector() at calib time
  final DateTime timestamp;

  const BpCalibration({
    required this.refSbp,
    required this.refDbp,
    required this.refFeatures,
    required this.timestamp,
  });

  /// Calibrations drift as the body changes; recommend re-calibrating monthly.
  Duration get age => DateTime.now().difference(timestamp);
  bool get isStale => age.inDays > 30;

  Map<String, dynamic> toJson() => {
        'refSbp': refSbp,
        'refDbp': refDbp,
        'refFeatures': refFeatures,
        'timestamp': timestamp.toIso8601String(),
      };

  factory BpCalibration.fromJson(Map<String, dynamic> j) => BpCalibration(
        refSbp: (j['refSbp'] as num?)?.toDouble() ?? 120,
        refDbp: (j['refDbp'] as num?)?.toDouble() ?? 80,
        refFeatures: (j['refFeatures'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ) ??
            const {},
        timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
      );
}

/// Per-user local store for the BP calibration (shared_preferences).
class BpCalibrationStore {
  static String _key(String userId) => 'bp_calibration_${userId.isEmpty ? 'local' : userId}';

  static Future<void> save(String userId, BpCalibration c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), jsonEncode(c.toJson()));
  }

  static Future<BpCalibration?> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return BpCalibration.fromJson(
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
