import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/disease_risk_result.dart';

class DiseaseAlert {
  final String id;
  final DiseaseType disease;
  final DetectionMethod method;
  final RiskLevel risk;
  final String headline;
  final String dataSource;
  final DateTime timestamp;
  final bool read;

  DiseaseAlert({
    required this.id,
    required this.disease,
    required this.method,
    required this.risk,
    required this.headline,
    required this.dataSource,
    required this.timestamp,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'disease': disease.name,
        'method': method.name,
        'risk': risk.label,
        'headline': headline,
        'dataSource': dataSource,
        'timestamp': timestamp.toIso8601String(),
        'read': read,
      };

  factory DiseaseAlert.fromJson(Map<String, dynamic> j) => DiseaseAlert(
        id: j['id'] ?? '',
        disease: DiseaseType.values
            .firstWhere((d) => d.name == j['disease'], orElse: () => DiseaseType.diabetes),
        method: DetectionMethod.values.firstWhere(
            (m) => m.name == j['method'],
            orElse: () => DetectionMethod.labReportPdf),
        risk: parseRiskLevel(j['risk']),
        headline: j['headline'] ?? '',
        dataSource: j['dataSource'] ?? '',
        timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
        read: j['read'] == true,
      );
}

/// Disease alerting uses the same semantic pipeline as vitals alerts:
///  • Store locally in SharedPreferences so patient / doctor see them instantly.
///  • Best-effort push to the backend's mental_health/notifications endpoint
///    (same data shape — "urgency" + "patientId" + "clinicalReport") so
///    doctors see them in the existing notifications center.
class DiseaseAlertService {
  static const _key = 'disease_alerts';
  static const _maxStored = 50;

  /// Convert a risk level to the mental-health notification urgency field.
  static String _urgency(RiskLevel r) {
    switch (r) {
      case RiskLevel.critical:
        return 'high';
      case RiskLevel.high:
        return 'high';
      case RiskLevel.moderate:
        return 'moderate';
      case RiskLevel.low:
        return 'low';
    }
  }

  /// Only fire an alert for high / critical results.
  static bool _shouldAlert(DiseaseRiskResult r) =>
      r.risk == RiskLevel.high || r.risk == RiskLevel.critical;

  /// Persist locally. Returns the stored DiseaseAlert.
  static Future<DiseaseAlert> _storeLocally(DiseaseRiskResult r) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    final alert = DiseaseAlert(
      id: '${r.disease.name}_${r.method.name}_${r.timestamp.millisecondsSinceEpoch}',
      disease: r.disease,
      method: r.method,
      risk: r.risk,
      headline: r.headline,
      dataSource: r.dataSource,
      timestamp: r.timestamp,
    );
    raw.insert(0, jsonEncode(alert.toJson()));
    if (raw.length > _maxStored) raw.removeRange(_maxStored, raw.length);
    await prefs.setStringList(_key, raw);
    return alert;
  }

  /// Entry point — called by every disease method screen after saving
  /// the result. High / critical results create an alert + doctor notify.
  static Future<DiseaseAlert?> maybeAlert({
    required DiseaseRiskResult result,
    required String patientId,
    required String patientName,
    String? doctorId,
  }) async {
    if (!_shouldAlert(result)) return null;
    final alert = await _storeLocally(result);

    // Best-effort doctor notification via the existing backend endpoint.
    // We format the disease result as a clinical report string so the
    // doctor's notifications screen can display it alongside mental-health
    // notifications — no backend changes required.
    if (doctorId != null && doctorId.isNotEmpty) {
      try {
        final clinical = _buildClinicalReport(result);
        await http
            .post(
              Uri.parse('${ApiConstants.baseUrl}/mental-health/notifications'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'doctorId': doctorId,
                'patientId': patientId,
                'patientName': patientName,
                'clinicalReport': clinical,
                'urgency': _urgency(result.risk),
                'transcript':
                    '[Auto] ${DiseaseRegistry.of(result.disease).title} screening via ${MethodRegistry.of(result.method).title}',
                'source': 'disease_screening_${result.disease.name}',
              }),
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Offline / server down — local alert is still stored.
      }
    }
    return alert;
  }

  static String _buildClinicalReport(DiseaseRiskResult r) {
    final buf = StringBuffer();
    buf.writeln('MedicoScope Auto-Screening Report');
    buf.writeln('Disease: ${DiseaseRegistry.of(r.disease).title}');
    buf.writeln('Method: ${MethodRegistry.of(r.method).title}');
    buf.writeln('Risk: ${r.risk.label} (score ${(r.score * 100).toStringAsFixed(0)}%)');
    buf.writeln('Headline: ${r.headline}');
    buf.writeln('Data source: ${r.dataSource}');
    if (r.findings.isNotEmpty) {
      buf.writeln('\nKey findings:');
      for (final f in r.findings) {
        buf.writeln('  • ${f.name} ${f.value} ${f.unit} (${f.flag}) — ${f.interpretation}');
      }
    }
    if (r.recommendations.isNotEmpty) {
      buf.writeln('\nRecommendations:');
      for (final rec in r.recommendations) {
        buf.writeln('  • $rec');
      }
    }
    if (r.llmExplanation != null && r.llmExplanation!.isNotEmpty) {
      buf.writeln('\nMedicoScope AI notes:\n${r.llmExplanation}');
    }
    return buf.toString();
  }

  static Future<List<DiseaseAlert>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return raw
        .map((s) {
          try {
            return DiseaseAlert.fromJson(
                Map<String, dynamic>.from(jsonDecode(s) as Map));
          } catch (_) {
            return null;
          }
        })
        .whereType<DiseaseAlert>()
        .toList();
  }

  static Future<int> unreadCount() async {
    final all = await getAll();
    return all.where((a) => !a.read).length;
  }

  static Future<void> markAllRead() async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    final updated = all.map((a) => DiseaseAlert(
          id: a.id,
          disease: a.disease,
          method: a.method,
          risk: a.risk,
          headline: a.headline,
          dataSource: a.dataSource,
          timestamp: a.timestamp,
          read: true,
        ));
    await prefs.setStringList(
        _key, updated.map((a) => jsonEncode(a.toJson())).toList());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Minimal-fields variant used by legacy modalities (skin scan, heart
  /// sound, OG vitals alerts) that don't build a full DiseaseRiskResult.
  /// Only sends to the backend — no local store write.
  static Future<void> sendGenericAlert({
    required String doctorId,
    required String patientId,
    required String patientName,
    required String clinicalReport,
    required String urgency,
    required String source,
  }) async {
    if (doctorId.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/mental-health/notifications'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'doctorId': doctorId,
              'patientId': patientId,
              'patientName': patientName,
              'clinicalReport': clinicalReport,
              'urgency': urgency,
              'transcript': '[Auto] MedicoScope screening — $source',
              'source': source,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}
