import 'dart:convert';
import 'package:crypto/crypto.dart';

enum QualityGateStatus { passed, warning, blocked }

enum QualityDimensionType {
  structure,
  readability,
  safety,
  actionability,
  grounding,
}

class QualityDimensionScore {
  final QualityDimensionType type;
  final String title;
  final String description;
  final double score; // 0.0 to 1.0
  final QualityGateStatus status;
  final List<String> passedChecks;
  final List<String> warnings;
  final List<String> criticalIssues;

  const QualityDimensionScore({
    required this.type,
    required this.title,
    required this.description,
    required this.score,
    required this.status,
    this.passedChecks = const [],
    this.warnings = const [],
    this.criticalIssues = const [],
  });

  int get scorePercent => (score * 100).round();

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'title': title,
        'description': description,
        'score': score,
        'status': status.name,
        'passedChecks': passedChecks,
        'warnings': warnings,
        'criticalIssues': criticalIssues,
      };

  factory QualityDimensionScore.fromJson(Map<String, dynamic> j) =>
      QualityDimensionScore(
        type: QualityDimensionType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => QualityDimensionType.structure,
        ),
        title: j['title'] ?? '',
        description: j['description'] ?? '',
        score: (j['score'] as num?)?.toDouble() ?? 0.0,
        status: QualityGateStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => QualityGateStatus.warning,
        ),
        passedChecks: List<String>.from(j['passedChecks'] ?? []),
        warnings: List<String>.from(j['warnings'] ?? []),
        criticalIssues: List<String>.from(j['criticalIssues'] ?? []),
      );
}

/// The result of executing a Repeatable Quality Gate evaluation.
class QualityGateResult {
  final double overallScore; // 0.0 to 1.0
  final QualityGateStatus status;
  final String headline;
  final List<QualityDimensionScore> dimensions;
  final List<String> autoFixSuggestions;
  final String? enhancedContent;
  final String auditHash;
  final String rulesVersion;
  final DateTime evaluatedAt;
  final String gateVersion;

  const QualityGateResult({
    required this.overallScore,
    required this.status,
    required this.headline,
    required this.dimensions,
    this.autoFixSuggestions = const [],
    this.enhancedContent,
    required this.auditHash,
    required this.rulesVersion,
    required this.evaluatedAt,
    this.gateVersion = 'Aegis-QGate-v2.6.0',
  });

  int get overallScorePercent => (overallScore * 100).round();
  bool get isPassed => status == QualityGateStatus.passed;
  bool get isBlocked => status == QualityGateStatus.blocked;
  bool get hasWarnings => status == QualityGateStatus.warning;

  static String generateAuditHash({
    required String rawContent,
    required double score,
    required String rulesVersion,
    required DateTime timestamp,
  }) {
    final payload = '${rawContent.trim()}|$score|$rulesVersion|${timestamp.toIso8601String()}';
    return sha256.convert(utf8.encode(payload)).toString().substring(0, 16).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'overallScore': overallScore,
        'status': status.name,
        'headline': headline,
        'dimensions': dimensions.map((d) => d.toJson()).toList(),
        'autoFixSuggestions': autoFixSuggestions,
        'enhancedContent': enhancedContent,
        'auditHash': auditHash,
        'rulesVersion': rulesVersion,
        'evaluatedAt': evaluatedAt.toIso8601String(),
        'gateVersion': gateVersion,
      };

  factory QualityGateResult.fromJson(Map<String, dynamic> j) =>
      QualityGateResult(
        overallScore: (j['overallScore'] as num?)?.toDouble() ?? 0.0,
        status: QualityGateStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => QualityGateStatus.blocked,
        ),
        headline: j['headline'] ?? '',
        dimensions: (j['dimensions'] as List? ?? [])
            .map((e) => QualityDimensionScore.fromJson(e as Map<String, dynamic>))
            .toList(),
        autoFixSuggestions: List<String>.from(j['autoFixSuggestions'] ?? []),
        enhancedContent: j['enhancedContent'],
        auditHash: j['auditHash'] ?? '',
        rulesVersion: j['rulesVersion'] ?? 'QG-2026.1',
        evaluatedAt: DateTime.tryParse(j['evaluatedAt'] ?? '') ?? DateTime.now(),
        gateVersion: j['gateVersion'] ?? 'Aegis-QGate-v2.6.0',
      );
}
