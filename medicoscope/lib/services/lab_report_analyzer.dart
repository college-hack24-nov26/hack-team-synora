import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/disease_risk_result.dart';

/// Definition of one lab marker we know how to parse + interpret.
class _MarkerSpec {
  final String key;            // canonical id e.g. 'hba1c'
  final String display;        // "HbA1c"
  final String unit;
  final List<RegExp> patterns; // permissive patterns that match the marker name
  // Any text matching one of these immediately *before* the marker hit is a
  // sign we're looking at a different analyte (e.g. "HbA1c" vs "Hb"); skip.
  final List<RegExp> negativeLookbehind;
  final String referenceRange;
  final double? lowCritical;   // < this => 'critical' (severely low)
  final double? lowCutoff;     // < this => 'low'
  final double? highWarn;      // >= this => 'high'
  final double? highCritical;  // >= this => 'critical'
  final String Function(double value) interpret;

  const _MarkerSpec({
    required this.key,
    required this.display,
    required this.unit,
    required this.patterns,
    this.negativeLookbehind = const [],
    required this.referenceRange,
    this.lowCritical,
    this.lowCutoff,
    this.highWarn,
    this.highCritical,
    required this.interpret,
  });
}

/// Knowledge base of all markers, grouped by disease.
class _Knowledge {
  static final Map<DiseaseType, List<_MarkerSpec>> byDisease = {
    DiseaseType.diabetes: [
      _MarkerSpec(
        key: 'hba1c',
        display: 'HbA1c',
        unit: '%',
        patterns: [
          RegExp(r'hba1c', caseSensitive: false),
          RegExp(r'glycated\s+haemoglobin', caseSensitive: false),
          RegExp(r'glycated\s+hemoglobin', caseSensitive: false),
          RegExp(r'a1c', caseSensitive: false),
        ],
        referenceRange: '< 5.7% normal • 5.7–6.4% prediabetes • ≥ 6.5% diabetes',
        highWarn: 5.7,
        highCritical: 9.0,
        interpret: (v) {
          if (v >= 9.0) return 'Uncontrolled diabetes — urgent physician review';
          if (v >= 6.5) return 'Diabetic range per ADA / ICMR thresholds';
          if (v >= 5.7) return 'Prediabetic range — lifestyle modification recommended';
          return 'Normal glycemic control';
        },
      ),
      _MarkerSpec(
        key: 'fbs',
        display: 'Fasting Blood Sugar',
        unit: 'mg/dL',
        patterns: [
          RegExp(r'fasting\s+blood\s+(sugar|glucose)', caseSensitive: false),
          RegExp(r'\bfbs\b', caseSensitive: false),
          RegExp(r'\bfbg\b', caseSensitive: false),
          RegExp(r'fasting\s+plasma\s+glucose', caseSensitive: false),
        ],
        referenceRange: '70–99 normal • 100–125 prediabetes • ≥ 126 diabetes mg/dL',
        lowCutoff: 70,
        highWarn: 100,
        highCritical: 200,
        interpret: (v) {
          if (v >= 200) return 'Severe hyperglycemia — seek medical care';
          if (v >= 126) return 'Diabetic range (ADA)';
          if (v >= 100) return 'Impaired fasting glucose (prediabetes)';
          if (v < 70) return 'Hypoglycemia — verify with repeat test';
          return 'Normal fasting glucose';
        },
      ),
      _MarkerSpec(
        key: 'ppbs',
        display: 'Postprandial Blood Sugar',
        unit: 'mg/dL',
        patterns: [
          RegExp(r'post\s*prandial', caseSensitive: false),
          RegExp(r'\bppbs\b', caseSensitive: false),
          RegExp(r'\bppg\b', caseSensitive: false),
          RegExp(r'2\s*hr?\s*pp', caseSensitive: false),
        ],
        referenceRange: '< 140 normal • 140–199 prediabetes • ≥ 200 diabetes mg/dL',
        highWarn: 140,
        highCritical: 200,
        interpret: (v) {
          if (v >= 200) return 'Diabetic range (ADA)';
          if (v >= 140) return 'Impaired glucose tolerance';
          return 'Normal postprandial glucose';
        },
      ),
      _MarkerSpec(
        key: 'rbs',
        display: 'Random Blood Sugar',
        unit: 'mg/dL',
        patterns: [
          RegExp(r'random\s+blood\s+(sugar|glucose)', caseSensitive: false),
          RegExp(r'\brbs\b', caseSensitive: false),
        ],
        referenceRange: '< 200 mg/dL',
        highWarn: 140,
        highCritical: 200,
        interpret: (v) {
          if (v >= 200) return 'Suggestive of diabetes — confirm with FBS/HbA1c';
          if (v >= 140) return 'Elevated — follow up with fasting test';
          return 'Within expected range';
        },
      ),
    ],
    DiseaseType.hypertension: [
      _MarkerSpec(
        key: 'systolic_bp',
        display: 'Systolic BP',
        unit: 'mmHg',
        patterns: [
          RegExp(r'systolic', caseSensitive: false),
          RegExp(r'\bsbp\b', caseSensitive: false),
        ],
        referenceRange: '< 120 normal • 120–129 elevated • 130–139 stage 1 • ≥ 140 stage 2',
        lowCutoff: 90,
        highWarn: 130,
        highCritical: 180,
        interpret: (v) {
          if (v >= 180) return 'Hypertensive crisis — seek immediate care';
          if (v >= 140) return 'Stage 2 hypertension (AHA)';
          if (v >= 130) return 'Stage 1 hypertension';
          if (v >= 120) return 'Elevated BP — lifestyle changes advised';
          if (v < 90) return 'Hypotension — verify symptoms';
          return 'Normal systolic pressure';
        },
      ),
      _MarkerSpec(
        key: 'diastolic_bp',
        display: 'Diastolic BP',
        unit: 'mmHg',
        patterns: [
          RegExp(r'diastolic', caseSensitive: false),
          RegExp(r'\bdbp\b', caseSensitive: false),
        ],
        referenceRange: '< 80 normal • 80–89 stage 1 • ≥ 90 stage 2',
        lowCutoff: 60,
        highWarn: 80,
        highCritical: 120,
        interpret: (v) {
          if (v >= 120) return 'Hypertensive crisis';
          if (v >= 90) return 'Stage 2 hypertension';
          if (v >= 80) return 'Stage 1 hypertension';
          if (v < 60) return 'Low diastolic — monitor';
          return 'Normal diastolic pressure';
        },
      ),
      _MarkerSpec(
        key: 'total_cholesterol',
        display: 'Total Cholesterol',
        unit: 'mg/dL',
        patterns: [
          RegExp(r'total\s+cholesterol', caseSensitive: false),
          RegExp(r'cholesterol,?\s*total', caseSensitive: false),
        ],
        referenceRange: '< 200 desirable • 200–239 borderline • ≥ 240 high',
        highWarn: 200,
        highCritical: 240,
        interpret: (v) {
          if (v >= 240) return 'High — cardiovascular risk';
          if (v >= 200) return 'Borderline high cholesterol';
          return 'Desirable level';
        },
      ),
      _MarkerSpec(
        key: 'ldl',
        display: 'LDL Cholesterol',
        unit: 'mg/dL',
        patterns: [
          RegExp(r'\bldl\b', caseSensitive: false),
          RegExp(r'low\s+density', caseSensitive: false),
        ],
        referenceRange: '< 100 optimal • 100–129 near optimal • ≥ 160 high',
        highWarn: 130,
        highCritical: 160,
        interpret: (v) {
          if (v >= 160) return 'High LDL — atherosclerosis risk';
          if (v >= 130) return 'Borderline high';
          return 'Optimal / near optimal';
        },
      ),
      _MarkerSpec(
        key: 'creatinine',
        display: 'Serum Creatinine',
        unit: 'mg/dL',
        patterns: [
          RegExp(r'creatinine', caseSensitive: false),
        ],
        referenceRange: '0.6–1.3 mg/dL (adults)',
        highWarn: 1.3,
        highCritical: 2.0,
        interpret: (v) {
          if (v >= 2.0) return 'Severely elevated — possible renal damage';
          if (v >= 1.3) return 'Elevated — consider renal function tests';
          return 'Within reference range';
        },
      ),
      _MarkerSpec(
        key: 'sodium',
        display: 'Sodium',
        unit: 'mmol/L',
        patterns: [RegExp(r'sodium', caseSensitive: false)],
        referenceRange: '135–145 mmol/L',
        lowCutoff: 135,
        highWarn: 145,
        highCritical: 160,
        interpret: (v) {
          if (v >= 160) return 'Severe hypernatremia';
          if (v >= 145) return 'Hypernatremia — hydration / BP correlation';
          if (v < 135) return 'Hyponatremia';
          return 'Normal sodium';
        },
      ),
    ],
    DiseaseType.anemia: [
      _MarkerSpec(
        key: 'hemoglobin',
        display: 'Hemoglobin',
        unit: 'g/dL',
        patterns: [
          // Anchor word-boundaries tightly so "HbA1c" is NOT matched for
          // hemoglobin. The order matters — longer patterns first.
          RegExp(r'h(a)?emoglobin\s*(?!a1c)', caseSensitive: false),
          RegExp(r'\bhgb\b', caseSensitive: false),
          // "Hb" followed by a number / space, not by A1c or any letter.
          RegExp(r'\bhb\b(?!\s*a?1c)', caseSensitive: false),
        ],
        referenceRange: 'Men ≥ 13 • Women ≥ 12 • Severe < 8 g/dL (WHO)',
        lowCritical: 8.0,
        lowCutoff: 12.0,
        interpret: (v) {
          if (v < 7) return 'Severe anemia — clinical attention required';
          if (v < 8) return 'Severe anemia (WHO < 8 g/dL)';
          if (v < 10) return 'Moderate anemia (WHO)';
          if (v < 12) return 'Mild anemia (WHO female / borderline male)';
          return 'Hemoglobin within normal range';
        },
      ),
      _MarkerSpec(
        key: 'mcv',
        display: 'MCV',
        unit: 'fL',
        patterns: [RegExp(r'\bmcv\b', caseSensitive: false)],
        referenceRange: '80–100 fL',
        lowCutoff: 80,
        highWarn: 100,
        interpret: (v) {
          if (v < 80) return 'Microcytic — iron-deficiency / thalassemia pattern';
          if (v > 100) return 'Macrocytic — B12 / folate / liver pattern';
          return 'Normocytic';
        },
      ),
      _MarkerSpec(
        key: 'mch',
        display: 'MCH',
        unit: 'pg',
        // Avoid matching MCHC which is a different index.
        patterns: [RegExp(r'\bmch\b(?!c)', caseSensitive: false)],
        referenceRange: '27–33 pg',
        lowCutoff: 27,
        highWarn: 33,
        interpret: (v) {
          if (v < 27) return 'Hypochromic — iron-deficiency pattern';
          if (v > 33) return 'Hyperchromic';
          return 'Normochromic';
        },
      ),
      _MarkerSpec(
        key: 'ferritin',
        display: 'Ferritin',
        unit: 'ng/mL',
        patterns: [RegExp(r'ferritin', caseSensitive: false)],
        referenceRange: 'Men 24–336 • Women 11–307 ng/mL',
        lowCritical: 10,
        lowCutoff: 15,
        highWarn: 300,
        interpret: (v) {
          if (v < 10) return 'Severely depleted iron stores';
          if (v < 15) return 'Iron-deficient stores';
          if (v > 300) return 'Elevated — chronic inflammation / overload';
          return 'Adequate iron stores';
        },
      ),
      _MarkerSpec(
        key: 'rbc',
        display: 'RBC Count',
        unit: 'million/µL',
        patterns: [
          RegExp(r'\brbc\b', caseSensitive: false),
          RegExp(r'red\s+blood\s+cell', caseSensitive: false),
        ],
        referenceRange: 'Men 4.7–6.1 • Women 4.2–5.4',
        lowCritical: 3.5,
        lowCutoff: 4.2,
        interpret: (v) {
          if (v < 3.5) return 'Markedly low RBC count';
          if (v < 4.2) return 'Low RBC count';
          return 'Normal RBC count';
        },
      ),
      _MarkerSpec(
        key: 'hct',
        display: 'Hematocrit',
        unit: '%',
        patterns: [
          RegExp(r'h(a)?ematocrit', caseSensitive: false),
          RegExp(r'\bhct\b', caseSensitive: false),
          RegExp(r'\bpcv\b', caseSensitive: false),
        ],
        referenceRange: 'Men 41–50 • Women 36–44 %',
        lowCritical: 30,
        lowCutoff: 36,
        interpret: (v) {
          if (v < 25) return 'Very low hematocrit — severe anemia';
          if (v < 36) return 'Low hematocrit — anaemia likely';
          return 'Normal hematocrit';
        },
      ),
    ],
  };
}

/// End-to-end analyzer: given raw text from a PDF, produce a DiseaseRiskResult.
class LabReportAnalyzer {
  /// Tries to parse a numeric value on the same line as (or within ~120 chars of)
  /// any marker pattern. Returns the FIRST plausible value found — as soon as
  /// any pattern matches, we short-circuit, which prevents duplicate findings
  /// from the same marker with multiple synonyms.
  static double? _extractValue(String text, _MarkerSpec spec) {
    for (final pat in spec.patterns) {
      for (final m in pat.allMatches(text)) {
        final tail = text.substring(
          m.end,
          (m.end + 160).clamp(0, text.length),
        );
        // Walk the tail to find the first plausible standalone numeric value.
        // Allow up to 6 digits before the decimal so huge counts (e.g. platelets
        // 450 000) still resolve. Skip numbers that are obviously part of a
        // reference range like "4.2-5.4" by consuming the pair and taking the
        // value before the dash if the marker value itself is missing.
        final numMatch =
            RegExp(r'([-+]?\d{1,6}(?:\.\d+)?)').firstMatch(tail);
        if (numMatch != null) {
          final v = double.tryParse(numMatch.group(1)!);
          if (v != null && v > 0 && v < 100000) return v;
        }
      }
    }
    return null;
  }

  static String _flagFor(_MarkerSpec s, double v) {
    if (s.highCritical != null && v >= s.highCritical!) return 'critical';
    if (s.highWarn != null && v >= s.highWarn!) return 'high';
    if (s.lowCritical != null && v < s.lowCritical!) return 'critical';
    if (s.lowCutoff != null && v < s.lowCutoff!) return 'low';
    return 'normal';
  }

  /// Score contribution of each flag, summed and squashed for the overall risk.
  static const _flagWeight = {
    'normal': 0.0,
    'low': 0.55,
    'high': 0.55,
    'critical': 0.95,
  };

  static DiseaseRiskResult analyze({
    required DiseaseType disease,
    required String text,
  }) {
    final specs = _Knowledge.byDisease[disease]!;
    final findings = <MarkerFinding>[];
    double totalWeight = 0;
    int counted = 0;
    bool anyCritical = false;
    final contributors = <String>[];

    for (final s in specs) {
      final v = _extractValue(text, s);
      if (v == null) continue;
      final flag = _flagFor(s, v);
      final weight = _flagWeight[flag] ?? 0.0;
      totalWeight += weight;
      counted += 1;
      if (flag == 'critical') anyCritical = true;
      if (weight >= 0.5) contributors.add('${s.display}: ${v.toStringAsFixed(1)} ${s.unit}');
      findings.add(MarkerFinding(
        name: s.display,
        value: v.toStringAsFixed(1),
        unit: s.unit,
        referenceRange: s.referenceRange,
        flag: flag,
        interpretation: s.interpret(v),
      ));
    }

    final avg = counted == 0 ? 0.0 : (totalWeight / counted).clamp(0.0, 1.0);
    // If any single marker is critical, force overall score to ≥ 0.75
    // so the UI correctly surfaces "CRITICAL" and the alert pipeline fires.
    final score = anyCritical ? avg.clamp(0.75, 1.0) : avg;
    RiskLevel risk;
    if (counted == 0) {
      risk = RiskLevel.low;
    } else if (anyCritical || score >= 0.75) {
      risk = RiskLevel.critical;
    } else if (score >= 0.5) {
      risk = RiskLevel.high;
    } else if (score >= 0.25) {
      risk = RiskLevel.moderate;
    } else {
      risk = RiskLevel.low;
    }

    final headline = _headline(disease, risk, counted);
    final recs = _recommendations(disease, risk);
    final source = _dataSource(disease);

    return DiseaseRiskResult(
      disease: disease,
      method: DetectionMethod.labReportPdf,
      risk: risk,
      score: score,
      headline: headline,
      findings: findings,
      topContributors: contributors.take(3).toList(),
      recommendations: recs,
      dataSource: source,
      timestamp: DateTime.now(),
    );
  }

  static String _headline(DiseaseType d, RiskLevel r, int markers) {
    if (markers == 0) {
      return 'No recognizable ${DiseaseRegistry.of(d).title.toLowerCase()} markers found in this report.';
    }
    final disease = DiseaseRegistry.of(d).title.toLowerCase();
    switch (r) {
      case RiskLevel.critical:
        return 'Markers suggest CRITICAL $disease indicators — see a clinician promptly.';
      case RiskLevel.high:
        return 'Report indicates HIGH risk for $disease.';
      case RiskLevel.moderate:
        return 'Report indicates MODERATE risk for $disease — monitor and retest.';
      case RiskLevel.low:
        return 'Markers in the normal range for $disease.';
    }
  }

  static List<String> _recommendations(DiseaseType d, RiskLevel r) {
    final disease = DiseaseRegistry.of(d).title;
    final base = <String>[];
    switch (d) {
      case DiseaseType.diabetes:
        base.addAll([
          'Maintain a glycemic-controlled diet (low-GI carbs, adequate protein)',
          'Daily 30-minute moderate activity (walking / cycling)',
          'Repeat HbA1c every 3–6 months',
        ]);
        break;
      case DiseaseType.hypertension:
        base.addAll([
          'Limit sodium to < 2 g/day and increase potassium-rich foods',
          'Home BP log, morning & evening for 7 days',
          'Stress management — meditation / breathing exercises',
        ]);
        break;
      case DiseaseType.anemia:
        base.addAll([
          'Iron-rich diet (leafy greens, jaggery, pulses, red meat if non-veg)',
          'Vitamin C with iron-rich meals improves absorption',
          'Retest hemoglobin in 4–6 weeks',
        ]);
        break;
    }
    if (r == RiskLevel.high || r == RiskLevel.critical) {
      base.insert(0, 'URGENT: Book an in-person consult with a $disease specialist');
    }
    return base;
  }

  static String _dataSource(DiseaseType d) {
    switch (d) {
      case DiseaseType.diabetes:
        return 'ADA Standards of Care + ICMR-INDIAB thresholds';
      case DiseaseType.hypertension:
        return 'AHA/ACC 2017 + ICMR Hypertension Guidelines';
      case DiseaseType.anemia:
        return 'WHO Anemia Thresholds + NFHS-5 baselines';
    }
  }
}
