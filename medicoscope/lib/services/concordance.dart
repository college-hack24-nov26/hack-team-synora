import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/disease_risk_result.dart';

/// Cross-modality concordance for one disease - how strongly INDEPENDENT
/// detection methods agree. The headline differentiator of a multi-modal app:
/// a single screening can be wrong, but when several distinct modalities point
/// the same way, the finding is far more trustworthy - and we quantify that
/// honestly instead of just taking the loudest signal.
class DiseaseConcordance {
  final DiseaseType disease;
  final int modalityCount; // distinct methods that contributed
  final int agreeingCount; // distinct methods flagging >= moderate
  final double score; // 0..1 concordance
  final bool corroborated; // >=2 modalities AND score >= 0.5
  final RiskLevel topRisk;

  const DiseaseConcordance({
    required this.disease,
    required this.modalityCount,
    required this.agreeingCount,
    required this.score,
    required this.corroborated,
    required this.topRisk,
  });

  String get label => corroborated
      ? 'Corroborated by $agreeingCount of $modalityCount methods'
      : modalityCount >= 2
          ? 'Mixed signals across $modalityCount methods'
          : modalityCount == 1
              ? 'Single method only - not yet corroborated'
              : 'No screenings yet';
}

class Concordance {
  static int _rank(RiskLevel r) => switch (r) {
        RiskLevel.low => 0,
        RiskLevel.moderate => 1,
        RiskLevel.high => 2,
        RiskLevel.critical => 3,
      };

  /// Compute concordance for a disease from its recent results. We keep only
  /// the LATEST result per distinct method, so two readings from the same
  /// method don't masquerade as independent corroboration.
  static DiseaseConcordance forDisease(
    DiseaseType disease,
    List<DiseaseRiskResult> results,
  ) {
    final latestPerMethod = <DetectionMethod, DiseaseRiskResult>{};
    for (final r in results) {
      final existing = latestPerMethod[r.method];
      if (existing == null || r.timestamp.isAfter(existing.timestamp)) {
        latestPerMethod[r.method] = r;
      }
    }
    final distinct = latestPerMethod.values.toList();
    if (distinct.isEmpty) {
      return DiseaseConcordance(
        disease: disease,
        modalityCount: 0,
        agreeingCount: 0,
        score: 0,
        corroborated: false,
        topRisk: RiskLevel.low,
      );
    }

    final elevated =
        distinct.where((r) => _rank(r.risk) >= 1).toList(); // >= moderate
    final topRisk = distinct
        .map((r) => r.risk)
        .reduce((a, b) => _rank(a) >= _rank(b) ? a : b);

    double score = 0;
    if (distinct.length >= 2 && elevated.isNotEmpty) {
      final agreeFrac = elevated.length / distinct.length;
      final meanScore =
          elevated.map((r) => r.score).reduce((a, b) => a + b) / elevated.length;
      // Reward breadth of agreement AND evidence strength. A lone modality
      // scores 0 by design - no corroboration is claimed for single signals.
      score = (agreeFrac * (0.5 + 0.5 * meanScore)).clamp(0.0, 1.0);
    }

    return DiseaseConcordance(
      disease: disease,
      modalityCount: distinct.length,
      agreeingCount: elevated.length,
      score: double.parse(score.toStringAsFixed(2)),
      corroborated: distinct.length >= 2 && score >= 0.5,
      topRisk: topRisk,
    );
  }
}
