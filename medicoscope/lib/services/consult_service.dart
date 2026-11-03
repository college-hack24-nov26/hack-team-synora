import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:medicoscope/core/constants/api_constants.dart';

/// One event in the live agentic decision-trace, parsed from the backend's
/// Server-Sent-Events stream (POST /aegis/consult).
class ConsultEvent {
  final String event; // consult_start | triage_result | plan_published | tool_call | tool_result | diagnostic_result | plan_replan | guardrail_verdict | consult_complete | consult_error
  final Map<String, dynamic> data;
  const ConsultEvent(this.event, this.data);
}

/// Streams the autonomous consult from the chatbot's SSE endpoint. This is the
/// agent thinking out loud: triage -> plan -> tool calls -> fusion -> gate.
class ConsultService {
  /// Opens the SSE stream and yields each [ConsultEvent] as it arrives.
  /// Caller supplies the patient context + bearer token (required by the
  /// backend, which calls the auth-gated Node tool/aegis APIs).
  static Stream<ConsultEvent> run({
    required String patientId,
    required String patientName,
    String? doctorId,
    required String complaint,
    required String authToken,
    Map<String, dynamic> captures = const {},
    double? latitude,
    double? longitude,
    String? locationLabel,
    String? mapsUrl,
  }) async* {
    final uri = Uri.parse('${ApiConstants.chatbotBaseUrl}/aegis/consult');
    final body = jsonEncode({
      'patient_id': patientId,
      'patient_name': patientName,
      'doctor_id': doctorId,
      'complaint': complaint,
      'auth_token': authToken,
      'captures': captures,
      'latitude': latitude,
      'longitude': longitude,
      'location_label': locationLabel,
      'maps_url': mapsUrl,
    });

    final client = http.Client();
    try {
      // Cold-start resilience: the chatbot runs on Render's free tier, which
      // sleeps when idle and can 502/503 or drop the first connection while it
      // wakes. Try once, then retry a single time after a short delay.
      http.StreamedResponse? resp;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final req = http.Request('POST', uri)
            ..headers['Content-Type'] = 'application/json'
            ..headers['Accept'] = 'text/event-stream'
            ..body = body;
          resp = await client.send(req).timeout(const Duration(seconds: 120));
        } catch (e) {
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 3));
            continue;
          }
          yield ConsultEvent('consult_error',
              {'error': 'Could not reach the consult service. $e'});
          return;
        }
        // Waking-up responses are worth one retry; other statuses are final.
        if ((resp.statusCode == 502 || resp.statusCode == 503) && attempt == 0) {
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        break;
      }

      final r = resp!;
      if (r.statusCode != 200) {
        String detail = '';
        try {
          detail = (await r.stream.bytesToString()).trim();
        } catch (_) {}
        yield ConsultEvent(
            'consult_error', {'error': _describeError(r.statusCode, detail)});
        return;
      }

      // SSE frames are separated by a blank line; each frame has an
      // "event:" line and a "data:" line.
      String? curEvent;
      final buf = StringBuffer();
      await for (final chunk in r.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('event:')) {
          curEvent = chunk.substring(6).trim();
        } else if (chunk.startsWith('data:')) {
          buf.write(chunk.substring(5).trim());
        } else if (chunk.isEmpty) {
          // end of one frame
          if (curEvent != null && buf.isNotEmpty) {
            Map<String, dynamic> data = {};
            try {
              data = jsonDecode(buf.toString()) as Map<String, dynamic>;
            } catch (_) {}
            yield ConsultEvent(curEvent, data);
          }
          curEvent = null;
          buf.clear();
        }
      }
    } catch (e) {
      yield ConsultEvent('consult_error', {'error': e.toString()});
    } finally {
      client.close();
    }
  }

  /// Turns an HTTP status into a message a patient/clinician can act on.
  static String _describeError(int code, String detail) {
    final extra = detail.isNotEmpty ? ' ($detail)' : '';
    switch (code) {
      case 404:
        return 'Consult endpoint not found (404). The service may be redeploying, please try again shortly.$extra';
      case 401:
      case 403:
        return 'Session not authorized ($code). Please sign in again and retry.$extra';
      case 502:
      case 503:
        return 'The consult service is waking up ($code). Please try again in a moment.$extra';
      default:
        return 'Consult failed ($code).$extra';
    }
  }
}
