import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/providers/coins_provider.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/services/disease_alert_service.dart';
import 'package:medicoscope/services/disease_risk_store.dart';

/// One-line helper every disease method screen calls after analysis.
/// Persists the result locally AND fires a doctor alert for high/critical.
class DiseaseResultPipeline {
  static String? _cachedDoctorId;

  /// Publicly-exposed doctor-id resolver so legacy modalities (skin, heart,
  /// OG vitals) can use the same cached lookup.
  static Future<String?> resolveDoctorIdFor(String? token) =>
      _resolveDoctorId(token);

  static Future<String?> _resolveDoctorId(String? token) async {
    if (_cachedDoctorId != null) return _cachedDoctorId;
    if (token == null) return null;
    try {
      final api = ApiService(token: token);
      final data = await api.get(ApiConstants.patientDoctor);
      final doctor = data['doctor'];
      if (doctor is Map<String, dynamic>) {
        final id = doctor['userId']?.toString() ?? doctor['_id']?.toString();
        if (id != null && id.isNotEmpty) {
          _cachedDoctorId = id;
          return id;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> persist(
    BuildContext context,
    DiseaseRiskResult result,
  ) async {
    await DiseaseRiskStore.save(result);

    // Award MindCoins for the detection (rate-limited: once per modality per day).
    try {
      final coins = Provider.of<CoinsProvider>(context, listen: false);
      final modality = '${result.disease.name}_${result.method.name}';
      await coins.addDetectionCoins(modality: modality, amount: 10);
    } catch (_) {}

    // Fire alert for high/critical — best effort, won't throw.
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    if (user == null) return;
    final patientId = user.id;
    final patientName = user.name;
    final doctorId = await _resolveDoctorId(auth.token);
    await DiseaseAlertService.maybeAlert(
      result: result,
      patientId: patientId,
      patientName: patientName,
      doctorId: doctorId,
    );
  }

  /// Legacy flows (skin scan, heart sound, OG vitals session) use this to
  /// award coins without going through the full disease-risk pipeline.
  /// Rate-limited to once per modality per day by CoinsProvider.
  static Future<int> awardCoinsOnly(
    BuildContext context, {
    required String modality,
    int amount = 10,
  }) async {
    try {
      final coins = Provider.of<CoinsProvider>(context, listen: false);
      return await coins.addDetectionCoins(modality: modality, amount: amount);
    } catch (_) {
      return 0;
    }
  }

  /// Unused import guard — keeps DiseaseRegistry available for callers.
  static String diseaseTitle(DiseaseType d) => DiseaseRegistry.of(d).title;
}
