import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/services/health_connect_service.dart';

/// Converts a wearable snapshot (real or simulated) into a disease risk result.
/// Uses AHA, ADA and WHO clinical thresholds.
class VitalsAnalyzer {
  static DiseaseRiskResult analyze({
    required DiseaseType disease,
    required WearableSnapshot snapshot,
    required bool isSimulated,
  }) {
    final findings = <MarkerFinding>[];
    final contributors = <String>[];
    double totalScore = 0;
    int counted = 0;

    double addFinding({
      required String name,
      required double? value,
      required String unit,
      required String referenceRange,
      required String Function(double) interpret,
      double? lowCut,
      double? highWarn,
      double? highCritical,
    }) {
      if (value == null || value == 0) return 0;
      String flag;
      double weight;
      if (highCritical != null && value >= highCritical) {
        flag = 'critical';
        weight = 0.95;
      } else if (highWarn != null && value >= highWarn) {
        flag = 'high';
        weight = 0.6;
      } else if (lowCut != null && value < lowCut) {
        flag = 'low';
        weight = 0.45;
      } else {
        flag = 'normal';
        weight = 0;
      }
      findings.add(MarkerFinding(
        name: name,
        value: value.toStringAsFixed(1),
        unit: unit,
        referenceRange: referenceRange,
        flag: flag,
        interpretation: interpret(value),
      ));
      counted += 1;
      totalScore += weight;
      if (weight >= 0.5) contributors.add('$name: ${value.toStringAsFixed(1)} $unit');
      return weight;
    }

    switch (disease) {
      case DiseaseType.diabetes:
        addFinding(
          name: 'Resting Heart Rate',
          value: snapshot.restingHeartRate,
          unit: 'bpm',
          referenceRange: '60–80 bpm typical',
          highWarn: 85,
          highCritical: 100,
          interpret: (v) {
            if (v >= 100) return 'High resting HR — often seen with glycaemic dysregulation';
            if (v >= 85) return 'Slightly elevated resting HR';
            return 'Normal resting HR';
          },
        );
        addFinding(
          name: 'HRV (RMSSD)',
          value: snapshot.hrvRmssd,
          unit: 'ms',
          referenceRange: '> 30 ms healthy',
          lowCut: 30,
          interpret: (v) {
            if (v < 20) return 'Very low HRV — autonomic stress marker';
            if (v < 30) return 'Reduced HRV — glycaemic / stress correlation';
            return 'Healthy HRV';
          },
        );
        addFinding(
          name: 'Daily Steps',
          value: snapshot.steps.toDouble(),
          unit: 'steps',
          referenceRange: 'Target ≥ 7,000 / day',
          lowCut: 5000,
          interpret: (v) {
            if (v < 3000) return 'Sedentary — major diabetes risk factor';
            if (v < 5000) return 'Low activity — aim for more movement';
            return 'Active lifestyle';
          },
        );
        break;

      case DiseaseType.hypertension:
        addFinding(
          name: 'Systolic BP',
          value: snapshot.systolic,
          unit: 'mmHg',
          referenceRange: '< 120 normal • ≥ 130 stage 1 • ≥ 140 stage 2',
          highWarn: 130,
          highCritical: 180,
          interpret: (v) {
            if (v >= 180) return 'Hypertensive crisis — urgent care';
            if (v >= 140) return 'Stage 2 hypertension';
            if (v >= 130) return 'Stage 1 hypertension';
            return 'Normal systolic';
          },
        );
        addFinding(
          name: 'Diastolic BP',
          value: snapshot.diastolic,
          unit: 'mmHg',
          referenceRange: '< 80 normal • ≥ 90 stage 2',
          highWarn: 80,
          highCritical: 120,
          interpret: (v) {
            if (v >= 120) return 'Hypertensive crisis';
            if (v >= 90) return 'Stage 2 hypertension';
            if (v >= 80) return 'Stage 1 hypertension';
            return 'Normal diastolic';
          },
        );
        addFinding(
          name: 'Avg Heart Rate',
          value: snapshot.avgHeartRate,
          unit: 'bpm',
          referenceRange: '60–100 bpm',
          highWarn: 100,
          highCritical: 130,
          interpret: (v) {
            if (v >= 130) return 'Tachycardia';
            if (v >= 100) return 'Elevated heart rate';
            return 'Normal HR';
          },
        );
        break;

      case DiseaseType.anemia:
        addFinding(
          name: 'SpO₂',
          value: snapshot.spO2,
          unit: '%',
          referenceRange: '≥ 95% healthy',
          lowCut: 95,
          interpret: (v) {
            if (v < 90) return 'Severely low — urgent care';
            if (v < 95) return 'Low SpO₂ — oxygen-carrying capacity reduced';
            return 'Normal SpO₂';
          },
        );
        addFinding(
          name: 'Resting Heart Rate',
          value: snapshot.restingHeartRate,
          unit: 'bpm',
          referenceRange: '60–80 bpm typical',
          highWarn: 85,
          highCritical: 100,
          interpret: (v) {
            if (v >= 100) return 'Compensatory tachycardia — classic anaemia sign';
            if (v >= 85) return 'Slightly elevated resting HR';
            return 'Normal resting HR';
          },
        );
        addFinding(
          name: 'Avg Heart Rate',
          value: snapshot.avgHeartRate,
          unit: 'bpm',
          referenceRange: '60–100 bpm',
          highWarn: 100,
          interpret: (v) {
            if (v >= 100) return 'Elevated — heart working harder';
            return 'Normal HR';
          },
        );
        break;
    }

    final score = counted == 0 ? 0.0 : (totalScore / counted).clamp(0.0, 1.0);
    RiskLevel risk;
    if (counted == 0) {
      risk = RiskLevel.low;
    } else if (score >= 0.75) {
      risk = RiskLevel.critical;
    } else if (score >= 0.5) {
      risk = RiskLevel.high;
    } else if (score >= 0.25) {
      risk = RiskLevel.moderate;
    } else {
      risk = RiskLevel.low;
    }

    return DiseaseRiskResult(
      disease: disease,
      method: DetectionMethod.vitalsWearable,
      risk: risk,
      score: score,
      headline: _headline(disease, risk, isSimulated, counted),
      findings: findings,
      topContributors: contributors.take(3).toList(),
      recommendations: _recommendations(disease, risk, isSimulated),
      dataSource: isSimulated
          ? 'Simulation fallback — connect a smartwatch for live data'
          : 'Health Connect / HealthKit (live wearable data)',
      timestamp: DateTime.now(),
    );
  }

  static String _headline(
      DiseaseType d, RiskLevel r, bool isSimulated, int counted) {
    final src = isSimulated ? '(simulated)' : '(live)';
    final disease = DiseaseRegistry.of(d).title.toLowerCase();
    if (counted == 0) {
      return 'No wearable vitals available yet — connect a device or use simulation.';
    }
    switch (r) {
      case RiskLevel.critical:
        return '$src Wearable signals suggest CRITICAL $disease indicators.';
      case RiskLevel.high:
        return '$src Wearable signals suggest HIGH risk for $disease.';
      case RiskLevel.moderate:
        return '$src Wearable signals show MODERATE risk for $disease.';
      case RiskLevel.low:
        return '$src Wearable signals are within normal range for $disease.';
    }
  }

  static List<String> _recommendations(
      DiseaseType d, RiskLevel r, bool isSimulated) {
    final recs = <String>[];
    if (isSimulated) {
      recs.add('Connect a smartwatch via Health Connect for real-time tracking.');
    }
    if (r == RiskLevel.high || r == RiskLevel.critical) {
      recs.add('URGENT: Consult a ${DiseaseRegistry.of(d).title} specialist this week.');
    }
    switch (d) {
      case DiseaseType.diabetes:
        recs.add('Walk 30 minutes a day — reduces insulin resistance');
        recs.add('Follow up with an HbA1c lab test for confirmation');
        break;
      case DiseaseType.hypertension:
        recs.add('Home BP log: morning + evening for 7 days');
        recs.add('Reduce sodium to < 2 g / day and manage stress');
        break;
      case DiseaseType.anemia:
        recs.add('Get a CBC + ferritin blood test');
        recs.add('Add iron-rich foods with vitamin C');
        break;
    }
    return recs;
  }
}
