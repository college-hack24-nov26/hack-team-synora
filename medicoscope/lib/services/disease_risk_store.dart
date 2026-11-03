import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/disease_risk_result.dart';

/// Local store for disease risk results. Keeps the 20 most recent per disease
/// and exposes accessors for the unified dashboard + chatbot context builder.
class DiseaseRiskStore {
  static const _maxPerDisease = 20;
  static String _key(DiseaseType d) => 'disease_risk_${d.name}';

  static Future<void> save(DiseaseRiskResult r) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(r.disease)) ?? [];
    raw.insert(0, r.toJsonString());
    if (raw.length > _maxPerDisease) raw.removeRange(_maxPerDisease, raw.length);
    await prefs.setStringList(_key(r.disease), raw);
  }

  static Future<List<DiseaseRiskResult>> getAll(DiseaseType d) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(d)) ?? const [];
    return raw
        .map((s) {
          try {
            return DiseaseRiskResult.fromJson(
                Map<String, dynamic>.from(jsonDecode(s) as Map));
          } catch (_) {
            return null;
          }
        })
        .whereType<DiseaseRiskResult>()
        .toList();
  }

  static Future<DiseaseRiskResult?> latest(DiseaseType d) async {
    final all = await getAll(d);
    return all.isEmpty ? null : all.first;
  }

  /// All diseases in one shot — used by the unified dashboard.
  static Future<Map<DiseaseType, DiseaseRiskResult?>> latestAll() async {
    final out = <DiseaseType, DiseaseRiskResult?>{};
    for (final d in DiseaseType.values) {
      out[d] = await latest(d);
    }
    return out;
  }

  /// Compact summary used when building the chatbot context so the LLM
  /// knows everything the user has measured.
  static Future<String> chatbotSummary() async {
    final map = await latestAll();
    final lines = <String>[];
    for (final entry in map.entries) {
      final r = entry.value;
      if (r == null) continue;
      lines.add(
        '${DiseaseRegistry.of(entry.key).title}: '
        '${r.risk.label} risk (score ${(r.score * 100).toStringAsFixed(0)}%) '
        'via ${MethodRegistry.of(r.method).title} — ${r.headline}',
      );
    }
    if (lines.isEmpty) return '';
    return 'Recent chronic-disease screenings:\n${lines.join('\n')}';
  }

  static Future<void> clear(DiseaseType d) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(d));
  }
}
