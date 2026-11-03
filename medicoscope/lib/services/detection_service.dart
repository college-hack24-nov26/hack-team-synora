import '../core/constants/api_constants.dart';
import '../models/detection_record.dart';
import 'api_service.dart';

class DetectionService {
  final ApiService _api;

  DetectionService(String token) : _api = ApiService(token: token);

  Future<DetectionRecord?> saveRecord({
    required String className,
    required double confidence,
    required String category,
    String? description,
    String? patientId,
  }) async {
    try {
      final response = await _api.post(ApiConstants.detections, {
        'className': className,
        'confidence': confidence,
        'category': category,
        'description': description ?? '',
        if (patientId != null) 'patientId': patientId,
      });
      return DetectionRecord.fromJson(response['record']);
    } catch (e) {
      // Silently fail - detection saving should not block the results screen
      return null;
    }
  }

  Future<List<DetectionRecord>> getMyRecords() async {
    try {
      final response = await _api.get(ApiConstants.patientRecords);
      final records = response['records'] as List;
      return records.map((r) => DetectionRecord.fromJson(r)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<DetectionRecord>> getPatientRecords(String patientId) async {
    try {
      final response = await _api.get('${ApiConstants.detections}/$patientId');
      final records = response['records'] as List;
      return records.map((r) => DetectionRecord.fromJson(r)).toList();
    } catch (e) {
      return [];
    }
  }
}
