import 'package:flutter_test/flutter_test.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/models/quality_gate_result.dart';
import 'package:medicoscope/services/quality_gate_service.dart';

void main() {
  group('Aegis Repeatable Quality Gate Tests (Challenge #386)', () {
    final testRecord = DetectionRecord(
      id: 'test-rec-001',
      patientId: 'patient-123',
      performedBy: 'doc-456',
      category: 'skin',
      className: 'Melanocytic Nevi',
      confidence: 0.92,
      timestamp: DateTime(2026, 8, 22, 10, 30),
      description: 'Benign melanocytic proliferation on dorsal forearm.',
    );

    test('QualityGate should evaluate 5 standardized dimensions', () {
      final result = QualityGateService.auditDetectionRecord(
        record: testRecord,
        patientName: 'John Doe',
        doctorNotes: 'Clinical impression consistent with benign nevus. Follow-up recommended within 14 business days.',
      );

      expect(result.dimensions.length, 5);
      expect(result.overallScore, greaterThan(0.85));
      expect(result.status, QualityGateStatus.passed);
      expect(result.auditHash.isNotEmpty, true);
      expect(result.auditHash.length, 16);
    });

    test('QualityGate must be 100% mathematically deterministic (Repeatable)', () async {
      final proof = await QualityGateService.runRepeatabilityBenchmark(
        record: testRecord,
        patientName: 'John Doe',
        doctorNotes: 'Follow-up in 14 business days.',
        iterations: 10,
      );

      expect(proof.iterations, 10);
      expect(proof.isDeterministic, true);
      expect(proof.variance, 0.0);
      expect(proof.matchedHashes, 10);
      expect(proof.executionTimeMs, greaterThan(0));
    });

    test('QualityGate detects medical jargon in Redline Studio', () {
      final result = QualityGateService.auditDetectionRecord(
        record: testRecord,
        patientName: 'John Doe',
        doctorNotes: 'Patient experiencing tachycardia and dyspnea.',
        perspective: QualityPerspective.patient,
      );

      expect(result.redlines.isNotEmpty, true);
      final jargonIssues = result.redlines.where((r) => r.category == 'jargon').toList();
      expect(jargonIssues.length, greaterThanOrEqualTo(2));
      expect(jargonIssues.any((j) => j.originalClause == 'tachycardia'), true);
      expect(jargonIssues.any((j) => j.originalClause == 'dyspnea'), true);
    });

    test('QualityGate flags missing urgency qualifiers on high-confidence severe cases', () {
      final severeRecord = DetectionRecord(
        id: 'severe-001',
        patientId: 'patient-123',
        performedBy: 'doc-456',
        category: 'heart_sound',
        className: 'Severe Aortic Murmur',
        confidence: 0.95,
        timestamp: DateTime(2026, 8, 22, 10, 30),
        description: 'Abnormal cardiac acoustic profile.',
      );

      final result = QualityGateService.auditDetectionRecord(
        record: severeRecord,
        patientName: 'John Doe',
        doctorNotes: 'Routine review advised.',
      );

      final safetyDim = result.dimensions.firstWhere((d) => d.type == QualityDimensionType.safety);
      expect(safetyDim.warnings.isNotEmpty, true);
    });
  });
}
