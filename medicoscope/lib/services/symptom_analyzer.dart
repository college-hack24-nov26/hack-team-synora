import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/data/symptom_questions.dart';
import 'package:medicoscope/models/disease_risk_result.dart';

/// Weighted symptom scoring engine. For each question the user answered 'yes',
/// we add the question's weight. A 'sometimes' answer counts for 0.5 weight.
class SymptomAnalyzer {
  static DiseaseRiskResult analyze({
    required DiseaseType disease,
    required Map<String, double> answers, // id -> 0, 0.5, or 1
    String? freeText,
  }) {
    final bank = SymptomQuestionBank.byDisease[disease]!;
    double totalWeight = 0;
    double maxWeight = 0;
    final triggered = <String>[];
    bool criticalFlag = false;

    for (final q in bank) {
      maxWeight += q.weight;
      final ans = answers[q.id] ?? 0.0;
      if (ans > 0) {
        totalWeight += q.weight * ans;
        if (ans >= 1.0 && q.weight >= 0.9) triggered.add(q.text);
      }
      if (freeText != null && q.redFlags.isNotEmpty) {
        for (final rf in q.redFlags) {
          if (freeText.toLowerCase().contains(rf.toLowerCase())) {
            criticalFlag = true;
          }
        }
      }
    }

    final score = maxWeight == 0 ? 0.0 : (totalWeight / maxWeight).clamp(0.0, 1.0);
    RiskLevel risk;
    if (criticalFlag && score >= 0.4) {
      risk = RiskLevel.critical;
    } else if (score >= 0.7) {
      risk = RiskLevel.high;
    } else if (score >= 0.4) {
      risk = RiskLevel.moderate;
    } else {
      risk = RiskLevel.low;
    }

    final findings = <MarkerFinding>[];
    for (final q in bank) {
      final ans = answers[q.id] ?? 0;
      final flag = ans >= 1.0
          ? (q.weight >= 0.9 ? 'high' : 'low')
          : ans > 0
              ? 'low'
              : 'normal';
      findings.add(MarkerFinding(
        name: _shortLabel(q.text),
        value: ans >= 1.0 ? 'Yes' : (ans > 0 ? 'Sometimes' : 'No'),
        unit: '',
        referenceRange: 'weight ${q.weight.toStringAsFixed(1)}',
        flag: flag,
        interpretation: q.text,
      ));
    }

    return DiseaseRiskResult(
      disease: disease,
      method: DetectionMethod.symptomQuestionnaire,
      risk: risk,
      score: score,
      headline: _headline(disease, risk),
      findings: findings,
      topContributors: triggered.take(3).toList(),
      recommendations: _recommendations(disease, risk),
      dataSource: 'Validated clinical questionnaire + ICMR / ADA guidance',
      timestamp: DateTime.now(),
    );
  }

  static String _shortLabel(String q) {
    // Trim to a short marker-like name (first 3 words)
    final words = q.replaceAll(RegExp(r'[?.]'), '').split(' ');
    return words.take(4).join(' ');
  }

  static String _headline(DiseaseType d, RiskLevel r) {
    final disease = DiseaseRegistry.of(d).title.toLowerCase();
    switch (r) {
      case RiskLevel.critical:
        return 'Reported red-flag symptoms for $disease — urgent evaluation advised.';
      case RiskLevel.high:
        return 'Symptom pattern is consistent with HIGH risk for $disease.';
      case RiskLevel.moderate:
        return 'Some symptoms align with $disease — consider screening labs.';
      case RiskLevel.low:
        return 'Symptom burden for $disease is low right now.';
    }
  }

  static List<String> _recommendations(DiseaseType d, RiskLevel r) {
    final recs = <String>[];
    if (r == RiskLevel.critical) {
      recs.add('URGENT: See a clinician today — red-flag symptoms reported.');
    } else if (r == RiskLevel.high) {
      recs.add('URGENT: Book a consult with a ${DiseaseRegistry.of(d).title} specialist this week.');
    }
    switch (d) {
      case DiseaseType.diabetes:
        recs.add('Confirm with an HbA1c or Fasting Blood Sugar test');
        recs.add('Track water intake & urination frequency for 7 days');
        break;
      case DiseaseType.hypertension:
        recs.add('Take home BP readings morning & evening for 7 days');
        recs.add('Reduce sodium intake and increase potassium-rich foods');
        break;
      case DiseaseType.anemia:
        recs.add('Get a CBC (Complete Blood Count) and ferritin test');
        recs.add('Include iron-rich foods + vitamin C with meals');
        break;
    }
    return recs;
  }
}
