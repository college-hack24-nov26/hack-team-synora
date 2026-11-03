import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/services/api_service.dart';

class MentalHealthService {
  static Future<Map<String, dynamic>> uploadAudio({
    required String filePath,
    required String patientId,
    required String patientName,
    required String doctorId,
  }) async {
    final url = Uri.parse(
      '${ApiConstants.chatbotBaseUrl}${ApiConstants.mentalHealthAnalyze}',
    );

    final request = http.MultipartRequest('POST', url)
      ..fields['patient_id'] = patientId
      ..fields['patient_name'] = patientName
      ..fields['doctor_id'] = doctorId
      ..files.add(await http.MultipartFile.fromPath('audio', filePath));

    // Render free-tier cold start + Whisper transcription can take up to
    // ~3 minutes on the first call of the day; warm calls are ~5 seconds.
    final streamedResponse = await request.send().timeout(
          const Duration(seconds: 180),
        );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 503) {
      throw Exception('Service is warming up. Please try again in a moment.');
    } else if (response.statusCode == 429) {
      throw Exception(
          'Rate limit reached. Please try again later.');
    }
    // Surface backend error detail when available for easier debugging.
    String detail;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      detail = body['detail']?.toString() ?? 'Analysis failed (${response.statusCode})';
    } catch (_) {
      detail = 'Analysis failed (${response.statusCode})';
    }
    throw Exception(detail);
  }

  static Future<List<Map<String, dynamic>>> getNotifications({
    required String doctorId,
    required String token,
  }) async {
    final api = ApiService(token: token);
    final response = await api.get(
      '${ApiConstants.mentalHealthNotifications}/$doctorId',
    );
    return List<Map<String, dynamic>>.from(response['notifications'] ?? []);
  }

  static Future<void> markAsRead({
    required String notificationId,
    required String token,
  }) async {
    final api = ApiService(token: token);
    await api.put(
      '${ApiConstants.mentalHealthNotifications}/$notificationId/read',
      {},
    );
  }

  static Future<void> deleteNotification({
    required String notificationId,
    required String token,
  }) async {
    final api = ApiService(token: token);
    await api.delete(
      '${ApiConstants.mentalHealthNotifications}/$notificationId',
    );
  }

  static Future<String> redeemReward({
    required String rewardType,
    required String patientName,
  }) async {
    final url = Uri.parse(
      '${ApiConstants.chatbotBaseUrl}${ApiConstants.rewardsRedeem}',
    );

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'reward_type': rewardType,
            'patient_name': patientName,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['content'] as String? ?? 'Content unavailable.';
    } else if (response.statusCode == 503) {
      throw Exception('Service is warming up. Please try again in a moment.');
    } else {
      throw Exception('Failed to generate reward: ${response.statusCode}');
    }
  }

  /// Save mindspace session to DB
  static Future<void> saveSessionToDb({
    required String token,
    required String transcript,
    required String userMessage,
    String? doctorReport,
    String urgency = 'low',
    int coinsEarned = 0,
    String? doctorId,
  }) async {
    try {
      final api = ApiService(token: token);
      await api.post(ApiConstants.mindspaceSession, {
        'transcript': transcript,
        'userMessage': userMessage,
        'doctorReport': doctorReport,
        'urgency': urgency,
        'coinsEarned': coinsEarned,
        'doctorId': doctorId,
      });
    } catch (_) {
      // Silently fail
    }
  }

  /// Get mindspace history for patient
  static Future<List<Map<String, dynamic>>> getHistory(String token) async {
    final api = ApiService(token: token);
    final response = await api.get(ApiConstants.mindspaceHistory);
    return List<Map<String, dynamic>>.from(response['sessions'] ?? []);
  }

  /// Delete a mindspace session
  static Future<void> deleteSession(String token, String sessionId) async {
    final api = ApiService(token: token);
    await api.delete('${ApiConstants.mindspaceSession}/$sessionId');
  }

  /// Save a claimed reward to DB
  static Future<void> saveClaimedReward({
    required String token,
    required String rewardType,
    required String title,
    required String content,
    required int coinsCost,
  }) async {
    try {
      final api = ApiService(token: token);
      await api.post(ApiConstants.claimedRewards, {
        'rewardType': rewardType,
        'title': title,
        'content': content,
        'coinsCost': coinsCost,
      });
    } catch (_) {
      // Silently fail — reward was already displayed
    }
  }

  /// Get claimed rewards history
  static Future<List<Map<String, dynamic>>> getClaimedRewards(
      String token) async {
    final api = ApiService(token: token);
    final response = await api.get(ApiConstants.claimedRewards);
    return List<Map<String, dynamic>>.from(response['rewards'] ?? []);
  }
}
